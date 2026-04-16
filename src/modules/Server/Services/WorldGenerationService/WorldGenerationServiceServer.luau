--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local WorldGeneration = require(script:FindFirstAncestor("game").Shared.Classes.WorldGeneration)
local WorldGenerationServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.WorldGenerationService.WorldGenerationServiceUtils)
local WorldSimulationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldSimulationService.WorldSimulationServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)

type WorldGenerationClass = WorldGeneration.WorldGeneration
type WorldGenerationConfig = WorldGenerationServiceUtils.WorldGenerationConfig
type WorldGenerationServiceState = WorldGenerationServiceUtils.WorldGenerationServiceState

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

local MIN_INT32_SEED = -2147483648
local MAX_INT32_SEED = 2147483647
local CHUNK_STREAM_SYNC_INTERVAL = 0.08
local CHUNK_STREAM_GLOBAL_BUDGET_PER_TICK = 12
local CHUNK_STREAM_PER_PLAYER_BUDGET_PER_TICK = 3
local CHUNK_STREAM_SIMULATION_BUDGET_PER_TICK = 24
local CHUNK_STREAM_MAX_QUEUE_PER_PLAYER = 4096

local function resolveConfigSource(): any
	if typeof(Configs) ~= "table" then
		return nil
	end
	return (Configs :: any).worldGeneration
end

local function cloneTableShallow(sourceRaw: any): { [any]: any }
	local source = if typeof(sourceRaw) == "table" then sourceRaw else {}
	local clone = {}
	for key, value in source do
		clone[key] = value
	end
	return clone
end

local function isGameplayReplicationActive(player: Player): boolean
	local activeCheck = (PlayerServiceServer :: any).isGameplayActiveForPlayer
	if typeof(activeCheck) ~= "function" then
		return true
	end
	local ok, isActive = pcall(function()
		return (PlayerServiceServer :: any):isGameplayActiveForPlayer(player)
	end)
	return ok and isActive == true
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

local function resolveRuntimeSeed(configSource: any, sanitizedConfig: WorldGenerationConfig): number
	if hasExplicitSeed(configSource) then
		return sanitizedConfig.seed
	end
	return Random.new():NextInteger(MIN_INT32_SEED, MAX_INT32_SEED)
end

local function resolveStudioPreviewEnabled(configSource: any): boolean
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

local function toTileCoordinate(worldAxis: number, tileSize: number): number
	return math.floor(worldAxis / tileSize)
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
	local configSource = resolveConfigSource()
	self.config = WorldGenerationServiceUtils.sanitizeConfig(configSource, nil)
	self.config.seed = resolveRuntimeSeed(configSource, self.config)
	self.world = WorldGeneration.new(self.config)
	self.world:init()
	self:pushSeedToWorldSimulation()
	self.studioPreviewEnabled = RunService:IsStudio() and resolveStudioPreviewEnabled(configSource)
	self.studioPreviewInterestKeys = {}
	self.studioPreviewActive = false
	self.worldBootstrapPlayerUserId = nil

	self.playerRenderSettings = {}
	self.playerChunkStreams = {}
	self.worldSimulationChunkQueue = self:createChunkSendQueue()
	self.worldSimulationSentRevisions = {}
	self.chunkStreamAccumulator = CHUNK_STREAM_SYNC_INTERVAL
	self.networker = Networker.server.new("WorldGenerationService", self, {
		self.RequestSync,
		self.SetRenderDistance,
	})

	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:onHeartbeat(deltaTime)
	end)

	if self.studioPreviewEnabled and self.worldBootstrapPlayerUserId == nil and next(self.playerRenderSettings) == nil then
		self:enableStudioPreview()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if isGameplayReplicationActive(player) then
			self:trackPlayer(player)
		end
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
		if self.studioPreviewEnabled and self.worldBootstrapPlayerUserId == nil and next(self.playerRenderSettings) == nil then
			self:enableStudioPreview()
		end
	end)
end

function WorldGenerationServiceServer.ResetStreamingState(self: WorldGenerationServiceServer)
	for player, stream in self.playerChunkStreams do
		if self.networker ~= nil then
			for chunkKey in stream.interestKeys do
				self.networker:fire(player, "onChunkUnloaded", chunkKey)
			end
		end

		table.clear(stream.interestKeys)
		table.clear(stream.sentRevisions)
		table.clear(stream.queuedLookup)
		table.clear(stream.sendQueue)
		stream.sendQueueHead = 1
		stream.sendQueueTail = 0
		self:pushPlayerInterestToWorldSimulation(player, {})
	end

	table.clear(self.worldSimulationSentRevisions)
	table.clear(self.worldSimulationChunkQueue.sendQueue)
	table.clear(self.worldSimulationChunkQueue.queuedLookup)
	self.worldSimulationChunkQueue.sendQueueHead = 1
	self.worldSimulationChunkQueue.sendQueueTail = 0
end

function WorldGenerationServiceServer.LoadWorld(self: WorldGenerationServiceServer, worldRaw: any)
	local worldSource = if typeof(worldRaw) == "table" then worldRaw else {}
	local configSource = cloneTableShallow(resolveConfigSource())
	for key, value in worldSource do
		if key == "seed" or key == "worldOrigin" or key == "minTileY" or key == "maxTileY" or key == "bedrockThickness" then
			configSource[key] = value
		end
	end

	local nextConfig = WorldGenerationServiceUtils.sanitizeConfig(configSource, nil)
	nextConfig.seed = resolveRuntimeSeed(configSource, nextConfig)

	self:disableStudioPreview()
	self:resetStreamingState()

	if self.world ~= nil then
		self.world:destroy()
	end

	self.config = nextConfig
	self.world = WorldGeneration.new(self.config)
	self.world:init()
	self:pushSeedToWorldSimulation()

	for _, player in Players:GetPlayers() do
		self:trackPlayer(player)
	end

	if self.studioPreviewEnabled and self.worldBootstrapPlayerUserId == nil and next(self.playerRenderSettings) == nil then
		self:enableStudioPreview()
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
		self.world:adjustChunkDemand(chunkKey, 1)
	end

	for chunkKey in self.studioPreviewInterestKeys do
		if nextInterest[chunkKey] then
			continue
		end
		self.world:adjustChunkDemand(chunkKey, -1)
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
	self:applyStudioPreviewInterest(self:buildStudioPreviewInterest())
end

function WorldGenerationServiceServer.DisableStudioPreview(self: WorldGenerationServiceServer)
	if not self.studioPreviewActive then
		return
	end
	self.studioPreviewActive = false
	self:applyStudioPreviewInterest({})
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
	local renderSettings = self:getOrCreatePlayerRenderSettings(player)
	local snapshot = WorldGenerationServiceUtils.createState({
		seed = self.config.seed,
		chunkSize = self.config.chunkSize,
		tileSize = self.world.tileSize,
		tileDepth = self.world.tileDepth,
		renderDistanceChunks = renderSettings.renderDistanceChunks,
		verticalRenderDistanceChunks = renderSettings.verticalRenderDistanceChunks,
		minTileY = self.config.minTileY,
		maxTileY = self.config.maxTileY,
		ready = true,
		stats = self.world:getStats(),
	}, nil)
	return snapshot
end

function WorldGenerationServiceServer.PushState(self: WorldGenerationServiceServer, player: Player)
	if self.networker == nil then
		return
	end

	self.networker:fire(player, "applyState", self:createStateSnapshot(player))
end

function WorldGenerationServiceServer.CreateChunkSendQueue(self: WorldGenerationServiceServer): ChunkSendQueue
	return {
		sendQueue = {},
		sendQueueHead = 1,
		sendQueueTail = 0,
		queuedLookup = {},
	}
end

function WorldGenerationServiceServer.CreateChunkStream(self: WorldGenerationServiceServer): PlayerChunkStream
	local sendQueue = self:createChunkSendQueue()
	return {
		interestKeys = {},
		sentRevisions = {},
		sendQueue = sendQueue.sendQueue,
		sendQueueHead = sendQueue.sendQueueHead,
		sendQueueTail = sendQueue.sendQueueTail,
		queuedLookup = sendQueue.queuedLookup,
	}
end

function WorldGenerationServiceServer.PushSeedToWorldSimulation(self: WorldGenerationServiceServer)
	local setAuthoritativeSeedMethod = (WorldSimulationServiceServer :: any).setAuthoritativeSeed
	if typeof(setAuthoritativeSeedMethod) ~= "function" then
		return
	end
	pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:setAuthoritativeSeed(self.config.seed)
	end)
end

function WorldGenerationServiceServer.PushPlayerInterestToWorldSimulation(
	self: WorldGenerationServiceServer,
	player: Player,
	interestKeys: { [string]: boolean }
)
	local hasAnyInterest = false
	for _ in interestKeys do
		hasAnyInterest = true
		break
	end

	if not hasAnyInterest then
		local clearInterestMethod = (WorldSimulationServiceServer :: any).clearGeneratedPlayerInterest
		if typeof(clearInterestMethod) == "function" then
			pcall(function()
				local worldSimulationServiceAny = WorldSimulationServiceServer :: any
				worldSimulationServiceAny:clearGeneratedPlayerInterest(player)
			end)
			return
		end
	end

	local pushInterestMethod = (WorldSimulationServiceServer :: any).pushGeneratedPlayerInterest
	if typeof(pushInterestMethod) ~= "function" then
		return
	end
	pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:pushGeneratedPlayerInterest(player, interestKeys)
	end)
end

function WorldGenerationServiceServer.PushChunkSnapshotToWorldSimulation(
	self: WorldGenerationServiceServer,
	snapshotRaw: any
): boolean
	local registerChunkMethod = (WorldSimulationServiceServer :: any).registerGeneratedChunkSnapshot
	if typeof(registerChunkMethod) ~= "function" then
		return false
	end
	local ok = pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:registerGeneratedChunkSnapshot(snapshotRaw)
	end)
	return ok
end

function WorldGenerationServiceServer.PushPlayerRenderDistanceToWorldSimulation(
	self: WorldGenerationServiceServer,
	player: Player,
	renderDistance: number,
	verticalRenderDistance: number
)
	local setStreamRadiusMethod = (WorldSimulationServiceServer :: any).setStreamRadius
	if typeof(setStreamRadiusMethod) ~= "function" then
		return
	end
	pcall(function()
		local worldSimulationServiceAny = WorldSimulationServiceServer :: any
		worldSimulationServiceAny:setStreamRadius(player, renderDistance, verticalRenderDistance)
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

	local stream = self:createChunkStream()
	self.playerChunkStreams[player] = stream
	return stream
end

function WorldGenerationServiceServer.ResetChunkStream(self: WorldGenerationServiceServer, player: Player)
	local stream = self:getOrCreateChunkStream(player)
	table.clear(stream.sentRevisions)
	table.clear(stream.queuedLookup)
	table.clear(stream.sendQueue)
	stream.sendQueueHead = 1
	stream.sendQueueTail = 0
end

function WorldGenerationServiceServer.EnqueueChunkForWorldSimulation(
	self: WorldGenerationServiceServer,
	chunkKey: string,
	revisionRaw: number?
)
	local revision = revisionRaw
	if revision == nil then
		revision = self.world:getChunkRevisionByKey(chunkKey)
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
	self:enqueueChunkForWorldSimulation(packChunkKey(chunkX, chunkY))

	if localTileX == 0 then
		self:enqueueChunkForWorldSimulation(packChunkKey(chunkX - 1, chunkY))
	elseif localTileX == chunkSize - 1 then
		self:enqueueChunkForWorldSimulation(packChunkKey(chunkX + 1, chunkY))
	end

	if localTileY == 0 then
		local belowChunkY = chunkY - 1
		if isChunkYWithinBounds(self.config, belowChunkY) then
			self:enqueueChunkForWorldSimulation(packChunkKey(chunkX, belowChunkY))
		end
	elseif localTileY == chunkSize - 1 then
		local aboveChunkY = chunkY + 1
		if isChunkYWithinBounds(self.config, aboveChunkY) then
			self:enqueueChunkForWorldSimulation(packChunkKey(chunkX, aboveChunkY))
		end
	end
end

function WorldGenerationServiceServer.SyncPlayerChunkStream(
	self: WorldGenerationServiceServer,
	player: Player,
	stream: PlayerChunkStream
)
	local world = self.world
	local nextInterest = world:getPlayerInterestKeys(player)
	self:pushPlayerInterestToWorldSimulation(player, nextInterest)

	for chunkKey in nextInterest do
		local revision = world:getChunkRevisionByKey(chunkKey)
		self:enqueueChunkForWorldSimulation(chunkKey, revision)
		if stream.sentRevisions[chunkKey] ~= revision then
			enqueueChunkForStream(stream, chunkKey)
		elseif stream.interestKeys[chunkKey] == nil then
			enqueueChunkForStream(stream, chunkKey)
		end
	end

	for chunkKey in stream.interestKeys do
		if nextInterest[chunkKey] then
			continue
		end
		stream.sentRevisions[chunkKey] = nil
		if self.networker then
			self.networker:fire(player, "onChunkUnloaded", chunkKey)
		end
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
		while perPlayerProcessed < CHUNK_STREAM_PER_PLAYER_BUDGET_PER_TICK
			and totalProcessed < CHUNK_STREAM_GLOBAL_BUDGET_PER_TICK do
			local chunkKey = dequeueChunkForStream(stream)
			if chunkKey == nil then
				break
			end
			if stream.interestKeys[chunkKey] == nil then
				continue
			end

			local revision = self.world:getChunkRevisionByKey(chunkKey)
			if stream.sentRevisions[chunkKey] == revision then
				continue
			end

			local snapshot = self.world:getChunkSnapshotByKey(chunkKey)
			if snapshot == nil then
				continue
			end

			if self.networker then
				self.networker:fire(player, "onChunkSnapshot", snapshot)
			end
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

		local revision = world:getChunkRevisionByKey(chunkKey)
		if self.worldSimulationSentRevisions[chunkKey] == revision then
			continue
		end

		local snapshot = world:getChunkSnapshotByKey(chunkKey)
		if snapshot == nil then
			continue
		end

		if not self:pushChunkSnapshotToWorldSimulation(snapshot) then
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

	for player in self.playerRenderSettings do
		local stream = self:getOrCreateChunkStream(player)
		self:syncPlayerChunkStream(player, stream)
	end

	self:processChunkStreamQueues()
	self:processWorldSimulationChunkQueue()
end

function WorldGenerationServiceServer.TrackPlayer(self: WorldGenerationServiceServer, player: Player)
	if self.worldBootstrapPlayerUserId == nil then
		self.worldBootstrapPlayerUserId = player.UserId
		if self.studioPreviewActive then
			self:disableStudioPreview()
		end
	end

	local renderSettings = self:getOrCreatePlayerRenderSettings(player)
	self.world:trackPlayer(player, renderSettings.renderDistanceChunks, renderSettings.verticalRenderDistanceChunks)
	self:pushPlayerRenderDistanceToWorldSimulation(
		player,
		renderSettings.renderDistanceChunks,
		renderSettings.verticalRenderDistanceChunks
	)
	self:pushPlayerInterestToWorldSimulation(player, self.world:getPlayerInterestKeys(player))
	self:resetChunkStream(player)
	self:pushState(player)
end

function WorldGenerationServiceServer.UntrackPlayer(self: WorldGenerationServiceServer, player: Player)
	self.playerRenderSettings[player] = nil
	self.playerChunkStreams[player] = nil
	self.world:untrackPlayer(player)
	self:pushPlayerInterestToWorldSimulation(player, {})
end

function WorldGenerationServiceServer.RequestSync(self: WorldGenerationServiceServer, player: Player)
	if self.playerRenderSettings[player] == nil then
		self:trackPlayer(player)
		return
	end
	self:resetChunkStream(player)
	self:pushPlayerInterestToWorldSimulation(player, self.world:getPlayerInterestKeys(player))
	self:pushState(player)
end

function WorldGenerationServiceServer.SetRenderDistance(
	self: WorldGenerationServiceServer,
	player: Player,
	renderDistanceRaw: any,
	verticalRenderDistanceRaw: any?
)
	local renderSettings = self:getOrCreatePlayerRenderSettings(player)
	local nextRenderDistance = WorldGenerationServiceUtils.sanitizeRenderDistance(
		renderDistanceRaw,
		renderSettings.renderDistanceChunks
	)
	local nextVerticalRenderDistance = WorldGenerationServiceUtils.sanitizeVerticalRenderDistance(
		verticalRenderDistanceRaw,
		renderSettings.verticalRenderDistanceChunks
	)

	renderSettings.renderDistanceChunks = nextRenderDistance
	renderSettings.verticalRenderDistanceChunks = nextVerticalRenderDistance
	self.world:setPlayerRenderDistance(player, nextRenderDistance, nextVerticalRenderDistance)
	self:pushPlayerRenderDistanceToWorldSimulation(player, nextRenderDistance, nextVerticalRenderDistance)
	self:pushPlayerInterestToWorldSimulation(player, self.world:getPlayerInterestKeys(player))
	self:resetChunkStream(player)
	self:pushState(player)
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
	local changed, previousTileId, nextTileId = self.world:setTileAt(tileXRaw, tileYRaw, tileIdRaw)
	if changed and isFiniteNumber(tileXRaw) and isFiniteNumber(tileYRaw) then
		self:enqueueAffectedWorldSimulationChunkKeysForTile(math.floor(tileXRaw), math.floor(tileYRaw))
	end
	return changed, previousTileId, nextTileId
end

function WorldGenerationServiceServer.GetBiomeTypeAt(
	self: WorldGenerationServiceServer,
	tileXRaw: any,
	tileYRaw: any
): number
	return self.world:getBiomeTypeAt(tileXRaw, tileYRaw)
end

function WorldGenerationServiceServer.GetBiomeTypeAtWorldPosition(
	self: WorldGenerationServiceServer,
	worldPosition: Vector3
): number
	return self.world:getBiomeTypeAtWorldPosition(worldPosition)
end

function WorldGenerationServiceServer.SetBiomeTypeAt(
	self: WorldGenerationServiceServer,
	tileXRaw: any,
	tileYRaw: any,
	biomeTypeRaw: any
): (boolean, number, number)
	local changed, previousBiomeType, nextBiomeType = self.world:setBiomeTypeAt(tileXRaw, tileYRaw, biomeTypeRaw)
	if changed and isFiniteNumber(tileXRaw) and isFiniteNumber(tileYRaw) then
		self:enqueueAffectedWorldSimulationChunkKeysForTile(math.floor(tileXRaw), math.floor(tileYRaw))
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
	return self:setTileAt(tileX, tileY, tileIdRaw)
end

function WorldGenerationServiceServer.SetBiomeTypeAtWorldPosition(
	self: WorldGenerationServiceServer,
	worldPosition: Vector3,
	biomeTypeRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.world.worldOrigin.Z, self.world.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.world.worldOrigin.Y, self.world.tileSize)
	return self:setBiomeTypeAt(tileX, tileY, biomeTypeRaw)
end

function WorldGenerationServiceServer.GetConfig(self: WorldGenerationServiceServer): WorldGenerationConfig
	return self.config
end

function WorldGenerationServiceServer.Destroy(self: WorldGenerationServiceServer)
	self:disableStudioPreview()

	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end

	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	local playersToUntrack = {}
	for player in self.playerRenderSettings do
		table.insert(playersToUntrack, player)
	end
	for _, player in playersToUntrack do
		self:untrackPlayer(player)
	end
	table.clear(self.playerChunkStreams)

	if self.world then
		self.world:destroy()
	end

	if self.networker then
		self.networker:destroy()
	end
end

WorldGenerationServiceServer.init = WorldGenerationServiceServer.Init
WorldGenerationServiceServer.resetStreamingState = WorldGenerationServiceServer.ResetStreamingState
WorldGenerationServiceServer.loadWorld = WorldGenerationServiceServer.LoadWorld
WorldGenerationServiceServer.buildStudioPreviewInterest = WorldGenerationServiceServer.BuildStudioPreviewInterest
WorldGenerationServiceServer.applyStudioPreviewInterest = WorldGenerationServiceServer.ApplyStudioPreviewInterest
WorldGenerationServiceServer.enableStudioPreview = WorldGenerationServiceServer.EnableStudioPreview
WorldGenerationServiceServer.disableStudioPreview = WorldGenerationServiceServer.DisableStudioPreview
WorldGenerationServiceServer.getOrCreatePlayerRenderSettings = WorldGenerationServiceServer.GetOrCreatePlayerRenderSettings
WorldGenerationServiceServer.createStateSnapshot = WorldGenerationServiceServer.CreateStateSnapshot
WorldGenerationServiceServer.pushState = WorldGenerationServiceServer.PushState
WorldGenerationServiceServer.createChunkSendQueue = WorldGenerationServiceServer.CreateChunkSendQueue
WorldGenerationServiceServer.createChunkStream = WorldGenerationServiceServer.CreateChunkStream
WorldGenerationServiceServer.pushSeedToWorldSimulation = WorldGenerationServiceServer.PushSeedToWorldSimulation
WorldGenerationServiceServer.pushPlayerInterestToWorldSimulation = WorldGenerationServiceServer.PushPlayerInterestToWorldSimulation
WorldGenerationServiceServer.pushChunkSnapshotToWorldSimulation = WorldGenerationServiceServer.PushChunkSnapshotToWorldSimulation
WorldGenerationServiceServer.pushPlayerRenderDistanceToWorldSimulation = WorldGenerationServiceServer.PushPlayerRenderDistanceToWorldSimulation
WorldGenerationServiceServer.getOrCreateChunkStream = WorldGenerationServiceServer.GetOrCreateChunkStream
WorldGenerationServiceServer.resetChunkStream = WorldGenerationServiceServer.ResetChunkStream
WorldGenerationServiceServer.enqueueChunkForWorldSimulation = WorldGenerationServiceServer.EnqueueChunkForWorldSimulation
WorldGenerationServiceServer.enqueueAffectedWorldSimulationChunkKeysForTile = WorldGenerationServiceServer.EnqueueAffectedWorldSimulationChunkKeysForTile
WorldGenerationServiceServer.syncPlayerChunkStream = WorldGenerationServiceServer.SyncPlayerChunkStream
WorldGenerationServiceServer.processChunkStreamQueues = WorldGenerationServiceServer.ProcessChunkStreamQueues
WorldGenerationServiceServer.processWorldSimulationChunkQueue = WorldGenerationServiceServer.ProcessWorldSimulationChunkQueue
WorldGenerationServiceServer.onHeartbeat = WorldGenerationServiceServer.OnHeartbeat
WorldGenerationServiceServer.trackPlayer = WorldGenerationServiceServer.TrackPlayer
WorldGenerationServiceServer.untrackPlayer = WorldGenerationServiceServer.UntrackPlayer
WorldGenerationServiceServer.requestSync = WorldGenerationServiceServer.RequestSync
WorldGenerationServiceServer.setRenderDistance = WorldGenerationServiceServer.SetRenderDistance
WorldGenerationServiceServer.getWorld = WorldGenerationServiceServer.GetWorld
WorldGenerationServiceServer.setTileAt = WorldGenerationServiceServer.SetTileAt
WorldGenerationServiceServer.getBiomeTypeAt = WorldGenerationServiceServer.GetBiomeTypeAt
WorldGenerationServiceServer.getBiomeTypeAtWorldPosition = WorldGenerationServiceServer.GetBiomeTypeAtWorldPosition
WorldGenerationServiceServer.setBiomeTypeAt = WorldGenerationServiceServer.SetBiomeTypeAt
WorldGenerationServiceServer.setTileAtWorldPosition = WorldGenerationServiceServer.SetTileAtWorldPosition
WorldGenerationServiceServer.setBiomeTypeAtWorldPosition = WorldGenerationServiceServer.SetBiomeTypeAtWorldPosition
WorldGenerationServiceServer.getConfig = WorldGenerationServiceServer.GetConfig
WorldGenerationServiceServer.destroy = WorldGenerationServiceServer.Destroy

type WorldGenerationServiceServer = typeof(WorldGenerationServiceServer) & {
	networker: Networker.Server,
	world: WorldGenerationClass,
	config: WorldGenerationConfig,
	playerRenderSettings: { [Player]: PlayerRenderSettings },
	studioPreviewEnabled: boolean,
	studioPreviewActive: boolean,
	studioPreviewInterestKeys: { [string]: boolean },
	worldBootstrapPlayerUserId: number?,
	playerChunkStreams: { [Player]: PlayerChunkStream },
	worldSimulationChunkQueue: ChunkSendQueue,
	worldSimulationSentRevisions: { [string]: number },
	chunkStreamAccumulator: number,
	heartbeatConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return WorldGenerationServiceServer :: WorldGenerationServiceServer
