local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local Sift: any = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")

local CoreRuntime = require("CoreRuntime")
local PacketPayload = require("PacketPayload")
local WorldSimulationServicePackets = require("NetPacketsShared").WorldSimulationService

local function sendPacket(methodName: string, ...: any)
	local packet = WorldSimulationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldSimulationService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = WorldSimulationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldSimulationService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyState")
	bindPacket(self, "onChunkDelta")
	bindPacket(self, "onChunkUnloaded")
	bindPacket(self, "onDebugCounters")
	bindPacket(self, "requestSync")
	bindPacket(self, "setStreamRadius")
	bindPacket(self, "submitInput")
end

local Maid = require("Maid")
local Rx: any = require("Rx")
local Signal = require("Signal")

local Cache = require("SimulationCache")
local Config = require("SimulationConfig")
local Debug = require("WorldSimulationDebug")
local Net = require("Net")
local Render = require("WorldSimulationRender")
local Shared = require("Shared")
local Stream = require("Stream")

type MaidClass = any

type SignalObject = Signal.Signal<...any>

type ObservableObject = any

local WorldSimulationServiceClient = {}

local SNAPSHOT_APPLY_BUDGET_PER_HEARTBEAT = 3
local SNAPSHOT_CATCHUP_ENQUEUE_BUDGET_PER_HEARTBEAT = 24
local INVARIANT_CHECK_INTERVAL_SECONDS = 1.5
local DEV_GUARDS_ENABLED = RunService:IsStudio()

local function cloneDictionary(dictionaryRaw: any): { [string]: any }
	local cloned = {}
	if typeof(dictionaryRaw) ~= "table" then
		return cloned
	end

	for key, value in dictionaryRaw do
		cloned[key] = value
	end

	return cloned
end

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

local function GetRootPart(player: Player): BasePart?
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

function WorldSimulationServiceClient.GetCenterChunk(self: WorldSimulationServiceClient): (number, number, number)
	local rootPart = GetRootPart(self.localPlayer)
	if rootPart == nil then
		return 0, 0, 0
	end
	local tileX = Shared.ToTileCoordinate(rootPart.Position.X, self.config.tileSize)
	local tileY = Shared.ToTileCoordinate(rootPart.Position.Y, self.config.tileSize)
	local tileZ = Shared.ToTileCoordinate(rootPart.Position.Z, self.config.tileSize)
	return Shared.ToChunkCoordinate(tileX, self.config.chunkSize),
		Shared.ToChunkCoordinate(tileY, self.config.chunkHeight),
		Shared.ToChunkCoordinate(tileZ, self.config.chunkDepth)
end

function WorldSimulationServiceClient.GetRenderChunkRadii(self: WorldSimulationServiceClient): (number, number)
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

function WorldSimulationServiceClient.StreamInChunk(
	self: WorldSimulationServiceClient,
	snapshot: { [string]: any }
): boolean
	if typeof(snapshot) ~= "table" then
		return false
	end
	local chunkKey = snapshot.key
	if typeof(chunkKey) ~= "string" or chunkKey == "" then
		return false
	end

	local applied = self.render:ApplyChunkSnapshot(snapshot)
	if applied then
		local wasActive = self.activeChunkModels[chunkKey] == true
		self.activeChunkModels[chunkKey] = true
		if not wasActive and self.debug ~= nil and self.debug.incrementCounter then
			self.debug:IncrementCounter("chunk_models_streamed_in")
		end
		return true
	end

	self.activeChunkModels[chunkKey] = nil
	self.streamState.loadedLookup[chunkKey] = nil
	return false
end

function WorldSimulationServiceClient.StreamOutChunk(self: WorldSimulationServiceClient, chunkKeyRaw: any)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end
	local wasActive = self.activeChunkModels[chunkKeyRaw] == true
	self.activeChunkModels[chunkKeyRaw] = nil
	self.streamState.loadedLookup[chunkKeyRaw] = nil
	self.render:UnloadChunk(chunkKeyRaw)
	if wasActive and self.debug ~= nil and self.debug.incrementCounter then
		self.debug:IncrementCounter("chunk_models_streamed_out")
	end
end

function WorldSimulationServiceClient.RunChunkModelInvariantCheck(self: WorldSimulationServiceClient, label: string)
	local renderRadius, renderVerticalRadius = self:GetRenderChunkRadii()
	local theoreticalMax = computeTheoreticalMaxActiveChunkModels(renderRadius, renderVerticalRadius)
	local activeCount = countLookupEntries(self.activeChunkModels)
	local renderCount = self.render:GetActiveChunkCount()
	local folderModelCount = self.render:GetChunkFolderModelCount()
	if self.debug ~= nil then
		if self.debug.setCounter then
			self.debug:SetCounter("active_chunk_models", activeCount)
			self.debug:SetCounter("active_chunk_folder_models", folderModelCount)
			self.debug:SetCounter("active_chunk_models_theoretical_max", theoreticalMax)
		end
	end

	if folderModelCount ~= renderCount then
		local message =
			`[WorldSimulationService][{label}] Chunk folder contains stray models: folder={folderModelCount} render={renderCount}`
		if DEV_GUARDS_ENABLED or self.config.enableDebug then
			error(message)
		end
	end

	local leakedKeys = Sift.Array.create(8)
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
			self.debug:IncrementCounter("active_chunk_models_exceeded")
		end
		local message =
			`[WorldSimulationService][{label}] ActiveChunkModels ({strictCount}) exceeds theoretical max ({theoreticalMax})`
		if DEV_GUARDS_ENABLED or self.config.enableDebug then
			error(message)
		end
	end
end

function WorldSimulationServiceClient.AssertStartupChunkFolderEmpty(self: WorldSimulationServiceClient)
	local folderModelCount = self.render:GetChunkFolderModelCount()
	if self.debug ~= nil and self.debug.setCounter then
		self.debug:SetCounter("startup_chunk_folder_models", folderModelCount)
	end
	if folderModelCount > 0 then
		error(
			`[WorldSimulationService][startup] Expected empty chunk folder before streaming, found {folderModelCount} chunk model(s)`
		)
	end
end

function WorldSimulationServiceClient.ReconcileRenderWindow(
	self: WorldSimulationServiceClient,
	centerX: number,
	centerY: number,
	centerZ: number
)
	local renderRadius, renderVerticalRadius = self:GetRenderChunkRadii()
	local desiredLookup = {} :: { [string]: boolean }

	local catchupBudget = SNAPSHOT_CATCHUP_ENQUEUE_BUDGET_PER_HEARTBEAT
	local catchupEnqueued = 0
	for chunkKey, snapshot in self.chunkSnapshotsByKey do
		if
			isChunkWithinInterest(
				snapshot.chunkX,
				snapshot.chunkY,
				snapshot.chunkZ,
				centerX,
				centerY,
				centerZ,
				renderRadius,
				renderVerticalRadius
			)
		then
			desiredLookup[chunkKey] = true
			if self.streamState.loadedLookup[chunkKey] ~= true and catchupEnqueued < catchupBudget then
				local priority = Net.ChunkPriorityFromCenter(
					snapshot.chunkX,
					snapshot.chunkY,
					snapshot.chunkZ,
					centerX,
					centerY,
					centerZ
				)
				Stream.PushClientSnapshot(self.streamState, snapshot, priority)
				catchupEnqueued += 1
			end
		end
	end

	local unloadKeys = Sift.Array.create(16)
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

function WorldSimulationServiceClient.ApplyState(self: WorldSimulationServiceClient, stateRaw: any)
	self.config = Config.Coerce(stateRaw, self.config)
	self.render.config = self.config
	self.debug.enabled = self.config.enableDebug
	self.debug.profilingEnabled = self.config.enableProfiling
	self:RunChunkModelInvariantCheck("state_apply")
	self.stateChanged:Fire(self:GetState())
end

function WorldSimulationServiceClient.OnChunkDelta(self: WorldSimulationServiceClient, deltaRaw: any)
	local decoded = Net.DecodeChunkDelta(deltaRaw)
	if decoded == nil then
		decoded = Net.DecodeLegacyChunkTransitional(deltaRaw)
		if decoded == nil then
			return
		end
		if self.debug ~= nil then
			self.debug:IncrementCounter("legacy_chunk_payload_applied")
		end
	end
	if self.debug ~= nil then
		self.debug:ValidateChunkArrays(decoded)
	end
	local chunkSnapshot = decoded :: { [string]: any }
	self.chunkSnapshotsByKey[chunkSnapshot.key] = chunkSnapshot
	local centerX, centerY, centerZ = self:GetCenterChunk()
	local priority = Net.ChunkPriorityFromCenter(
		chunkSnapshot.chunkX,
		chunkSnapshot.chunkY,
		chunkSnapshot.chunkZ,
		centerX,
		centerY,
		centerZ
	)
	Stream.PushClientSnapshot(self.streamState, chunkSnapshot, priority)
end

function WorldSimulationServiceClient.OnChunkUnloaded(self: WorldSimulationServiceClient, chunkKeyRaw: any)
	if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then
		self.chunkSnapshotsByKey[chunkKeyRaw] = nil
	end
	Stream.MarkClientChunkUnloaded(self.streamState, chunkKeyRaw)
	self:StreamOutChunk(chunkKeyRaw)
end

function WorldSimulationServiceClient.OnEntityDelta(self: WorldSimulationServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	self.lastEntityDelta = payloadRaw
end

function WorldSimulationServiceClient.OnDebugCounters(self: WorldSimulationServiceClient, countersRaw: any)
	if typeof(countersRaw) ~= "table" then
		return
	end
	self.lastDebugCounters = cloneDictionary(countersRaw)
	if self.debugCountersChanged ~= nil then
		self.debugCountersChanged:Fire(cloneDictionary(self.lastDebugCounters))
	end
end

function WorldSimulationServiceClient.RequestSync(self: WorldSimulationServiceClient)
	sendPacket(Net.NETWORK_METHOD_REQUEST_SYNC)
end

function WorldSimulationServiceClient.SetStreamRadius(
	self: WorldSimulationServiceClient,
	streamRadiusRaw: any,
	verticalRadiusRaw: any
)
	sendPacket(Net.NETWORK_METHOD_SET_STREAM_RADIUS, streamRadiusRaw, verticalRadiusRaw)
end

function WorldSimulationServiceClient.SubmitInput(self: WorldSimulationServiceClient, inputPayload: { [string]: any })
	sendPacket(Net.NETWORK_METHOD_SUBMIT_INPUT, inputPayload)
end

function WorldSimulationServiceClient.GetState(self: WorldSimulationServiceClient): { [string]: any }
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

function WorldSimulationServiceClient.ObserveState(self: WorldSimulationServiceClient): ObservableObject
	if self.stateChanged == nil then
		error("[WorldSimulationService] init must be called before ObserveState", 2)
	end
	if self.stateObservable == nil then
		self.stateObservable = Rx.fromSignal(self.stateChanged):Pipe({
			Rx.start(function()
				return self:GetState()
			end),
		}) :: ObservableObject
	end
	return self.stateObservable :: ObservableObject
end

function WorldSimulationServiceClient.ObserveDebugCounters(self: WorldSimulationServiceClient): ObservableObject
	if self.debugCountersChanged == nil then
		error("[WorldSimulationService] init must be called before ObserveDebugCounters", 2)
	end
	if self.debugCountersObservable == nil then
		self.debugCountersObservable = Rx.fromSignal(self.debugCountersChanged):Pipe({
			Rx.start(function()
				return cloneDictionary(self.lastDebugCounters)
			end),
		}) :: ObservableObject
	end
	return self.debugCountersObservable :: ObservableObject
end

function WorldSimulationServiceClient.OnHeartbeat(self: WorldSimulationServiceClient, dt: number)
	self.render:BindExistingChunkFolderGuard()
	local centerX, centerY, centerZ = self:GetCenterChunk()
	self:ReconcileRenderWindow(centerX, centerY, centerZ)
	local renderRadius, renderVerticalRadius = self:GetRenderChunkRadii()

	self.render:BeginStreamingTick()
	for _index = 1, SNAPSHOT_APPLY_BUDGET_PER_HEARTBEAT do
		local snapshot = Stream.PopClientSnapshot(self.streamState)
		if snapshot == nil then
			break
		end
		local latest = self.chunkSnapshotsByKey[snapshot.key]
		if latest ~= nil then
			snapshot = latest
		end
		if
			not isChunkWithinInterest(
				snapshot.chunkX,
				snapshot.chunkY,
				snapshot.chunkZ,
				centerX,
				centerY,
				centerZ,
				renderRadius,
				renderVerticalRadius
			)
		then
			self:StreamOutChunk(snapshot.key)
			continue
		end
		self:StreamInChunk(snapshot)
	end
	self.render:EndStreamingTick()

	self.invariantCheckAccumulator += dt
	if self.invariantCheckAccumulator >= INVARIANT_CHECK_INTERVAL_SECONDS then
		self.invariantCheckAccumulator = 0
		self:RunChunkModelInvariantCheck("periodic")
	end
end

function WorldSimulationServiceClient.Init(self: WorldSimulationServiceClient)
	if self.maid ~= nil then
		return
	end

	self.localPlayer = Players.LocalPlayer
	self.runtimeContext = CoreRuntime.GetClientRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).Init) == "function" then
		local runtimeAny = self.runtimeContext :: any
		runtimeAny:Init()
	end
	self.config = Config.CreateDefault()
	self.cache = Cache.New({
		tablePoolSize = self.config.cacheTablePoolSize,
		arrayPoolSize = self.config.cacheArrayPoolSize,
		vectorPoolSize = math.max(16, math.floor(self.config.cacheArrayPoolSize * 0.5)),
	})
	self.debug = Debug.New({
		enabled = self.config.enableDebug,
		profilingEnabled = self.config.enableProfiling,
	})
	self.render = Render.New(self.config, self.cache, self.debug)
	self.render:BindExistingChunkFolderGuard()
	self:AssertStartupChunkFolderEmpty()
	self.streamState = Stream.CreateClientStreamState()
	self.chunkSnapshotsByKey = {} :: { [string]: { [string]: any } }
	self.activeChunkModels = {} :: { [string]: boolean }
	self.activeStreamingSet = {} :: { [string]: boolean }
	self.invariantCheckAccumulator = 0
	self.stateChanged = Signal.new()
	self.debugCountersChanged = Signal.new()
	self.lastEntityDelta = nil
	self.lastDebugCounters = {}
	self.stateObservable = nil
	self.debugCountersObservable = nil

	bindPackets(self)
	self.maid = Maid.new()
	self.maid:GiveTask(function()
		self.stateChanged:Destroy()
	end)
	self.maid:GiveTask(function()
		self.debugCountersChanged:Destroy()
	end)
	local tickScheduler = if self.runtimeContext ~= nil then (self.runtimeContext :: any).tickScheduler else nil
	if tickScheduler ~= nil and typeof((tickScheduler :: any).ScheduleEvery) == "function" then
		local heartbeatToken = (tickScheduler :: any):ScheduleEvery(
			function(dt: number)
				self:OnHeartbeat(dt)
			end,
			1 / 60,
			{
				group = "service.worldSimulation.client",
				priority = 120,
				catchUp = false,
			}
		)
		self.maid:GiveTask(function()
			if heartbeatToken ~= nil and typeof(heartbeatToken.Cancel) == "function" then
				heartbeatToken:Cancel()
			elseif heartbeatToken ~= nil and typeof((tickScheduler :: any).Cancel) == "function" then
				local schedulerAny = tickScheduler :: any
				schedulerAny:Cancel(heartbeatToken)
			end
		end)
	else
		self.maid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
			self:OnHeartbeat(dt)
		end))
	end

	self:RunChunkModelInvariantCheck("startup")
	self:RequestSync()
end

function WorldSimulationServiceClient.Destroy(self: WorldSimulationServiceClient)
	if self.maid ~= nil then
		self.maid:Destroy()
		self.maid = nil
	end
	if self.render ~= nil then
		self.render:Destroy()
		self.render = nil
	end
	if self.debug ~= nil then
		self.debug:Destroy()
		self.debug = nil
	end
	if self.cache ~= nil then
		self.cache:Destroy()
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
	self.stateObservable = nil
	self.debugCountersObservable = nil
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
	maid: any,
	stateChanged: SignalObject,
	debugCountersChanged: SignalObject,
	stateObservable: ObservableObject?,
	debugCountersObservable: ObservableObject?,
	lastEntityDelta: any,
	lastDebugCounters: { [string]: any },
}

return WorldSimulationServiceClient :: WorldSimulationServiceClient
