local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Maid = require("Maid")
local Rx: any = require("Rx")
local RxSignal: any = require("RxSignal")
local Signal = require("Signal")

local Configs = require("CoreConfigs")
local PacketPayload = require("PacketPayload")
local WorldGenerationServicePackets = require("NetPacketsShared").WorldGenerationService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = WorldGenerationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldGenerationService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = WorldGenerationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldGenerationService`)
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
	bindPacket(self, "setRenderDistance")
end

local NevermoreSupport = require("NevermoreSupport")
local BinderSupportServer = require("BinderSupportServer")
local TagBinder = require("TagBinder")
local WorldGeneration = require("WorldGeneration")
local WorldGenerationServiceUtils = require("WorldGenerationServiceUtils")
local WorldSimulationServiceServer = require("WorldSimulationServiceServer")

type WorldGenerationClass = WorldGeneration.WorldGeneration
type WorldGenerationConfig = WorldGenerationServiceUtils.WorldGenerationConfig
type WorldGenerationServiceState = WorldGenerationServiceUtils.WorldGenerationServiceState
type MaidClass = any
type SignalObject = Signal.Signal<...any>
type ObservableObject = any
type RxSignalObject = any

type PlayerRenderSettings = {
	renderDistanceChunks: number,
	verticalRenderDistanceChunks: number,
}

type ChunkSendQueue = {
	sendQueue: { string },
	sendQueueHead: number,
	sendQueueTail: number,
	queuedLookup: { [string]: boolean },
}

type PlayerChunkStream = ChunkSendQueue & {
	interestKeys: { [string]: boolean },
	sentRevisions: { [string]: number },
}

type PlayerInterestChangedEvent = {
	player: Player,
	interestKeys: { [string]: boolean },
}

type ChunkLifecycleEvent = {
	chunkKey: string,
	chunkX: number,
	chunkY: number,
	context: { [string]: any },
}

local MIN_INT32_SEED = -2147483648
local MAX_INT32_SEED = 2147483647
local CHUNK_STREAM_SYNC_INTERVAL = 0.03
local CHUNK_STREAM_GLOBAL_BUDGET_PER_TICK = 64
local CHUNK_STREAM_PER_PLAYER_BUDGET_PER_TICK = 16
local CHUNK_STREAM_SIMULATION_BUDGET_PER_TICK = 24
local CHUNK_STREAM_MAX_QUEUE_PER_PLAYER = 4096

local function GetConfigSource(): any
	if typeof(Configs) ~= "table" then
		return nil
	end
	return (Configs :: any).worldGeneration
end

local function cloneTableShallow(sourceRaw: any): { [any]: any }
	local source = if typeof(sourceRaw) == "table" then sourceRaw else {} :: any
	return table.clone(source)
end

local function cloneBooleanLookup(sourceRaw: any): { [string]: boolean }
	local clone = {}
	if typeof(sourceRaw) ~= "table" then
		return clone
	end

	for key, value in sourceRaw do
		if typeof(key) == "string" and value == true then
			clone[key] = true
		end
	end

	return clone
end

local function countLookupEntries(lookup: { [any]: any }): number
	local count = 0
	for _ in lookup do
		count += 1
	end
	return count
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function hasExplicitSeed(configSource: any): boolean
	if typeof(configSource) ~= "table" then
		return false
	end
	return isFiniteNumber((configSource :: any).seed)
end

local function GetUntimeSeed(configSource: any, CoerceDConfig: WorldGenerationConfig): number
	if hasExplicitSeed(configSource) then
		return CoerceDConfig.seed
	end
	return Random.new():NextInteger(MIN_INT32_SEED, MAX_INT32_SEED)
end

local function GetStudioPreviewEnabled(configSource: any): boolean
	if typeof(configSource) ~= "table" then
		return false
	end
	local previewEnabled = (configSource :: any).studioPreviewEnabled
	if typeof(previewEnabled) == "boolean" then
		return previewEnabled
	end
	return false
end

local function packChunkKey(chunkX: number, chunkY: number): string
	return `{chunkX}:{chunkY}`
end

local function unpackChunkKey(chunkKey: string): (number?, number?)
	local xRaw, yRaw = string.match(chunkKey, "^(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil then
		return nil, nil
	end
	return tonumber(xRaw), tonumber(yRaw)
end

local function toTileCoordinate(worldAxis: number, tileSize: number): number
	return math.floor(worldAxis / tileSize)
end

local function toChunkCoordinate(tile: number, chunkSize: number): number
	return math.floor(tile / chunkSize)
end

local function collectSortedInterestKeys(
	world: WorldGenerationClass,
	player: Player,
	interestKeys: { [string]: boolean }
): { string }
	local centerChunkX = 0
	local centerChunkY = 0
	local focusPosition = world:GetPlayerFocusPosition(player)
	if typeof(focusPosition) == "Vector3" then
		local tileX = toTileCoordinate(focusPosition.Z - world.worldOrigin.Z, world.tileSize)
		local tileY = toTileCoordinate(focusPosition.Y - world.worldOrigin.Y, world.tileSize)
		centerChunkX = toChunkCoordinate(tileX, world.chunkSize)
		centerChunkY = toChunkCoordinate(tileY, world.chunkSize)
	end

	local entries = {}
	for chunkKey in interestKeys do
		local chunkX, chunkY = unpackChunkKey(chunkKey)
		local distanceSquared = math.huge
		if chunkX ~= nil and chunkY ~= nil then
			local deltaX = chunkX - centerChunkX
			local deltaY = chunkY - centerChunkY
			distanceSquared = deltaX * deltaX + deltaY * deltaY
		end
		entries[#entries + 1] = {
			key = chunkKey,
			distanceSquared = distanceSquared,
		}
	end

	table.sort(entries, function(left, right)
		if left.distanceSquared ~= right.distanceSquared then
			return left.distanceSquared < right.distanceSquared
		end
		return left.key < right.key
	end)

	local sortedKeys = table.create(#entries)
	for index, entry in entries do
		sortedKeys[index] = entry.key
	end
	return sortedKeys
end

local function isChunkYWithinBounds(config: WorldGenerationConfig, chunkY: number): boolean
	local chunkTileMinY = chunkY * config.chunkSize
	local chunkTileMaxY = chunkTileMinY + config.chunkSize - 1
	if chunkTileMaxY < config.minTileY then
		return false
	end
	if chunkTileMinY > config.maxTileY then
		return false
	end
	return true
end

local function enqueueChunkForStream(sendQueue: ChunkSendQueue, chunkKey: string)
	if sendQueue.queuedLookup[chunkKey] then
		return
	end
	if sendQueue.sendQueueTail - sendQueue.sendQueueHead + 1 >= CHUNK_STREAM_MAX_QUEUE_PER_PLAYER then
		return
	end
	sendQueue.queuedLookup[chunkKey] = true
	sendQueue.sendQueueTail += 1
	sendQueue.sendQueue[sendQueue.sendQueueTail] = chunkKey
end

local function dequeueChunkForStream(sendQueue: ChunkSendQueue): string?
	if sendQueue.sendQueueHead > sendQueue.sendQueueTail then
		if sendQueue.sendQueueHead ~= 1 or sendQueue.sendQueueTail ~= 0 then
			table.clear(sendQueue.sendQueue)
			sendQueue.sendQueueHead = 1
			sendQueue.sendQueueTail = 0
		end
		return nil
	end

	local chunkKey = sendQueue.sendQueue[sendQueue.sendQueueHead]
	if chunkKey == nil then
		return nil
	end

	sendQueue.sendQueue[sendQueue.sendQueueHead] = nil
	sendQueue.sendQueueHead += 1
	if sendQueue.sendQueueHead > sendQueue.sendQueueTail then
		table.clear(sendQueue.sendQueue)
		sendQueue.sendQueueHead = 1
		sendQueue.sendQueueTail = 0
	end

	sendQueue.queuedLookup[chunkKey] = nil
	return chunkKey
end

local WorldGenerationServiceServer = {}

function WorldGenerationServiceServer.Init(self: WorldGenerationServiceServer)
	self.maid = Maid.new() :: MaidClass
	local configSource = GetConfigSource()
	self.config = WorldGenerationServiceUtils.CoerceConfig(configSource, nil)
	self.config.seed = GetUntimeSeed(configSource, self.config)
	self.world = (WorldGeneration.New :: any)(self.config)
	self.world:Init()
	self.latestWorldStats = self.world:GetStats()
	self:PushSeedToWorldSimulation()
	self.studioPreviewEnabled = RunService:IsStudio() and GetStudioPreviewEnabled(configSource)
	self.studioPreviewInterestKeys = {}
	self.studioPreviewActive = false
	self.worldBootstrapPlayerUserId = nil

	self.binders = NevermoreSupport.GetService(BinderSupportServer)
	self.chunkBinder = self.binders:Get(TagBinder.Tags.Chunk)
	self.playerRenderSettings = {}
	self.playerChunkStreams = {}
	self.playersPendingSync = {} :: { [Player]: boolean }
	self.pendingPlayerInterest = {} :: { [Player]: { [string]: boolean } }
	self.worldSimulationChunkQueue = self:CreateChunkSendQueue()
	self.worldSimulationSentRevisions = {}
	self.chunkRuntimeByKey = {} :: { [string]: any }
	self.boundChunkRuntimeCount = 0
	self.chunkStreamAccumulator = CHUNK_STREAM_SYNC_INTERVAL
	self.worldObserverMaid = Maid.new() :: MaidClass
	self.maid:GiveTask(self.worldObserverMaid)
	self._stateChangedSignal = Signal.new() :: SignalObject
	self.stateChangedSignal = RxSignal.new(function(): ObservableObject
		return self:ObserveStateChanged()
	end) :: RxSignalObject
	self.maid:GiveTask(self._stateChangedSignal)
	bindPackets(self)
	self:ConnectReactiveWorldObservers()
	self:ConnectChunkBinderObservers()

	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:OnHeartbeat(deltaTime)
	end)
	self.maid:GiveTask(self.heartbeatConnection)

	if
		self.studioPreviewEnabled
		and self.worldBootstrapPlayerUserId == nil
		and next(self.playerRenderSettings) == nil
	then
		self:EnableStudioPreview()
	end

	for _, player in Players:GetPlayers() do
		self:TrackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:TrackPlayer(player)
	end)
	self.maid:GiveTask(self.playerAddedConnection)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:UntrackPlayer(player)
		if
			self.studioPreviewEnabled
			and self.worldBootstrapPlayerUserId == nil
			and next(self.playerRenderSettings) == nil
		then
			self:EnableStudioPreview()
		end
	end)
	self.maid:GiveTask(self.playerRemovingConnection)
end

function WorldGenerationServiceServer.ResetStreamingState(self: WorldGenerationServiceServer)
	for player, stream in self.playerChunkStreams do
		for chunkKey in stream.interestKeys do
			sendPacket(player, "onChunkUnloaded", chunkKey)
		end

		table.clear(stream.interestKeys)
		table.clear(stream.sentRevisions)
		table.clear(stream.queuedLookup)
		table.clear(stream.sendQueue)
		stream.sendQueueHead = 1
		stream.sendQueueTail = 0
		self.playersPendingSync[player] = nil
		self.pendingPlayerInterest[player] = nil
		self:PushPlayerInterestToWorldSimulation(player, {})
	end

	table.clear(self.worldSimulationSentRevisions)
	table.clear(self.worldSimulationChunkQueue.sendQueue)
	table.clear(self.worldSimulationChunkQueue.queuedLookup)
	self.worldSimulationChunkQueue.sendQueueHead = 1
	self.worldSimulationChunkQueue.sendQueueTail = 0
	table.clear(self.playersPendingSync)
	table.clear(self.pendingPlayerInterest)
end

function WorldGenerationServiceServer.LoadWorld(self: WorldGenerationServiceServer, worldRaw: any)
	local worldSource = if typeof(worldRaw) == "table" then worldRaw else {} :: any
	local configSource = cloneTableShallow(GetConfigSource())
	for key, value in worldSource do
		if
			key == "seed"
			or key == "worldOrigin"
			or key == "minTileY"
			or key == "maxTileY"
			or key == "bedrockThickness"
		then
			configSource[key] = value
		end
	end

	local nextConfig = WorldGenerationServiceUtils.CoerceConfig(configSource, nil)
	nextConfig.seed = GetUntimeSeed(configSource, nextConfig)

	self:DisableStudioPreview()
	self:ResetStreamingState()
	if self.worldObserverMaid ~= nil then
		self.worldObserverMaid:DoCleaning()
	end

	if self.world ~= nil then
		self.world:Destroy()
	end
	table.clear(self.chunkRuntimeByKey)
	self.boundChunkRuntimeCount = 0

	self.config = nextConfig
	self.world = (WorldGeneration.New :: any)(self.config)
	self.world:Init()
	self.latestWorldStats = self.world:GetStats()
	self:ConnectReactiveWorldObservers()
	self:PushSeedToWorldSimulation()

	for _, player in Players:GetPlayers() do
		self:TrackPlayer(player)
	end

	if
		self.studioPreviewEnabled
		and self.worldBootstrapPlayerUserId == nil
		and next(self.playerRenderSettings) == nil
	then
		self:EnableStudioPreview()
	end
end

function WorldGenerationServiceServer.BuildStudioPreviewInterest(
	self: WorldGenerationServiceServer
): { [string]: boolean }
	local renderDistance = self.config.defaultRenderDistanceChunks
	local verticalRenderDistance = self.config.defaultVerticalRenderDistanceChunks
	local centerChunkX = 0
	local centerChunkY = 0
	local radiusSquared = renderDistance * renderDistance
	local nextInterest: { [string]: boolean } = {}

	for offsetY = -verticalRenderDistance, verticalRenderDistance do
		local chunkY = centerChunkY + offsetY
		if not isChunkYWithinBounds(self.config, chunkY) then
			continue
		end

		for offsetX = -renderDistance, renderDistance do
			if offsetX * offsetX + offsetY * offsetY > radiusSquared then
				continue
			end
			local chunkX = centerChunkX + offsetX
			nextInterest[packChunkKey(chunkX, chunkY)] = true
		end
	end

	return nextInterest
end

function WorldGenerationServiceServer.ApplyStudioPreviewInterest(
	self: WorldGenerationServiceServer,
	nextInterest: { [string]: boolean }
)
	for chunkKey in nextInterest do
		if self.studioPreviewInterestKeys[chunkKey] then
			continue
		end
		self.world:AdjustChunkDemand(chunkKey, 1)
	end

	for chunkKey in self.studioPreviewInterestKeys do
		if nextInterest[chunkKey] then
			continue
		end
		self.world:AdjustChunkDemand(chunkKey, -1)
	end

	self.studioPreviewInterestKeys = nextInterest
end

function WorldGenerationServiceServer.EnableStudioPreview(self: WorldGenerationServiceServer)
	if not self.studioPreviewEnabled then
		return
	end
	if self.studioPreviewActive then
		return
	end
	self.studioPreviewActive = true
	self:ApplyStudioPreviewInterest(self:BuildStudioPreviewInterest())
end

function WorldGenerationServiceServer.DisableStudioPreview(self: WorldGenerationServiceServer)
	if not self.studioPreviewActive then
		return
	end
	self.studioPreviewActive = false
	self:ApplyStudioPreviewInterest({})
end

function WorldGenerationServiceServer.GetOrCreatePlayerRenderSettings(
	self: WorldGenerationServiceServer,
	player: Player
): PlayerRenderSettings
	local existing = self.playerRenderSettings[player]
	if existing then
		return existing
	end

	local settings: PlayerRenderSettings = {
		renderDistanceChunks = self.config.defaultRenderDistanceChunks,
		verticalRenderDistanceChunks = self.config.defaultVerticalRenderDistanceChunks,
	}
	self.playerRenderSettings[player] = settings
	return settings
end

function WorldGenerationServiceServer.CreateStateSnapshot(
	self: WorldGenerationServiceServer,
	player: Player
): WorldGenerationServiceState
	local renderSettings = self:GetOrCreatePlayerRenderSettings(player)
	local stats = cloneTableShallow(self.latestWorldStats or self.world:GetStats())
	stats.boundCollisionChunkModels = self.boundChunkRuntimeCount
	local snapshot = WorldGenerationServiceUtils.CreateState({
		seed = self.config.seed,
		chunkSize = self.config.chunkSize,
		tileSize = self.world.tileSize,
		tileDepth = self.world.tileDepth,
		renderDistanceChunks = renderSettings.renderDistanceChunks,
		verticalRenderDistanceChunks = renderSettings.verticalRenderDistanceChunks,
		minTileY = self.config.minTileY,
		maxTileY = self.config.maxTileY,
		ready = true,
		stats = stats,
	}, nil)
	return snapshot
end

function WorldGenerationServiceServer.PushState(self: WorldGenerationServiceServer, player: Player)
	local snapshot = self:CreateStateSnapshot(player)
	sendPacket(player, "applyState", snapshot)
	self:EmitStateChanged(player, snapshot)
end

function WorldGenerationServiceServer.CreateChunkSendQueue(_self: WorldGenerationServiceServer): ChunkSendQueue
	return {
		sendQueue = {},
		sendQueueHead = 1,
		sendQueueTail = 0,
		queuedLookup = {},
	}
end

function WorldGenerationServiceServer.CreateChunkStream(self: WorldGenerationServiceServer): PlayerChunkStream
	local sendQueue = self:CreateChunkSendQueue()
	return {
		interestKeys = {},
		sentRevisions = {},
		sendQueue = sendQueue.sendQueue,
		sendQueueHead = sendQueue.sendQueueHead,
		sendQueueTail = sendQueue.sendQueueTail,
		queuedLookup = sendQueue.queuedLookup,
	}
end

function WorldGenerationServiceServer.ObserveStateChanged(
	self: WorldGenerationServiceServer,
	playerRaw: any?
): ObservableObject
	local targetPlayer = if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then playerRaw else nil
	return Rx.fromSignal(self._stateChangedSignal):Pipe({
		Rx.where(function(player: Player)
			return targetPlayer == nil or player == targetPlayer
		end),
	}) :: ObservableObject
end

function WorldGenerationServiceServer.EmitStateChanged(
	self: WorldGenerationServiceServer,
	player: Player,
	snapshot: WorldGenerationServiceState
)
	self._stateChangedSignal:Fire(player, snapshot)
end

function WorldGenerationServiceServer.MarkPlayerStreamDirty(
	self: WorldGenerationServiceServer,
	player: Player,
	interestOverrideRaw: any?
)
	if self.playerRenderSettings[player] == nil then
		return
	end

	self.playersPendingSync[player] = true
	if typeof(interestOverrideRaw) == "table" then
		self.pendingPlayerInterest[player] = cloneBooleanLookup(interestOverrideRaw)
	end
end

function WorldGenerationServiceServer.QueueChunkForInterestedPlayers(
	self: WorldGenerationServiceServer,
	chunkKeyRaw: any,
	revisionRaw: number?
)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end

	local revision = revisionRaw
	if revision == nil then
		revision = self.world:GetChunkRevisionByKey(chunkKeyRaw)
	end

	for _, player in self.world:GetPlayersInterestedInChunk(chunkKeyRaw) do
		local stream = self:GetOrCreateChunkStream(player)
		if stream.interestKeys[chunkKeyRaw] == true then
			enqueueChunkForStream(stream, chunkKeyRaw)
		end
	end

	self:EnqueueChunkForWorldSimulation(chunkKeyRaw, revision)
end

function WorldGenerationServiceServer.ConnectReactiveWorldObservers(self: WorldGenerationServiceServer)
	local observerMaid = self.worldObserverMaid
	observerMaid:DoCleaning()

	observerMaid:GiveTask(self.world:ObserveStats():Subscribe(function(stats)
		if typeof(stats) == "table" then
			self.latestWorldStats = stats
		end
	end))

	observerMaid:GiveTask(self.world:ObservePlayerInterest():Subscribe(function(event: PlayerInterestChangedEvent)
		if typeof(event) ~= "table" then
			return
		end
		if typeof(event.player) ~= "Instance" or not event.player:IsA("Player") then
			return
		end
		self:MarkPlayerStreamDirty(event.player, event.interestKeys)
	end))

	observerMaid:GiveTask(self.world:ObserveChunkCollisionReady():Subscribe(function(event: ChunkLifecycleEvent)
		if typeof(event) ~= "table" then
			return
		end
		self:QueueChunkForInterestedPlayers(event.chunkKey)
	end))

	observerMaid:GiveTask(self.world:ObserveChunkTerrainChanged():Subscribe(function(event: ChunkLifecycleEvent)
		if typeof(event) ~= "table" then
			return
		end
		self:QueueChunkForInterestedPlayers(event.chunkKey)
	end))

	observerMaid:GiveTask(self.world:ObserveChunkCollisionUnloaded():Subscribe(function(event: ChunkLifecycleEvent)
		if typeof(event) ~= "table" or typeof(event.chunkKey) ~= "string" then
			return
		end
		self.worldSimulationSentRevisions[event.chunkKey] = nil
	end))
end

function WorldGenerationServiceServer.ConnectChunkBinderObservers(self: WorldGenerationServiceServer)
	if self.chunkBinder == nil then
		return
	end

	self.maid:GiveTask(self.chunkBinder:ObserveAllBrio():Subscribe(function(brio)
		if brio == nil or typeof(brio) ~= "table" or typeof((brio :: any).GetValue) ~= "function" then
			return
		end

		local runtime = brio:GetValue()
		if runtime == nil then
			return
		end

		local chunkKey = if typeof((runtime :: any).GetChunkKey) == "function"
			then (runtime :: any):GetChunkKey()
			else ((runtime :: any).chunkKey or "")
		if typeof(chunkKey) ~= "string" or chunkKey == "" then
			return
		end

		local brioMaid = brio:ToMaid()
		self.chunkRuntimeByKey[chunkKey] = runtime
		self.boundChunkRuntimeCount = countLookupEntries(self.chunkRuntimeByKey)
		brioMaid:GiveTask(function()
			if self.chunkRuntimeByKey[chunkKey] == runtime then
				self.chunkRuntimeByKey[chunkKey] = nil
			end
			self.boundChunkRuntimeCount = countLookupEntries(self.chunkRuntimeByKey)
		end)
	end))
end

function WorldGenerationServiceServer.PushSeedToWorldSimulation(self: WorldGenerationServiceServer)
	local setAuthoritativeSeedMethod = (WorldSimulationServiceServer :: any).SetAuthoritativeSeed
	if typeof(setAuthoritativeSeedMethod) ~= "function" then
		return
	end
	pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:SetAuthoritativeSeed(self.config.seed)
	end)
end

function WorldGenerationServiceServer.PushPlayerInterestToWorldSimulation(
	_self: WorldGenerationServiceServer,
	player: Player,
	interestKeys: { [string]: boolean }
)
	local hasAnyInterest = false
	for _ in interestKeys do
		hasAnyInterest = true
		break
	end

	if not hasAnyInterest then
		local clearInterestMethod = (WorldSimulationServiceServer :: any).ClearGeneratedPlayerInterest
		if typeof(clearInterestMethod) == "function" then
			pcall(function()
				local worldSimulationServiceAny = WorldSimulationServiceServer :: any
				worldSimulationServiceAny:ClearGeneratedPlayerInterest(player)
			end)
			return
		end
	end

	local pushInterestMethod = (WorldSimulationServiceServer :: any).PushGeneratedPlayerInterest
	if typeof(pushInterestMethod) ~= "function" then
		return
	end
	pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:PushGeneratedPlayerInterest(player, interestKeys)
	end)
end

function WorldGenerationServiceServer.PushChunkSnapshotToWorldSimulation(
	_self: WorldGenerationServiceServer,
	snapshotRaw: any
): boolean
	local registerChunkMethod = (WorldSimulationServiceServer :: any).RegisterGeneratedChunkSnapshot
	if typeof(registerChunkMethod) ~= "function" then
		return false
	end
	local ok = pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:RegisterGeneratedChunkSnapshot(snapshotRaw)
	end)
	return ok
end

function WorldGenerationServiceServer.PushPlayerRenderDistanceToWorldSimulation(
	_self: WorldGenerationServiceServer,
	player: Player,
	renderDistance: number,
	verticalRenderDistance: number
)
	local setStreamRadiusMethod = (WorldSimulationServiceServer :: any).SetStreamRadius
	if typeof(setStreamRadiusMethod) ~= "function" then
		return
	end
	pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:SetStreamRadius(player, renderDistance, verticalRenderDistance)
	end)
end

function WorldGenerationServiceServer.GetOrCreateChunkStream(
	self: WorldGenerationServiceServer,
	player: Player
): PlayerChunkStream
	local existing = self.playerChunkStreams[player]
	if existing ~= nil then
		return existing
	end

	local stream = self:CreateChunkStream()
	self.playerChunkStreams[player] = stream
	return stream
end

function WorldGenerationServiceServer.ResetChunkStream(self: WorldGenerationServiceServer, player: Player)
	local stream = self:GetOrCreateChunkStream(player)
	table.clear(stream.sentRevisions)
	table.clear(stream.queuedLookup)
	table.clear(stream.sendQueue)
	stream.sendQueueHead = 1
	stream.sendQueueTail = 0
	self.pendingPlayerInterest[player] = nil
end

function WorldGenerationServiceServer.EnqueueChunkForWorldSimulation(
	self: WorldGenerationServiceServer,
	chunkKey: string,
	revisionRaw: number?
)
	local revision = revisionRaw
	if revision == nil then
		revision = self.world:GetChunkRevisionByKey(chunkKey)
	end
	if self.worldSimulationSentRevisions[chunkKey] == revision then
		return
	end
	enqueueChunkForStream(self.worldSimulationChunkQueue, chunkKey)
end

function WorldGenerationServiceServer.EnqueueAffectedWorldSimulationChunkKeysForTile(
	self: WorldGenerationServiceServer,
	tileX: number,
	tileY: number
)
	local chunkSize = self.config.chunkSize
	local chunkX = math.floor(tileX / chunkSize)
	local chunkY = math.floor(tileY / chunkSize)
	if not isChunkYWithinBounds(self.config, chunkY) then
		return
	end

	local localTileX = tileX - chunkX * chunkSize
	local localTileY = tileY - chunkY * chunkSize
	self:EnqueueChunkForWorldSimulation(packChunkKey(chunkX, chunkY))

	if localTileX == 0 then
		self:EnqueueChunkForWorldSimulation(packChunkKey(chunkX - 1, chunkY))
	elseif localTileX == chunkSize - 1 then
		self:EnqueueChunkForWorldSimulation(packChunkKey(chunkX + 1, chunkY))
	end

	if localTileY == 0 then
		local belowChunkY = chunkY - 1
		if isChunkYWithinBounds(self.config, belowChunkY) then
			self:EnqueueChunkForWorldSimulation(packChunkKey(chunkX, belowChunkY))
		end
	elseif localTileY == chunkSize - 1 then
		local aboveChunkY = chunkY + 1
		if isChunkYWithinBounds(self.config, aboveChunkY) then
			self:EnqueueChunkForWorldSimulation(packChunkKey(chunkX, aboveChunkY))
		end
	end
end

function WorldGenerationServiceServer.SyncPlayerChunkStream(
	self: WorldGenerationServiceServer,
	player: Player,
	stream: PlayerChunkStream,
	nextInterestRaw: { [string]: boolean }?
)
	local world = self.world
	local nextInterest = if typeof(nextInterestRaw) == "table"
		then cloneBooleanLookup(nextInterestRaw)
		else world:GetPlayerInterestKeys(player)
	self:PushPlayerInterestToWorldSimulation(player, nextInterest)

	for _, chunkKey in collectSortedInterestKeys(world, player, nextInterest) do
		local revision = world:GetChunkRevisionByKey(chunkKey)
		self:EnqueueChunkForWorldSimulation(chunkKey, revision)
		if not world:IsChunkCollisionReadyByKey(chunkKey) then
			continue
		end
		if stream.sentRevisions[chunkKey] ~= revision or stream.interestKeys[chunkKey] == nil then
			enqueueChunkForStream(stream, chunkKey)
		end
	end

	for chunkKey in stream.interestKeys do
		if nextInterest[chunkKey] then
			continue
		end
		stream.sentRevisions[chunkKey] = nil
		sendPacket(player, "onChunkUnloaded", chunkKey)
	end

	stream.interestKeys = nextInterest
end

function WorldGenerationServiceServer.ProcessChunkStreamQueues(self: WorldGenerationServiceServer)
	local totalProcessed = 0

	for player, stream in self.playerChunkStreams do
		if totalProcessed >= CHUNK_STREAM_GLOBAL_BUDGET_PER_TICK then
			break
		end

		local perPlayerProcessed = 0
		while
			perPlayerProcessed < CHUNK_STREAM_PER_PLAYER_BUDGET_PER_TICK
			and totalProcessed < CHUNK_STREAM_GLOBAL_BUDGET_PER_TICK
		do
			local chunkKey = dequeueChunkForStream(stream)
			if chunkKey == nil then
				break
			end
			if stream.interestKeys[chunkKey] == nil then
				continue
			end

			local revision = self.world:GetChunkRevisionByKey(chunkKey)
			if stream.sentRevisions[chunkKey] == revision then
				continue
			end
			if not self.world:IsChunkCollisionReadyByKey(chunkKey) then
				continue
			end

			local snapshot = self.world:GetChunkSnapshotByKey(chunkKey)
			if snapshot == nil then
				continue
			end

			sendPacket(player, "onChunkSnapshot", snapshot)
			stream.sentRevisions[chunkKey] = revision
			perPlayerProcessed += 1
			totalProcessed += 1
		end
	end
end

function WorldGenerationServiceServer.ProcessWorldSimulationChunkQueue(self: WorldGenerationServiceServer)
	local processed = 0
	local maxProcessed = CHUNK_STREAM_SIMULATION_BUDGET_PER_TICK
	local world = self.world

	while processed < maxProcessed do
		local chunkKey = dequeueChunkForStream(self.worldSimulationChunkQueue)
		if chunkKey == nil then
			break
		end

		local revision = world:GetChunkRevisionByKey(chunkKey)
		if self.worldSimulationSentRevisions[chunkKey] == revision then
			continue
		end

		local snapshot = world:GetChunkSnapshotByKey(chunkKey)
		if snapshot == nil then
			continue
		end

		if not self:PushChunkSnapshotToWorldSimulation(snapshot) then
			enqueueChunkForStream(self.worldSimulationChunkQueue, chunkKey)
			break
		end

		self.worldSimulationSentRevisions[chunkKey] = revision
		processed += 1
	end
end

function WorldGenerationServiceServer.OnHeartbeat(self: WorldGenerationServiceServer, deltaTime: number)
	self.chunkStreamAccumulator += deltaTime
	if self.chunkStreamAccumulator < CHUNK_STREAM_SYNC_INTERVAL then
		return
	end
	self.chunkStreamAccumulator = 0

	for player in self.playersPendingSync do
		local stream = self:GetOrCreateChunkStream(player)
		self:SyncPlayerChunkStream(player, stream, self.pendingPlayerInterest[player])
		self.playersPendingSync[player] = nil
		self.pendingPlayerInterest[player] = nil
	end

	self:ProcessChunkStreamQueues()
	self:ProcessWorldSimulationChunkQueue()
end

function WorldGenerationServiceServer.TrackPlayer(self: WorldGenerationServiceServer, player: Player)
	if self.worldBootstrapPlayerUserId == nil then
		self.worldBootstrapPlayerUserId = player.UserId
		if self.studioPreviewActive then
			self:DisableStudioPreview()
		end
	end

	local renderSettings = self:GetOrCreatePlayerRenderSettings(player)
	self.world:TrackPlayer(player, renderSettings.renderDistanceChunks, renderSettings.verticalRenderDistanceChunks)
	self:PushPlayerRenderDistanceToWorldSimulation(
		player,
		renderSettings.renderDistanceChunks,
		renderSettings.verticalRenderDistanceChunks
	)
	self:ResetChunkStream(player)
	self:MarkPlayerStreamDirty(player, self.world:GetPlayerInterestKeys(player))
	self:PushState(player)
end

function WorldGenerationServiceServer.UntrackPlayer(self: WorldGenerationServiceServer, player: Player)
	self.playerRenderSettings[player] = nil
	self.playerChunkStreams[player] = nil
	self.playersPendingSync[player] = nil
	self.pendingPlayerInterest[player] = nil
	self.world:UntrackPlayer(player)
	self:PushPlayerInterestToWorldSimulation(player, {})
end

function WorldGenerationServiceServer.RequestSync(self: WorldGenerationServiceServer, player: Player)
	if self.playerRenderSettings[player] == nil then
		self:TrackPlayer(player)
		return
	end
	self:ResetChunkStream(player)
	self:MarkPlayerStreamDirty(player, self.world:GetPlayerInterestKeys(player))
	self:PushState(player)
end

function WorldGenerationServiceServer.SetRenderDistance(
	self: WorldGenerationServiceServer,
	player: Player,
	renderDistanceRaw: any,
	verticalRenderDistanceRaw: any?
)
	local renderSettings = self:GetOrCreatePlayerRenderSettings(player)
	local nextRenderDistance =
		WorldGenerationServiceUtils.CoerceRenderDistance(renderDistanceRaw, renderSettings.renderDistanceChunks)
	local nextVerticalRenderDistance = WorldGenerationServiceUtils.CoerceVerticalRenderDistance(
		verticalRenderDistanceRaw,
		renderSettings.verticalRenderDistanceChunks
	)

	renderSettings.renderDistanceChunks = nextRenderDistance
	renderSettings.verticalRenderDistanceChunks = nextVerticalRenderDistance
	self.world:SetPlayerRenderDistance(player, nextRenderDistance, nextVerticalRenderDistance)
	self:PushPlayerRenderDistanceToWorldSimulation(player, nextRenderDistance, nextVerticalRenderDistance)
	self:ResetChunkStream(player)
	self:MarkPlayerStreamDirty(player, self.world:GetPlayerInterestKeys(player))
	self:PushState(player)
end

function WorldGenerationServiceServer.GetWorld(self: WorldGenerationServiceServer): WorldGenerationClass
	return self.world
end

function WorldGenerationServiceServer.SetTileAt(
	self: WorldGenerationServiceServer,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any
): (boolean, number, number)
	local changed, previousTileId, nextTileId = self.world:SetTileAt(tileXRaw, tileYRaw, tileIdRaw)
	if changed and isFiniteNumber(tileXRaw) and isFiniteNumber(tileYRaw) then
		self:EnqueueAffectedWorldSimulationChunkKeysForTile(math.floor(tileXRaw), math.floor(tileYRaw))
	end
	return changed, previousTileId, nextTileId
end

function WorldGenerationServiceServer.GetBiomeTypeAt(
	self: WorldGenerationServiceServer,
	tileXRaw: any,
	tileYRaw: any
): number
	return self.world:GetBiomeTypeAt(tileXRaw, tileYRaw)
end

function WorldGenerationServiceServer.GetBiomeTypeAtWorldPosition(
	self: WorldGenerationServiceServer,
	worldPosition: Vector3
): number
	return self.world:GetBiomeTypeAtWorldPosition(worldPosition)
end

function WorldGenerationServiceServer.SetBiomeTypeAt(
	self: WorldGenerationServiceServer,
	tileXRaw: any,
	tileYRaw: any,
	biomeTypeRaw: any
): (boolean, number, number)
	local changed, previousBiomeType, nextBiomeType = self.world:SetBiomeTypeAt(tileXRaw, tileYRaw, biomeTypeRaw)
	if changed and isFiniteNumber(tileXRaw) and isFiniteNumber(tileYRaw) then
		self:EnqueueAffectedWorldSimulationChunkKeysForTile(math.floor(tileXRaw), math.floor(tileYRaw))
	end
	return changed, previousBiomeType, nextBiomeType
end

function WorldGenerationServiceServer.SetTileAtWorldPosition(
	self: WorldGenerationServiceServer,
	worldPosition: Vector3,
	tileIdRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.world.worldOrigin.Z, self.world.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.world.worldOrigin.Y, self.world.tileSize)
	return self:SetTileAt(tileX, tileY, tileIdRaw)
end

function WorldGenerationServiceServer.SetBiomeTypeAtWorldPosition(
	self: WorldGenerationServiceServer,
	worldPosition: Vector3,
	biomeTypeRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.world.worldOrigin.Z, self.world.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.world.worldOrigin.Y, self.world.tileSize)
	return self:SetBiomeTypeAt(tileX, tileY, biomeTypeRaw)
end

function WorldGenerationServiceServer.GetConfig(self: WorldGenerationServiceServer): WorldGenerationConfig
	return self.config
end

function WorldGenerationServiceServer.Destroy(self: WorldGenerationServiceServer)
	self:DisableStudioPreview()
	if self.worldObserverMaid ~= nil then
		self.worldObserverMaid:DoCleaning()
	end

	local playersToUntrack = {}
	for player in self.playerRenderSettings do
		table.insert(playersToUntrack, player)
	end
	for _, player in playersToUntrack do
		self:UntrackPlayer(player)
	end
	table.clear(self.playerChunkStreams)
	table.clear(self.playersPendingSync)
	table.clear(self.pendingPlayerInterest)
	table.clear(self.chunkRuntimeByKey)

	if self.world then
		self.world:Destroy()
	end

	if self.maid ~= nil then
		self.maid:Destroy()
	end
	self.heartbeatConnection = nil
	self.playerAddedConnection = nil
	self.playerRemovingConnection = nil
end
type WorldGenerationServiceServer = typeof(WorldGenerationServiceServer) & {
	maid: MaidClass,
	world: WorldGenerationClass,
	config: WorldGenerationConfig,
	binders: any,
	chunkBinder: any,
	playerRenderSettings: { [Player]: PlayerRenderSettings },
	playersPendingSync: { [Player]: boolean },
	pendingPlayerInterest: { [Player]: { [string]: boolean } },
	studioPreviewEnabled: boolean,
	studioPreviewActive: boolean,
	studioPreviewInterestKeys: { [string]: boolean },
	worldBootstrapPlayerUserId: number?,
	playerChunkStreams: { [Player]: PlayerChunkStream },
	worldSimulationChunkQueue: ChunkSendQueue,
	worldSimulationSentRevisions: { [string]: number },
	chunkRuntimeByKey: { [string]: any },
	boundChunkRuntimeCount: number,
	latestWorldStats: { [string]: any },
	chunkStreamAccumulator: number,
	worldObserverMaid: MaidClass,
	_stateChangedSignal: SignalObject,
	stateChangedSignal: RxSignalObject,
	heartbeatConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return WorldGenerationServiceServer :: WorldGenerationServiceServer
