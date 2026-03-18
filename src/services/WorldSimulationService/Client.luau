--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)
local WorldSimulationModules = ReplicatedStorage.Shared.Services.WorldSimulationService

local Cache = require(WorldSimulationModules.Cache)
local Config = require(WorldSimulationModules.Config)
local Debug = require(WorldSimulationModules.Debug)
local Net = require(WorldSimulationModules.Net)
local Render = require(WorldSimulationModules.Render)
local Shared = require(WorldSimulationModules.Shared)
local Stream = require(WorldSimulationModules.Stream)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Destroy: (self: JanitorClass) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

local WorldSimulationServiceClient = {}

local SNAPSHOT_APPLY_BUDGET_PER_HEARTBEAT = 3
local SNAPSHOT_CATCHUP_ENQUEUE_BUDGET_PER_HEARTBEAT = 24
local INVARIANT_CHECK_INTERVAL_SECONDS = 1.5
local DEV_GUARDS_ENABLED = RunService:IsStudio()

local function isChunkWithinInterest(
	chunkX: number,
	chunkY: number,
	chunkZ: number,
	centerChunkX: number,
	centerChunkY: number,
	centerChunkZ: number,
	radius: number,
	verticalRadius: number
): boolean
	local deltaY = chunkY - centerChunkY
	if math.abs(deltaY) > verticalRadius then
		return false
	end
	local deltaX = chunkX - centerChunkX
	local deltaZ = chunkZ - centerChunkZ
	return deltaX * deltaX + deltaZ * deltaZ <= radius * radius
end

local function countLookupEntries(lookup: { [string]: any }): number
	local count = 0
	for _ in lookup do
		count += 1
	end
	return count
end

local function computeTheoreticalMaxActiveChunkModels(radius: number, verticalRadius: number): number
	local horizontalRadius = math.max(1, math.floor(radius))
	local vertical = math.max(1, math.floor(verticalRadius))
	local perLayer = 0
	local radiusSq = horizontalRadius * horizontalRadius
	for offsetX = -horizontalRadius, horizontalRadius do
		for offsetZ = -horizontalRadius, horizontalRadius do
			if offsetX * offsetX + offsetZ * offsetZ <= radiusSq then
				perLayer += 1
			end
		end
	end
	return perLayer * (vertical * 2 + 1)
end

local function resolveRootPart(player: Player): BasePart?
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

function WorldSimulationServiceClient:getCenterChunk(): (number, number, number)
	local rootPart = resolveRootPart(self.localPlayer)
	if rootPart == nil then
		return 0, 0, 0
	end
	local tileX = Shared.toTileCoordinate(rootPart.Position.X, self.config.tileSize)
	local tileY = Shared.toTileCoordinate(rootPart.Position.Y, self.config.tileSize)
	local tileZ = Shared.toTileCoordinate(rootPart.Position.Z, self.config.tileSize)
	return Shared.toChunkCoordinate(tileX, self.config.chunkSize),
		Shared.toChunkCoordinate(tileY, self.config.chunkHeight),
		Shared.toChunkCoordinate(tileZ, self.config.chunkDepth)
end

function WorldSimulationServiceClient:getRenderChunkRadii(): (number, number)
	local horizontal = self.config.renderRadiusChunks
	if horizontal == nil then
		horizontal = self.config.streamRadiusChunks
	end
	local vertical = self.config.renderVerticalRadiusChunks
	if vertical == nil then
		vertical = self.config.streamVerticalRadiusChunks
	end
	return math.max(1, math.min(horizontal, self.config.streamRadiusChunks)),
		math.max(1, math.min(vertical, self.config.streamVerticalRadiusChunks))
end

function WorldSimulationServiceClient:StreamInChunk(snapshot: { [string]: any }): boolean
	if typeof(snapshot) ~= "table" then
		return false
	end
	local chunkKey = snapshot.key
	if typeof(chunkKey) ~= "string" or chunkKey == "" then
		return false
	end

	local applied = self.render:applyChunkSnapshot(snapshot)
	if applied then
		local wasActive = self.activeChunkModels[chunkKey] == true
		self.activeChunkModels[chunkKey] = true
		if not wasActive and self.debug ~= nil and self.debug.incrementCounter then
			self.debug:incrementCounter("chunk_models_streamed_in")
		end
		return true
	end

	self.activeChunkModels[chunkKey] = nil
	self.streamState.loadedLookup[chunkKey] = nil
	return false
end

function WorldSimulationServiceClient:StreamOutChunk(chunkKeyRaw: any)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end
	local wasActive = self.activeChunkModels[chunkKeyRaw] == true
	self.activeChunkModels[chunkKeyRaw] = nil
	self.streamState.loadedLookup[chunkKeyRaw] = nil
	self.render:unloadChunk(chunkKeyRaw)
	if wasActive and self.debug ~= nil and self.debug.incrementCounter then
		self.debug:incrementCounter("chunk_models_streamed_out")
	end
end

function WorldSimulationServiceClient:runChunkModelInvariantCheck(label: string)
	local renderRadius, renderVerticalRadius = self:getRenderChunkRadii()
	local theoreticalMax = computeTheoreticalMaxActiveChunkModels(renderRadius, renderVerticalRadius)
	local activeCount = countLookupEntries(self.activeChunkModels)
	local renderCount = self.render:getActiveChunkCount()
	local folderModelCount = self.render:getChunkFolderModelCount()
	if self.debug ~= nil then
		if self.debug.setCounter then
			self.debug:setCounter("active_chunk_models", activeCount)
			self.debug:setCounter("active_chunk_folder_models", folderModelCount)
			self.debug:setCounter("active_chunk_models_theoretical_max", theoreticalMax)
		end
	end

	if folderModelCount ~= renderCount then
		local message = `[WorldSimulationService][{label}] Chunk folder contains stray models: folder={folderModelCount} render={renderCount}`
		if DEV_GUARDS_ENABLED or self.config.enableDebug then
			error(message)
		end
	end

	local leakedKeys = table.create(8)
	for chunkKey in self.activeChunkModels do
		if self.activeStreamingSet[chunkKey] ~= true then
			leakedKeys[#leakedKeys + 1] = chunkKey
		end
	end

	for _, chunkKey in leakedKeys do
		self:StreamOutChunk(chunkKey)
	end

	local strictCount = countLookupEntries(self.activeChunkModels)
	if strictCount > theoreticalMax then
		if self.debug ~= nil and self.debug.incrementCounter then
			self.debug:incrementCounter("active_chunk_models_exceeded")
		end
		local message = `[WorldSimulationService][{label}] ActiveChunkModels ({strictCount}) exceeds theoretical max ({theoreticalMax})`
		if DEV_GUARDS_ENABLED or self.config.enableDebug then
			error(message)
		end
	end
end

function WorldSimulationServiceClient:assertStartupChunkFolderEmpty()
	local folderModelCount = self.render:getChunkFolderModelCount()
	if self.debug ~= nil and self.debug.setCounter then
		self.debug:setCounter("startup_chunk_folder_models", folderModelCount)
	end
	if folderModelCount > 0 then
		error(
			`[WorldSimulationService][startup] Expected empty chunk folder before streaming, found {folderModelCount} chunk model(s)`
		)
	end
end

function WorldSimulationServiceClient:reconcileRenderWindow(centerX: number, centerY: number, centerZ: number)
	local renderRadius, renderVerticalRadius = self:getRenderChunkRadii()
	local desiredLookup = {} :: { [string]: boolean }

	local catchupBudget = SNAPSHOT_CATCHUP_ENQUEUE_BUDGET_PER_HEARTBEAT
	local catchupEnqueued = 0
	for chunkKey, snapshot in self.chunkSnapshotsByKey do
		if isChunkWithinInterest(
			snapshot.chunkX,
			snapshot.chunkY,
			snapshot.chunkZ,
			centerX,
			centerY,
			centerZ,
			renderRadius,
			renderVerticalRadius
		) then
			desiredLookup[chunkKey] = true
			if self.streamState.loadedLookup[chunkKey] ~= true and catchupEnqueued < catchupBudget then
				local priority = Net.chunkPriorityFromCenter(
					snapshot.chunkX,
					snapshot.chunkY,
					snapshot.chunkZ,
					centerX,
					centerY,
					centerZ
				)
				Stream.pushClientSnapshot(self.streamState, snapshot, priority)
				catchupEnqueued += 1
			end
		end
	end

	local unloadKeys = table.create(16)
	for chunkKey in self.activeChunkModels do
		if desiredLookup[chunkKey] ~= true then
			unloadKeys[#unloadKeys + 1] = chunkKey
		end
	end

	for _, chunkKey in unloadKeys do
		self:StreamOutChunk(chunkKey)
	end

	self.activeStreamingSet = desiredLookup
end

function WorldSimulationServiceClient:applyState(stateRaw: any)
	self.config = Config.sanitize(stateRaw, self.config)
	self.render.config = self.config
	self.debug.enabled = self.config.enableDebug
	self.debug.profilingEnabled = self.config.enableProfiling
	self:runChunkModelInvariantCheck("state_apply")
	self.stateChanged:Fire(self:getState())
end

function WorldSimulationServiceClient:onChunkDelta(deltaRaw: any)
	local decoded = Net.decodeChunkDelta(deltaRaw)
	if decoded == nil then
		decoded = Net.decodeLegacyChunkTransitional(deltaRaw)
		if decoded == nil then
			return
		end
		if self.debug ~= nil then
			self.debug:incrementCounter("legacy_chunk_payload_applied")
		end
	end
	if self.debug ~= nil then
		self.debug:validateChunkArrays(decoded)
	end
	self.chunkSnapshotsByKey[decoded.key] = decoded
	local centerX, centerY, centerZ = self:getCenterChunk()
	local priority = Net.chunkPriorityFromCenter(decoded.chunkX, decoded.chunkY, decoded.chunkZ, centerX, centerY, centerZ)
	Stream.pushClientSnapshot(self.streamState, decoded, priority)
end

function WorldSimulationServiceClient:onChunkUnloaded(chunkKeyRaw: any)
	if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then
		self.chunkSnapshotsByKey[chunkKeyRaw] = nil
	end
	Stream.markClientChunkUnloaded(self.streamState, chunkKeyRaw)
	self:StreamOutChunk(chunkKeyRaw)
end

function WorldSimulationServiceClient:onEntityDelta(payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	self.lastEntityDelta = payloadRaw
end

function WorldSimulationServiceClient:onDebugCounters(countersRaw: any)
	if typeof(countersRaw) ~= "table" then
		return
	end
	self.lastDebugCounters = countersRaw
end

function WorldSimulationServiceClient:requestSync()
	self.networker:fire(Net.NETWORK_METHOD_REQUEST_SYNC)
end

function WorldSimulationServiceClient:setStreamRadius(streamRadiusRaw: any, verticalRadiusRaw: any)
	self.networker:fire(Net.NETWORK_METHOD_SET_STREAM_RADIUS, streamRadiusRaw, verticalRadiusRaw)
end

function WorldSimulationServiceClient:submitInput(inputPayload: { [string]: any })
	self.networker:fire(Net.NETWORK_METHOD_SUBMIT_INPUT, inputPayload)
end

function WorldSimulationServiceClient:getState(): { [string]: any }
	return {
		seed = self.config.seed,
		tileSize = self.config.tileSize,
		chunkSize = self.config.chunkSize,
		chunkHeight = self.config.chunkHeight,
		chunkDepth = self.config.chunkDepth,
		clusterSize = self.config.clusterSize,
		streamRadiusChunks = self.config.streamRadiusChunks,
		streamVerticalRadiusChunks = self.config.streamVerticalRadiusChunks,
		renderRadiusChunks = self.config.renderRadiusChunks,
		renderVerticalRadiusChunks = self.config.renderVerticalRadiusChunks,
		enableDebug = self.config.enableDebug,
		enableProfiling = self.config.enableProfiling,
	}
end

function WorldSimulationServiceClient:onHeartbeat(dt: number)
	self.render:bindExistingChunkFolderGuard()
	local centerX, centerY, centerZ = self:getCenterChunk()
	self:reconcileRenderWindow(centerX, centerY, centerZ)
	local renderRadius, renderVerticalRadius = self:getRenderChunkRadii()

	self.render:beginStreamingTick()
	for _index = 1, SNAPSHOT_APPLY_BUDGET_PER_HEARTBEAT do
		local snapshot = Stream.popClientSnapshot(self.streamState)
		if snapshot == nil then
			break
		end
		local latest = self.chunkSnapshotsByKey[snapshot.key]
		if latest ~= nil then
			snapshot = latest
		end
		if not isChunkWithinInterest(
			snapshot.chunkX,
			snapshot.chunkY,
			snapshot.chunkZ,
			centerX,
			centerY,
			centerZ,
			renderRadius,
			renderVerticalRadius
		) then
			self:StreamOutChunk(snapshot.key)
			continue
		end
		self:StreamInChunk(snapshot)
	end
	self.render:endStreamingTick()

	self.invariantCheckAccumulator += dt
	if self.invariantCheckAccumulator >= INVARIANT_CHECK_INTERVAL_SECONDS then
		self.invariantCheckAccumulator = 0
		self:runChunkModelInvariantCheck("periodic")
	end
end

function WorldSimulationServiceClient:init()
	if self.janitor ~= nil then
		return
	end

	self.localPlayer = Players.LocalPlayer
	self.runtimeContext = CoreRuntime.getClientRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).init) == "function" then
		local runtimeAny = self.runtimeContext :: any
		runtimeAny:init()
	end
	self.config = Config.createDefault()
	self.cache = Cache.new({
		tablePoolSize = self.config.cacheTablePoolSize,
		arrayPoolSize = self.config.cacheArrayPoolSize,
		vectorPoolSize = math.max(16, math.floor(self.config.cacheArrayPoolSize * 0.5)),
	})
	self.debug = Debug.new({
		enabled = self.config.enableDebug,
		profilingEnabled = self.config.enableProfiling,
	})
	self.render = Render.new(self.config, self.cache, self.debug)
	self.render:bindExistingChunkFolderGuard()
	self:assertStartupChunkFolderEmpty()
	self.streamState = Stream.createClientStreamState()
	self.chunkSnapshotsByKey = {} :: { [string]: { [string]: any } }
	self.activeChunkModels = {} :: { [string]: boolean }
	self.activeStreamingSet = {} :: { [string]: boolean }
	self.invariantCheckAccumulator = 0
	self.stateChanged = Signal.new()
	self.lastEntityDelta = nil
	self.lastDebugCounters = {}

	self.networker = Networker.client.new("WorldSimulationService", self)
	self.janitor = Janitor.new()
	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)
	local tickScheduler = if self.runtimeContext ~= nil then (self.runtimeContext :: any).tickScheduler else nil
	if tickScheduler ~= nil and typeof((tickScheduler :: any).scheduleEvery) == "function" then
		local heartbeatToken = (tickScheduler :: any):scheduleEvery(function(dt: number)
			self:onHeartbeat(dt)
		end, 1 / 60, {
			group = "service.worldSimulation.client",
			priority = 120,
			catchUp = false,
		})
		self.janitor:GiveChore(function()
			if heartbeatToken ~= nil and typeof(heartbeatToken.cancel) == "function" then
				heartbeatToken:cancel()
			elseif heartbeatToken ~= nil and typeof((tickScheduler :: any).cancel) == "function" then
				local schedulerAny = tickScheduler :: any
				schedulerAny:cancel(heartbeatToken)
			end
		end)
	else
		self.janitor:GiveChore(RunService.Heartbeat:Connect(function(dt: number)
			self:onHeartbeat(dt)
		end))
	end

	self:runChunkModelInvariantCheck("startup")
	self:requestSync()
end

function WorldSimulationServiceClient:destroy()
	if self.janitor ~= nil then
		self.janitor:Destroy()
		self.janitor = nil
	end
	if self.render ~= nil then
		self.render:destroy()
		self.render = nil
	end
	if self.debug ~= nil then
		self.debug:destroy()
		self.debug = nil
	end
	if self.cache ~= nil then
		self.cache:destroy()
		self.cache = nil
	end
	if self.chunkSnapshotsByKey ~= nil then
		table.clear(self.chunkSnapshotsByKey)
	end
	if self.activeChunkModels ~= nil then
		table.clear(self.activeChunkModels)
	end
	if self.activeStreamingSet ~= nil then
		table.clear(self.activeStreamingSet)
	end
end

type WorldSimulationServiceClient = typeof(WorldSimulationServiceClient) & {
	runtimeContext: any?,
	localPlayer: Player,
	config: Config.SimulationConfig,
	cache: Cache.Cache,
	debug: Debug.Debug,
	render: Render.Render,
	streamState: Stream.ClientStreamState,
	chunkSnapshotsByKey: { [string]: { [string]: any } },
	activeChunkModels: { [string]: boolean },
	activeStreamingSet: { [string]: boolean },
	invariantCheckAccumulator: number,
	networker: Networker.Client,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	lastEntityDelta: any,
	lastDebugCounters: { [string]: any },
}

return WorldSimulationServiceClient :: WorldSimulationServiceClient
