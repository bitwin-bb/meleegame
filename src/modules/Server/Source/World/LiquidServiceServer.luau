local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local Sift: any = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local HpServiceServer = require("HpServiceServer")
local LiquidServiceUtils = require("LiquidServiceUtils")
local PacketPayload = require("PacketPayload")
local LiquidServicePackets = require("NetPacketsShared").LiquidService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = LiquidServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for LiquidService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = LiquidServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for LiquidService`)
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
end

local ObjectPool = require("ObjectPool")
local PlayerServiceServer = require("PlayerServiceServer")
local PlayerServiceUtils = require("PlayerServiceUtils")
local Signal = require("Signal")
local SpatialHashGrid = require("SpatialHashGrid")
local TickSchedulerModule = require("TickScheduler")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")
local WorldMutationQueue = require("WorldMutationQueue")
local WorldSimulationDebug = require("WorldSimulationDebug")

type LiquidServiceConfig = LiquidServiceUtils.LiquidServiceConfig
type LiquidServiceState = LiquidServiceUtils.LiquidServiceState
type LiquidChunkSnapshot = LiquidServiceUtils.LiquidChunkSnapshot
type LiquidQueryResult = LiquidServiceUtils.LiquidQueryResult
type LiquidDefinition = LiquidServiceUtils.LiquidDefinition
type LiquidSolverAccess = LiquidServiceUtils.LiquidSolverAccess
type LiquidSolverStepResult = LiquidServiceUtils.LiquidSolverStepResult
type CancellationToken = TickSchedulerModule.CancellationToken
type DebugObject = WorldSimulationDebug.Debug

type SignalObject = Signal.Signal<...any>

type ChunkLifecycleConnection = {
	Disconnect: (self: ChunkLifecycleConnection) -> (),
}

type ChunkDirtyBounds = {
	minTileX: number,
	minTileY: number,
	maxTileX: number,
	maxTileY: number,
}

type WorldObject = {
	chunkSize: number,
	tileSize: number,
	worldOrigin: Vector3,
	basePlaneX: number?,
	tileId: { AIR: number },
	GetPlayerInterestKeys: (self: WorldObject, player: Player) -> { [string]: boolean },
	RegisterChunkLifecycleObserver: (self: WorldObject, observerRaw: any) -> ChunkLifecycleConnection?,
	IsChunkCollisionReadyByKey: (self: WorldObject, chunkKeyRaw: any) -> boolean,
	IsChunkCollisionReady: (self: WorldObject, chunkXRaw: any, chunkYRaw: any) -> boolean,
	GetLoadedCollisionChunkCount: (self: WorldObject) -> number,
	GetLiquidChunkSnapshotByKey: (self: WorldObject, chunkKeyRaw: any) -> { [string]: any }?,
	GetLiquidCellAt: (self: WorldObject, tileXRaw: any, tileYRaw: any) -> number,
	SetLiquidCellAt: (self: WorldObject, tileXRaw: any, tileYRaw: any, packedCellRaw: any) -> (boolean, number, number),
	GetTileAt: (self: WorldObject, tileXRaw: any, tileYRaw: any) -> (number, number),
}

type WorldGenerationServiceServerObject = {
	GetWorld: (self: WorldGenerationServiceServerObject) -> WorldObject,
}

type PlayerServiceServerObject = {
	isGameplayActiveForPlayer: (self: PlayerServiceServerObject, player: Player) -> boolean,
}

type HpServiceServerObject = {
	DamagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
}

type ChunkRuntime = {
	key: string,
	revision: number,
	dirtyLookup: { [number]: boolean },
	queuedDirtyCount: number,
	pendingDeltaByIndex: { [number]: number },
	pendingDeltaIndices: { number },
	pendingDeltaCount: number,
	forceFullResync: boolean,
	lastDisturbedAt: number,
	lastActiveStepId: number,
	lastActivationAt: number,
	lastActivationReason: string,
	lastStableAt: number,
	lastStableReason: string,
	lastProcessedAt: number,
	lastProcessedCells: number,
	lastChangedCells: number,
	lastPrimedCells: number,
	dirtyMarkCount: number,
	mutationCount: number,
	lastMutationTileX: number,
	lastMutationTileY: number,
	lastMutationFill: number,
	lastMutationType: number,
	lastActiveCellCount: number,
	lastDownwardTransfer: number,
	lastLateralTransfer: number,
	lastCrossChunkWakeups: number,
	lastStabilityScanUnstableCells: number,
	waitingOnChunkReady: boolean,
	dependencyChunkKey: string,
	lastDeferredAt: number,
	lastDeferredReason: string,
	regionState: string,
	regionReason: string,
}

type WakeRequest = {
	key: string,
	tileX: number,
	tileY: number,
	radius: number,
	reason: string,
	sourceTileX: number?,
	sourceTileY: number?,
	scanNearby: boolean,
}

type RecentChunkActivity = {
	key: string,
	chunkX: number,
	chunkY: number,
	touchedAt: number,
}

type PlayerStream = {
	ready: boolean,
	interestKeys: { [string]: boolean },
	simulationInterestKeys: { [string]: boolean },
	sentRevisions: { [string]: number },
	fullQueue: { string },
	fullQueueHead: number,
	fullQueueTail: number,
	fullQueueLookup: { [string]: boolean },
}

type PlayerHazardRuntime = {
	lastQuery: LiquidQueryResult?,
	lastQueryAt: number,
	wasInLiquid: boolean,
	wasMeaningfullySubmerged: boolean,
	wasBurning: boolean,
	lastDominantType: number,
	lastLavaDamageAt: number,
	lastBurnDamageAt: number,
	burnEndsAt: number,
}

type SimulationTickStats = {
	activeChunks: number,
	dirtyChunks: number,
	queuedCells: number,
	wakeRequestsQueued: number,
	wakeRequestsProcessed: number,
	activeCells: number,
	cellsProcessed: number,
	crossChunkWakeups: number,
	downwardTransfers: number,
	lateralTransfers: number,
	solverIterations: number,
	consistencyRequeues: number,
	deferredChunks: number,
	chunkReadinessWakeups: number,
	collisionChunksLoaded: number,
}

local LiquidServiceServer = {}

local function isGameplayReplicationActive(player: Player): boolean
	local activeCheck = (PlayerServiceServer :: any).isGameplayActiveForPlayer
	if typeof(activeCheck) ~= "function" then
		return true
	end
	local ok, isActive = pcall(function()
		return (PlayerServiceServer :: any):IsGameplayActiveForPlayer(player)
	end)
	return ok and isActive == true
end

local LIQUID_TYPE = LiquidServiceUtils.LIQUID_TYPE
local CELL_DEBUG_STATE = LiquidServiceUtils.CELL_DEBUG_STATE
local LiquidCell = LiquidServiceUtils.LiquidCell
local LiquidQuery = LiquidServiceUtils.LiquidQuery
local LiquidDamage = LiquidServiceUtils.LiquidDamage
local LiquidSolver = LiquidServiceUtils.LiquidSolver

local FULL_SNAPSHOT_BUDGET_PER_PLAYER = 3
local QUERY_CACHE_WINDOW = 1 / 30
local CELL_DEBUG_PART_DEPTH = 0.08

local CELL_DEBUG_COLORS = {
	[CELL_DEBUG_STATE.ACTIVE] = Color3.fromRGB(255, 255, 255),
	[CELL_DEBUG_STATE.STABLE] = Color3.fromRGB(94, 218, 122),
	[CELL_DEBUG_STATE.BLOCKED] = Color3.fromRGB(133, 144, 156),
	[CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN] = Color3.fromRGB(83, 101, 120),
	[CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK] = Color3.fromRGB(255, 153, 71),
	[CELL_DEBUG_STATE.SEARCHING_LEAK_PATH] = Color3.fromRGB(255, 216, 84),
	[CELL_DEBUG_STATE.FALLING] = Color3.fromRGB(88, 196, 255),
	[CELL_DEBUG_STATE.EQUALIZING] = Color3.fromRGB(112, 154, 255),
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function GetSourceConfig(): any
	if typeof(Configs) ~= "table" then
		return nil
	end
	return (Configs :: any).liquid
end

local function createStringQueue(): ({ string }, number, number, { [string]: boolean })
	return {}, 1, 0, {}
end

local function enqueueString(queue: { string }, queueLookup: { [string]: boolean }, tail: number, value: string): number
	if queueLookup[value] then
		return tail
	end
	queueLookup[value] = true
	tail += 1
	queue[tail] = value
	return tail
end

local function dequeueString(
	queue: { string },
	queueLookup: { [string]: boolean },
	head: number,
	tail: number
): (string?, number, number)
	if head > tail then
		if head ~= 1 or tail ~= 0 then
			table.clear(queue)
			head = 1
			tail = 0
		end
		return nil, head, tail
	end
	local value = queue[head]
	queue[head] = nil
	head += 1
	if value ~= nil then
		queueLookup[value] = nil
	end
	if head > tail then
		table.clear(queue)
		head = 1
		tail = 0
	end
	return value, head, tail
end

local function CoerceChunkDebugName(chunkKey: string): string
	return string.gsub(chunkKey, ":", "_")
end

local function getDirtyCount(runtime: ChunkRuntime): number
	return math.max(0, runtime.queuedDirtyCount)
end

local function appendReason(reasons: { string }, label: string)
	for _, existing in reasons do
		if existing == label then
			return
		end
	end
	table.insert(reasons, label)
end

local function createSimulationTickStats(): SimulationTickStats
	return {
		activeChunks = 0,
		dirtyChunks = 0,
		queuedCells = 0,
		wakeRequestsQueued = 0,
		wakeRequestsProcessed = 0,
		activeCells = 0,
		cellsProcessed = 0,
		crossChunkWakeups = 0,
		downwardTransfers = 0,
		lateralTransfers = 0,
		solverIterations = 0,
		consistencyRequeues = 0,
		deferredChunks = 0,
		chunkReadinessWakeups = 0,
		collisionChunksLoaded = 0,
	}
end

local function GetPlayerCharacter(player: Player): Model?
	local character = player.Character
	if character ~= nil and character:IsA("Model") then
		return character
	end
	return nil
end

local function GetCharacterRootPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
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

local function GetCharacterHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid:IsA("Humanoid") then
		return humanoid
	end
	return nil
end

function LiquidServiceServer.CreateChunkRuntime(self: LiquidServiceServer, chunkKey: string): ChunkRuntime
	local runtime: ChunkRuntime = {
		key = chunkKey,
		revision = 1,
		dirtyLookup = {},
		queuedDirtyCount = 0,
		pendingDeltaByIndex = {},
		pendingDeltaIndices = {},
		pendingDeltaCount = 0,
		forceFullResync = false,
		lastDisturbedAt = -math.huge,
		lastActiveStepId = 0,
		lastActivationAt = -math.huge,
		lastActivationReason = "never",
		lastStableAt = -math.huge,
		lastStableReason = "never",
		lastProcessedAt = -math.huge,
		lastProcessedCells = 0,
		lastChangedCells = 0,
		lastPrimedCells = 0,
		dirtyMarkCount = 0,
		mutationCount = 0,
		lastMutationTileX = 0,
		lastMutationTileY = 0,
		lastMutationFill = 0,
		lastMutationType = LIQUID_TYPE.NONE,
		lastActiveCellCount = 0,
		lastDownwardTransfer = 0,
		lastLateralTransfer = 0,
		lastCrossChunkWakeups = 0,
		lastStabilityScanUnstableCells = 0,
		waitingOnChunkReady = false,
		dependencyChunkKey = "",
		lastDeferredAt = -math.huge,
		lastDeferredReason = "never",
		regionState = CELL_DEBUG_STATE.ACTIVE,
		regionReason = "initial",
	}
	return runtime
end

function LiquidServiceServer.GetChunkRuntime(self: LiquidServiceServer, chunkKey: string): ChunkRuntime
	local runtime = self.chunkRuntimes[chunkKey]
	if runtime ~= nil then
		return runtime
	end
	runtime = self:CreateChunkRuntime(chunkKey)
	self.chunkRuntimes[chunkKey] = runtime
	return runtime
end

function LiquidServiceServer.IsCollisionChunkReadyByKey(self: LiquidServiceServer, chunkKey: string): boolean
	local world = self.world
	if world == nil then
		return false
	end
	local readinessMethod = (world :: any).IsChunkCollisionReadyByKey
	if typeof(readinessMethod) == "function" then
		return readinessMethod(world, chunkKey) == true
	end
	return true
end

function LiquidServiceServer.GetLoadedCollisionChunkCount(self: LiquidServiceServer): number
	local world = self.world
	if world == nil then
		return 0
	end
	local countMethod = (world :: any).GetLoadedCollisionChunkCount
	if typeof(countMethod) == "function" then
		local count = countMethod(world)
		if isFiniteNumber(count) then
			return math.max(0, math.floor(count))
		end
	end
	return 0
end

function LiquidServiceServer.SetChunkRegionState(
	self: LiquidServiceServer,
	chunkKey: string,
	runtime: ChunkRuntime,
	state: string,
	reasonRaw: any?,
	dependencyChunkKeyRaw: any?
)
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else state
	runtime.regionState = state
	runtime.regionReason = reason
	if state == CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK then
		runtime.waitingOnChunkReady = true
		runtime.dependencyChunkKey = if typeof(dependencyChunkKeyRaw) == "string" then dependencyChunkKeyRaw else ""
		runtime.lastDeferredAt = os.clock()
		runtime.lastDeferredReason = reason
	else
		runtime.waitingOnChunkReady = false
		runtime.dependencyChunkKey = ""
	end
	self:UpdateChunkDebugAttributes(chunkKey, runtime)
end

function LiquidServiceServer.RestoreQueuedDirtyCellsForChunk(
	self: LiquidServiceServer,
	chunkKey: string,
	reasonRaw: any?
): number
	local runtime = self.chunkRuntimes[chunkKey]
	if runtime == nil or getDirtyCount(runtime) <= 0 then
		return 0
	end
	local snapshot = self:GetChunkSnapshot(chunkKey)
	if snapshot == nil then
		return 0
	end
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "chunkReady"
	local requeued = 0
	for index in runtime.dirtyLookup do
		local zeroIndex = index - 1
		local localY = math.floor(zeroIndex / snapshot.width)
		local localX = zeroIndex - localY * snapshot.width
		self:RequeueDirtyMutation({
			x = snapshot.tileMinX + localX,
			y = snapshot.tileMinY + localY,
			z = 0,
			tileId = 1,
			metadata = {
				chunkKey = chunkKey,
				reason = reason,
			},
		})
		requeued += 1
	end
	return requeued
end

function LiquidServiceServer.WakeChunkBounds(
	self: LiquidServiceServer,
	chunkX: number,
	chunkY: number,
	dirtyBoundsRaw: any?,
	reasonRaw: any?,
	sourceTileXRaw: any?,
	sourceTileYRaw: any?
)
	local world = self.world
	if world == nil then
		return 0
	end
	local dirtyBounds = if typeof(dirtyBoundsRaw) == "table" then dirtyBoundsRaw :: { [string]: any } else {} :: any
	local chunkMinX = chunkX * world.chunkSize
	local chunkMinY = chunkY * world.chunkSize
	local chunkMaxX = chunkMinX + world.chunkSize - 1
	local chunkMaxY = chunkMinY + world.chunkSize - 1
	local minTileX = if isFiniteNumber(dirtyBounds.minTileX) then math.floor(dirtyBounds.minTileX) else chunkMinX
	local minTileY = if isFiniteNumber(dirtyBounds.minTileY) then math.floor(dirtyBounds.minTileY) else chunkMinY
	local maxTileX = if isFiniteNumber(dirtyBounds.maxTileX) then math.floor(dirtyBounds.maxTileX) else chunkMaxX
	local maxTileY = if isFiniteNumber(dirtyBounds.maxTileY) then math.floor(dirtyBounds.maxTileY) else chunkMaxY
	local sourceTileX = if isFiniteNumber(sourceTileXRaw) then math.floor(sourceTileXRaw :: number) else nil
	local sourceTileY = if isFiniteNumber(sourceTileYRaw) then math.floor(sourceTileYRaw :: number) else nil
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "chunkWake"
	local marked = 0

	for tileY = math.max(chunkMinY, minTileY), math.min(chunkMaxY, maxTileY) do
		for tileX = math.max(chunkMinX, minTileX), math.min(chunkMaxX, maxTileX) do
			if self:MarkTileDirty(tileX, tileY, reason, sourceTileX, sourceTileY) then
				marked += 1
			end
		end
	end

	return marked
end

function LiquidServiceServer.WakeChunkDependencyNeighborhood(
	self: LiquidServiceServer,
	chunkX: number,
	chunkY: number,
	reasonRaw: any?
)
	local world = self.world
	if world == nil then
		return
	end
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "chunkReady"
	for offsetY = -1, 1 do
		for offsetX = -1, 1 do
			local neighborChunkX = chunkX + offsetX
			local neighborChunkY = chunkY + offsetY
			local neighborKey = LiquidServiceUtils.PackChunkKey(neighborChunkX, neighborChunkY)
			local runtime = if offsetX == 0 and offsetY == 0
				then self:GetChunkRuntime(neighborKey)
				else self.chunkRuntimes[neighborKey]
			if self:IsCollisionChunkReadyByKey(neighborKey) then
				if runtime == nil then
					continue
				end
				local restored = self:RestoreQueuedDirtyCellsForChunk(neighborKey, `{reason}:restoreDirty`)
				if restored == 0 then
					self:PrimeChunkRuntime(neighborKey, reason)
				end
				self:SetChunkRegionState(neighborKey, runtime, CELL_DEBUG_STATE.ACTIVE, reason)
			else
				if runtime == nil then
					continue
				end
				self:SetChunkRegionState(
					neighborKey,
					runtime,
					CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
					`awaitingCollisionChunk {neighborKey}`,
					neighborKey
				)
			end
		end
	end
end

function LiquidServiceServer.OnChunkCollisionReady(
	self: LiquidServiceServer,
	chunkXRaw: any,
	chunkYRaw: any,
	contextRaw: any?
)
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return
	end
	local chunkX = math.floor(chunkXRaw)
	local chunkY = math.floor(chunkYRaw)
	local chunkKey = LiquidServiceUtils.PackChunkKey(chunkX, chunkY)
	local context = if typeof(contextRaw) == "table" then contextRaw :: { [string]: any } else {} :: any
	self.pendingChunkReadinessWakeups += 1
	self:DebugLog(
		"logActivations",
		`{chunkKey} collision-ready ({if typeof(context.reason) == "string" then context.reason else "ready"})`
	)
	self:WakeChunkDependencyNeighborhood(chunkX, chunkY, "chunkCollisionReady")
end

function LiquidServiceServer.OnChunkCollisionUnloaded(
	self: LiquidServiceServer,
	chunkXRaw: any,
	chunkYRaw: any,
	_contextRaw: any?
)
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return
	end
	local chunkX = math.floor(chunkXRaw)
	local chunkY = math.floor(chunkYRaw)
	local chunkKey = LiquidServiceUtils.PackChunkKey(chunkX, chunkY)
	local runtime = self:GetChunkRuntime(chunkKey)
	self:SetChunkRegionState(
		chunkKey,
		runtime,
		CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
		`awaitingCollisionChunk {chunkKey}`,
		chunkKey
	)
	self:DebugLog("logStableTransitions", `{chunkKey} deferred (collision chunk unloaded)`)
	for offsetY = -1, 1 do
		for offsetX = -1, 1 do
			if offsetX == 0 and offsetY == 0 then
				continue
			end
			local neighborChunkX = chunkX + offsetX
			local neighborChunkY = chunkY + offsetY
			local neighborKey = LiquidServiceUtils.PackChunkKey(neighborChunkX, neighborChunkY)
			local neighborRuntime = self.chunkRuntimes[neighborKey]
			if neighborRuntime == nil or not self:IsCollisionChunkReadyByKey(neighborKey) then
				continue
			end
			self:PrimeChunkRuntime(neighborKey, "neighborCollisionUnavailable")
			self:SetChunkRegionState(
				neighborKey,
				neighborRuntime,
				CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
				`awaitingCollisionChunk {chunkKey}`,
				chunkKey
			)
		end
	end
end

function LiquidServiceServer.OnChunkTerrainChanged(
	self: LiquidServiceServer,
	chunkXRaw: any,
	chunkYRaw: any,
	dirtyBoundsRaw: any?,
	contextRaw: any?
)
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return
	end
	local chunkX = math.floor(chunkXRaw)
	local chunkY = math.floor(chunkYRaw)
	local chunkKey = LiquidServiceUtils.PackChunkKey(chunkX, chunkY)
	local context = if typeof(contextRaw) == "table" then contextRaw :: { [string]: any } else {} :: any
	local runtime = self:GetChunkRuntime(chunkKey)
	local sourceTileX = if isFiniteNumber(context.sourceTileX) then math.floor(context.sourceTileX) else nil
	local sourceTileY = if isFiniteNumber(context.sourceTileY) then math.floor(context.sourceTileY) else nil
	local nextTileId = if isFiniteNumber(context.nextTileId) then math.floor(context.nextTileId) else nil
	local reason = if typeof(context.reason) == "string" and context.reason ~= ""
		then context.reason
		else "chunkTerrainChanged"

	if
		sourceTileX ~= nil
		and sourceTileY ~= nil
		and nextTileId ~= nil
		and self.world ~= nil
		and nextTileId ~= self.world.tileId.AIR
	then
		local packedCell = self.world:GetLiquidCellAt(sourceTileX, sourceTileY)
		if packedCell ~= 0 then
			self:SetPackedCell(sourceTileX, sourceTileY, 0)
			self:RedistributeDisplacedLiquid(sourceTileX, sourceTileY, packedCell)
		end
	end

	self:SetChunkRegionState(
		chunkKey,
		runtime,
		CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
		`awaitingCollisionChunk {chunkKey}`,
		chunkKey
	)
	self:WakeChunkBounds(chunkX, chunkY, dirtyBoundsRaw, reason, sourceTileX, sourceTileY)
	if sourceTileX ~= nil and sourceTileY ~= nil then
		self:WakeLiquidRegion(sourceTileX, sourceTileY, reason, {
			radius = 2,
			sourceTileX = sourceTileX,
			sourceTileY = sourceTileY,
			scanNearby = true,
		})
	end
end

function LiquidServiceServer.IsDebugEnabled(self: LiquidServiceServer): boolean
	return self.config.debug.enabled
end

function LiquidServiceServer.ShouldDebugLog(self: LiquidServiceServer, flagName: string): boolean
	if not self:IsDebugEnabled() then
		return false
	end
	return (self.config.debug :: any)[flagName] == true
end

function LiquidServiceServer.DebugLog(self: LiquidServiceServer, _flagName: string, _message: string)
	return
end

function LiquidServiceServer.GetDebugFolder(self: LiquidServiceServer): Folder?
	if not self:IsDebugEnabled() then
		return nil
	end
	if not self.config.debug.visualizeChunks and not self.config.debug.visualizeCells then
		return nil
	end
	if self.debugFolder ~= nil and self.debugFolder.Parent ~= nil then
		return self.debugFolder
	end
	self.debugFolder = WorkspaceFolders.GetOrCreateFolderInGame("LiquidDebug")
	return self.debugFolder
end

function LiquidServiceServer.GetChunkDebugFolder(self: LiquidServiceServer, chunkKey: string): Folder?
	local debugFolder = self:GetDebugFolder()
	if debugFolder == nil then
		return nil
	end
	local folderName = `Chunk_{CoerceChunkDebugName(chunkKey)}`
	local existing = debugFolder:FindFirstChild(folderName)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = debugFolder
	return folder
end

function LiquidServiceServer.GetChunkCellDebugFolder(self: LiquidServiceServer, chunkKey: string): Folder?
	if not self.config.debug.visualizeCells then
		return nil
	end
	local chunkFolder = self:GetChunkDebugFolder(chunkKey)
	if chunkFolder == nil then
		return nil
	end
	local existing = chunkFolder:FindFirstChild("Cells")
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Cells"
	folder.Parent = chunkFolder
	return folder
end

function LiquidServiceServer.UpdateSimulationDebugStats(self: LiquidServiceServer)
	local debugFolder = self:GetDebugFolder()
	local debugCounters = if self.debug ~= nil then self.debug:GetCounters() else {} :: any
	local wakePoolStats = if self.wakeRequestPool ~= nil
			and typeof((self.wakeRequestPool :: any).GetStats) == "function"
		then (self.wakeRequestPool :: any):GetStats()
		else {} :: any
	if debugFolder == nil then
		if self.debug ~= nil then
			self.debug:SetCounter("liquid_active_chunks", self.currentSimulationStats.activeChunks)
			self.debug:SetCounter("liquid_dirty_chunks", self.currentSimulationStats.dirtyChunks)
			self.debug:SetCounter("liquid_queued_cells", self.currentSimulationStats.queuedCells)
			self.debug:SetCounter("liquid_pending_wake_requests", self:GetPendingWakeRequestCount())
			self.debug:SetCounter("liquid_wake_requests_queued", self.currentSimulationStats.wakeRequestsQueued)
			self.debug:SetCounter("liquid_wake_requests_processed", self.currentSimulationStats.wakeRequestsProcessed)
			self.debug:SetCounter("liquid_cells_processed", self.currentSimulationStats.cellsProcessed)
			self.debug:SetCounter("liquid_active_cells", self.currentSimulationStats.activeCells)
			self.debug:SetCounter("liquid_cross_chunk_wakeups", self.currentSimulationStats.crossChunkWakeups)
			self.debug:SetCounter("liquid_downward_transfer", self.currentSimulationStats.downwardTransfers)
			self.debug:SetCounter("liquid_lateral_transfer", self.currentSimulationStats.lateralTransfers)
			self.debug:SetCounter("liquid_solver_iterations", self.currentSimulationStats.solverIterations)
			self.debug:SetCounter("liquid_consistency_requeues", self.currentSimulationStats.consistencyRequeues)
			self.debug:SetCounter("liquid_deferred_chunks", self.currentSimulationStats.deferredChunks)
			self.debug:SetCounter("liquid_chunk_readiness_wakeups", self.currentSimulationStats.chunkReadinessWakeups)
			self.debug:SetCounter("liquid_collision_chunks_loaded", self.currentSimulationStats.collisionChunksLoaded)
			self.debug:SetCounter(
				"liquid_wake_pool_available",
				if typeof(wakePoolStats.available) == "number" then wakePoolStats.available else 0
			)
			self.debug:SetCounter(
				"liquid_wake_pool_in_use",
				if typeof(wakePoolStats.inUse) == "number" then wakePoolStats.inUse else 0
			)
		end
		return
	end
	debugFolder:SetAttribute("SimulationStepId", self.simulationStepId)
	debugFolder:SetAttribute("ActiveChunks", self.currentSimulationStats.activeChunks)
	debugFolder:SetAttribute("DirtyChunks", self.currentSimulationStats.dirtyChunks)
	debugFolder:SetAttribute("QueuedCells", self.currentSimulationStats.queuedCells)
	debugFolder:SetAttribute("PendingWakeRequests", self:GetPendingWakeRequestCount())
	debugFolder:SetAttribute("WakeRequestsQueued", self.currentSimulationStats.wakeRequestsQueued)
	debugFolder:SetAttribute("WakeRequestsProcessed", self.currentSimulationStats.wakeRequestsProcessed)
	debugFolder:SetAttribute("ActiveCells", self.currentSimulationStats.activeCells)
	debugFolder:SetAttribute("CellsProcessed", self.currentSimulationStats.cellsProcessed)
	debugFolder:SetAttribute("CrossChunkWakeups", self.currentSimulationStats.crossChunkWakeups)
	debugFolder:SetAttribute("DownwardTransfers", self.currentSimulationStats.downwardTransfers)
	debugFolder:SetAttribute("LateralTransfers", self.currentSimulationStats.lateralTransfers)
	debugFolder:SetAttribute("SolverIterations", self.currentSimulationStats.solverIterations)
	debugFolder:SetAttribute("ConsistencyRequeues", self.currentSimulationStats.consistencyRequeues)
	debugFolder:SetAttribute("DeferredChunks", self.currentSimulationStats.deferredChunks)
	debugFolder:SetAttribute("ChunkReadinessWakeups", self.currentSimulationStats.chunkReadinessWakeups)
	debugFolder:SetAttribute("CollisionChunksLoaded", self.currentSimulationStats.collisionChunksLoaded)
	debugFolder:SetAttribute(
		"WakePoolAvailable",
		if typeof(wakePoolStats.available) == "number" then wakePoolStats.available else 0
	)
	debugFolder:SetAttribute(
		"WakePoolInUse",
		if typeof(wakePoolStats.inUse) == "number" then wakePoolStats.inUse else 0
	)
	debugFolder:SetAttribute(
		"TimeServerSolveMs",
		math.round(((debugCounters.time_liquid_server_solve or 0) * 1000) * 100) / 100
	)
	debugFolder:SetAttribute(
		"TimeConsistencySweepMs",
		math.round(((debugCounters.time_liquid_consistency_sweep or 0) * 1000) * 100) / 100
	)
	if self.debug ~= nil then
		self.debug:SetCounter("liquid_active_chunks", self.currentSimulationStats.activeChunks)
		self.debug:SetCounter("liquid_dirty_chunks", self.currentSimulationStats.dirtyChunks)
		self.debug:SetCounter("liquid_queued_cells", self.currentSimulationStats.queuedCells)
		self.debug:SetCounter("liquid_pending_wake_requests", self:GetPendingWakeRequestCount())
		self.debug:SetCounter("liquid_wake_requests_queued", self.currentSimulationStats.wakeRequestsQueued)
		self.debug:SetCounter("liquid_wake_requests_processed", self.currentSimulationStats.wakeRequestsProcessed)
		self.debug:SetCounter("liquid_cells_processed", self.currentSimulationStats.cellsProcessed)
		self.debug:SetCounter("liquid_active_cells", self.currentSimulationStats.activeCells)
		self.debug:SetCounter("liquid_cross_chunk_wakeups", self.currentSimulationStats.crossChunkWakeups)
		self.debug:SetCounter("liquid_downward_transfer", self.currentSimulationStats.downwardTransfers)
		self.debug:SetCounter("liquid_lateral_transfer", self.currentSimulationStats.lateralTransfers)
		self.debug:SetCounter("liquid_solver_iterations", self.currentSimulationStats.solverIterations)
		self.debug:SetCounter("liquid_consistency_requeues", self.currentSimulationStats.consistencyRequeues)
		self.debug:SetCounter("liquid_deferred_chunks", self.currentSimulationStats.deferredChunks)
		self.debug:SetCounter("liquid_chunk_readiness_wakeups", self.currentSimulationStats.chunkReadinessWakeups)
		self.debug:SetCounter("liquid_collision_chunks_loaded", self.currentSimulationStats.collisionChunksLoaded)
		self.debug:SetCounter(
			"liquid_wake_pool_available",
			if typeof(wakePoolStats.available) == "number" then wakePoolStats.available else 0
		)
		self.debug:SetCounter(
			"liquid_wake_pool_in_use",
			if typeof(wakePoolStats.inUse) == "number" then wakePoolStats.inUse else 0
		)
	end
end

function LiquidServiceServer.UpdateCellDebugVisual(
	self: LiquidServiceServer,
	tileX: number,
	tileY: number,
	state: string,
	reason: string,
	fill: number,
	liquidType: number
)
	if not self:IsDebugEnabled() or not self.config.debug.visualizeCells then
		return
	end
	local world = self.world
	if world == nil then
		return
	end
	local chunkKey = LiquidServiceUtils.PackChunkKey(
		LiquidServiceUtils.ToChunkCoordinate(tileX, world.chunkSize),
		LiquidServiceUtils.ToChunkCoordinate(tileY, world.chunkSize)
	)
	local folder = self:GetChunkCellDebugFolder(chunkKey)
	if folder == nil then
		return
	end

	local partName = `Cell_{tileX}_{tileY}`
	local existing = folder:FindFirstChild(partName)
	if fill <= 0 or liquidType == LIQUID_TYPE.NONE then
		if existing ~= nil then
			existing:Destroy()
		end
		return
	end

	local part = if existing ~= nil and existing:IsA("Part") then existing else nil
	if part == nil then
		if existing ~= nil then
			existing:Destroy()
		end
		local newPart = Instance.new("Part")
		newPart.Name = partName
		newPart.Anchored = true
		newPart.CanCollide = false
		newPart.CanQuery = false
		newPart.CanTouch = false
		newPart.CastShadow = false
		newPart.Material = Enum.Material.Neon
		newPart.Parent = folder
		part = newPart
	end
	local debugPart = part :: Part

	local basePlaneX = if isFiniteNumber((world :: any).basePlaneX) then (world :: any).basePlaneX else 0
	local center = LiquidServiceUtils.TileToWorldCenter(tileX, tileY, world.worldOrigin, world.tileSize, basePlaneX)
	debugPart.CFrame = CFrame.new(center.X - 0.9, center.Y, center.Z)
	debugPart.Size = Vector3.new(CELL_DEBUG_PART_DEPTH, world.tileSize * 0.22, world.tileSize * 0.22)
	debugPart.Color = CELL_DEBUG_COLORS[state] or Color3.fromRGB(255, 255, 255)
	debugPart.Transparency = if state == CELL_DEBUG_STATE.STABLE
			or state == CELL_DEBUG_STATE.BLOCKED
			or state == CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN
		then 0.45
		else 0.15
	debugPart:SetAttribute("TileX", tileX)
	debugPart:SetAttribute("TileY", tileY)
	debugPart:SetAttribute("State", state)
	debugPart:SetAttribute("Reason", reason)
	debugPart:SetAttribute("Fill", fill)
	debugPart:SetAttribute("LiquidType", liquidType)
end

function LiquidServiceServer.UpdateChunkDebugAttributes(
	self: LiquidServiceServer,
	chunkKey: string,
	runtime: ChunkRuntime,
	extraRaw: any?
)
	if not self.config.debug.visualizeChunks then
		return
	end
	local folder = self:GetChunkDebugFolder(chunkKey)
	if folder == nil then
		return
	end
	local extra = if typeof(extraRaw) == "table" then extraRaw :: { [string]: any } else {} :: any
	folder:SetAttribute("ChunkKey", chunkKey)
	folder:SetAttribute("Revision", runtime.revision)
	folder:SetAttribute("DirtyCount", getDirtyCount(runtime))
	folder:SetAttribute("HasDirtyCells", getDirtyCount(runtime) > 0)
	folder:SetAttribute("LastDisturbedAt", runtime.lastDisturbedAt)
	folder:SetAttribute("LastActiveStepId", runtime.lastActiveStepId)
	folder:SetAttribute("LastActivationAt", runtime.lastActivationAt)
	folder:SetAttribute("LastActivationReason", runtime.lastActivationReason)
	folder:SetAttribute("LastStableAt", runtime.lastStableAt)
	folder:SetAttribute("LastStableReason", runtime.lastStableReason)
	folder:SetAttribute("LastProcessedAt", runtime.lastProcessedAt)
	folder:SetAttribute("LastProcessedCells", runtime.lastProcessedCells)
	folder:SetAttribute("LastChangedCells", runtime.lastChangedCells)
	folder:SetAttribute("LastPrimedCells", runtime.lastPrimedCells)
	folder:SetAttribute("DirtyMarks", runtime.dirtyMarkCount)
	folder:SetAttribute("MutationCount", runtime.mutationCount)
	folder:SetAttribute("LastMutationTileX", runtime.lastMutationTileX)
	folder:SetAttribute("LastMutationTileY", runtime.lastMutationTileY)
	folder:SetAttribute("LastMutationFill", runtime.lastMutationFill)
	folder:SetAttribute("LastMutationType", runtime.lastMutationType)
	folder:SetAttribute("LastActiveCellCount", runtime.lastActiveCellCount)
	folder:SetAttribute("LastDownwardTransfer", runtime.lastDownwardTransfer)
	folder:SetAttribute("LastLateralTransfer", runtime.lastLateralTransfer)
	folder:SetAttribute("LastCrossChunkWakeups", runtime.lastCrossChunkWakeups)
	folder:SetAttribute("LastStabilityScanUnstableCells", runtime.lastStabilityScanUnstableCells)
	folder:SetAttribute("WaitingOnChunkReady", runtime.waitingOnChunkReady)
	folder:SetAttribute("DependencyChunkKey", runtime.dependencyChunkKey)
	folder:SetAttribute("LastDeferredAt", runtime.lastDeferredAt)
	folder:SetAttribute("LastDeferredReason", runtime.lastDeferredReason)
	folder:SetAttribute("RegionState", runtime.regionState)
	folder:SetAttribute("RegionReason", runtime.regionReason)
	folder:SetAttribute("CollisionChunkReady", self:IsCollisionChunkReadyByKey(chunkKey))
	if extra.InActiveSet ~= nil then
		folder:SetAttribute("InActiveSet", extra.InActiveSet == true)
	end
	if typeof(extra.ActiveReason) == "string" then
		folder:SetAttribute("ActiveReason", extra.ActiveReason)
	end
	if isFiniteNumber(extra.LastStepBudget) then
		folder:SetAttribute("LastStepBudget", math.floor(extra.LastStepBudget))
	end
	if isFiniteNumber(extra.LastQueuedTileX) then
		folder:SetAttribute("LastQueuedTileX", math.floor(extra.LastQueuedTileX))
	end
	if isFiniteNumber(extra.LastQueuedTileY) then
		folder:SetAttribute("LastQueuedTileY", math.floor(extra.LastQueuedTileY))
	end
	if typeof(extra.LastDirtyReason) == "string" then
		folder:SetAttribute("LastDirtyReason", extra.LastDirtyReason)
	end
end

function LiquidServiceServer.CreatePlayerStream(self: LiquidServiceServer): PlayerStream
	local fullQueue, head, tail, lookup = createStringQueue()
	return {
		ready = false,
		interestKeys = {},
		simulationInterestKeys = {},
		sentRevisions = {},
		fullQueue = fullQueue,
		fullQueueHead = head,
		fullQueueTail = tail,
		fullQueueLookup = lookup,
	}
end

function LiquidServiceServer.GetPlayerStream(self: LiquidServiceServer, player: Player): PlayerStream
	local stream = self.playerStreams[player]
	if stream ~= nil then
		return stream
	end
	stream = self:CreatePlayerStream()
	self.playerStreams[player] = stream
	return stream
end

function LiquidServiceServer.IsPlayerStreamReady(self: LiquidServiceServer, player: Player): boolean
	local stream = self.playerStreams[player]
	return stream ~= nil and stream.ready == true
end

function LiquidServiceServer.CreateHazardRuntime(self: LiquidServiceServer): PlayerHazardRuntime
	return {
		lastQuery = nil,
		lastQueryAt = -math.huge,
		wasInLiquid = false,
		wasMeaningfullySubmerged = false,
		wasBurning = false,
		lastDominantType = LIQUID_TYPE.NONE,
		lastLavaDamageAt = -math.huge,
		lastBurnDamageAt = -math.huge,
		burnEndsAt = -math.huge,
	}
end

function LiquidServiceServer.GetHazardRuntime(self: LiquidServiceServer, player: Player): PlayerHazardRuntime
	local runtime = self.playerHazards[player]
	if runtime ~= nil then
		return runtime
	end
	runtime = self:CreateHazardRuntime()
	self.playerHazards[player] = runtime
	return runtime
end

function LiquidServiceServer.CreateStateSnapshot(self: LiquidServiceServer): LiquidServiceState
	local world = self.world
	return LiquidServiceUtils.CreateState({
		ready = world ~= nil,
		tileSize = if world ~= nil and isFiniteNumber((world :: any).tileSize) then (world :: any).tileSize else 2,
		chunkSize = if world ~= nil and isFiniteNumber((world :: any).chunkSize)
			then math.floor((world :: any).chunkSize)
			else 32,
		worldOrigin = if world ~= nil and typeof((world :: any).worldOrigin) == "Vector3"
			then (world :: any).worldOrigin
			else Vector3.zero,
		maxFill = self.config.maxFill,
		interpolationTime = self.config.render.interpolationTime,
	}, self.state)
end

function LiquidServiceServer.PushState(self: LiquidServiceServer, player: Player)
	self.state = self:CreateStateSnapshot()
	sendPacket(player, LiquidServiceUtils.CLIENT_METHOD_APPLY_STATE, LiquidServiceUtils.CloneState(self.state))
end

function LiquidServiceServer.GetDefinition(self: LiquidServiceServer, liquidType: number): LiquidDefinition?
	return self.config.definitions[liquidType]
end

function LiquidServiceServer.GetChunkSnapshot(self: LiquidServiceServer, chunkKey: string): LiquidChunkSnapshot?
	local world = self.world
	if world == nil then
		return nil
	end
	local snapshotRaw = world:GetLiquidChunkSnapshotByKey(chunkKey)
	if typeof(snapshotRaw) ~= "table" then
		return nil
	end
	local source = snapshotRaw :: { [string]: any }
	local runtime = self:GetChunkRuntime(chunkKey)
	return {
		key = if typeof(source.key) == "string" then source.key else chunkKey,
		chunkX = if isFiniteNumber(source.chunkX) then math.floor(source.chunkX) else 0,
		chunkY = if isFiniteNumber(source.chunkY) then math.floor(source.chunkY) else 0,
		tileMinX = if isFiniteNumber(source.tileMinX) then math.floor(source.tileMinX) else 0,
		tileMinY = if isFiniteNumber(source.tileMinY) then math.floor(source.tileMinY) else 0,
		width = if isFiniteNumber(source.width) then math.floor(source.width) else world.chunkSize,
		height = if isFiniteNumber(source.height) then math.floor(source.height) else world.chunkSize,
		cells = if typeof(source.cells) == "table" then Sift.Dictionary.copy(source.cells) else {} :: any,
		revision = runtime.revision,
		updatedAt = os.clock(),
	}
end

function LiquidServiceServer.EnqueueFullSnapshot(self: LiquidServiceServer, stream: PlayerStream, chunkKey: string)
	stream.fullQueueTail = enqueueString(stream.fullQueue, stream.fullQueueLookup, stream.fullQueueTail, chunkKey)
end

function LiquidServiceServer.MarkChunkStable(
	self: LiquidServiceServer,
	chunkKey: string,
	runtime: ChunkRuntime,
	reason: string
)
	runtime.lastStableAt = os.clock()
	runtime.lastStableReason = reason
	local stableState = if runtime.regionState == CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN
		then CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN
		else CELL_DEBUG_STATE.STABLE
	self:SetChunkRegionState(chunkKey, runtime, stableState, reason)
	self:UpdateChunkDebugAttributes(chunkKey, runtime)
	self:DebugLog("logStableTransitions", `{chunkKey} stable ({reason})`)
end

function LiquidServiceServer.RecordSimulationMetric(
	self: LiquidServiceServer,
	metricName: string,
	amountRaw: any?,
	runtime: ChunkRuntime?
)
	if self.currentSimulationStats == nil then
		self.currentSimulationStats = createSimulationTickStats()
	end
	local amount = if isFiniteNumber(amountRaw) then math.max(0, amountRaw :: number) else 1
	if metricName == "activeCells" then
		self.currentSimulationStats.activeCells += amount
		if runtime ~= nil then
			runtime.lastActiveCellCount += amount
		end
	elseif metricName == "crossChunkWakeups" then
		self.currentSimulationStats.crossChunkWakeups += amount
		if runtime ~= nil then
			runtime.lastCrossChunkWakeups += amount
		end
	elseif metricName == "downwardTransfers" then
		self.currentSimulationStats.downwardTransfers += amount
		if runtime ~= nil then
			runtime.lastDownwardTransfer += amount
		end
	elseif metricName == "lateralTransfers" then
		self.currentSimulationStats.lateralTransfers += amount
		if runtime ~= nil then
			runtime.lastLateralTransfer += amount
		end
	elseif metricName == "solverIterations" then
		self.currentSimulationStats.solverIterations += amount
	elseif metricName == "cellsProcessed" then
		self.currentSimulationStats.cellsProcessed += amount
	elseif metricName == "consistencyRequeues" then
		self.currentSimulationStats.consistencyRequeues += amount
	elseif metricName == "chunkReadinessWakeups" then
		self.currentSimulationStats.chunkReadinessWakeups += amount
	end
end

function LiquidServiceServer.GetPendingWakeRequestCount(self: LiquidServiceServer): number
	if self.pendingWakeHead > self.pendingWakeTail then
		return 0
	end
	return self.pendingWakeTail - self.pendingWakeHead + 1
end

function LiquidServiceServer.GetChunkWorldPosition(
	self: LiquidServiceServer,
	chunkX: number,
	chunkY: number
): (number, number, number)
	local world = self.world
	if world == nil then
		return chunkX, chunkY, 0
	end
	local tileSize = math.max(0.001, world.tileSize)
	local centerTileX = chunkX * world.chunkSize + world.chunkSize * 0.5
	local centerTileY = chunkY * world.chunkSize + world.chunkSize * 0.5
	return world.worldOrigin.Z + centerTileX * tileSize, world.worldOrigin.Y + centerTileY * tileSize, 0
end

function LiquidServiceServer.TrackRecentChunkActivity(
	self: LiquidServiceServer,
	chunkKey: string,
	chunkX: number,
	chunkY: number
)
	local touchedAt = os.clock()
	self.recentChunkTouchedAt[chunkKey] = touchedAt
	local worldX, worldY, worldZ = self:GetChunkWorldPosition(chunkX, chunkY)
	local payload: RecentChunkActivity = {
		key = chunkKey,
		chunkX = chunkX,
		chunkY = chunkY,
		touchedAt = touchedAt,
	}
	if not self.recentChunkGrid:update(chunkKey, worldX, worldY, worldZ, payload) then
		self.recentChunkGrid:insert(chunkKey, worldX, worldY, worldZ, payload)
	end
end

function LiquidServiceServer.PruneRecentChunkActivity(self: LiquidServiceServer)
	local expiry = self.config.simulation.disturbedChunkKeepAliveSeconds * 2
	local now = os.clock()
	for chunkKey, touchedAt in self.recentChunkTouchedAt do
		if now - touchedAt <= expiry then
			continue
		end
		self.recentChunkTouchedAt[chunkKey] = nil
		self.recentChunkGrid:Remove(chunkKey)
	end
end

function LiquidServiceServer.RequeueDirtyMutation(self: LiquidServiceServer, mutationRaw: any)
	if typeof(mutationRaw) ~= "table" then
		return
	end
	self.dirtyCellQueue:Enqueue(mutationRaw)
end

function LiquidServiceServer.PrimeChunkRuntime(self: LiquidServiceServer, chunkKey: string, reasonRaw: any?): number
	local runtime = self:GetChunkRuntime(chunkKey)
	if not self:IsCollisionChunkReadyByKey(chunkKey) then
		self:SetChunkRegionState(
			chunkKey,
			runtime,
			CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
			`awaitingCollisionChunk {chunkKey}`,
			chunkKey
		)
		runtime.lastPrimedCells = 0
		self:UpdateChunkDebugAttributes(chunkKey, runtime)
		return 0
	end
	if getDirtyCount(runtime) > 0 then
		runtime.lastPrimedCells = 0
		self:UpdateChunkDebugAttributes(chunkKey, runtime)
		return 0
	end

	local snapshot = self:GetChunkSnapshot(chunkKey)
	if snapshot == nil then
		runtime.lastPrimedCells = 0
		self:UpdateChunkDebugAttributes(chunkKey, runtime)
		return 0
	end

	local primedCount = 0
	for index = 1, #snapshot.cells do
		local packedCell = snapshot.cells[index]
		if not isFiniteNumber(packedCell) or packedCell <= 0 then
			continue
		end
		local zeroIndex = index - 1
		local localY = math.floor(zeroIndex / snapshot.width)
		local localX = zeroIndex - localY * snapshot.width
		local tileX = snapshot.tileMinX + localX
		local tileY = snapshot.tileMinY + localY
		if self:MarkTileDirty(tileX, tileY, reasonRaw or "activation") then
			primedCount += 1
		end
	end

	runtime.lastPrimedCells = primedCount
	if primedCount > 0 then
		runtime.lastDisturbedAt = os.clock()
		self:DebugLog(
			"logActivations",
			`{chunkKey} primed {primedCount} liquid cells ({if typeof(reasonRaw) == "string"
				then reasonRaw
				else "activation"})`
		)
	end
	self:UpdateChunkDebugAttributes(chunkKey, runtime)
	return primedCount
end

function LiquidServiceServer.ExpandInterestKeys(
	self: LiquidServiceServer,
	baseInterest: { [string]: boolean }
): { [string]: boolean }
	local margin = math.max(0, self.config.simulation.activeSafetyMarginChunks)
	if margin <= 0 then
		local clone: { [string]: boolean } = {}
		for chunkKey in baseInterest do
			clone[chunkKey] = true
		end
		return clone
	end

	local expanded: { [string]: boolean } = {}
	for chunkKey in baseInterest do
		local chunkX, chunkY = LiquidServiceUtils.UnpackChunkKey(chunkKey)
		if chunkX == nil or chunkY == nil then
			continue
		end
		for offsetY = -margin, margin do
			for offsetX = -margin, margin do
				expanded[LiquidServiceUtils.PackChunkKey(chunkX + offsetX, chunkY + offsetY)] = true
			end
		end
	end
	return expanded
end

function LiquidServiceServer.RefreshPlayerInterest(self: LiquidServiceServer, player: Player)
	local world = self.world
	if world == nil then
		return
	end
	local stream = self:GetPlayerStream(player)
	if not stream.ready then
		return
	end
	local nextInterest = world:GetPlayerInterestKeys(player)
	local nextSimulationInterest = self:ExpandInterestKeys(nextInterest)

	for chunkKey in nextInterest do
		if stream.interestKeys[chunkKey] == nil or stream.sentRevisions[chunkKey] == nil then
			self:EnqueueFullSnapshot(stream, chunkKey)
		end
	end

	for chunkKey in stream.interestKeys do
		if nextInterest[chunkKey] then
			continue
		end
		stream.sentRevisions[chunkKey] = nil
		sendPacket(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_UNLOADED, chunkKey)
	end

	stream.interestKeys = nextInterest
	stream.simulationInterestKeys = nextSimulationInterest
end

function LiquidServiceServer.MarkTileDirty(
	self: LiquidServiceServer,
	tileX: number,
	tileY: number,
	reasonRaw: any?,
	sourceTileXRaw: any?,
	sourceTileYRaw: any?
): boolean
	local world = self.world
	if world == nil then
		return false
	end
	local chunkSize = math.max(1, world.chunkSize)
	local chunkX = LiquidServiceUtils.ToChunkCoordinate(tileX, chunkSize)
	local chunkY = LiquidServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	local chunkKey = LiquidServiceUtils.PackChunkKey(chunkX, chunkY)
	local runtime = self:GetChunkRuntime(chunkKey)
	local localX = tileX - chunkX * chunkSize
	local localY = tileY - chunkY * chunkSize
	if localX < 0 or localX >= chunkSize or localY < 0 or localY >= chunkSize then
		return false
	end
	local index = LiquidServiceUtils.ComputeTileIndex(localX, localY, chunkSize)
	if runtime.dirtyLookup[index] then
		return false
	end
	local sourceTileX = if isFiniteNumber(sourceTileXRaw) then math.floor(sourceTileXRaw :: number) else nil
	local sourceTileY = if isFiniteNumber(sourceTileYRaw) then math.floor(sourceTileYRaw :: number) else nil
	if sourceTileX ~= nil and sourceTileY ~= nil then
		local sourceChunkX = LiquidServiceUtils.ToChunkCoordinate(sourceTileX, chunkSize)
		local sourceChunkY = LiquidServiceUtils.ToChunkCoordinate(sourceTileY, chunkSize)
		local sourceChunkKey = LiquidServiceUtils.PackChunkKey(sourceChunkX, sourceChunkY)
		if sourceChunkKey ~= chunkKey then
			self:RecordSimulationMetric("crossChunkWakeups", 1, runtime)
		end
	end
	runtime.dirtyLookup[index] = true
	runtime.queuedDirtyCount += 1
	runtime.lastDisturbedAt = os.clock()
	runtime.dirtyMarkCount += 1
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "unspecified"
	self.dirtyCellQueue:Enqueue({
		x = tileX,
		y = tileY,
		z = 0,
		tileId = 1,
		metadata = {
			chunkKey = chunkKey,
			reason = reason,
			sourceTileX = sourceTileX,
			sourceTileY = sourceTileY,
		},
	})
	self:TrackRecentChunkActivity(chunkKey, chunkX, chunkY)
	self:UpdateChunkDebugAttributes(chunkKey, runtime, {
		LastQueuedTileX = tileX,
		LastQueuedTileY = tileY,
		LastDirtyReason = reason,
	})
	self:DebugLog("logDirtyMarks", `{chunkKey} queued tile {tileX},{tileY} ({reason})`)
	if self.debug ~= nil then
		self.debug:IncrementCounter("liquid_dirty_marks")
	end
	return true
end

function LiquidServiceServer.MarkAreaDirty(
	self: LiquidServiceServer,
	tileX: number,
	tileY: number,
	radiusRaw: any?,
	reasonRaw: any?
)
	self:WakeLiquidRegion(tileX, tileY, reasonRaw, {
		radius = radiusRaw,
		sourceTileX = tileX,
		sourceTileY = tileY,
		scanNearby = false,
	})
end

function LiquidServiceServer.WakeLiquidRegion(
	self: LiquidServiceServer,
	tileXRaw: any,
	tileYRaw: any,
	reasonRaw: any?,
	optionsRaw: any?
): boolean
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return false
	end
	local options = if typeof(optionsRaw) == "table" then optionsRaw :: { [string]: any } else {} :: any
	local tileX = math.floor(tileXRaw)
	local tileY = math.floor(tileYRaw)
	local radius = if isFiniteNumber(options.radius) then math.max(0, math.floor(options.radius :: number)) else 1
	local sourceTileX = if isFiniteNumber(options.sourceTileX) then math.floor(options.sourceTileX :: number) else nil
	local sourceTileY = if isFiniteNumber(options.sourceTileY) then math.floor(options.sourceTileY :: number) else nil
	local scanNearby = options.scanNearby == true
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "wakeRegion"
	local key = `{tileX}:{tileY}:{radius}:{if scanNearby then 1 else 0}`
	if self.pendingWakeLookup[key] then
		return false
	end

	local request = self.wakeRequestPool:Acquire() :: WakeRequest
	request.key = key
	request.tileX = tileX
	request.tileY = tileY
	request.radius = radius
	request.reason = reason
	request.sourceTileX = sourceTileX
	request.sourceTileY = sourceTileY
	request.scanNearby = scanNearby

	self.pendingWakeLookup[key] = true
	self.pendingWakeTail += 1
	self.pendingWakeQueue[self.pendingWakeTail] = request
	if self.debug ~= nil then
		self.debug:IncrementCounter("liquid_wake_requests_enqueued")
	end
	return true
end

function LiquidServiceServer.ApplyWakeRequest(self: LiquidServiceServer, request: WakeRequest)
	local sourceTileX = if request.sourceTileX ~= nil then request.sourceTileX else request.tileX
	local sourceTileY = if request.sourceTileY ~= nil then request.sourceTileY else request.tileY
	for offsetY = -request.radius, request.radius do
		for offsetX = -request.radius, request.radius do
			self:MarkTileDirty(
				request.tileX + offsetX,
				request.tileY + offsetY,
				request.reason,
				sourceTileX,
				sourceTileY
			)
		end
	end

	if not request.scanNearby then
		return
	end
	local world = self.world
	if world == nil then
		return
	end
	local horizontalRadius = 4 + request.radius
	local verticalBelow = 3 + request.radius
	local verticalAbove = 7 + request.radius
	for scanY = request.tileY - verticalBelow, request.tileY + verticalAbove do
		for scanX = request.tileX - horizontalRadius, request.tileX + horizontalRadius do
			if not self:IsTileCollisionReady(scanX, scanY) then
				continue
			end
			if world:GetLiquidCellAt(scanX, scanY) == 0 then
				continue
			end
			self:MarkTileDirty(scanX, scanY, `{request.reason}:nearbyLiquid`, request.tileX, request.tileY)
		end
	end
end

function LiquidServiceServer.FlushWakeRequests(self: LiquidServiceServer, maxRequestsRaw: any?): number
	local maxRequests = if isFiniteNumber(maxRequestsRaw)
		then math.max(1, math.floor(maxRequestsRaw :: number))
		else math.max(8, self.config.simulation.maxChunkStepsPerTick * 4)
	local processed = 0
	while processed < maxRequests do
		if self.pendingWakeHead > self.pendingWakeTail then
			if self.pendingWakeHead ~= 1 or self.pendingWakeTail ~= 0 then
				table.clear(self.pendingWakeQueue)
				self.pendingWakeHead = 1
				self.pendingWakeTail = 0
			end
			break
		end
		local request = self.pendingWakeQueue[self.pendingWakeHead] :: WakeRequest?
		self.pendingWakeQueue[self.pendingWakeHead] = nil
		self.pendingWakeHead += 1
		if request == nil then
			continue
		end
		self.pendingWakeLookup[request.key] = nil
		self:ApplyWakeRequest(request)
		self.wakeRequestPool:Release(request)
		processed += 1
	end
	if processed > 0 and self.debug ~= nil then
		self.debug:IncrementCounter("liquid_wake_requests_processed", processed)
	end
	return processed
end

function LiquidServiceServer.RegisterCellMutation(
	self: LiquidServiceServer,
	tileX: number,
	tileY: number,
	packedCell: number
)
	local world = self.world
	if world == nil then
		return
	end
	local chunkSize = math.max(1, world.chunkSize)
	local chunkX = LiquidServiceUtils.ToChunkCoordinate(tileX, chunkSize)
	local chunkY = LiquidServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	local chunkKey = LiquidServiceUtils.PackChunkKey(chunkX, chunkY)
	local runtime = self:GetChunkRuntime(chunkKey)
	local liquidType, fill = LiquidCell.Unpack(packedCell)
	runtime.revision += 1
	runtime.lastDisturbedAt = os.clock()
	runtime.mutationCount += 1
	runtime.lastMutationTileX = tileX
	runtime.lastMutationTileY = tileY
	runtime.lastMutationFill = fill
	runtime.lastMutationType = liquidType
	self.changedChunkKeys[chunkKey] = true
	self:UpdateChunkDebugAttributes(chunkKey, runtime)
	self:DebugLog("logSimulationSteps", `{chunkKey} mutated tile {tileX},{tileY} -> type={liquidType} fill={fill}`)
	if runtime.forceFullResync then
		return
	end

	local localX = tileX - chunkX * chunkSize
	local localY = tileY - chunkY * chunkSize
	local index = LiquidServiceUtils.ComputeTileIndex(localX, localY, chunkSize)
	if runtime.pendingDeltaByIndex[index] == nil then
		runtime.pendingDeltaCount += 1
		table.insert(runtime.pendingDeltaIndices, index)
	end
	runtime.pendingDeltaByIndex[index] = packedCell
	if
		runtime.pendingDeltaCount >= self.config.simulation.fullSnapshotThreshold
		or runtime.pendingDeltaCount >= self.config.simulation.maxDeltaCellsPerChunk
	then
		runtime.forceFullResync = true
	end
end

function LiquidServiceServer.SetPackedCell(
	self: LiquidServiceServer,
	tileX: number,
	tileY: number,
	packedCell: number
): boolean
	local world = self.world
	if world == nil then
		return false
	end
	local changed, _, nextPackedCell = world:SetLiquidCellAt(tileX, tileY, packedCell)
	if changed then
		self:RegisterCellMutation(tileX, tileY, nextPackedCell)
	end
	return changed
end

function LiquidServiceServer.IsSolid(self: LiquidServiceServer, tileX: number, tileY: number): boolean
	local world = self.world
	if world == nil then
		return true
	end
	local tileId = select(1, world:GetTileAt(tileX, tileY))
	return tileId ~= world.tileId.AIR
end

function LiquidServiceServer.IsTileCollisionReady(self: LiquidServiceServer, tileX: number, tileY: number): boolean
	local world = self.world
	if world == nil then
		return false
	end
	local chunkSize = math.max(1, world.chunkSize)
	local chunkX = LiquidServiceUtils.ToChunkCoordinate(tileX, chunkSize)
	local chunkY = LiquidServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	return world:IsChunkCollisionReady(chunkX, chunkY)
end

function LiquidServiceServer.BuildSolverAccess(self: LiquidServiceServer, runtime: ChunkRuntime): LiquidSolverAccess
	local world = self.world
	local access: LiquidSolverAccess = {
		maxFill = self.config.maxFill,
		chunkSize = if world ~= nil then world.chunkSize else 32,
		maxLeakScanDistance = self.config.simulation.leakScanDistanceTiles,
		getCell = function(tileX: number, tileY: number): number
			if world == nil then
				return 0
			end
			return world:GetLiquidCellAt(tileX, tileY)
		end,
		setCell = function(tileX: number, tileY: number, packedCell: number): boolean
			return self:SetPackedCell(tileX, tileY, packedCell)
		end,
		isSolid = function(tileX: number, tileY: number): boolean
			return self:IsSolid(tileX, tileY)
		end,
		isChunkReady = function(chunkX: number, chunkY: number): boolean
			if world == nil then
				return false
			end
			local readinessMethod = (world :: any).IsChunkCollisionReady
			if typeof(readinessMethod) == "function" then
				return readinessMethod(world, chunkX, chunkY) == true
			end
			return true
		end,
		pushDirty = function(tileX: number, tileY: number, reason: string?, sourceTileX: number?, sourceTileY: number?)
			self:MarkTileDirty(tileX, tileY, reason or "solverCascade", sourceTileX, sourceTileY)
		end,
		getDefinition = function(liquidType: number): LiquidDefinition?
			return self:GetDefinition(liquidType)
		end,
		reportCellState = function(
			tileX: number,
			tileY: number,
			state: string,
			reason: string,
			fill: number,
			liquidType: number
		)
			self:UpdateCellDebugVisual(tileX, tileY, state, reason, fill, liquidType)
		end,
		recordMetric = function(metricName: string, amountRaw: any?)
			self:RecordSimulationMetric(metricName, amountRaw, runtime)
		end,
	}
	return access
end

function LiquidServiceServer.StepChunk(
	self: LiquidServiceServer,
	chunkKey: string,
	mutationsRaw: any,
	budgetRaw: any
): (number, number)
	local world = self.world
	if world == nil then
		return 0, 0
	end
	local snapshot = self:GetChunkSnapshot(chunkKey)
	if snapshot == nil then
		return 0, 0
	end
	local runtime = self:GetChunkRuntime(chunkKey)
	local budget = if isFiniteNumber(budgetRaw)
		then math.max(1, math.floor(budgetRaw))
		else self.config.simulation.maxCellsPerChunkStep
	local mutations = if typeof(mutationsRaw) == "table" then mutationsRaw :: { [number]: any } else {} :: any
	local access = self:BuildSolverAccess(runtime)
	runtime.lastActiveCellCount = 0
	runtime.lastDownwardTransfer = 0
	runtime.lastLateralTransfer = 0
	runtime.lastCrossChunkWakeups = 0

	local processed = 0
	local changed = 0
	for mutationIndex = 1, #mutations do
		local mutation = mutations[mutationIndex]
		if processed >= budget then
			self:RequeueDirtyMutation(mutation)
			continue
		end
		if typeof(mutation) ~= "table" then
			continue
		end
		local tileX = if isFiniteNumber(mutation.x) then math.floor(mutation.x) else nil
		local tileY = if isFiniteNumber(mutation.y) then math.floor(mutation.y) else nil
		if tileX == nil or tileY == nil then
			continue
		end
		local localX = tileX - snapshot.tileMinX
		local localY = tileY - snapshot.tileMinY
		if localX < 0 or localX >= snapshot.width or localY < 0 or localY >= snapshot.height then
			continue
		end
		local index = LiquidServiceUtils.ComputeTileIndex(localX, localY, snapshot.width)
		if not runtime.dirtyLookup[index] then
			continue
		end
		runtime.dirtyLookup[index] = nil
		if runtime.queuedDirtyCount > 0 then
			runtime.queuedDirtyCount -= 1
		end
		local stepResult: LiquidSolverStepResult = LiquidSolver.StepCell(access, tileX, tileY)
		if stepResult.changed then
			changed += 1
		end
		if stepResult.waitingOnChunkReady then
			self:SetChunkRegionState(
				chunkKey,
				runtime,
				CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
				stepResult.reason,
				stepResult.dependencyChunkKey
			)
		elseif stepResult.active then
			self:SetChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, stepResult.reason)
		elseif stepResult.state == CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN then
			self:SetChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN, stepResult.reason)
		end
		processed += 1
	end
	runtime.lastProcessedAt = os.clock()
	runtime.lastProcessedCells = processed
	runtime.lastChangedCells = changed
	self:RecordSimulationMetric("cellsProcessed", processed, runtime)
	self:UpdateChunkDebugAttributes(chunkKey, runtime, {
		LastStepBudget = budget,
	})
	if processed > 0 then
		self:DebugLog(
			"logSimulationSteps",
			`{chunkKey} stepped processed={processed} changed={changed} active={runtime.lastActiveCellCount} down={runtime.lastDownwardTransfer} lateral={runtime.lastLateralTransfer} remainingDirty={getDirtyCount(
				runtime
			)}`
		)
	end
	return processed, changed
end

function LiquidServiceServer.VerifyChunkStability(
	self: LiquidServiceServer,
	chunkKey: string,
	runtime: ChunkRuntime,
	reasonRaw: any?
): (boolean, string, number)
	if not self:IsCollisionChunkReadyByKey(chunkKey) then
		local deferredReason = `awaitingCollisionChunk {chunkKey}`
		self:SetChunkRegionState(
			chunkKey,
			runtime,
			CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
			deferredReason,
			chunkKey
		)
		runtime.lastStabilityScanUnstableCells = math.max(1, runtime.lastStabilityScanUnstableCells)
		return false, deferredReason, runtime.lastStabilityScanUnstableCells
	end

	local snapshot = self:GetChunkSnapshot(chunkKey)
	if snapshot == nil then
		runtime.lastStabilityScanUnstableCells = 0
		return true, "missingSnapshot", 0
	end

	local access = self:BuildSolverAccess(runtime)
	local unstableCount = 0
	local deferredCount = 0
	local firstReason = nil :: string?
	local dependencyChunkKey = nil :: string?
	for index = 1, #snapshot.cells do
		local packedCell = snapshot.cells[index]
		if not isFiniteNumber(packedCell) or packedCell <= 0 then
			continue
		end
		local zeroIndex = index - 1
		local localY = math.floor(zeroIndex / snapshot.width)
		local localX = zeroIndex - localY * snapshot.width
		local tileX = snapshot.tileMinX + localX
		local tileY = snapshot.tileMinY + localY
		local inspection = LiquidSolver.InspectCell(access, tileX, tileY)
		if inspection.hasLiquid and not inspection.isStable then
			if inspection.waitingOnChunkReady then
				deferredCount += 1
				dependencyChunkKey = dependencyChunkKey or inspection.dependencyChunkKey
				if firstReason == nil then
					firstReason = inspection.reason
				end
			else
				unstableCount += 1
				if firstReason == nil then
					firstReason = inspection.reason
				end
				self:MarkTileDirty(tileX, tileY, `stabilityScan:{inspection.state}`)
				for _, wakeTileEntry in inspection.wakeTiles do
					self:MarkTileDirty(
						wakeTileEntry.tileX,
						wakeTileEntry.tileY,
						`stabilityScan:{inspection.state}`,
						tileX,
						tileY
					)
				end
			end
		end
	end

	runtime.lastStabilityScanUnstableCells = unstableCount + deferredCount
	self:UpdateChunkDebugAttributes(chunkKey, runtime)
	if deferredCount > 0 then
		local deferredReason = firstReason or `awaitingCollisionChunk {dependencyChunkKey or chunkKey}`
		self:SetChunkRegionState(
			chunkKey,
			runtime,
			CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
			deferredReason,
			dependencyChunkKey
		)
		return false, deferredReason, deferredCount
	end
	if unstableCount > 0 then
		self:SetChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, firstReason or "unstable")
		local reopenedReason =
			`{if typeof(reasonRaw) == "string" then reasonRaw else "stabilityScan"} reopened; unstableCells={unstableCount}; first={firstReason or "unknown"}`
		self:DebugLog("logStableTransitions", `{chunkKey} reopened ({reopenedReason})`)
		return false, reopenedReason, unstableCount
	end

	return true, "downwardSealed lateralSealed leakPathClear boundaryClear", 0
end

function LiquidServiceServer.CollectActiveChunkKeys(
	self: LiquidServiceServer
): ({ string }, { [string]: string }, { [string]: boolean })
	local activeLookup: { [string]: boolean } = {}
	local activeKeys: { string } = {}
	local activeReasonLists: { [string]: { string } } = {}
	local now = os.clock()

	for _, stream in self.playerStreams do
		for chunkKey in stream.simulationInterestKeys do
			if not activeLookup[chunkKey] then
				activeLookup[chunkKey] = true
				table.insert(activeKeys, chunkKey)
				activeReasonLists[chunkKey] = {}
			end
			appendReason(activeReasonLists[chunkKey], "playerSimulationInterest")
		end
	end

	for chunkKey, runtime in self.chunkRuntimes do
		local hasDirtyTiles = getDirtyCount(runtime) > 0
		local recentlyDisturbed = now - runtime.lastDisturbedAt <= self.config.simulation.disturbedChunkKeepAliveSeconds
		local waitingOnChunkReady = runtime.waitingOnChunkReady
		if not hasDirtyTiles and not recentlyDisturbed and not waitingOnChunkReady then
			continue
		end
		if not activeLookup[chunkKey] then
			activeLookup[chunkKey] = true
			table.insert(activeKeys, chunkKey)
			activeReasonLists[chunkKey] = {}
		end
		if hasDirtyTiles then
			appendReason(activeReasonLists[chunkKey], "dirty")
		end
		if recentlyDisturbed then
			appendReason(activeReasonLists[chunkKey], "disturbed")
		end
		if waitingOnChunkReady then
			appendReason(activeReasonLists[chunkKey], "waitingOnChunkReady")
		end
	end

	table.sort(activeKeys)
	local activeReasons: { [string]: string } = {}
	for chunkKey, reasons in activeReasonLists do
		activeReasons[chunkKey] = table.concat(reasons, "+")
	end
	return activeKeys, activeReasons, activeLookup
end

function LiquidServiceServer.ProcessSimulationStep(self: LiquidServiceServer)
	if self.debug ~= nil then
		self.debug:ResetFrameCounters()
	end
	local solveToken = if self.debug ~= nil then self.debug:BeginFrameScope("liquid_server_solve") else nil
	self.simulationStepId += 1
	self.currentSimulationStats = createSimulationTickStats()
	self.currentSimulationStats.chunkReadinessWakeups = self.pendingChunkReadinessWakeups
	self.pendingChunkReadinessWakeups = 0
	self.currentSimulationStats.collisionChunksLoaded = self:GetLoadedCollisionChunkCount()
	self.currentSimulationStats.wakeRequestsQueued = self:GetPendingWakeRequestCount()
	self.currentSimulationStats.wakeRequestsProcessed =
		self:FlushWakeRequests(self.config.simulation.maxWakeRequestsPerTick)
	local activeKeys, activeReasons, activeLookup = self:CollectActiveChunkKeys()
	self.currentSimulationStats.activeChunks = #activeKeys
	local reactivatedChunks: { [string]: boolean } = {}
	for _, chunkKey in activeKeys do
		local runtime = self:GetChunkRuntime(chunkKey)
		local activeReason = activeReasons[chunkKey] or "active"
		local wasActiveLastStep = runtime.lastActiveStepId > 0 and runtime.lastActiveStepId == self.simulationStepId - 1
		reactivatedChunks[chunkKey] = not wasActiveLastStep
		runtime.lastActiveStepId = self.simulationStepId
		if not wasActiveLastStep then
			runtime.lastActivationAt = os.clock()
			runtime.lastActivationReason = activeReason
			if self:IsCollisionChunkReadyByKey(chunkKey) then
				local restored = self:RestoreQueuedDirtyCellsForChunk(chunkKey, `{activeReason}:reactivationRestore`)
				if restored == 0 then
					self:PrimeChunkRuntime(chunkKey, activeReason)
				end
				self:SetChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, activeReason)
			else
				self:SetChunkRegionState(
					chunkKey,
					runtime,
					CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
					`awaitingCollisionChunk {chunkKey}`,
					chunkKey
				)
			end
			self:UpdateChunkDebugAttributes(chunkKey, runtime, {
				InActiveSet = true,
				ActiveReason = activeReason,
			})
			self:DebugLog("logActivations", `{chunkKey} entered active set ({activeReason})`)
		end
	end
	self.currentSimulationStats.queuedCells = self.dirtyCellQueue:GetPendingCount()
	for _, chunkKey in activeKeys do
		if getDirtyCount(self:GetChunkRuntime(chunkKey)) > 0 then
			self.currentSimulationStats.dirtyChunks += 1
		end
	end
	if self:IsDebugEnabled() and self.config.debug.visualizeChunks then
		for chunkKey, runtime in self.chunkRuntimes do
			self:UpdateChunkDebugAttributes(chunkKey, runtime, {
				InActiveSet = activeLookup[chunkKey] == true,
				ActiveReason = activeReasons[chunkKey] or "",
			})
		end
	end

	local processedChunks = 0
	local touchedChunks: { [string]: boolean } = {}
	local maxMutationBudget = self.config.simulation.maxChunkStepsPerTick * self.config.simulation.maxCellsPerChunkStep
	local flushBatch = self.dirtyCellQueue:Flush(maxMutationBudget)
	if flushBatch ~= nil then
		for _, chunkBatch in flushBatch.chunks do
			local chunkKey = LiquidServiceUtils.PackChunkKey(chunkBatch.chunkX, chunkBatch.chunkY)
			if processedChunks >= self.config.simulation.maxChunkStepsPerTick then
				for _, mutation in chunkBatch.mutations do
					self:RequeueDirtyMutation(mutation)
				end
				continue
			end
			local runtime = self:GetChunkRuntime(chunkKey)
			if not self:IsCollisionChunkReadyByKey(chunkKey) then
				self:SetChunkRegionState(
					chunkKey,
					runtime,
					CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
					`awaitingCollisionChunk {chunkKey}`,
					chunkKey
				)
				continue
			end
			local processedCells, _changedCells =
				self:StepChunk(chunkKey, chunkBatch.mutations, self.config.simulation.maxCellsPerChunkStep)
			if processedCells <= 0 then
				continue
			end
			processedChunks += 1
			touchedChunks[chunkKey] = true
			if getDirtyCount(runtime) <= 0 then
				local isStable, stableReason = self:VerifyChunkStability(chunkKey, runtime, "dirtyQueueDrained")
				if isStable then
					self:MarkChunkStable(chunkKey, runtime, stableReason)
				end
			end
		end
	end

	for _, chunkKey in activeKeys do
		if touchedChunks[chunkKey] then
			continue
		end
		local runtime = self:GetChunkRuntime(chunkKey)
		if getDirtyCount(runtime) > 0 then
			continue
		end
		if reactivatedChunks[chunkKey] then
			local isStable, stableReason = self:VerifyChunkStability(chunkKey, runtime, "reactivatedWithoutDirtyWork")
			if isStable then
				self:MarkChunkStable(chunkKey, runtime, stableReason)
			end
		end
	end

	self.currentSimulationStats.queuedCells = self.dirtyCellQueue:GetPendingCount()
	self.currentSimulationStats.dirtyChunks = 0
	self.currentSimulationStats.deferredChunks = 0
	for _, runtime in self.chunkRuntimes do
		if getDirtyCount(runtime) > 0 then
			self.currentSimulationStats.dirtyChunks += 1
		end
		if runtime.waitingOnChunkReady then
			self.currentSimulationStats.deferredChunks += 1
		end
	end
	self.currentSimulationStats.collisionChunksLoaded = self:GetLoadedCollisionChunkCount()
	if self.debug ~= nil then
		self.debug:EndFrameScope("liquid_server_solve", solveToken)
	end
	self:UpdateSimulationDebugStats()
end

function LiquidServiceServer.ProcessConsistencySweep(self: LiquidServiceServer)
	local world = self.world
	if world == nil then
		return
	end
	local debugToken = if self.debug ~= nil then self.debug:BeginFrameScope("liquid_consistency_sweep") else nil
	self:PruneRecentChunkActivity()

	local queryResults = self.sweepResultPool:Acquire() :: { any }
	local candidateLookup: { [string]: boolean } = {}
	local candidateKeys: { string } = {}
	local sweepRadiusStuds = world.chunkSize
		* world.tileSize
		* math.max(1, self.config.simulation.activeSafetyMarginChunks + 2)

	for player in self.playerStreams do
		local rootPart = GetCharacterRootPart(GetPlayerCharacter(player))
		if rootPart == nil then
			continue
		end
		table.clear(queryResults)
		local entries = self.recentChunkGrid:queryRadius(
			rootPart.Position.Z,
			rootPart.Position.Y,
			0,
			sweepRadiusStuds,
			queryResults
		)
		for entryIndex = 1, #entries do
			local entry = entries[entryIndex]
			local payload = if typeof(entry) == "table" then entry.payload else nil
			local chunkKey = if typeof(payload) == "table" and typeof(payload.key) == "string" then payload.key else nil
			if chunkKey == nil or candidateLookup[chunkKey] then
				continue
			end
			candidateLookup[chunkKey] = true
			candidateKeys[#candidateKeys + 1] = chunkKey
		end
	end

	table.clear(queryResults)
	self.sweepResultPool:Release(queryResults)
	table.sort(candidateKeys)

	local processed = 0
	for _, chunkKey in candidateKeys do
		if processed >= self.config.simulation.consistencySweepChunkBudget then
			break
		end
		local runtime = self.chunkRuntimes[chunkKey]
		if runtime == nil or getDirtyCount(runtime) > 0 then
			continue
		end
		if
			runtime.waitingOnChunkReady
			and runtime.dependencyChunkKey ~= ""
			and self:IsCollisionChunkReadyByKey(chunkKey)
			and self:IsCollisionChunkReadyByKey(runtime.dependencyChunkKey)
		then
			local restored = self:RestoreQueuedDirtyCellsForChunk(chunkKey, "consistencyChunkReady")
			if restored == 0 then
				self:PrimeChunkRuntime(chunkKey, "consistencyChunkReady")
			end
			self:SetChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, "consistencyChunkReady")
			self:RecordSimulationMetric("consistencyRequeues", 1, runtime)
			processed += 1
			continue
		end
		if not self:IsCollisionChunkReadyByKey(chunkKey) then
			self:SetChunkRegionState(
				chunkKey,
				runtime,
				CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
				`awaitingCollisionChunk {chunkKey}`,
				chunkKey
			)
			processed += 1
			continue
		end
		local isStable = self:VerifyChunkStability(chunkKey, runtime, "consistencySweep")
		if not isStable then
			self:RecordSimulationMetric("consistencyRequeues", 1, runtime)
		end
		processed += 1
	end

	if self.debug ~= nil then
		self.debug:SetCounter("liquid_consistency_candidates", #candidateKeys)
		self.debug:SetCounter("liquid_consistency_processed", processed)
		self.debug:EndFrameScope("liquid_consistency_sweep", debugToken)
	end
	local debugFolder = self:GetDebugFolder()
	if debugFolder ~= nil and self.debug ~= nil then
		local counters = self.debug:GetCounters()
		debugFolder:SetAttribute("ConsistencyCandidates", #candidateKeys)
		debugFolder:SetAttribute("ConsistencyProcessed", processed)
		debugFolder:SetAttribute(
			"TimeConsistencySweepMs",
			math.round(((counters.time_liquid_consistency_sweep or 0) * 1000) * 100) / 100
		)
	end
end

function LiquidServiceServer.RedistributeDisplacedLiquid(
	self: LiquidServiceServer,
	tileX: number,
	tileY: number,
	packedCell: number
)
	local liquidType, fill = LiquidCell.Unpack(packedCell)
	if liquidType == LIQUID_TYPE.NONE or fill <= 0 then
		return
	end

	local remaining = fill
	for _, target in
		{
			{ tileX, tileY + 1 },
			{ tileX - 1, tileY },
			{ tileX + 1, tileY },
		}
	do
		if remaining <= 0 then
			break
		end
		local targetX = target[1]
		local targetY = target[2]
		if self:IsSolid(targetX, targetY) then
			continue
		end
		local existingCell = if self.world ~= nil then self.world:GetLiquidCellAt(targetX, targetY) else 0
		local existingType, existingFill = LiquidCell.Unpack(existingCell)
		if existingType ~= LIQUID_TYPE.NONE and existingType ~= liquidType then
			continue
		end
		local transfer = math.min(remaining, self.config.maxFill - existingFill)
		if transfer <= 0 then
			continue
		end
		remaining -= transfer
		self:SetPackedCell(
			targetX,
			targetY,
			LiquidCell.Make(liquidType, existingFill + transfer, LiquidServiceUtils.FLOW_STATE.SPREADING)
		)
		self:WakeLiquidRegion(targetX, targetY, "displacedLiquid", {
			radius = 1,
			sourceTileX = tileX,
			sourceTileY = tileY,
			scanNearby = false,
		})
	end
end

function LiquidServiceServer.ReactivateNearbyLiquid(
	self: LiquidServiceServer,
	tileX: number,
	tileY: number,
	reasonRaw: any?
)
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "terrainChange"
	self:WakeLiquidRegion(tileX, tileY, reason, {
		radius = 2,
		sourceTileX = tileX,
		sourceTileY = tileY,
		scanNearby = true,
	})
end

function LiquidServiceServer.NotifyTerrainChanged(
	self: LiquidServiceServer,
	tileXRaw: any,
	tileYRaw: any,
	previousTileIdRaw: any,
	nextTileIdRaw: any,
	reasonRaw: any?
)
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return
	end
	local tileX = math.floor(tileXRaw)
	local tileY = math.floor(tileYRaw)
	local world = self.world
	if world == nil then
		return
	end
	local chunkX = LiquidServiceUtils.ToChunkCoordinate(tileX, world.chunkSize)
	local chunkY = LiquidServiceUtils.ToChunkCoordinate(tileY, world.chunkSize)
	self:OnChunkTerrainChanged(chunkX, chunkY, {
		minTileX = tileX,
		minTileY = tileY,
		maxTileX = tileX,
		maxTileY = tileY,
	}, {
		reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "terrainChange",
		sourceTileX = tileX,
		sourceTileY = tileY,
		previousTileId = if isFiniteNumber(previousTileIdRaw) then math.floor(previousTileIdRaw) else world.tileId.AIR,
		nextTileId = if isFiniteNumber(nextTileIdRaw) then math.floor(nextTileIdRaw) else world.tileId.AIR,
	})
end

function LiquidServiceServer.ProcessFullSnapshotQueues(self: LiquidServiceServer)
	for player, stream in self.playerStreams do
		if not stream.ready then
			continue
		end
		local processed = 0
		while processed < FULL_SNAPSHOT_BUDGET_PER_PLAYER do
			local chunkKey
			chunkKey, stream.fullQueueHead, stream.fullQueueTail =
				dequeueString(stream.fullQueue, stream.fullQueueLookup, stream.fullQueueHead, stream.fullQueueTail)
			if chunkKey == nil then
				break
			end
			if stream.interestKeys[chunkKey] == nil then
				continue
			end
			if not self:IsCollisionChunkReadyByKey(chunkKey) then
				continue
			end
			local snapshot = self:GetChunkSnapshot(chunkKey)
			if snapshot == nil then
				continue
			end
			sendPacket(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_SNAPSHOT, snapshot)
			stream.sentRevisions[chunkKey] = snapshot.revision
			processed += 1
		end
	end
end

function LiquidServiceServer.ProcessChangedChunks(self: LiquidServiceServer)
	for chunkKey in self.changedChunkKeys do
		local runtime = self.chunkRuntimes[chunkKey]
		if runtime == nil then
			continue
		end
		if runtime.pendingDeltaCount <= 0 then
			continue
		end
		table.sort(runtime.pendingDeltaIndices)

		local snapshot = if runtime.forceFullResync then self:GetChunkSnapshot(chunkKey) else nil
		local deltaPayload = nil :: { [string]: any }?
		if not runtime.forceFullResync then
			local chunkSnapshot = self:GetChunkSnapshot(chunkKey)
			if chunkSnapshot ~= nil then
				local changes = Sift.Array.create(#runtime.pendingDeltaIndices)
				for index, cellIndex in runtime.pendingDeltaIndices do
					changes[index] = {
						index = cellIndex,
						cell = runtime.pendingDeltaByIndex[cellIndex],
					}
				end
				deltaPayload = {
					key = chunkKey,
					chunkX = chunkSnapshot.chunkX,
					chunkY = chunkSnapshot.chunkY,
					width = chunkSnapshot.width,
					height = chunkSnapshot.height,
					revision = runtime.revision,
					changes = changes,
					updatedAt = os.clock(),
				}
			end
		end

		for player, stream in self.playerStreams do
			if not stream.ready then
				continue
			end
			if stream.interestKeys[chunkKey] == nil then
				continue
			end
			if stream.sentRevisions[chunkKey] == nil then
				self:EnqueueFullSnapshot(stream, chunkKey)
				continue
			end

			if runtime.forceFullResync then
				if snapshot ~= nil then
					sendPacket(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_SNAPSHOT, snapshot)
					stream.sentRevisions[chunkKey] = snapshot.revision
				end
			elseif deltaPayload ~= nil then
				sendPacket(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_DELTA, deltaPayload)
				stream.sentRevisions[chunkKey] = runtime.revision
			end
		end

		table.clear(runtime.pendingDeltaByIndex)
		table.clear(runtime.pendingDeltaIndices)
		runtime.pendingDeltaCount = 0
		runtime.forceFullResync = false
	end
	table.clear(self.changedChunkKeys)
end

function LiquidServiceServer.GetPlayerQuery(self: LiquidServiceServer, player: Player): LiquidQueryResult
	local hazard = self:GetHazardRuntime(player)
	local now = os.clock()
	if hazard.lastQuery ~= nil and now - hazard.lastQueryAt <= QUERY_CACHE_WINDOW then
		return hazard.lastQuery
	end

	local query = LiquidQuery.QueryCharacter({
		tileSize = if self.world ~= nil then self.world.tileSize else 4,
		worldOrigin = if self.world ~= nil then self.world.worldOrigin else Vector3.zero,
		getCellAt = function(tileX: number, tileY: number): number
			if self.world == nil then
				return 0
			end
			if not self:IsTileCollisionReady(tileX, tileY) then
				return 0
			end
			return self.world:GetLiquidCellAt(tileX, tileY)
		end,
		getLiquidDefinition = function(liquidType: number): LiquidDefinition?
			return self:GetDefinition(liquidType)
		end,
	}, GetPlayerCharacter(player))
	hazard.lastQuery = query
	hazard.lastQueryAt = now
	return query
end

function LiquidServiceServer.FireEffectEvent(
	self: LiquidServiceServer,
	player: Player,
	eventType: string,
	liquidType: number,
	query: LiquidQueryResult
)
	if not self:IsPlayerStreamReady(player) then
		return
	end
	sendPacket(player, LiquidServiceUtils.CLIENT_METHOD_ON_EFFECT_EVENT, {
		eventType = eventType,
		liquidType = liquidType,
		submersionRatio = query.submersionRatio,
		updatedAt = os.clock(),
	})
end

function LiquidServiceServer.ApplyLiquidMovementSpeed(
	self: LiquidServiceServer,
	player: Player,
	query: LiquidQueryResult
)
	local humanoid = GetCharacterHumanoid(GetPlayerCharacter(player))
	if humanoid == nil or not PlayerServiceUtils.IsHumanoidAlive(humanoid) then
		return
	end

	local multiplier = nil :: number?
	if query.inLiquid then
		local definition = self:GetDefinition(query.dominantType)
		if definition ~= nil and definition.movementSpeedMultiplier < 0.999 then
			multiplier = definition.movementSpeedMultiplier
		end
	end

	PlayerServiceUtils.SetMovementSpeedMultiplier(
		humanoid,
		PlayerServiceUtils.LIQUID_WALK_SPEED_MULTIPLIER_ATTRIBUTE,
		multiplier
	)
end

function LiquidServiceServer.ProcessHazards(self: LiquidServiceServer)
	local lavaDefinition = LiquidDamage.GetLavaDefinition(self.config)
	local now = os.clock()

	for player in self.playerStreams do
		if not self:IsPlayerStreamReady(player) then
			continue
		end
		local hazard = self:GetHazardRuntime(player)
		local query = self:GetPlayerQuery(player)
		self:ApplyLiquidMovementSpeed(player, query)

		if query.inLiquid ~= hazard.wasInLiquid then
			if query.inLiquid then
				self.enteredLiquid:Fire(player, query)
				self:FireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.ENTER, query.dominantType, query)
			else
				self.exitedLiquid:Fire(player, hazard.lastDominantType, query)
				self:FireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.EXIT, hazard.lastDominantType, query)
			end
		end

		if query.meaningfulSubmersion ~= hazard.wasMeaningfullySubmerged then
			if query.meaningfulSubmersion then
				self.submergedStarted:Fire(player, query)
				self:FireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.SUBMERGED_START, query.dominantType, query)
			else
				self.submergedEnded:Fire(player, hazard.lastDominantType, query)
				self:FireEffectEvent(
					player,
					LiquidServiceUtils.EFFECT_EVENT.SUBMERGED_END,
					hazard.lastDominantType,
					query
				)
			end
		end

		if lavaDefinition ~= nil and LiquidDamage.ShouldApplyLavaContact(self.config, query) then
			if now - hazard.lastLavaDamageAt >= lavaDefinition.lavaTouchInterval then
				self.hpService:DamagePlayer(player, lavaDefinition.lavaTouchDamage)
				hazard.lastLavaDamageAt = now
			end
			hazard.burnEndsAt = math.max(hazard.burnEndsAt, now + lavaDefinition.burnDuration)
		end

		local isBurning = hazard.burnEndsAt > now
		if isBurning and lavaDefinition ~= nil and now - hazard.lastBurnDamageAt >= lavaDefinition.burnInterval then
			self.hpService:DamagePlayer(player, lavaDefinition.burnDamage)
			hazard.lastBurnDamageAt = now
		end

		if isBurning ~= hazard.wasBurning then
			if isBurning then
				self.burnStarted:Fire(player, hazard.burnEndsAt - now)
				self:FireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.BURN_START, LIQUID_TYPE.LAVA, query)
			else
				self.burnEnded:Fire(player)
				self:FireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.BURN_END, LIQUID_TYPE.LAVA, query)
			end
		end

		hazard.wasInLiquid = query.inLiquid
		hazard.wasMeaningfullySubmerged = query.meaningfulSubmersion
		hazard.wasBurning = isBurning
		hazard.lastDominantType = query.dominantType
	end
end

function LiquidServiceServer.OnHeartbeat(self: LiquidServiceServer, deltaTime: number)
	self:RefreshWorldBinding()

	self.streamAccumulator += deltaTime
	self.simulationAccumulator += deltaTime
	self.hazardAccumulator += deltaTime
	self.consistencyAccumulator += deltaTime

	if self.streamAccumulator >= self.config.simulation.streamSyncInterval then
		self.streamAccumulator = 0
		for player in self.playerStreams do
			self:RefreshPlayerInterest(player)
		end
		self:ProcessFullSnapshotQueues()
	end

	local simulationStep = 1 / self.config.simulation.stepRate
	while self.simulationAccumulator >= simulationStep do
		self.simulationAccumulator -= simulationStep
		self:ProcessSimulationStep()
	end

	local hazardStep = 1 / self.config.simulation.hazardCheckRate
	while self.hazardAccumulator >= hazardStep do
		self.hazardAccumulator -= hazardStep
		self:ProcessHazards()
	end

	local consistencyStep = self.config.simulation.consistencySweepInterval
	while self.consistencyAccumulator >= consistencyStep do
		self.consistencyAccumulator -= consistencyStep
		self:ProcessConsistencySweep()
	end

	self:ProcessChangedChunks()
end

function LiquidServiceServer.TrackPlayer(self: LiquidServiceServer, player: Player)
	local stream = self.playerStreams[player]
	if stream == nil then
		stream = self:CreatePlayerStream()
		self.playerStreams[player] = stream
	end
	self.playerHazards[player] = self:CreateHazardRuntime()
end

function LiquidServiceServer.UntrackPlayer(self: LiquidServiceServer, player: Player)
	self.playerStreams[player] = nil
	self.playerHazards[player] = nil
end

function LiquidServiceServer.RequestSync(self: LiquidServiceServer, player: Player)
	if self.playerStreams[player] == nil then
		self:TrackPlayer(player)
	end
	self:RefreshWorldBinding()
	local stream = self:GetPlayerStream(player)
	stream.ready = true
	table.clear(stream.interestKeys)
	table.clear(stream.simulationInterestKeys)
	table.clear(stream.sentRevisions)
	table.clear(stream.fullQueue)
	table.clear(stream.fullQueueLookup)
	stream.fullQueueHead = 1
	stream.fullQueueTail = 0
	self:PushState(player)
	self:RefreshPlayerInterest(player)
end

function LiquidServiceServer.GetPlayerLiquidQuery(self: LiquidServiceServer, player: Player): LiquidQueryResult
	return self:GetPlayerQuery(player)
end

function LiquidServiceServer.RefreshWorldBinding(self: LiquidServiceServer)
	local latestWorld = self.worldGenerationService:GetWorld()
	if latestWorld == self.world then
		return
	end

	if self.chunkLifecycleConnection ~= nil then
		self.chunkLifecycleConnection:Disconnect()
		self.chunkLifecycleConnection = nil
	end
	self.world = latestWorld
	if self.world ~= nil and typeof((self.world :: any).RegisterChunkLifecycleObserver) == "function" then
		self.chunkLifecycleConnection = (
			(self.world :: any):RegisterChunkLifecycleObserver(self)
		) :: ChunkLifecycleConnection?
	end

	table.clear(self.chunkRuntimes)
	table.clear(self.changedChunkKeys)
	table.clear(self.pendingWakeQueue)
	table.clear(self.pendingWakeLookup)
	self.pendingWakeHead = 1
	self.pendingWakeTail = 0
	self.pendingChunkReadinessWakeups = 0
	self.currentSimulationStats = createSimulationTickStats()

	if self.dirtyCellQueue ~= nil then
		self.dirtyCellQueue:Destroy()
	end
	self.dirtyCellQueue = WorldMutationQueue.New({
		chunkSize = if self.world ~= nil then self.world.chunkSize else 32,
		flushInterval = 1 / self.config.simulation.stepRate,
		maxMutationsPerFlush = self.config.simulation.maxChunkStepsPerTick
			* self.config.simulation.maxCellsPerChunkStep,
	})

	self.recentChunkGrid = SpatialHashGrid.new({
		cellSize = if self.world ~= nil then math.max(1, self.world.chunkSize * self.world.tileSize) else 64,
		cellsPerChunk = 2,
		deterministicQueries = true,
	})
	table.clear(self.recentChunkTouchedAt)

	if self.debugFolder ~= nil and self.debugFolder.Parent ~= nil then
		self.debugFolder:Destroy()
		self.debugFolder = nil
	end

	for player, stream in self.playerStreams do
		local nextStream = self:CreatePlayerStream()
		nextStream.ready = stream.ready
		self.playerStreams[player] = nextStream
	end
	for player in self.playerHazards do
		self.playerHazards[player] = self:CreateHazardRuntime()
	end
end

function LiquidServiceServer.Init(self: LiquidServiceServer)
	self.runtimeContext = CoreRuntime.GetServerRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).Init) == "function" then
		local runtimeAny = self.runtimeContext :: any
		runtimeAny:Init()
	end
	self.config = LiquidServiceUtils.CoerceConfig(GetSourceConfig(), nil)
	self.state = LiquidServiceUtils.CreateDefaultState()
	self.worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.world = self.worldGenerationService:GetWorld()
	self.chunkLifecycleConnection = nil :: ChunkLifecycleConnection?
	if self.world ~= nil and typeof((self.world :: any).RegisterChunkLifecycleObserver) == "function" then
		self.chunkLifecycleConnection = (
			(self.world :: any):RegisterChunkLifecycleObserver(self)
		) :: ChunkLifecycleConnection?
	end
	self.hpService = HpServiceServer :: any
	self.debug = WorldSimulationDebug.New({
		enabled = self.config.debug.enabled,
		profilingEnabled = self.config.debug.enabled,
	})
	self.chunkRuntimes = {} :: { [string]: ChunkRuntime }
	self.playerStreams = {} :: { [Player]: PlayerStream }
	self.playerHazards = {} :: { [Player]: PlayerHazardRuntime }
	self.changedChunkKeys = {} :: { [string]: boolean }
	self.dirtyCellQueue = WorldMutationQueue.New({
		chunkSize = if self.world ~= nil then self.world.chunkSize else 32,
		flushInterval = 1 / self.config.simulation.stepRate,
		maxMutationsPerFlush = self.config.simulation.maxChunkStepsPerTick
			* self.config.simulation.maxCellsPerChunkStep,
	})
	self.wakeRequestPool = ObjectPool.new(function()
		return {
			key = "",
			tileX = 0,
			tileY = 0,
			radius = 0,
			reason = "",
			sourceTileX = nil,
			sourceTileY = nil,
			scanNearby = false,
		} :: WakeRequest
	end, {
		expandBy = 24,
		maxAvailable = 2048,
		reset = function(request: WakeRequest)
			request.key = ""
			request.tileX = 0
			request.tileY = 0
			request.radius = 0
			request.reason = ""
			request.sourceTileX = nil
			request.sourceTileY = nil
			request.scanNearby = false
		end,
	})
	self.sweepResultPool = ObjectPool.new(function()
		return {}
	end, {
		expandBy = 4,
		maxAvailable = 48,
		reset = function(array: { any })
			table.clear(array)
		end,
	})
	self.pendingWakeQueue = {} :: { WakeRequest }
	self.pendingWakeHead = 1
	self.pendingWakeTail = 0
	self.pendingWakeLookup = {} :: { [string]: boolean }
	self.recentChunkGrid = SpatialHashGrid.new({
		cellSize = if self.world ~= nil then math.max(1, self.world.chunkSize * self.world.tileSize) else 64,
		cellsPerChunk = 2,
		deterministicQueries = true,
	})
	self.recentChunkTouchedAt = {} :: { [string]: number }
	self.streamAccumulator = self.config.simulation.streamSyncInterval
	self.simulationAccumulator = 0
	self.hazardAccumulator = 0
	self.consistencyAccumulator = 0
	self.simulationStepId = 0
	self.pendingChunkReadinessWakeups = 0
	self.debugFolder = nil :: Folder?
	self.currentSimulationStats = createSimulationTickStats()

	self.enteredLiquid = Signal.new()
	self.exitedLiquid = Signal.new()
	self.submergedStarted = Signal.new()
	self.submergedEnded = Signal.new()
	self.burnStarted = Signal.new()
	self.burnEnded = Signal.new()

	bindPackets(self)

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if isGameplayReplicationActive(player) then
			self:TrackPlayer(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:UntrackPlayer(player)
	end)
	local tickScheduler = if self.runtimeContext ~= nil then (self.runtimeContext :: any).tickScheduler else nil
	if tickScheduler ~= nil and typeof((tickScheduler :: any).ScheduleEvery) == "function" then
		self.heartbeatToken = (tickScheduler :: any):ScheduleEvery(
			function(deltaTime: number)
				self:OnHeartbeat(deltaTime)
			end,
			1 / 60,
			{
				group = "service.liquid.server",
				priority = TickSchedulerModule.Priority.NORMAL + 20,
				catchUp = false,
			}
		)
		self.poolMaintenanceToken = (tickScheduler :: any):ScheduleEvery(
			function()
				self.wakeRequestPool:SoftShrink(24)
				self.sweepResultPool:SoftShrink(6)
			end,
			2.5,
			{
				group = "service.liquid.server",
				priority = TickSchedulerModule.Priority.LOW,
				catchUp = false,
			}
		)
	else
		self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
			self:OnHeartbeat(deltaTime)
		end)
	end
end

function LiquidServiceServer.Destroy(self: LiquidServiceServer)
	if self.heartbeatToken ~= nil and typeof(self.heartbeatToken.Cancel) == "function" then
		self.heartbeatToken:Cancel()
		self.heartbeatToken = nil
	end
	if self.poolMaintenanceToken ~= nil and typeof(self.poolMaintenanceToken.Cancel) == "function" then
		self.poolMaintenanceToken:Cancel()
		self.poolMaintenanceToken = nil
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
	if self.chunkLifecycleConnection ~= nil then
		self.chunkLifecycleConnection:Disconnect()
		self.chunkLifecycleConnection = nil
	end
	if self.enteredLiquid ~= nil then
		self.enteredLiquid:Destroy()
		self.exitedLiquid:Destroy()
		self.submergedStarted:Destroy()
		self.submergedEnded:Destroy()
		self.burnStarted:Destroy()
		self.burnEnded:Destroy()
	end
	table.clear(self.chunkRuntimes)
	table.clear(self.playerStreams)
	table.clear(self.playerHazards)
	table.clear(self.changedChunkKeys)
	if self.dirtyCellQueue ~= nil then
		self.dirtyCellQueue:Destroy()
	end
	if self.wakeRequestPool ~= nil then
		self.wakeRequestPool:Destroy()
	end
	if self.sweepResultPool ~= nil then
		self.sweepResultPool:Destroy()
	end
	if self.recentChunkGrid ~= nil then
		self.recentChunkGrid:Clear()
	end
	if self.debug ~= nil then
		self.debug:Destroy()
		self.debug = nil
	end
	if self.debugFolder ~= nil and self.debugFolder.Parent ~= nil then
		self.debugFolder:Destroy()
		self.debugFolder = nil
	end
end
type LiquidServiceServer = typeof(LiquidServiceServer) & {
	runtimeContext: any?,
	config: LiquidServiceConfig,
	state: LiquidServiceState,
	worldGenerationService: WorldGenerationServiceServerObject,
	playerService: PlayerServiceServerObject?,
	world: WorldObject,
	hpService: HpServiceServerObject,
	debug: DebugObject?,
	chunkRuntimes: { [string]: ChunkRuntime },
	playerStreams: { [Player]: PlayerStream },
	playerHazards: { [Player]: PlayerHazardRuntime },
	changedChunkKeys: { [string]: boolean },
	dirtyCellQueue: any,
	wakeRequestPool: any,
	sweepResultPool: any,
	pendingWakeQueue: { WakeRequest },
	pendingWakeHead: number,
	pendingWakeTail: number,
	pendingWakeLookup: { [string]: boolean },
	recentChunkGrid: any,
	recentChunkTouchedAt: { [string]: number },
	streamAccumulator: number,
	simulationAccumulator: number,
	hazardAccumulator: number,
	consistencyAccumulator: number,
	simulationStepId: number,
	pendingChunkReadinessWakeups: number,
	currentSimulationStats: SimulationTickStats,
	enteredLiquid: SignalObject,
	exitedLiquid: SignalObject,
	submergedStarted: SignalObject,
	submergedEnded: SignalObject,
	burnStarted: SignalObject,
	burnEnded: SignalObject,
	debugFolder: Folder?,
	chunkLifecycleConnection: ChunkLifecycleConnection?,
	heartbeatToken: CancellationToken?,
	poolMaintenanceToken: CancellationToken?,
	heartbeatConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return LiquidServiceServer :: LiquidServiceServer
