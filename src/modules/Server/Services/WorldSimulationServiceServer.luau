--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Plasma = require(ReplicatedStorage.Packages.Plasma)
local CoreConfigs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CmdrUtils = require(script:FindFirstAncestor("game").Shared.Cmdr.CmdrUtils)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerServiceServer)

local Cache = require(script:FindFirstAncestor("game").Shared.Services.SimulationCache)
local Config = require(script:FindFirstAncestor("game").Shared.Services.SimulationConfig)
local Data = require(script:FindFirstAncestor("game").Shared.Services.SimulationData)
local Debug = require(script:FindFirstAncestor("game").Shared.Services.Debug)
local Net = require(script:FindFirstAncestor("game").Shared.Services.Net)
local Runtime = require(script:FindFirstAncestor("game").Shared.Services.SimulationRuntime)
local Shared = require(script:FindFirstAncestor("game").Shared.Services.Shared)
local State = require(script:FindFirstAncestor("game").Shared.Services.SimulationState)
local Stream = require(script:FindFirstAncestor("game").Shared.Services.Stream)

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

local function resolvePlayerRootPart(player: Player): BasePart?
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

local function resolveSourceConfig(): any
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
	local rootPart = resolvePlayerRootPart(player)
	if rootPart == nil then
		return 0, 0
	end
	local tileX = Shared.toTileCoordinate(rootPart.Position.Z, config.tileSize)
	local tileY = Shared.toTileCoordinate(rootPart.Position.Y, config.tileSize)
	return Shared.toChunkCoordinate(tileX, config.chunkSize),
		Shared.toChunkCoordinate(tileY, config.chunkHeight)
end

function WorldSimulationServiceServer:CreateStateSnapshot(player: Player): { [string]: any }
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

function WorldSimulationServiceServer:PushState(player: Player)
	if self.networker == nil then
		return
	end
	self.networker:fire(player, Net.CLIENT_METHOD_APPLY_STATE, self:createStateSnapshot(player))
end

function WorldSimulationServiceServer:SetAuthoritativeSeed(seedRaw: any)
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

function WorldSimulationServiceServer:ToSimulationChunkKey(rawChunkKey: any): (string?, number?, number?, number?)
	local chunkX, chunkY, chunkZ = Shared.unpackChunkKey(rawChunkKey)
	if chunkX ~= nil and chunkY ~= nil and chunkZ ~= nil then
		return Shared.packChunkKey(chunkX, chunkY, chunkZ), chunkX, chunkY, chunkZ
	end
	local generationChunkX, generationChunkY = parseWorldGenerationChunkKey(rawChunkKey)
	if generationChunkX == nil or generationChunkY == nil then
		return nil, nil, nil, nil
	end
	return Shared.packChunkKey(generationChunkX, generationChunkY, SIMULATION_CHUNK_Z),
		generationChunkX,
		generationChunkY,
		SIMULATION_CHUNK_Z
end

function WorldSimulationServiceServer:PushGeneratedPlayerInterest(player: Player, interestRaw: any)
	if self.config == nil or self.generatedInterestByPlayer == nil then
		if self.pendingGeneratedInterestRawByPlayer == nil then
			self.pendingGeneratedInterestRawByPlayer = {}
		end
		self.pendingGeneratedInterestRawByPlayer[player] = interestRaw
		return
	end

	local nextInterest = {} :: GeneratedPlayerInterest
	local centerChunkX, centerChunkY = getPlayerCenterChunkForWorldGeneration(self.config, player)
	if typeof(interestRaw) == "table" then
		for rawChunkKey, rawPriority in interestRaw do
			if rawPriority == false or rawPriority == nil then
				continue
			end
			local simulationKey, chunkX, chunkY, chunkZ = self:toSimulationChunkKey(rawChunkKey)
			if simulationKey == nil or chunkX == nil or chunkY == nil or chunkZ == nil then
				continue
			end
			local priority = if isFiniteNumber(rawPriority)
				then math.max(0, math.floor(rawPriority))
				else Net.chunkPriorityFromCenter(
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

function WorldSimulationServiceServer:ClearGeneratedPlayerInterest(player: Player)
	if self.generatedInterestByPlayer == nil then
		if self.pendingGeneratedInterestRawByPlayer == nil then
			self.pendingGeneratedInterestRawByPlayer = {}
		end
		self.pendingGeneratedInterestRawByPlayer[player] = {}
		return
	end
	self.generatedInterestByPlayer[player] = {}
end

function WorldSimulationServiceServer:RegisterGeneratedChunkSnapshot(chunkSnapshotRaw: any): boolean
	if self.world == nil then
		if self.pendingChunkSnapshots == nil then
			self.pendingChunkSnapshots = {}
		end
		self.pendingChunkSnapshots[#self.pendingChunkSnapshots + 1] = chunkSnapshotRaw
		return false
	end

	local chunk = Data.ingestWorldGenerationChunkSnapshot(self.world, chunkSnapshotRaw, SIMULATION_CHUNK_Z)
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
			Stream.enqueueChunk(stream, chunkKey, priority)
		end
	end

	if self.debug ~= nil then
		self.debug:incrementCounter("wg_chunks_registered")
	end
	return true
end

function WorldSimulationServiceServer:TrackPlayer(player: Player)
	local settings = self.playerSettings[player]
	if settings == nil then
		settings = defaultPlayerSettings(self.config)
		self.playerSettings[player] = settings
	else
		settings.streamRadius = Net.sanitizeStreamRadius(settings.streamRadius, self.config.streamRadiusChunks)
		settings.streamVerticalRadius =
			Net.sanitizeStreamRadius(settings.streamVerticalRadius, self.config.streamVerticalRadiusChunks)
	end
	self.generatedInterestByPlayer[player] = {}
	local stream = Stream.getOrCreatePlayerStream(self.streamState, player)
	for chunkKey in stream.interestLookup do
		Data.setChunkDemandByKey(self.world, chunkKey, -1)
	end
	table.clear(stream.interestLookup)
	table.clear(stream.sentRevisions)
	table.clear(stream.queuedLookup)
	table.clear(stream.queueKeys)
	self:pushState(player)
end

function WorldSimulationServiceServer:UntrackPlayer(player: Player)
	local stream = self.streamState.players[player]
	if stream ~= nil then
		for chunkKey in stream.interestLookup do
			Data.setChunkDemandByKey(self.world, chunkKey, -1)
		end
	end
	Stream.removePlayerStream(self.streamState, player)
	self.playerSettings[player] = nil
	self.generatedInterestByPlayer[player] = nil
end

function WorldSimulationServiceServer:RequestSync(player: Player)
	self:trackPlayer(player)
end

function WorldSimulationServiceServer:SetStreamRadius(player: Player, streamRadiusRaw: any, verticalRadiusRaw: any)
	local fallbackConfig = if self.config ~= nil then self.config else Config.createDefault()
	if self.playerSettings == nil then
		self.playerSettings = {} :: { [Player]: PlayerSettings }
	end

	local settings = self.playerSettings[player]
	if settings == nil then
		settings = defaultPlayerSettings(fallbackConfig)
		self.playerSettings[player] = settings
	end
	settings.streamRadius = Net.sanitizeStreamRadius(streamRadiusRaw, settings.streamRadius)
	settings.streamVerticalRadius = Net.sanitizeStreamRadius(verticalRadiusRaw, settings.streamVerticalRadius)
	if self.config == nil then
		return
	end
	self:pushState(player)
end

function WorldSimulationServiceServer:SubmitInput(player: Player, inputRaw: any)
	local ok, reason = Net.validateClientInput(inputRaw)
	if not ok then
		if self.debug ~= nil then
			self.debug:incrementCounter("invalid_input")
		end
		return
	end

	local input = inputRaw :: { [string]: any }
	local targetEntityId = math.floor(input.entityId)
	local moveX = math.clamp(input.moveX, -1, 1)
	local moveZ = math.clamp(input.moveZ, -1, 1)

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
			entities.flags[slot] = State.setFlag(entities.flags[slot], State.ENTITY_FLAGS.PREDICTED, true)
			entities.velX[slot] = entities.velX[slot] * 0.4 + moveX * 8
			entities.velZ[slot] = entities.velZ[slot] * 0.4 + moveZ * 8
			Data.bumpChunkRevision(chunk)
			if self.debug ~= nil then
				self.debug:incrementCounter("input_applied")
			end
			return
		end
	end
end

function WorldSimulationServiceServer:SyncPlayerStream(player: Player)
	local stream = Stream.getOrCreatePlayerStream(self.streamState, player)
	local nextInterest = self.generatedInterestByPlayer[player] or {}

	Stream.reconcilePlayerInterest(stream, nextInterest, function(chunkKey: string, priority: number)
		Data.setChunkDemandByKey(self.world, chunkKey, 1)
		Stream.enqueueChunk(stream, chunkKey, priority)
	end, function(chunkKey: string)
		Data.setChunkDemandByKey(self.world, chunkKey, -1)
		if self.networker ~= nil then
			self.networker:fire(player, Net.CLIENT_METHOD_CHUNK_UNLOADED, chunkKey)
		end
	end)

	if self.networker == nil then
		return
	end

	for chunkKey, priority in nextInterest do
		local chunk = self.world.chunksByKey[chunkKey]
		if chunk == nil then
			Stream.enqueueChunk(stream, chunkKey, priority)
		elseif Stream.isRevisionOutOfDate(stream, chunkKey, chunk.revision) then
			Stream.enqueueChunk(stream, chunkKey, priority)
		end
	end

	local sendBudget = self.config.maxStreamSendsPerPlayerPerTick
	for _ = 1, sendBudget do
		local nextChunkKey = Stream.popNextChunk(stream)
		if nextChunkKey == nil then
			break
		end

		local chunk = self.world.chunksByKey[nextChunkKey]
		if chunk == nil then
			local retryPriority = stream.interestLookup[nextChunkKey]
			if retryPriority ~= nil then
				Stream.enqueueChunk(stream, nextChunkKey, retryPriority)
			end
			continue
		end
		local delta = Net.buildChunkDelta(chunk, stream.sentRevisions[nextChunkKey])
		if delta ~= nil and self.networker ~= nil then
			self.networker:fire(player, Net.CLIENT_METHOD_CHUNK_DELTA, delta)
			Stream.markRevisionSent(stream, nextChunkKey, chunk.revision)
		end
	end
end

function WorldSimulationServiceServer:OnHeartbeat(dt: number)
	self.runtime:tick(dt)
	for player in self.playerSettings do
		self:syncPlayerStream(player)
	end

	if self.debug ~= nil then
		self.debugCounterAccumulator += dt
		if self.debugCounterAccumulator >= DEBUG_COUNTER_PUSH_INTERVAL then
			self.debugCounterAccumulator = 0
			local counters = self.debug:getCounters()
			if self.networker ~= nil and next(counters) ~= nil then
				for player in self.playerSettings do
					self.networker:fire(player, Net.CLIENT_METHOD_DEBUG_COUNTERS, counters)
				end
			end
			self.debug:resetFrameCounters()
		end
	end
end

function WorldSimulationServiceServer:GetWorldData(): WorldData
	return self.world
end

function WorldSimulationServiceServer:GetConfig(): SimulationConfig
	return self.config
end

function WorldSimulationServiceServer:Init()
	if self.heartbeatConnection ~= nil or self.heartbeatToken ~= nil then
		return
	end

	self.runtimeContext = CoreRuntime.getServerRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).init) == "function" then
		local runtimeContextAny = self.runtimeContext :: any
		runtimeContextAny:init()
	end
	local sourceConfig = resolveSourceConfig()
	self.config = Config.sanitize(sourceConfig, nil)
	if self.pendingAuthoritativeSeed ~= nil then
		self.config.seed = self.pendingAuthoritativeSeed
	end
	self.cache = Cache.new({
		tablePoolSize = self.config.cacheTablePoolSize,
		arrayPoolSize = self.config.cacheArrayPoolSize,
		vectorPoolSize = math.max(16, math.floor(self.config.cacheArrayPoolSize * 0.5)),
	})
	self.debug = Debug.new({
		enabled = self.config.enableDebug,
		profilingEnabled = self.config.enableProfiling,
	})
	self.world = Data.createWorldData(self.config)
	self.runtime = Runtime.new(self.world, self.debug)
	local diagnostics = if self.runtime ~= nil then (self.runtime :: any).diagnostics else nil
	if diagnostics ~= nil and typeof((diagnostics :: any).attachDebugger) == "function" then
		self.matterDebugger = Matter.Debugger.new(Plasma)
		self.matterDebugger.authorize = function(player: Player): boolean
			return player:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == true
		end
		(diagnostics :: any):attachDebugger(self.matterDebugger)
	end
	self.streamState = Stream.createServerStreamState()
	if typeof(self.playerSettings) ~= "table" then
		self.playerSettings = {} :: { [Player]: PlayerSettings }
	end
	self.generatedInterestByPlayer = {} :: { [Player]: GeneratedPlayerInterest }
	self.debugCounterAccumulator = 0

	if self.config.enableClientReplication then
		self.networker = Networker.server.new("WorldSimulationService", self, {
			self.RequestSync,
			self.SetStreamRadius,
			self.SubmitInput,
		})
	else
		self.networker = nil
	end

	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self:trackPlayer(player)
		end
	end

	if self.pendingGeneratedInterestRawByPlayer ~= nil then
		for player, interestRaw in self.pendingGeneratedInterestRawByPlayer do
			self:pushGeneratedPlayerInterest(player, interestRaw)
		end
		table.clear(self.pendingGeneratedInterestRawByPlayer)
	end
	if self.pendingChunkSnapshots ~= nil then
		for _, chunkSnapshot in self.pendingChunkSnapshots do
			self:registerGeneratedChunkSnapshot(chunkSnapshot)
		end
		table.clear(self.pendingChunkSnapshots)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self:trackPlayer(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)

	local tickScheduler = if self.runtimeContext ~= nil then (self.runtimeContext :: any).tickScheduler else nil
	if tickScheduler ~= nil and typeof((tickScheduler :: any).scheduleEvery) == "function" then
		self.heartbeatToken = (tickScheduler :: any):scheduleEvery(function(dt: number)
			self:onHeartbeat(dt)
		end, 1 / 60, {
			group = "service.worldSimulation.server",
			priority = 120,
			catchUp = false,
		})
	else
		self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
			self:onHeartbeat(dt)
		end)
	end
end

function WorldSimulationServiceServer:Destroy()
	if self.heartbeatToken ~= nil then
		if typeof((self.heartbeatToken :: any).cancel) == "function" then
			local heartbeatTokenAny = self.heartbeatToken :: any
			heartbeatTokenAny:cancel()
		else
			local runtimeContext = self.runtimeContext
			local scheduler = if runtimeContext ~= nil then (runtimeContext :: any).tickScheduler else nil
			if scheduler ~= nil and typeof((scheduler :: any).cancel) == "function" then
				local schedulerAny = scheduler :: any
				schedulerAny:cancel(self.heartbeatToken)
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
		self:untrackPlayer(player)
	end

	if self.networker ~= nil then
		self.networker:destroy()
		self.networker = nil
	end
	if self.runtime ~= nil and typeof((self.runtime :: any).Destroy) == "function" then
		local runtimeAny = self.runtime :: any
		runtimeAny:Destroy()
	end
	self.matterDebugger = nil
	if self.debug ~= nil then
		self.debug:destroy()
		self.debug = nil
	end
	if self.cache ~= nil then
		self.cache:destroy()
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

WorldSimulationServiceServer.createStateSnapshot = WorldSimulationServiceServer.CreateStateSnapshot
WorldSimulationServiceServer.pushState = WorldSimulationServiceServer.PushState
WorldSimulationServiceServer.setAuthoritativeSeed = WorldSimulationServiceServer.SetAuthoritativeSeed
WorldSimulationServiceServer.toSimulationChunkKey = WorldSimulationServiceServer.ToSimulationChunkKey
WorldSimulationServiceServer.pushGeneratedPlayerInterest = WorldSimulationServiceServer.PushGeneratedPlayerInterest
WorldSimulationServiceServer.clearGeneratedPlayerInterest = WorldSimulationServiceServer.ClearGeneratedPlayerInterest
WorldSimulationServiceServer.registerGeneratedChunkSnapshot = WorldSimulationServiceServer.RegisterGeneratedChunkSnapshot
WorldSimulationServiceServer.trackPlayer = WorldSimulationServiceServer.TrackPlayer
WorldSimulationServiceServer.untrackPlayer = WorldSimulationServiceServer.UntrackPlayer
WorldSimulationServiceServer.requestSync = WorldSimulationServiceServer.RequestSync
WorldSimulationServiceServer.setStreamRadius = WorldSimulationServiceServer.SetStreamRadius
WorldSimulationServiceServer.submitInput = WorldSimulationServiceServer.SubmitInput
WorldSimulationServiceServer.syncPlayerStream = WorldSimulationServiceServer.SyncPlayerStream
WorldSimulationServiceServer.onHeartbeat = WorldSimulationServiceServer.OnHeartbeat
WorldSimulationServiceServer.getWorldData = WorldSimulationServiceServer.GetWorldData
WorldSimulationServiceServer.getConfig = WorldSimulationServiceServer.GetConfig
WorldSimulationServiceServer.init = WorldSimulationServiceServer.Init
WorldSimulationServiceServer.destroy = WorldSimulationServiceServer.Destroy

type WorldSimulationServiceServer = typeof(WorldSimulationServiceServer) & {
	runtimeContext: any?,
	heartbeatToken: any?,
	config: SimulationConfig,
	cache: Cache.Cache,
	debug: Debug.Debug,
	world: WorldData,
	runtime: RuntimeObject,
	streamState: ServerStreamState,
	networker: Networker.Server?,
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

