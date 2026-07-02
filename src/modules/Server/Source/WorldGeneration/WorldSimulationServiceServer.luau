local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CmdrUtils = require("CmdrUtils")
local CoreConfigs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local Matter = require(ReplicatedStorage.Packages.Matter)
local PacketPayload = require("PacketPayload")
local WorldSimulationServicePackets = require("NetPacketsShared").WorldSimulationService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = WorldSimulationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldSimulationService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = WorldSimulationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldSimulationService`)
		return
	end

	packet.listen(function(payload: any, player: Player?)
		if player == nil then
			return
		end

		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, player, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "requestSync")
	bindPacket(self, "setStreamRadius")
	bindPacket(self, "submitInput")
end

local Plasma = require(ReplicatedStorage.Packages.Plasma)
local PlayerServiceServer = require("PlayerServiceServer")

local Cache = require("SimulationCache")
local Config = require("SimulationConfig")
local Data = require("SimulationData")
local Debug = require("WorldSimulationDebug")
local Net = require("Net")
local Runtime = require("SimulationRuntime")
local Shared = require("Shared")
local State = require("SimulationState")
local Stream = require("Stream")

type SimulationConfig = Config.SimulationConfig
type WorldData = Data.WorldData
type RuntimeObject = Runtime.Runtime
type ServerStreamState = Stream.ServerStreamState
type PlayerStreamState = Stream.PlayerStreamState
type GeneratedPlayerInterest = { [string]: number }

type PlayerSettings = {
	streamRadius: number,
	streamVerticalRadius: number,
}

local WorldSimulationServiceServer = {}

local DEBUG_COUNTER_PUSH_INTERVAL = 0.5
local SIMULATION_CHUNK_Z = 0
local WORLD_GENERATION_CHUNK_KEY_PATTERN = "^(-?%d+):(-?%d+)$"

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function GetPlayerRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp
	end
	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function GetSourceConfig(): any
	if typeof(CoreConfigs) ~= "table" then
		return nil
	end
	return (CoreConfigs :: any).worldSimulation
end

local function defaultPlayerSettings(config: SimulationConfig): PlayerSettings
	return {
		streamRadius = config.streamRadiusChunks,
		streamVerticalRadius = config.streamVerticalRadiusChunks,
	}
end

local function parseWorldGenerationChunkKey(chunkKeyRaw: any): (number?, number?)
	if typeof(chunkKeyRaw) ~= "string" then
		return nil, nil
	end
	local xRaw, yRaw = string.match(chunkKeyRaw, WORLD_GENERATION_CHUNK_KEY_PATTERN)
	if xRaw == nil or yRaw == nil then
		return nil, nil
	end
	local chunkX = tonumber(xRaw)
	local chunkY = tonumber(yRaw)
	if chunkX == nil or chunkY == nil then
		return nil, nil
	end
	return chunkX, chunkY
end

local function getPlayerCenterChunkForWorldGeneration(config: SimulationConfig, player: Player): (number, number)
	local rootPart = GetPlayerRootPart(player)
	if rootPart == nil then
		return 0, 0
	end
	local tileX = Shared.ToTileCoordinate(rootPart.Position.Z, config.tileSize)
	local tileY = Shared.ToTileCoordinate(rootPart.Position.Y, config.tileSize)
	return Shared.ToChunkCoordinate(tileX, config.chunkSize), Shared.ToChunkCoordinate(tileY, config.chunkHeight)
end

local function applyInputToEntity(
	self: WorldSimulationServiceServer,
	chunk: Data.ChunkData,
	slot: number,
	moveX: number,
	moveZ: number
)
	local entities = chunk.entities
	entities.flags[slot] = State.setFlag(entities.flags[slot], State.ENTITY_FLAGS.PREDICTED, true)
	entities.velX[slot] = entities.velX[slot] * 0.4 + moveX * 8
	entities.velZ[slot] = entities.velZ[slot] * 0.4 + moveZ * 8
	Data.SyncEntitySlotToEcs(self.world, chunk, slot)
	Data.BumpChunkRevision(chunk)
	if self.debug ~= nil then
		self.debug:IncrementCounter("input_applied")
	end
end

function WorldSimulationServiceServer.CreateStateSnapshot(
	self: WorldSimulationServiceServer,
	player: Player
): { [string]: any }
	local settings = self.playerSettings[player] or defaultPlayerSettings(self.config)
	return {
		seed = self.config.seed,
		tileSize = self.config.tileSize,
		chunkSize = self.config.chunkSize,
		chunkHeight = self.config.chunkHeight,
		chunkDepth = self.config.chunkDepth,
		clusterSize = self.config.clusterSize,
		streamRadiusChunks = settings.streamRadius,
		streamVerticalRadiusChunks = settings.streamVerticalRadius,
		renderRadiusChunks = self.config.renderRadiusChunks,
		renderVerticalRadiusChunks = self.config.renderVerticalRadiusChunks,
		nearSurfaceDepth = self.config.nearSurfaceDepth,
		biomeTransitionWidth = self.config.biomeTransitionWidth,
		lodNearDistance = self.config.lodNearDistance,
		lodFarDistance = self.config.lodFarDistance,
		enableDebug = self.config.enableDebug,
	}
end

function WorldSimulationServiceServer.PushState(self: WorldSimulationServiceServer, player: Player)
	sendPacket(player, Net.CLIENT_METHOD_APPLY_STATE, self:CreateStateSnapshot(player))
end

function WorldSimulationServiceServer.SetAuthoritativeSeed(self: WorldSimulationServiceServer, seedRaw: any)
	if not isFiniteNumber(seedRaw) then
		return
	end
	local seed = math.floor(seedRaw)
	self.pendingAuthoritativeSeed = seed
	if self.config ~= nil then
		self.config.seed = seed
	end
	if self.world ~= nil then
		self.world.seed = seed
		self.world.config.seed = seed
	end
end

function WorldSimulationServiceServer.ToSimulationChunkKey(
	_self: WorldSimulationServiceServer,
	rawChunkKey: any
): (string?, number?, number?, number?)
	local chunkX, chunkY, chunkZ = Shared.UnpackChunkKey(rawChunkKey)
	if chunkX ~= nil and chunkY ~= nil and chunkZ ~= nil then
		return Shared.PackChunkKey(chunkX, chunkY, chunkZ), chunkX, chunkY, chunkZ
	end
	local generationChunkX, generationChunkY = parseWorldGenerationChunkKey(rawChunkKey)
	if generationChunkX == nil or generationChunkY == nil then
		return nil, nil, nil, nil
	end
	return Shared.PackChunkKey(generationChunkX, generationChunkY, SIMULATION_CHUNK_Z),
		generationChunkX,
		generationChunkY,
		SIMULATION_CHUNK_Z
end

function WorldSimulationServiceServer.PushGeneratedPlayerInterest(
	self: WorldSimulationServiceServer,
	player: Player,
	interestRaw: any
)
	if self.config == nil or self.generatedInterestByPlayer == nil then
		if self.pendingGeneratedInterestRawByPlayer == nil then
			self.pendingGeneratedInterestRawByPlayer = {}
		end
		local pending = self.pendingGeneratedInterestRawByPlayer :: { [Player]: any }
		pending[player] = interestRaw
		return
	end

	local nextInterest = {} :: GeneratedPlayerInterest
	local centerChunkX, centerChunkY = getPlayerCenterChunkForWorldGeneration(self.config, player)
	if typeof(interestRaw) == "table" then
		for rawChunkKey, rawPriority in interestRaw do
			if rawPriority == false or rawPriority == nil then
				continue
			end
			local simulationKey, chunkX, chunkY, chunkZ = self:ToSimulationChunkKey(rawChunkKey)
			if simulationKey == nil or chunkX == nil or chunkY == nil or chunkZ == nil then
				continue
			end
			local priority = if isFiniteNumber(rawPriority)
				then math.max(0, math.floor(rawPriority))
				else Net.ChunkPriorityFromCenter(
					chunkX,
					chunkY,
					chunkZ,
					centerChunkX,
					centerChunkY,
					SIMULATION_CHUNK_Z
				)
			nextInterest[simulationKey] = priority
		end
	end
	self.generatedInterestByPlayer[player] = nextInterest
end

function WorldSimulationServiceServer.ClearGeneratedPlayerInterest(self: WorldSimulationServiceServer, player: Player)
	if self.generatedInterestByPlayer == nil then
		if self.pendingGeneratedInterestRawByPlayer == nil then
			self.pendingGeneratedInterestRawByPlayer = {}
		end
		local pending = self.pendingGeneratedInterestRawByPlayer :: { [Player]: any }
		pending[player] = {}
		return
	end
	self.generatedInterestByPlayer[player] = {}
end

function WorldSimulationServiceServer.RegisterGeneratedChunkSnapshot(
	self: WorldSimulationServiceServer,
	chunkSnapshotRaw: any
): boolean
	if self.world == nil then
		if self.pendingChunkSnapshots == nil then
			self.pendingChunkSnapshots = {}
		end
		local pendingSnapshots = self.pendingChunkSnapshots :: { any }
		pendingSnapshots[#pendingSnapshots + 1] = chunkSnapshotRaw
		return false
	end

	local chunk = Data.IngestWorldGenerationChunkSnapshot(self.world, chunkSnapshotRaw, SIMULATION_CHUNK_Z)
	if chunk == nil then
		return false
	end

	local chunkKey = chunk.key
	for player, stream in self.streamState.players do
		local playerInterest = self.generatedInterestByPlayer[player]
		if playerInterest == nil then
			continue
		end
		local priority = playerInterest[chunkKey]
		if priority ~= nil then
			Stream.EnqueueChunk(stream, chunkKey, priority)
		end
	end

	if self.debug ~= nil then
		self.debug:IncrementCounter("wg_chunks_registered")
	end
	return true
end

function WorldSimulationServiceServer.TrackPlayer(self: WorldSimulationServiceServer, player: Player)
	local settings = self.playerSettings[player]
	if settings == nil then
		settings = defaultPlayerSettings(self.config)
		self.playerSettings[player] = settings
	else
		settings.streamRadius = Net.CoerceStreamRadius(settings.streamRadius, self.config.streamRadiusChunks)
		settings.streamVerticalRadius =
			Net.CoerceStreamRadius(settings.streamVerticalRadius, self.config.streamVerticalRadiusChunks)
	end
	self.generatedInterestByPlayer[player] = {}
	local stream = Stream.GetOrCreatePlayerStream(self.streamState, player)
	for chunkKey in stream.interestLookup do
		Data.SetChunkDemandByKey(self.world, chunkKey, -1)
	end
	table.clear(stream.interestLookup)
	table.clear(stream.sentRevisions)
	table.clear(stream.queuedLookup)
	table.clear(stream.queueKeys)
	self:PushState(player)
end

function WorldSimulationServiceServer.UntrackPlayer(self: WorldSimulationServiceServer, player: Player)
	local stream = self.streamState.players[player]
	if stream ~= nil then
		for chunkKey in stream.interestLookup do
			Data.SetChunkDemandByKey(self.world, chunkKey, -1)
		end
	end
	Stream.RemovePlayerStream(self.streamState, player)
	self.playerSettings[player] = nil
	self.generatedInterestByPlayer[player] = nil
end

function WorldSimulationServiceServer.RequestSync(self: WorldSimulationServiceServer, player: Player)
	self:TrackPlayer(player)
end

function WorldSimulationServiceServer.SetStreamRadius(
	self: WorldSimulationServiceServer,
	player: Player,
	streamRadiusRaw: any,
	verticalRadiusRaw: any
)
	local fallbackConfig = if self.config ~= nil then self.config else Config.CreateDefault()
	if self.playerSettings == nil then
		self.playerSettings = {} :: { [Player]: PlayerSettings }
	end

	local settings = self.playerSettings[player]
	if settings == nil then
		settings = defaultPlayerSettings(fallbackConfig)
		self.playerSettings[player] = settings
	end
	settings.streamRadius = Net.CoerceStreamRadius(streamRadiusRaw, settings.streamRadius)
	settings.streamVerticalRadius = Net.CoerceStreamRadius(verticalRadiusRaw, settings.streamVerticalRadius)
	if self.config == nil then
		return
	end
	self:PushState(player)
end

function WorldSimulationServiceServer.SubmitInput(self: WorldSimulationServiceServer, _player: Player, inputRaw: any)
	local ok, _reason = Net.ValidateClientInput(inputRaw)
	if not ok then
		if self.debug ~= nil then
			self.debug:IncrementCounter("invalid_input")
		end
		return
	end

	local input = inputRaw :: { [string]: any }
	local targetEntityId = math.floor(input.entityId)
	local moveX = math.clamp(input.moveX, -1, 1)
	local moveZ = math.clamp(input.moveZ, -1, 1)

	local indexedChunk, indexedSlot = Data.GetEntityLocationByRuntimeId(self.world, targetEntityId)
	if indexedChunk ~= nil and indexedSlot ~= nil and self.world.activeChunkLookup[indexedChunk.key] then
		applyInputToEntity(self, indexedChunk, indexedSlot, moveX, moveZ)
		return
	end

	for _, chunkKey in self.world.activeChunkKeys do
		local chunk = self.world.chunksByKey[chunkKey]
		if chunk == nil then
			continue
		end
		local entities = chunk.entities
		for slot = 1, entities.count do
			if entities.ids[slot] ~= targetEntityId then
				continue
			end
			applyInputToEntity(self, chunk, slot, moveX, moveZ)
			return
		end
	end
end

function WorldSimulationServiceServer.SyncPlayerStream(self: WorldSimulationServiceServer, player: Player)
	local stream = Stream.GetOrCreatePlayerStream(self.streamState, player)
	local nextInterest = self.generatedInterestByPlayer[player] or ({} :: any)

	Stream.ReconcilePlayerInterest(stream, nextInterest, function(chunkKey: string, priority: number)
		Data.SetChunkDemandByKey(self.world, chunkKey, 1)
		Stream.EnqueueChunk(stream, chunkKey, priority)
	end, function(chunkKey: string)
		Data.SetChunkDemandByKey(self.world, chunkKey, -1)
		sendPacket(player, Net.CLIENT_METHOD_CHUNK_UNLOADED, chunkKey)
	end)

	for chunkKey, priority in nextInterest do
		local chunk = self.world.chunksByKey[chunkKey]
		if chunk == nil or Stream.IsRevisionOutOfDate(stream, chunkKey, chunk.revision) then
			Stream.EnqueueChunk(stream, chunkKey, priority)
		end
	end

	local sendBudget = self.config.maxStreamSendsPerPlayerPerTick
	for _ = 1, sendBudget do
		local nextChunkKey = Stream.PopNextChunk(stream)
		if nextChunkKey == nil then
			break
		end

		local chunk = self.world.chunksByKey[nextChunkKey]
		if chunk == nil then
			local retryPriority = stream.interestLookup[nextChunkKey]
			if retryPriority ~= nil then
				Stream.EnqueueChunk(stream, nextChunkKey, retryPriority)
			end
			continue
		end
		local delta = Net.BuildChunkDelta(chunk, stream.sentRevisions[nextChunkKey])
		if delta ~= nil then
			sendPacket(player, Net.CLIENT_METHOD_CHUNK_DELTA, delta)
			Stream.MarkRevisionSent(stream, nextChunkKey, chunk.revision)
		end
	end
end

function WorldSimulationServiceServer.OnHeartbeat(self: WorldSimulationServiceServer, dt: number)
	self.runtime:Tick(dt)
	for player in self.playerSettings do
		self:SyncPlayerStream(player)
	end

	if self.debug ~= nil then
		self.debugCounterAccumulator += dt
		if self.debugCounterAccumulator >= DEBUG_COUNTER_PUSH_INTERVAL then
			self.debugCounterAccumulator = 0
			local counters = self.debug:GetCounters()
			if next(counters) ~= nil then
				for player in self.playerSettings do
					sendPacket(player, Net.CLIENT_METHOD_DEBUG_COUNTERS, counters)
				end
			end
			self.debug:ResetFrameCounters()
		end
	end
end

function WorldSimulationServiceServer.GetWorldData(self: WorldSimulationServiceServer): WorldData
	return self.world
end

function WorldSimulationServiceServer.GetConfig(self: WorldSimulationServiceServer): SimulationConfig
	return self.config
end

function WorldSimulationServiceServer.Init(self: WorldSimulationServiceServer)
	if self.heartbeatConnection ~= nil or self.heartbeatToken ~= nil then
		return
	end

	self.runtimeContext = CoreRuntime.GetServerRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).Init) == "function" then
		local runtimeContextAny = self.runtimeContext :: any
		runtimeContextAny:Init()
	end
	local sourceConfig = GetSourceConfig()
	self.config = Config.Coerce(sourceConfig, nil)
	if self.pendingAuthoritativeSeed ~= nil then
		self.config.seed = self.pendingAuthoritativeSeed
	end
	self.cache = Cache.New({
		tablePoolSize = self.config.cacheTablePoolSize,
		arrayPoolSize = self.config.cacheArrayPoolSize,
		vectorPoolSize = math.max(16, math.floor(self.config.cacheArrayPoolSize * 0.5)),
	})
	self.debug = Debug.New({
		enabled = self.config.enableDebug,
		profilingEnabled = self.config.enableProfiling,
	})
	self.world = Data.CreateWorldData(self.config)
	self.runtime = Runtime.New(self.world, self.debug)
	local diagnostics = if self.runtime ~= nil then (self.runtime :: any).diagnostics else nil
	if diagnostics ~= nil and typeof((diagnostics :: any).attachDebugger) == "function" then
		local matterDebugger = Matter.Debugger.new(Plasma)
		self.matterDebugger = matterDebugger;
		(matterDebugger :: any).authorize = function(player: Player): boolean
			return player:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == true
		end
		(diagnostics :: any):AttachDebugger(matterDebugger)
	end
	self.streamState = Stream.CreateServerStreamState()
	if typeof(self.playerSettings) ~= "table" then
		self.playerSettings = {} :: { [Player]: PlayerSettings }
	end
	self.generatedInterestByPlayer = {} :: { [Player]: GeneratedPlayerInterest }
	self.debugCounterAccumulator = 0

	if self.config.enableClientReplication then
		bindPackets(self)
	end

	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
			self:TrackPlayer(player)
		end
	end

	if self.pendingGeneratedInterestRawByPlayer ~= nil then
		for player, interestRaw in self.pendingGeneratedInterestRawByPlayer do
			self:PushGeneratedPlayerInterest(player, interestRaw)
		end
		table.clear(self.pendingGeneratedInterestRawByPlayer)
	end
	if self.pendingChunkSnapshots ~= nil then
		for _, chunkSnapshot in self.pendingChunkSnapshots do
			self:RegisterGeneratedChunkSnapshot(chunkSnapshot)
		end
		table.clear(self.pendingChunkSnapshots)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
			self:TrackPlayer(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:UntrackPlayer(player)
	end)

	local tickScheduler = if self.runtimeContext ~= nil then (self.runtimeContext :: any).tickScheduler else nil
	if tickScheduler ~= nil and typeof((tickScheduler :: any).ScheduleEvery) == "function" then
		self.heartbeatToken = (tickScheduler :: any):ScheduleEvery(
			function(dt: number)
				self:OnHeartbeat(dt)
			end,
			1 / 60,
			{
				group = "service.worldSimulation.server",
				priority = 120,
				catchUp = false,
			}
		)
	else
		self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
			self:OnHeartbeat(dt)
		end)
	end
end

function WorldSimulationServiceServer.Destroy(self: WorldSimulationServiceServer)
	if self.heartbeatToken ~= nil then
		if typeof((self.heartbeatToken :: any).Cancel) == "function" then
			local heartbeatTokenAny = self.heartbeatToken :: any
			heartbeatTokenAny:Cancel()
		else
			local runtimeContext = self.runtimeContext
			local scheduler = if runtimeContext ~= nil then (runtimeContext :: any).tickScheduler else nil
			if scheduler ~= nil and typeof((scheduler :: any).Cancel) == "function" then
				local schedulerAny = scheduler :: any
				schedulerAny:Cancel(self.heartbeatToken)
			end
		end
		self.heartbeatToken = nil
	end
	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	local trackedPlayers = {}
	for player in self.playerSettings do
		trackedPlayers[#trackedPlayers + 1] = player
	end
	for _, player in trackedPlayers do
		self:UntrackPlayer(player)
	end

	if self.runtime ~= nil and typeof((self.runtime :: any).Destroy) == "function" then
		local runtimeAny = self.runtime :: any
		runtimeAny:Destroy()
	end
	self.matterDebugger = nil
	if self.debug ~= nil then
		self.debug:Destroy()
		self.debug = nil
	end
	if self.cache ~= nil then
		self.cache:Destroy()
		self.cache = nil
	end
	self.generatedInterestByPlayer = {}
	if self.pendingGeneratedInterestRawByPlayer ~= nil then
		table.clear(self.pendingGeneratedInterestRawByPlayer)
	end
	if self.pendingChunkSnapshots ~= nil then
		table.clear(self.pendingChunkSnapshots)
	end
end
type WorldSimulationServiceServer = typeof(WorldSimulationServiceServer) & {
	runtimeContext: any?,
	heartbeatToken: any?,
	config: SimulationConfig,
	cache: Cache.Cache,
	debug: Debug.Debug,
	world: WorldData,
	runtime: RuntimeObject,
	streamState: ServerStreamState,
	playerSettings: { [Player]: PlayerSettings },
	generatedInterestByPlayer: { [Player]: GeneratedPlayerInterest },
	pendingAuthoritativeSeed: number?,
	pendingGeneratedInterestRawByPlayer: { [Player]: any }?,
	pendingChunkSnapshots: { any }?,
	debugCounterAccumulator: number,
	matterDebugger: any?,
	heartbeatConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return WorldSimulationServiceServer :: WorldSimulationServiceServer
