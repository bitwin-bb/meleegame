--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)
local ObjectPool = require(ReplicatedStorage.Shared.Modules.Core.ObjectPool)
local SpatialHashGrid = require(ReplicatedStorage.Shared.Modules.Core.SpatialHashGrid)
local TickSchedulerModule = require(ReplicatedStorage.Shared.Modules.Core.TickScheduler)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)
local WorldMutationQueue = require(ReplicatedStorage.Shared.Modules.Core.WorldMutationQueue)
local LiquidServiceUtils = require(ReplicatedStorage.Shared.Services.LiquidService.LiquidServiceUtils)
local PlayerServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerService.PlayerServiceUtils)
local WorldSimulationDebug = require(ReplicatedStorage.Shared.Services.WorldSimulationService.Debug)
local WorldGenerationServiceServer =
	require(ServerScriptService.Services.WorldGenerationService.WorldGenerationServiceServer)
local PlayerServiceServer = require(ServerScriptService.Services.PlayerService.PlayerServiceServer)
local HpServiceServer = require(ServerScriptService.Services.HpService.HpServiceServer)

type LiquidServiceConfig = LiquidServiceUtils.LiquidServiceConfig
type LiquidServiceState = LiquidServiceUtils.LiquidServiceState
type LiquidChunkSnapshot = LiquidServiceUtils.LiquidChunkSnapshot
type LiquidQueryResult = LiquidServiceUtils.LiquidQueryResult
type LiquidDefinition = LiquidServiceUtils.LiquidDefinition
type LiquidSolverAccess = LiquidServiceUtils.LiquidSolverAccess
type LiquidSolverStepResult = LiquidServiceUtils.LiquidSolverStepResult
type CancellationToken = TickSchedulerModule.CancellationToken
type DebugObject = WorldSimulationDebug.Debug

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

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
	getPlayerInterestKeys: (self: WorldObject, player: Player) -> { [string]: boolean },
	registerChunkLifecycleObserver: (self: WorldObject, observerRaw: any) -> ChunkLifecycleConnection?,
	isChunkCollisionReadyByKey: (self: WorldObject, chunkKeyRaw: any) -> boolean,
	isChunkCollisionReady: (self: WorldObject, chunkXRaw: any, chunkYRaw: any) -> boolean,
	getLoadedCollisionChunkCount: (self: WorldObject) -> number,
	getLiquidChunkSnapshotByKey: (self: WorldObject, chunkKeyRaw: any) -> { [string]: any }?,
	getLiquidCellAt: (self: WorldObject, tileXRaw: any, tileYRaw: any) -> number,
	setLiquidCellAt: (self: WorldObject, tileXRaw: any, tileYRaw: any, packedCellRaw: any) -> (boolean, number, number),
	getTileAt: (self: WorldObject, tileXRaw: any, tileYRaw: any) -> (number, number),
}

type WorldGenerationServiceServerObject = {
	getWorld: (self: WorldGenerationServiceServerObject) -> WorldObject,
}

type PlayerServiceServerObject = {
	isGameplayActiveForPlayer: (self: PlayerServiceServerObject, player: Player) -> boolean,
}

type HpServiceServerObject = {
	damagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
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
	interestKeys: { [string]: boolean },
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
		return (PlayerServiceServer :: any):isGameplayActiveForPlayer(player)
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

local function resolveSourceConfig(): any
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

local function sanitizeChunkDebugName(chunkKey: string): string
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

local function resolvePlayerCharacter(player: Player): Model?
	local character = player.Character
	if character ~= nil and character:IsA("Model") then
		return character
	end
	return nil
end

local function resolveCharacterRootPart(character: Model?): BasePart?
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

local function resolveCharacterHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid:IsA("Humanoid") then
		return humanoid
	end
	return nil
end

function LiquidServiceServer:createChunkRuntime(chunkKey: string): ChunkRuntime
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

function LiquidServiceServer:getChunkRuntime(chunkKey: string): ChunkRuntime
	local runtime = self.chunkRuntimes[chunkKey]
	if runtime ~= nil then
		return runtime
	end
	runtime = self:createChunkRuntime(chunkKey)
	self.chunkRuntimes[chunkKey] = runtime
	return runtime
end

function LiquidServiceServer:isCollisionChunkReadyByKey(chunkKey: string): boolean
	local world = self.world
	if world == nil then
		return false
	end
	local readinessMethod = (world :: any).isChunkCollisionReadyByKey
	if typeof(readinessMethod) == "function" then
		return readinessMethod(world, chunkKey) == true
	end
	return true
end

function LiquidServiceServer:getLoadedCollisionChunkCount(): number
	local world = self.world
	if world == nil then
		return 0
	end
	local countMethod = (world :: any).getLoadedCollisionChunkCount
	if typeof(countMethod) == "function" then
		local count = countMethod(world)
		if isFiniteNumber(count) then
			return math.max(0, math.floor(count))
		end
	end
	return 0
end

function LiquidServiceServer:setChunkRegionState(
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
	self:updateChunkDebugAttributes(chunkKey, runtime)
end

function LiquidServiceServer:restoreQueuedDirtyCellsForChunk(chunkKey: string, reasonRaw: any?): number
	local runtime = self.chunkRuntimes[chunkKey]
	if runtime == nil or getDirtyCount(runtime) <= 0 then
		return 0
	end
	local snapshot = self:getChunkSnapshot(chunkKey)
	if snapshot == nil then
		return 0
	end
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "chunkReady"
	local requeued = 0
	for index in runtime.dirtyLookup do
		local zeroIndex = index - 1
		local localY = math.floor(zeroIndex / snapshot.width)
		local localX = zeroIndex - localY * snapshot.width
		self:requeueDirtyMutation({
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

function LiquidServiceServer:wakeChunkBounds(
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
	local dirtyBounds = if typeof(dirtyBoundsRaw) == "table" then dirtyBoundsRaw :: { [string]: any } else {}
	local chunkMinX = chunkX * world.chunkSize
	local chunkMinY = chunkY * world.chunkSize
	local chunkMaxX = chunkMinX + world.chunkSize - 1
	local chunkMaxY = chunkMinY + world.chunkSize - 1
	local minTileX = if isFiniteNumber(dirtyBounds.minTileX) then math.floor(dirtyBounds.minTileX) else chunkMinX
	local minTileY = if isFiniteNumber(dirtyBounds.minTileY) then math.floor(dirtyBounds.minTileY) else chunkMinY
	local maxTileX = if isFiniteNumber(dirtyBounds.maxTileX) then math.floor(dirtyBounds.maxTileX) else chunkMaxX
	local maxTileY = if isFiniteNumber(dirtyBounds.maxTileY) then math.floor(dirtyBounds.maxTileY) else chunkMaxY
	local sourceTileX = if isFiniteNumber(sourceTileXRaw) then math.floor(sourceTileXRaw) else nil
	local sourceTileY = if isFiniteNumber(sourceTileYRaw) then math.floor(sourceTileYRaw) else nil
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "chunkWake"
	local marked = 0

	for tileY = math.max(chunkMinY, minTileY), math.min(chunkMaxY, maxTileY) do
		for tileX = math.max(chunkMinX, minTileX), math.min(chunkMaxX, maxTileX) do
			if self:markTileDirty(tileX, tileY, reason, sourceTileX, sourceTileY) then
				marked += 1
			end
		end
	end

	return marked
end

function LiquidServiceServer:wakeChunkDependencyNeighborhood(chunkX: number, chunkY: number, reasonRaw: any?)
	local world = self.world
	if world == nil then
		return
	end
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "chunkReady"
	for offsetY = -1, 1 do
		for offsetX = -1, 1 do
			local neighborChunkX = chunkX + offsetX
			local neighborChunkY = chunkY + offsetY
			local neighborKey = LiquidServiceUtils.packChunkKey(neighborChunkX, neighborChunkY)
			local runtime = if offsetX == 0 and offsetY == 0
				then self:getChunkRuntime(neighborKey)
				else self.chunkRuntimes[neighborKey]
			if self:isCollisionChunkReadyByKey(neighborKey) then
				if runtime == nil then
					continue
				end
				local restored = self:restoreQueuedDirtyCellsForChunk(neighborKey, `{reason}:restoreDirty`)
				if restored == 0 then
					self:primeChunkRuntime(neighborKey, reason)
				end
				self:setChunkRegionState(neighborKey, runtime, CELL_DEBUG_STATE.ACTIVE, reason)
			else
				if runtime == nil then
					continue
				end
				self:setChunkRegionState(
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

function LiquidServiceServer:OnChunkCollisionReady(chunkXRaw: any, chunkYRaw: any, contextRaw: any?)
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return
	end
	local chunkX = math.floor(chunkXRaw)
	local chunkY = math.floor(chunkYRaw)
	local chunkKey = LiquidServiceUtils.packChunkKey(chunkX, chunkY)
	local context = if typeof(contextRaw) == "table" then contextRaw :: { [string]: any } else {}
	self.pendingChunkReadinessWakeups += 1
	self:debugLog(
		"logActivations",
		`{chunkKey} collision-ready ({if typeof(context.reason) == "string" then context.reason else "ready"})`
	)
	self:wakeChunkDependencyNeighborhood(chunkX, chunkY, "chunkCollisionReady")
end

function LiquidServiceServer:OnChunkCollisionUnloaded(chunkXRaw: any, chunkYRaw: any, _contextRaw: any?)
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return
	end
	local chunkX = math.floor(chunkXRaw)
	local chunkY = math.floor(chunkYRaw)
	local chunkKey = LiquidServiceUtils.packChunkKey(chunkX, chunkY)
	local runtime = self:getChunkRuntime(chunkKey)
	self:setChunkRegionState(
		chunkKey,
		runtime,
		CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
		`awaitingCollisionChunk {chunkKey}`,
		chunkKey
	)
	self:debugLog("logStableTransitions", `{chunkKey} deferred (collision chunk unloaded)`)
	for offsetY = -1, 1 do
		for offsetX = -1, 1 do
			if offsetX == 0 and offsetY == 0 then
				continue
			end
			local neighborChunkX = chunkX + offsetX
			local neighborChunkY = chunkY + offsetY
			local neighborKey = LiquidServiceUtils.packChunkKey(neighborChunkX, neighborChunkY)
			local neighborRuntime = self.chunkRuntimes[neighborKey]
			if neighborRuntime == nil or not self:isCollisionChunkReadyByKey(neighborKey) then
				continue
			end
			self:primeChunkRuntime(neighborKey, "neighborCollisionUnavailable")
			self:setChunkRegionState(
				neighborKey,
				neighborRuntime,
				CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
				`awaitingCollisionChunk {chunkKey}`,
				chunkKey
			)
		end
	end
end

function LiquidServiceServer:OnChunkTerrainChanged(
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
	local chunkKey = LiquidServiceUtils.packChunkKey(chunkX, chunkY)
	local context = if typeof(contextRaw) == "table" then contextRaw :: { [string]: any } else {}
	local runtime = self:getChunkRuntime(chunkKey)
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
		local packedCell = self.world:getLiquidCellAt(sourceTileX, sourceTileY)
		if packedCell ~= 0 then
			self:setPackedCell(sourceTileX, sourceTileY, 0)
			self:redistributeDisplacedLiquid(sourceTileX, sourceTileY, packedCell)
		end
	end

	self:setChunkRegionState(
		chunkKey,
		runtime,
		CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
		`awaitingCollisionChunk {chunkKey}`,
		chunkKey
	)
	self:wakeChunkBounds(chunkX, chunkY, dirtyBoundsRaw, reason, sourceTileX, sourceTileY)
	if sourceTileX ~= nil and sourceTileY ~= nil then
		self:wakeLiquidRegion(sourceTileX, sourceTileY, reason, {
			radius = 2,
			sourceTileX = sourceTileX,
			sourceTileY = sourceTileY,
			scanNearby = true,
		})
	end
end

function LiquidServiceServer:isDebugEnabled(): boolean
	return self.config.debug.enabled
end

function LiquidServiceServer:shouldDebugLog(flagName: string): boolean
	if not self:isDebugEnabled() then
		return false
	end
	return (self.config.debug :: any)[flagName] == true
end

function LiquidServiceServer:debugLog(_flagName: string, _message: string)
	return
end

function LiquidServiceServer:getDebugFolder(): Folder?
	if not self:isDebugEnabled() then
		return nil
	end
	if not self.config.debug.visualizeChunks and not self.config.debug.visualizeCells then
		return nil
	end
	if self.debugFolder ~= nil and self.debugFolder.Parent ~= nil then
		return self.debugFolder
	end
	self.debugFolder = WorkspaceFolders.getOrCreateFolderInGame("LiquidDebug")
	return self.debugFolder
end

function LiquidServiceServer:getChunkDebugFolder(chunkKey: string): Folder?
	local debugFolder = self:getDebugFolder()
	if debugFolder == nil then
		return nil
	end
	local folderName = `Chunk_{sanitizeChunkDebugName(chunkKey)}`
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

function LiquidServiceServer:getChunkCellDebugFolder(chunkKey: string): Folder?
	if not self.config.debug.visualizeCells then
		return nil
	end
	local chunkFolder = self:getChunkDebugFolder(chunkKey)
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

function LiquidServiceServer:updateSimulationDebugStats()
	local debugFolder = self:getDebugFolder()
	local debugCounters = if self.debug ~= nil then self.debug:getCounters() else {}
	local wakePoolStats = if self.wakeRequestPool ~= nil
			and typeof((self.wakeRequestPool :: any).getStats) == "function"
		then (self.wakeRequestPool :: any):getStats()
		else {}
	if debugFolder == nil then
		if self.debug ~= nil then
			self.debug:setCounter("liquid_active_chunks", self.currentSimulationStats.activeChunks)
			self.debug:setCounter("liquid_dirty_chunks", self.currentSimulationStats.dirtyChunks)
			self.debug:setCounter("liquid_queued_cells", self.currentSimulationStats.queuedCells)
			self.debug:setCounter("liquid_pending_wake_requests", self:getPendingWakeRequestCount())
			self.debug:setCounter("liquid_wake_requests_queued", self.currentSimulationStats.wakeRequestsQueued)
			self.debug:setCounter("liquid_wake_requests_processed", self.currentSimulationStats.wakeRequestsProcessed)
			self.debug:setCounter("liquid_cells_processed", self.currentSimulationStats.cellsProcessed)
			self.debug:setCounter("liquid_active_cells", self.currentSimulationStats.activeCells)
			self.debug:setCounter("liquid_cross_chunk_wakeups", self.currentSimulationStats.crossChunkWakeups)
			self.debug:setCounter("liquid_downward_transfer", self.currentSimulationStats.downwardTransfers)
			self.debug:setCounter("liquid_lateral_transfer", self.currentSimulationStats.lateralTransfers)
			self.debug:setCounter("liquid_solver_iterations", self.currentSimulationStats.solverIterations)
			self.debug:setCounter("liquid_consistency_requeues", self.currentSimulationStats.consistencyRequeues)
			self.debug:setCounter("liquid_deferred_chunks", self.currentSimulationStats.deferredChunks)
			self.debug:setCounter("liquid_chunk_readiness_wakeups", self.currentSimulationStats.chunkReadinessWakeups)
			self.debug:setCounter("liquid_collision_chunks_loaded", self.currentSimulationStats.collisionChunksLoaded)
			self.debug:setCounter(
				"liquid_wake_pool_available",
				if typeof(wakePoolStats.available) == "number" then wakePoolStats.available else 0
			)
			self.debug:setCounter(
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
	debugFolder:SetAttribute("PendingWakeRequests", self:getPendingWakeRequestCount())
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
		self.debug:setCounter("liquid_active_chunks", self.currentSimulationStats.activeChunks)
		self.debug:setCounter("liquid_dirty_chunks", self.currentSimulationStats.dirtyChunks)
		self.debug:setCounter("liquid_queued_cells", self.currentSimulationStats.queuedCells)
		self.debug:setCounter("liquid_pending_wake_requests", self:getPendingWakeRequestCount())
		self.debug:setCounter("liquid_wake_requests_queued", self.currentSimulationStats.wakeRequestsQueued)
		self.debug:setCounter("liquid_wake_requests_processed", self.currentSimulationStats.wakeRequestsProcessed)
		self.debug:setCounter("liquid_cells_processed", self.currentSimulationStats.cellsProcessed)
		self.debug:setCounter("liquid_active_cells", self.currentSimulationStats.activeCells)
		self.debug:setCounter("liquid_cross_chunk_wakeups", self.currentSimulationStats.crossChunkWakeups)
		self.debug:setCounter("liquid_downward_transfer", self.currentSimulationStats.downwardTransfers)
		self.debug:setCounter("liquid_lateral_transfer", self.currentSimulationStats.lateralTransfers)
		self.debug:setCounter("liquid_solver_iterations", self.currentSimulationStats.solverIterations)
		self.debug:setCounter("liquid_consistency_requeues", self.currentSimulationStats.consistencyRequeues)
		self.debug:setCounter("liquid_deferred_chunks", self.currentSimulationStats.deferredChunks)
		self.debug:setCounter("liquid_chunk_readiness_wakeups", self.currentSimulationStats.chunkReadinessWakeups)
		self.debug:setCounter("liquid_collision_chunks_loaded", self.currentSimulationStats.collisionChunksLoaded)
		self.debug:setCounter(
			"liquid_wake_pool_available",
			if typeof(wakePoolStats.available) == "number" then wakePoolStats.available else 0
		)
		self.debug:setCounter(
			"liquid_wake_pool_in_use",
			if typeof(wakePoolStats.inUse) == "number" then wakePoolStats.inUse else 0
		)
	end
end

function LiquidServiceServer:updateCellDebugVisual(
	tileX: number,
	tileY: number,
	state: string,
	reason: string,
	fill: number,
	liquidType: number
)
	if not self:isDebugEnabled() or not self.config.debug.visualizeCells then
		return
	end
	local world = self.world
	if world == nil then
		return
	end
	local chunkKey = LiquidServiceUtils.packChunkKey(
		LiquidServiceUtils.toChunkCoordinate(tileX, world.chunkSize),
		LiquidServiceUtils.toChunkCoordinate(tileY, world.chunkSize)
	)
	local folder = self:getChunkCellDebugFolder(chunkKey)
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
		part = Instance.new("Part")
		part.Name = partName
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Parent = folder
	end

	local basePlaneX = if isFiniteNumber((world :: any).basePlaneX) then (world :: any).basePlaneX else 0
	local center = LiquidServiceUtils.tileToWorldCenter(tileX, tileY, world.worldOrigin, world.tileSize, basePlaneX)
	part.CFrame = CFrame.new(center.X - 0.9, center.Y, center.Z)
	part.Size = Vector3.new(CELL_DEBUG_PART_DEPTH, world.tileSize * 0.22, world.tileSize * 0.22)
	part.Color = CELL_DEBUG_COLORS[state] or Color3.fromRGB(255, 255, 255)
	part.Transparency = if state == CELL_DEBUG_STATE.STABLE
			or state == CELL_DEBUG_STATE.BLOCKED
			or state == CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN
		then 0.45
		else 0.15
	part:SetAttribute("TileX", tileX)
	part:SetAttribute("TileY", tileY)
	part:SetAttribute("State", state)
	part:SetAttribute("Reason", reason)
	part:SetAttribute("Fill", fill)
	part:SetAttribute("LiquidType", liquidType)
end

function LiquidServiceServer:updateChunkDebugAttributes(chunkKey: string, runtime: ChunkRuntime, extraRaw: any?)
	if not self.config.debug.visualizeChunks then
		return
	end
	local folder = self:getChunkDebugFolder(chunkKey)
	if folder == nil then
		return
	end
	local extra = if typeof(extraRaw) == "table" then extraRaw :: { [string]: any } else {}
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
	folder:SetAttribute("CollisionChunkReady", self:isCollisionChunkReadyByKey(chunkKey))
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

function LiquidServiceServer:createPlayerStream(): PlayerStream
	local fullQueue, head, tail, lookup = createStringQueue()
	return {
		interestKeys = {},
		sentRevisions = {},
		fullQueue = fullQueue,
		fullQueueHead = head,
		fullQueueTail = tail,
		fullQueueLookup = lookup,
	}
end

function LiquidServiceServer:getPlayerStream(player: Player): PlayerStream
	local stream = self.playerStreams[player]
	if stream ~= nil then
		return stream
	end
	stream = self:createPlayerStream()
	self.playerStreams[player] = stream
	return stream
end

function LiquidServiceServer:createHazardRuntime(): PlayerHazardRuntime
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

function LiquidServiceServer:getHazardRuntime(player: Player): PlayerHazardRuntime
	local runtime = self.playerHazards[player]
	if runtime ~= nil then
		return runtime
	end
	runtime = self:createHazardRuntime()
	self.playerHazards[player] = runtime
	return runtime
end

function LiquidServiceServer:createStateSnapshot(): LiquidServiceState
	local world = self.world
	return LiquidServiceUtils.createState({
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

function LiquidServiceServer:pushState(player: Player)
	self.state = self:createStateSnapshot()
	self.networker:fire(player, LiquidServiceUtils.CLIENT_METHOD_APPLY_STATE, LiquidServiceUtils.cloneState(self.state))
end

function LiquidServiceServer:getDefinition(liquidType: number): LiquidDefinition?
	return self.config.definitions[liquidType]
end

function LiquidServiceServer:getChunkSnapshot(chunkKey: string): LiquidChunkSnapshot?
	local world = self.world
	if world == nil then
		return nil
	end
	local snapshotRaw = world:getLiquidChunkSnapshotByKey(chunkKey)
	if typeof(snapshotRaw) ~= "table" then
		return nil
	end
	local source = snapshotRaw :: { [string]: any }
	local runtime = self:getChunkRuntime(chunkKey)
	return {
		key = if typeof(source.key) == "string" then source.key else chunkKey,
		chunkX = if isFiniteNumber(source.chunkX) then math.floor(source.chunkX) else 0,
		chunkY = if isFiniteNumber(source.chunkY) then math.floor(source.chunkY) else 0,
		tileMinX = if isFiniteNumber(source.tileMinX) then math.floor(source.tileMinX) else 0,
		tileMinY = if isFiniteNumber(source.tileMinY) then math.floor(source.tileMinY) else 0,
		width = if isFiniteNumber(source.width) then math.floor(source.width) else world.chunkSize,
		height = if isFiniteNumber(source.height) then math.floor(source.height) else world.chunkSize,
		cells = if typeof(source.cells) == "table" then Sift.Dictionary.copy(source.cells) else {},
		revision = runtime.revision,
		updatedAt = os.clock(),
	}
end

function LiquidServiceServer:enqueueFullSnapshot(stream: PlayerStream, chunkKey: string)
	stream.fullQueueTail = enqueueString(stream.fullQueue, stream.fullQueueLookup, stream.fullQueueTail, chunkKey)
end

function LiquidServiceServer:markChunkStable(chunkKey: string, runtime: ChunkRuntime, reason: string)
	runtime.lastStableAt = os.clock()
	runtime.lastStableReason = reason
	local stableState = if runtime.regionState == CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN
		then CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN
		else CELL_DEBUG_STATE.STABLE
	self:setChunkRegionState(chunkKey, runtime, stableState, reason)
	self:updateChunkDebugAttributes(chunkKey, runtime)
	self:debugLog("logStableTransitions", `{chunkKey} stable ({reason})`)
end

function LiquidServiceServer:recordSimulationMetric(metricName: string, amountRaw: any?, runtime: ChunkRuntime?)
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

function LiquidServiceServer:getPendingWakeRequestCount(): number
	if self.pendingWakeHead > self.pendingWakeTail then
		return 0
	end
	return self.pendingWakeTail - self.pendingWakeHead + 1
end

function LiquidServiceServer:getChunkWorldPosition(chunkX: number, chunkY: number): (number, number, number)
	local world = self.world
	if world == nil then
		return chunkX, chunkY, 0
	end
	local tileSize = math.max(0.001, world.tileSize)
	local centerTileX = chunkX * world.chunkSize + world.chunkSize * 0.5
	local centerTileY = chunkY * world.chunkSize + world.chunkSize * 0.5
	return world.worldOrigin.Z + centerTileX * tileSize, world.worldOrigin.Y + centerTileY * tileSize, 0
end

function LiquidServiceServer:trackRecentChunkActivity(chunkKey: string, chunkX: number, chunkY: number)
	local touchedAt = os.clock()
	self.recentChunkTouchedAt[chunkKey] = touchedAt
	local worldX, worldY, worldZ = self:getChunkWorldPosition(chunkX, chunkY)
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

function LiquidServiceServer:pruneRecentChunkActivity()
	local expiry = self.config.simulation.disturbedChunkKeepAliveSeconds * 2
	local now = os.clock()
	for chunkKey, touchedAt in self.recentChunkTouchedAt do
		if now - touchedAt <= expiry then
			continue
		end
		self.recentChunkTouchedAt[chunkKey] = nil
		self.recentChunkGrid:remove(chunkKey)
	end
end

function LiquidServiceServer:requeueDirtyMutation(mutationRaw: any)
	if typeof(mutationRaw) ~= "table" then
		return
	end
	self.dirtyCellQueue:enqueue(mutationRaw)
end

function LiquidServiceServer:primeChunkRuntime(chunkKey: string, reasonRaw: any?): number
	local runtime = self:getChunkRuntime(chunkKey)
	if not self:isCollisionChunkReadyByKey(chunkKey) then
		self:setChunkRegionState(
			chunkKey,
			runtime,
			CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
			`awaitingCollisionChunk {chunkKey}`,
			chunkKey
		)
		runtime.lastPrimedCells = 0
		self:updateChunkDebugAttributes(chunkKey, runtime)
		return 0
	end
	if getDirtyCount(runtime) > 0 then
		runtime.lastPrimedCells = 0
		self:updateChunkDebugAttributes(chunkKey, runtime)
		return 0
	end

	local snapshot = self:getChunkSnapshot(chunkKey)
	if snapshot == nil then
		runtime.lastPrimedCells = 0
		self:updateChunkDebugAttributes(chunkKey, runtime)
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
		if self:markTileDirty(tileX, tileY, reasonRaw or "activation") then
			primedCount += 1
		end
	end

	runtime.lastPrimedCells = primedCount
	if primedCount > 0 then
		runtime.lastDisturbedAt = os.clock()
		self:debugLog(
			"logActivations",
			`{chunkKey} primed {primedCount} liquid cells ({if typeof(reasonRaw) == "string"
				then reasonRaw
				else "activation"})`
		)
	end
	self:updateChunkDebugAttributes(chunkKey, runtime)
	return primedCount
end

function LiquidServiceServer:expandInterestKeys(baseInterest: { [string]: boolean }): { [string]: boolean }
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
		local chunkX, chunkY = LiquidServiceUtils.unpackChunkKey(chunkKey)
		if chunkX == nil or chunkY == nil then
			continue
		end
		for offsetY = -margin, margin do
			for offsetX = -margin, margin do
				expanded[LiquidServiceUtils.packChunkKey(chunkX + offsetX, chunkY + offsetY)] = true
			end
		end
	end
	return expanded
end

function LiquidServiceServer:refreshPlayerInterest(player: Player)
	local world = self.world
	if world == nil then
		return
	end
	local stream = self:getPlayerStream(player)
	local nextInterest = self:expandInterestKeys(world:getPlayerInterestKeys(player))

	for chunkKey in nextInterest do
		if stream.interestKeys[chunkKey] == nil or stream.sentRevisions[chunkKey] == nil then
			self:enqueueFullSnapshot(stream, chunkKey)
		end
	end

	for chunkKey in stream.interestKeys do
		if nextInterest[chunkKey] then
			continue
		end
		stream.sentRevisions[chunkKey] = nil
		if self.networker ~= nil then
			self.networker:fire(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_UNLOADED, chunkKey)
		end
	end

	stream.interestKeys = nextInterest
end

function LiquidServiceServer:markTileDirty(
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
	local chunkX = LiquidServiceUtils.toChunkCoordinate(tileX, chunkSize)
	local chunkY = LiquidServiceUtils.toChunkCoordinate(tileY, chunkSize)
	local chunkKey = LiquidServiceUtils.packChunkKey(chunkX, chunkY)
	local runtime = self:getChunkRuntime(chunkKey)
	local localX = tileX - chunkX * chunkSize
	local localY = tileY - chunkY * chunkSize
	if localX < 0 or localX >= chunkSize or localY < 0 or localY >= chunkSize then
		return false
	end
	local index = LiquidServiceUtils.computeTileIndex(localX, localY, chunkSize)
	if runtime.dirtyLookup[index] then
		return false
	end
	local sourceTileX = if isFiniteNumber(sourceTileXRaw) then math.floor(sourceTileXRaw) else nil
	local sourceTileY = if isFiniteNumber(sourceTileYRaw) then math.floor(sourceTileYRaw) else nil
	if sourceTileX ~= nil and sourceTileY ~= nil then
		local sourceChunkX = LiquidServiceUtils.toChunkCoordinate(sourceTileX, chunkSize)
		local sourceChunkY = LiquidServiceUtils.toChunkCoordinate(sourceTileY, chunkSize)
		local sourceChunkKey = LiquidServiceUtils.packChunkKey(sourceChunkX, sourceChunkY)
		if sourceChunkKey ~= chunkKey then
			self:recordSimulationMetric("crossChunkWakeups", 1, runtime)
		end
	end
	runtime.dirtyLookup[index] = true
	runtime.queuedDirtyCount += 1
	runtime.lastDisturbedAt = os.clock()
	runtime.dirtyMarkCount += 1
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "unspecified"
	self.dirtyCellQueue:enqueue({
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
	self:trackRecentChunkActivity(chunkKey, chunkX, chunkY)
	self:updateChunkDebugAttributes(chunkKey, runtime, {
		LastQueuedTileX = tileX,
		LastQueuedTileY = tileY,
		LastDirtyReason = reason,
	})
	self:debugLog("logDirtyMarks", `{chunkKey} queued tile {tileX},{tileY} ({reason})`)
	if self.debug ~= nil then
		self.debug:incrementCounter("liquid_dirty_marks")
	end
	return true
end

function LiquidServiceServer:markAreaDirty(tileX: number, tileY: number, radiusRaw: any?, reasonRaw: any?)
	self:wakeLiquidRegion(tileX, tileY, reasonRaw, {
		radius = radiusRaw,
		sourceTileX = tileX,
		sourceTileY = tileY,
		scanNearby = false,
	})
end

function LiquidServiceServer:wakeLiquidRegion(tileXRaw: any, tileYRaw: any, reasonRaw: any?, optionsRaw: any?): boolean
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return false
	end
	local options = if typeof(optionsRaw) == "table" then optionsRaw :: { [string]: any } else {}
	local tileX = math.floor(tileXRaw)
	local tileY = math.floor(tileYRaw)
	local radius = if isFiniteNumber(options.radius) then math.max(0, math.floor(options.radius)) else 1
	local sourceTileX = if isFiniteNumber(options.sourceTileX) then math.floor(options.sourceTileX) else nil
	local sourceTileY = if isFiniteNumber(options.sourceTileY) then math.floor(options.sourceTileY) else nil
	local scanNearby = options.scanNearby == true
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "wakeRegion"
	local key = `{tileX}:{tileY}:{radius}:{if scanNearby then 1 else 0}`
	if self.pendingWakeLookup[key] then
		return false
	end

	local request = self.wakeRequestPool:acquire() :: WakeRequest
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
		self.debug:incrementCounter("liquid_wake_requests_enqueued")
	end
	return true
end

function LiquidServiceServer:applyWakeRequest(request: WakeRequest)
	local sourceTileX = if request.sourceTileX ~= nil then request.sourceTileX else request.tileX
	local sourceTileY = if request.sourceTileY ~= nil then request.sourceTileY else request.tileY
	for offsetY = -request.radius, request.radius do
		for offsetX = -request.radius, request.radius do
			self:markTileDirty(
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
			if world:getLiquidCellAt(scanX, scanY) == 0 then
				continue
			end
			self:markTileDirty(scanX, scanY, `{request.reason}:nearbyLiquid`, request.tileX, request.tileY)
		end
	end
end

function LiquidServiceServer:flushWakeRequests(maxRequestsRaw: any?): number
	local maxRequests = if isFiniteNumber(maxRequestsRaw)
		then math.max(1, math.floor(maxRequestsRaw))
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
		self:applyWakeRequest(request)
		self.wakeRequestPool:release(request)
		processed += 1
	end
	if processed > 0 and self.debug ~= nil then
		self.debug:incrementCounter("liquid_wake_requests_processed", processed)
	end
	return processed
end

function LiquidServiceServer:registerCellMutation(tileX: number, tileY: number, packedCell: number)
	local world = self.world
	if world == nil then
		return
	end
	local chunkSize = math.max(1, world.chunkSize)
	local chunkX = LiquidServiceUtils.toChunkCoordinate(tileX, chunkSize)
	local chunkY = LiquidServiceUtils.toChunkCoordinate(tileY, chunkSize)
	local chunkKey = LiquidServiceUtils.packChunkKey(chunkX, chunkY)
	local runtime = self:getChunkRuntime(chunkKey)
	local liquidType, fill = LiquidCell.unpack(packedCell)
	runtime.revision += 1
	runtime.lastDisturbedAt = os.clock()
	runtime.mutationCount += 1
	runtime.lastMutationTileX = tileX
	runtime.lastMutationTileY = tileY
	runtime.lastMutationFill = fill
	runtime.lastMutationType = liquidType
	self.changedChunkKeys[chunkKey] = true
	self:updateChunkDebugAttributes(chunkKey, runtime)
	self:debugLog("logSimulationSteps", `{chunkKey} mutated tile {tileX},{tileY} -> type={liquidType} fill={fill}`)
	if runtime.forceFullResync then
		return
	end

	local localX = tileX - chunkX * chunkSize
	local localY = tileY - chunkY * chunkSize
	local index = LiquidServiceUtils.computeTileIndex(localX, localY, chunkSize)
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

function LiquidServiceServer:setPackedCell(tileX: number, tileY: number, packedCell: number): boolean
	local world = self.world
	if world == nil then
		return false
	end
	local changed, _, nextPackedCell = world:setLiquidCellAt(tileX, tileY, packedCell)
	if changed then
		self:registerCellMutation(tileX, tileY, nextPackedCell)
	end
	return changed
end

function LiquidServiceServer:isSolid(tileX: number, tileY: number): boolean
	local world = self.world
	if world == nil then
		return true
	end
	local tileId = select(1, world:getTileAt(tileX, tileY))
	return tileId ~= world.tileId.AIR
end

function LiquidServiceServer:buildSolverAccess(runtime: ChunkRuntime): LiquidSolverAccess
	local world = self.world
	local access: LiquidSolverAccess = {
		maxFill = self.config.maxFill,
		chunkSize = if world ~= nil then world.chunkSize else 32,
		maxLeakScanDistance = self.config.simulation.leakScanDistanceTiles,
		getCell = function(tileX: number, tileY: number): number
			if world == nil then
				return 0
			end
			return world:getLiquidCellAt(tileX, tileY)
		end,
		setCell = function(tileX: number, tileY: number, packedCell: number): boolean
			return self:setPackedCell(tileX, tileY, packedCell)
		end,
		isSolid = function(tileX: number, tileY: number): boolean
			return self:isSolid(tileX, tileY)
		end,
		isChunkReady = function(chunkX: number, chunkY: number): boolean
			if world == nil then
				return false
			end
			local readinessMethod = (world :: any).isChunkCollisionReady
			if typeof(readinessMethod) == "function" then
				return readinessMethod(world, chunkX, chunkY) == true
			end
			return true
		end,
		pushDirty = function(tileX: number, tileY: number, reason: string?, sourceTileX: number?, sourceTileY: number?)
			self:markTileDirty(tileX, tileY, reason or "solverCascade", sourceTileX, sourceTileY)
		end,
		getDefinition = function(liquidType: number): LiquidDefinition?
			return self:getDefinition(liquidType)
		end,
		reportCellState = function(
			tileX: number,
			tileY: number,
			state: string,
			reason: string,
			fill: number,
			liquidType: number
		)
			self:updateCellDebugVisual(tileX, tileY, state, reason, fill, liquidType)
		end,
		recordMetric = function(metricName: string, amountRaw: any?)
			self:recordSimulationMetric(metricName, amountRaw, runtime)
		end,
	}
	return access
end

function LiquidServiceServer:stepChunk(chunkKey: string, mutationsRaw: any, budgetRaw: any): (number, number)
	local world = self.world
	if world == nil then
		return 0, 0
	end
	local snapshot = self:getChunkSnapshot(chunkKey)
	if snapshot == nil then
		return 0, 0
	end
	local runtime = self:getChunkRuntime(chunkKey)
	local budget = if isFiniteNumber(budgetRaw)
		then math.max(1, math.floor(budgetRaw))
		else self.config.simulation.maxCellsPerChunkStep
	local mutations = if typeof(mutationsRaw) == "table" then mutationsRaw :: { [number]: any } else {}
	local access = self:buildSolverAccess(runtime)
	runtime.lastActiveCellCount = 0
	runtime.lastDownwardTransfer = 0
	runtime.lastLateralTransfer = 0
	runtime.lastCrossChunkWakeups = 0

	local processed = 0
	local changed = 0
	for mutationIndex = 1, #mutations do
		local mutation = mutations[mutationIndex]
		if processed >= budget then
			self:requeueDirtyMutation(mutation)
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
		local index = LiquidServiceUtils.computeTileIndex(localX, localY, snapshot.width)
		if not runtime.dirtyLookup[index] then
			continue
		end
		runtime.dirtyLookup[index] = nil
		if runtime.queuedDirtyCount > 0 then
			runtime.queuedDirtyCount -= 1
		end
		local stepResult: LiquidSolverStepResult = LiquidSolver.stepCell(access, tileX, tileY)
		if stepResult.changed then
			changed += 1
		end
		if stepResult.waitingOnChunkReady then
			self:setChunkRegionState(
				chunkKey,
				runtime,
				CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
				stepResult.reason,
				stepResult.dependencyChunkKey
			)
		elseif stepResult.active then
			self:setChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, stepResult.reason)
		elseif stepResult.state == CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN then
			self:setChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN, stepResult.reason)
		end
		processed += 1
	end
	runtime.lastProcessedAt = os.clock()
	runtime.lastProcessedCells = processed
	runtime.lastChangedCells = changed
	self:recordSimulationMetric("cellsProcessed", processed, runtime)
	self:updateChunkDebugAttributes(chunkKey, runtime, {
		LastStepBudget = budget,
	})
	if processed > 0 then
		self:debugLog(
			"logSimulationSteps",
			`{chunkKey} stepped processed={processed} changed={changed} active={runtime.lastActiveCellCount} down={runtime.lastDownwardTransfer} lateral={runtime.lastLateralTransfer} remainingDirty={getDirtyCount(
				runtime
			)}`
		)
	end
	return processed, changed
end

function LiquidServiceServer:verifyChunkStability(
	chunkKey: string,
	runtime: ChunkRuntime,
	reasonRaw: any?
): (boolean, string, number)
	if not self:isCollisionChunkReadyByKey(chunkKey) then
		local deferredReason = `awaitingCollisionChunk {chunkKey}`
		self:setChunkRegionState(
			chunkKey,
			runtime,
			CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
			deferredReason,
			chunkKey
		)
		runtime.lastStabilityScanUnstableCells = math.max(1, runtime.lastStabilityScanUnstableCells)
		return false, deferredReason, runtime.lastStabilityScanUnstableCells
	end

	local snapshot = self:getChunkSnapshot(chunkKey)
	if snapshot == nil then
		runtime.lastStabilityScanUnstableCells = 0
		return true, "missingSnapshot", 0
	end

	local access = self:buildSolverAccess(runtime)
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
		local inspection = LiquidSolver.inspectCell(access, tileX, tileY)
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
				self:markTileDirty(tileX, tileY, `stabilityScan:{inspection.state}`)
				for _, wakeTileEntry in inspection.wakeTiles do
					self:markTileDirty(
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
	self:updateChunkDebugAttributes(chunkKey, runtime)
	if deferredCount > 0 then
		local deferredReason = firstReason or `awaitingCollisionChunk {dependencyChunkKey or chunkKey}`
		self:setChunkRegionState(
			chunkKey,
			runtime,
			CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
			deferredReason,
			dependencyChunkKey
		)
		return false, deferredReason, deferredCount
	end
	if unstableCount > 0 then
		self:setChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, firstReason or "unstable")
		local reopenedReason =
			`{if typeof(reasonRaw) == "string" then reasonRaw else "stabilityScan"} reopened; unstableCells={unstableCount}; first={firstReason or "unknown"}`
		self:debugLog("logStableTransitions", `{chunkKey} reopened ({reopenedReason})`)
		return false, reopenedReason, unstableCount
	end

	return true, "downwardSealed lateralSealed leakPathClear boundaryClear", 0
end

function LiquidServiceServer:collectActiveChunkKeys(): ({ string }, { [string]: string }, { [string]: boolean })
	local activeLookup: { [string]: boolean } = {}
	local activeKeys: { string } = {}
	local activeReasonLists: { [string]: { string } } = {}
	local now = os.clock()

	for _, stream in self.playerStreams do
		for chunkKey in stream.interestKeys do
			if not activeLookup[chunkKey] then
				activeLookup[chunkKey] = true
				table.insert(activeKeys, chunkKey)
				activeReasonLists[chunkKey] = {}
			end
			appendReason(activeReasonLists[chunkKey], "playerInterest")
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

function LiquidServiceServer:processSimulationStep()
	if self.debug ~= nil then
		self.debug:resetFrameCounters()
	end
	local solveToken = if self.debug ~= nil then self.debug:beginFrameScope("liquid_server_solve") else nil
	self.simulationStepId += 1
	self.currentSimulationStats = createSimulationTickStats()
	self.currentSimulationStats.chunkReadinessWakeups = self.pendingChunkReadinessWakeups
	self.pendingChunkReadinessWakeups = 0
	self.currentSimulationStats.collisionChunksLoaded = self:getLoadedCollisionChunkCount()
	self.currentSimulationStats.wakeRequestsQueued = self:getPendingWakeRequestCount()
	self.currentSimulationStats.wakeRequestsProcessed =
		self:flushWakeRequests(self.config.simulation.maxWakeRequestsPerTick)
	local activeKeys, activeReasons, activeLookup = self:collectActiveChunkKeys()
	self.currentSimulationStats.activeChunks = #activeKeys
	local reactivatedChunks: { [string]: boolean } = {}
	for _, chunkKey in activeKeys do
		local runtime = self:getChunkRuntime(chunkKey)
		local activeReason = activeReasons[chunkKey] or "active"
		local wasActiveLastStep = runtime.lastActiveStepId > 0 and runtime.lastActiveStepId == self.simulationStepId - 1
		reactivatedChunks[chunkKey] = not wasActiveLastStep
		runtime.lastActiveStepId = self.simulationStepId
		if not wasActiveLastStep then
			runtime.lastActivationAt = os.clock()
			runtime.lastActivationReason = activeReason
			if self:isCollisionChunkReadyByKey(chunkKey) then
				local restored = self:restoreQueuedDirtyCellsForChunk(chunkKey, `{activeReason}:reactivationRestore`)
				if restored == 0 then
					self:primeChunkRuntime(chunkKey, activeReason)
				end
				self:setChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, activeReason)
			else
				self:setChunkRegionState(
					chunkKey,
					runtime,
					CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
					`awaitingCollisionChunk {chunkKey}`,
					chunkKey
				)
			end
			self:updateChunkDebugAttributes(chunkKey, runtime, {
				InActiveSet = true,
				ActiveReason = activeReason,
			})
			self:debugLog("logActivations", `{chunkKey} entered active set ({activeReason})`)
		end
	end
	self.currentSimulationStats.queuedCells = self.dirtyCellQueue:getPendingCount()
	for _, chunkKey in activeKeys do
		if getDirtyCount(self:getChunkRuntime(chunkKey)) > 0 then
			self.currentSimulationStats.dirtyChunks += 1
		end
	end
	if self:isDebugEnabled() and self.config.debug.visualizeChunks then
		for chunkKey, runtime in self.chunkRuntimes do
			self:updateChunkDebugAttributes(chunkKey, runtime, {
				InActiveSet = activeLookup[chunkKey] == true,
				ActiveReason = activeReasons[chunkKey] or "",
			})
		end
	end

	local processedChunks = 0
	local touchedChunks: { [string]: boolean } = {}
	local maxMutationBudget = self.config.simulation.maxChunkStepsPerTick * self.config.simulation.maxCellsPerChunkStep
	local flushBatch = self.dirtyCellQueue:flush(maxMutationBudget)
	if flushBatch ~= nil then
		for _, chunkBatch in flushBatch.chunks do
			local chunkKey = LiquidServiceUtils.packChunkKey(chunkBatch.chunkX, chunkBatch.chunkY)
			if processedChunks >= self.config.simulation.maxChunkStepsPerTick then
				for _, mutation in chunkBatch.mutations do
					self:requeueDirtyMutation(mutation)
				end
				continue
			end
			local runtime = self:getChunkRuntime(chunkKey)
			if not self:isCollisionChunkReadyByKey(chunkKey) then
				self:setChunkRegionState(
					chunkKey,
					runtime,
					CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
					`awaitingCollisionChunk {chunkKey}`,
					chunkKey
				)
				continue
			end
			local processedCells, _changedCells =
				self:stepChunk(chunkKey, chunkBatch.mutations, self.config.simulation.maxCellsPerChunkStep)
			if processedCells <= 0 then
				continue
			end
			processedChunks += 1
			touchedChunks[chunkKey] = true
			if getDirtyCount(runtime) <= 0 then
				local isStable, stableReason = self:verifyChunkStability(chunkKey, runtime, "dirtyQueueDrained")
				if isStable then
					self:markChunkStable(chunkKey, runtime, stableReason)
				end
			end
		end
	end

	for _, chunkKey in activeKeys do
		if touchedChunks[chunkKey] then
			continue
		end
		local runtime = self:getChunkRuntime(chunkKey)
		if getDirtyCount(runtime) > 0 then
			continue
		end
		if reactivatedChunks[chunkKey] then
			local isStable, stableReason = self:verifyChunkStability(chunkKey, runtime, "reactivatedWithoutDirtyWork")
			if isStable then
				self:markChunkStable(chunkKey, runtime, stableReason)
			end
		end
	end

	self.currentSimulationStats.queuedCells = self.dirtyCellQueue:getPendingCount()
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
	self.currentSimulationStats.collisionChunksLoaded = self:getLoadedCollisionChunkCount()
	if self.debug ~= nil then
		self.debug:endFrameScope("liquid_server_solve", solveToken)
	end
	self:updateSimulationDebugStats()
end

function LiquidServiceServer:processConsistencySweep()
	local world = self.world
	if world == nil then
		return
	end
	local debugToken = if self.debug ~= nil then self.debug:beginFrameScope("liquid_consistency_sweep") else nil
	self:pruneRecentChunkActivity()

	local queryResults = self.sweepResultPool:acquire() :: { any }
	local candidateLookup: { [string]: boolean } = {}
	local candidateKeys: { string } = {}
	local sweepRadiusStuds = world.chunkSize
		* world.tileSize
		* math.max(1, self.config.simulation.activeSafetyMarginChunks + 2)

	for player in self.playerStreams do
		local rootPart = resolveCharacterRootPart(resolvePlayerCharacter(player))
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
	self.sweepResultPool:release(queryResults)
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
			and self:isCollisionChunkReadyByKey(chunkKey)
			and self:isCollisionChunkReadyByKey(runtime.dependencyChunkKey)
		then
			local restored = self:restoreQueuedDirtyCellsForChunk(chunkKey, "consistencyChunkReady")
			if restored == 0 then
				self:primeChunkRuntime(chunkKey, "consistencyChunkReady")
			end
			self:setChunkRegionState(chunkKey, runtime, CELL_DEBUG_STATE.ACTIVE, "consistencyChunkReady")
			self:recordSimulationMetric("consistencyRequeues", 1, runtime)
			processed += 1
			continue
		end
		if not self:isCollisionChunkReadyByKey(chunkKey) then
			self:setChunkRegionState(
				chunkKey,
				runtime,
				CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK,
				`awaitingCollisionChunk {chunkKey}`,
				chunkKey
			)
			processed += 1
			continue
		end
		local isStable = self:verifyChunkStability(chunkKey, runtime, "consistencySweep")
		if not isStable then
			self:recordSimulationMetric("consistencyRequeues", 1, runtime)
		end
		processed += 1
	end

	if self.debug ~= nil then
		self.debug:setCounter("liquid_consistency_candidates", #candidateKeys)
		self.debug:setCounter("liquid_consistency_processed", processed)
		self.debug:endFrameScope("liquid_consistency_sweep", debugToken)
	end
	local debugFolder = self:getDebugFolder()
	if debugFolder ~= nil and self.debug ~= nil then
		local counters = self.debug:getCounters()
		debugFolder:SetAttribute("ConsistencyCandidates", #candidateKeys)
		debugFolder:SetAttribute("ConsistencyProcessed", processed)
		debugFolder:SetAttribute(
			"TimeConsistencySweepMs",
			math.round(((counters.time_liquid_consistency_sweep or 0) * 1000) * 100) / 100
		)
	end
end

function LiquidServiceServer:redistributeDisplacedLiquid(tileX: number, tileY: number, packedCell: number)
	local liquidType, fill = LiquidCell.unpack(packedCell)
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
		if self:isSolid(targetX, targetY) then
			continue
		end
		local existingCell = if self.world ~= nil then self.world:getLiquidCellAt(targetX, targetY) else 0
		local existingType, existingFill = LiquidCell.unpack(existingCell)
		if existingType ~= LIQUID_TYPE.NONE and existingType ~= liquidType then
			continue
		end
		local transfer = math.min(remaining, self.config.maxFill - existingFill)
		if transfer <= 0 then
			continue
		end
		remaining -= transfer
		self:setPackedCell(
			targetX,
			targetY,
			LiquidCell.make(liquidType, existingFill + transfer, LiquidServiceUtils.FLOW_STATE.SPREADING)
		)
		self:wakeLiquidRegion(targetX, targetY, "displacedLiquid", {
			radius = 1,
			sourceTileX = tileX,
			sourceTileY = tileY,
			scanNearby = false,
		})
	end
end

function LiquidServiceServer:reactivateNearbyLiquid(tileX: number, tileY: number, reasonRaw: any?)
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "terrainChange"
	self:wakeLiquidRegion(tileX, tileY, reason, {
		radius = 2,
		sourceTileX = tileX,
		sourceTileY = tileY,
		scanNearby = true,
	})
end

function LiquidServiceServer:notifyTerrainChanged(
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
	local chunkX = LiquidServiceUtils.toChunkCoordinate(tileX, world.chunkSize)
	local chunkY = LiquidServiceUtils.toChunkCoordinate(tileY, world.chunkSize)
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

function LiquidServiceServer:processFullSnapshotQueues()
	for player, stream in self.playerStreams do
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
			local snapshot = self:getChunkSnapshot(chunkKey)
			if snapshot == nil then
				continue
			end
			self.networker:fire(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_SNAPSHOT, snapshot)
			stream.sentRevisions[chunkKey] = snapshot.revision
			processed += 1
		end
	end
end

function LiquidServiceServer:processChangedChunks()
	for chunkKey in self.changedChunkKeys do
		local runtime = self.chunkRuntimes[chunkKey]
		if runtime == nil then
			continue
		end
		if runtime.pendingDeltaCount <= 0 then
			continue
		end
		table.sort(runtime.pendingDeltaIndices)

		local snapshot = if runtime.forceFullResync then self:getChunkSnapshot(chunkKey) else nil
		local deltaPayload = nil :: { [string]: any }?
		if not runtime.forceFullResync then
			local chunkSnapshot = self:getChunkSnapshot(chunkKey)
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
			if stream.interestKeys[chunkKey] == nil then
				continue
			end
			if stream.sentRevisions[chunkKey] == nil then
				self:enqueueFullSnapshot(stream, chunkKey)
				continue
			end

			if runtime.forceFullResync then
				if snapshot ~= nil then
					self.networker:fire(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_SNAPSHOT, snapshot)
					stream.sentRevisions[chunkKey] = snapshot.revision
				end
			elseif deltaPayload ~= nil then
				self.networker:fire(player, LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_DELTA, deltaPayload)
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

function LiquidServiceServer:getPlayerQuery(player: Player): LiquidQueryResult
	local hazard = self:getHazardRuntime(player)
	local now = os.clock()
	if hazard.lastQuery ~= nil and now - hazard.lastQueryAt <= QUERY_CACHE_WINDOW then
		return hazard.lastQuery
	end

	local query = LiquidQuery.queryCharacter({
		tileSize = if self.world ~= nil then self.world.tileSize else 2,
		worldOrigin = if self.world ~= nil then self.world.worldOrigin else Vector3.zero,
		getCellAt = function(tileX: number, tileY: number): number
			if self.world == nil then
				return 0
			end
			return self.world:getLiquidCellAt(tileX, tileY)
		end,
		getLiquidDefinition = function(liquidType: number): LiquidDefinition?
			return self:getDefinition(liquidType)
		end,
	}, resolvePlayerCharacter(player))
	hazard.lastQuery = query
	hazard.lastQueryAt = now
	return query
end

function LiquidServiceServer:fireEffectEvent(
	player: Player,
	eventType: string,
	liquidType: number,
	query: LiquidQueryResult
)
	if self.networker == nil then
		return
	end
	self.networker:fire(player, LiquidServiceUtils.CLIENT_METHOD_ON_EFFECT_EVENT, {
		eventType = eventType,
		liquidType = liquidType,
		submersionRatio = query.submersionRatio,
		updatedAt = os.clock(),
	})
end

function LiquidServiceServer:applyLiquidMovementSpeed(player: Player, query: LiquidQueryResult)
	local humanoid = resolveCharacterHumanoid(resolvePlayerCharacter(player))
	if humanoid == nil or not PlayerServiceUtils.isHumanoidAlive(humanoid) then
		return
	end

	local multiplier = nil :: number?
	if query.inLiquid then
		local definition = self:getDefinition(query.dominantType)
		if definition ~= nil and definition.movementSpeedMultiplier < 0.999 then
			multiplier = definition.movementSpeedMultiplier
		end
	end

	PlayerServiceUtils.setMovementSpeedMultiplier(
		humanoid,
		PlayerServiceUtils.LIQUID_WALK_SPEED_MULTIPLIER_ATTRIBUTE,
		multiplier
	)
end

function LiquidServiceServer:processHazards()
	local lavaDefinition = LiquidDamage.getLavaDefinition(self.config)
	local now = os.clock()

	for player in self.playerStreams do
		local hazard = self:getHazardRuntime(player)
		local query = self:getPlayerQuery(player)
		self:applyLiquidMovementSpeed(player, query)

		if query.inLiquid ~= hazard.wasInLiquid then
			if query.inLiquid then
				self.enteredLiquid:Fire(player, query)
				self:fireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.ENTER, query.dominantType, query)
			else
				self.exitedLiquid:Fire(player, hazard.lastDominantType, query)
				self:fireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.EXIT, hazard.lastDominantType, query)
			end
		end

		if query.meaningfulSubmersion ~= hazard.wasMeaningfullySubmerged then
			if query.meaningfulSubmersion then
				self.submergedStarted:Fire(player, query)
				self:fireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.SUBMERGED_START, query.dominantType, query)
			else
				self.submergedEnded:Fire(player, hazard.lastDominantType, query)
				self:fireEffectEvent(
					player,
					LiquidServiceUtils.EFFECT_EVENT.SUBMERGED_END,
					hazard.lastDominantType,
					query
				)
			end
		end

		if lavaDefinition ~= nil and LiquidDamage.shouldApplyLavaContact(self.config, query) then
			if now - hazard.lastLavaDamageAt >= lavaDefinition.lavaTouchInterval then
				self.hpService:damagePlayer(player, lavaDefinition.lavaTouchDamage)
				hazard.lastLavaDamageAt = now
			end
			hazard.burnEndsAt = math.max(hazard.burnEndsAt, now + lavaDefinition.burnDuration)
		end

		local isBurning = hazard.burnEndsAt > now
		if isBurning and lavaDefinition ~= nil and now - hazard.lastBurnDamageAt >= lavaDefinition.burnInterval then
			self.hpService:damagePlayer(player, lavaDefinition.burnDamage)
			hazard.lastBurnDamageAt = now
		end

		if isBurning ~= hazard.wasBurning then
			if isBurning then
				self.burnStarted:Fire(player, hazard.burnEndsAt - now)
				self:fireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.BURN_START, LIQUID_TYPE.LAVA, query)
			else
				self.burnEnded:Fire(player)
				self:fireEffectEvent(player, LiquidServiceUtils.EFFECT_EVENT.BURN_END, LIQUID_TYPE.LAVA, query)
			end
		end

		hazard.wasInLiquid = query.inLiquid
		hazard.wasMeaningfullySubmerged = query.meaningfulSubmersion
		hazard.wasBurning = isBurning
		hazard.lastDominantType = query.dominantType
	end
end

function LiquidServiceServer:onHeartbeat(deltaTime: number)
	self:refreshWorldBinding()

	self.streamAccumulator += deltaTime
	self.simulationAccumulator += deltaTime
	self.hazardAccumulator += deltaTime
	self.consistencyAccumulator += deltaTime

	if self.streamAccumulator >= self.config.simulation.streamSyncInterval then
		self.streamAccumulator = 0
		for player in self.playerStreams do
			self:refreshPlayerInterest(player)
		end
		self:processFullSnapshotQueues()
	end

	local simulationStep = 1 / self.config.simulation.stepRate
	while self.simulationAccumulator >= simulationStep do
		self.simulationAccumulator -= simulationStep
		self:processSimulationStep()
	end

	local hazardStep = 1 / self.config.simulation.hazardCheckRate
	while self.hazardAccumulator >= hazardStep do
		self.hazardAccumulator -= hazardStep
		self:processHazards()
	end

	local consistencyStep = self.config.simulation.consistencySweepInterval
	while self.consistencyAccumulator >= consistencyStep do
		self.consistencyAccumulator -= consistencyStep
		self:processConsistencySweep()
	end

	self:processChangedChunks()
end

function LiquidServiceServer:trackPlayer(player: Player)
	self.playerStreams[player] = self:createPlayerStream()
	self.playerHazards[player] = self:createHazardRuntime()
	self:pushState(player)
	self:refreshPlayerInterest(player)
end

function LiquidServiceServer:untrackPlayer(player: Player)
	self.playerStreams[player] = nil
	self.playerHazards[player] = nil
end

function LiquidServiceServer:requestSync(player: Player)
	if self.playerStreams[player] == nil then
		self:trackPlayer(player)
		return
	end
	self:refreshWorldBinding()
	local stream = self:getPlayerStream(player)
	table.clear(stream.interestKeys)
	table.clear(stream.sentRevisions)
	table.clear(stream.fullQueue)
	table.clear(stream.fullQueueLookup)
	stream.fullQueueHead = 1
	stream.fullQueueTail = 0
	self:pushState(player)
	self:refreshPlayerInterest(player)
end

function LiquidServiceServer:getPlayerLiquidQuery(player: Player): LiquidQueryResult
	return self:getPlayerQuery(player)
end

function LiquidServiceServer:refreshWorldBinding()
	local latestWorld = self.worldGenerationService:getWorld()
	if latestWorld == self.world then
		return
	end

	if self.chunkLifecycleConnection ~= nil then
		self.chunkLifecycleConnection:Disconnect()
		self.chunkLifecycleConnection = nil
	end
	self.world = latestWorld
	if self.world ~= nil and typeof((self.world :: any).registerChunkLifecycleObserver) == "function" then
		self.chunkLifecycleConnection = (
			(self.world :: any):registerChunkLifecycleObserver(self)
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
		self.dirtyCellQueue:destroy()
	end
	self.dirtyCellQueue = WorldMutationQueue.new({
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

	for player in self.playerStreams do
		self.playerStreams[player] = self:createPlayerStream()
	end
	for player in self.playerHazards do
		self.playerHazards[player] = self:createHazardRuntime()
	end
end

function LiquidServiceServer:init()
	self.runtimeContext = CoreRuntime.getServerRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).init) == "function" then
		local runtimeAny = self.runtimeContext :: any
		runtimeAny:init()
	end
	self.config = LiquidServiceUtils.sanitizeConfig(resolveSourceConfig(), nil)
	self.state = LiquidServiceUtils.createDefaultState()
	self.worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.world = self.worldGenerationService:getWorld()
	self.chunkLifecycleConnection = nil :: ChunkLifecycleConnection?
	if self.world ~= nil and typeof((self.world :: any).registerChunkLifecycleObserver) == "function" then
		self.chunkLifecycleConnection = (
			(self.world :: any):registerChunkLifecycleObserver(self)
		) :: ChunkLifecycleConnection?
	end
	self.hpService = HpServiceServer :: HpServiceServerObject
	self.debug = WorldSimulationDebug.new({
		enabled = self.config.debug.enabled,
		profilingEnabled = self.config.debug.enabled,
	})
	self.chunkRuntimes = {} :: { [string]: ChunkRuntime }
	self.playerStreams = {} :: { [Player]: PlayerStream }
	self.playerHazards = {} :: { [Player]: PlayerHazardRuntime }
	self.changedChunkKeys = {} :: { [string]: boolean }
	self.dirtyCellQueue = WorldMutationQueue.new({
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

	self.networker = Networker.server.new("LiquidService", self, {
		self.requestSync,
	})

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if isGameplayReplicationActive(player) then
			self:trackPlayer(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)
	local tickScheduler = if self.runtimeContext ~= nil then (self.runtimeContext :: any).tickScheduler else nil
	if tickScheduler ~= nil and typeof((tickScheduler :: any).scheduleEvery) == "function" then
		self.heartbeatToken = (tickScheduler :: any):scheduleEvery(
			function(deltaTime: number)
				self:onHeartbeat(deltaTime)
			end,
			1 / 60,
			{
				group = "service.liquid.server",
				priority = TickSchedulerModule.Priority.NORMAL + 20,
				catchUp = false,
			}
		)
		self.poolMaintenanceToken = (tickScheduler :: any):scheduleEvery(
			function()
				self.wakeRequestPool:softShrink(24)
				self.sweepResultPool:softShrink(6)
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
			self:onHeartbeat(deltaTime)
		end)
	end
end

function LiquidServiceServer:destroy()
	if self.heartbeatToken ~= nil and typeof(self.heartbeatToken.cancel) == "function" then
		self.heartbeatToken:cancel()
		self.heartbeatToken = nil
	end
	if self.poolMaintenanceToken ~= nil and typeof(self.poolMaintenanceToken.cancel) == "function" then
		self.poolMaintenanceToken:cancel()
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
	if self.networker ~= nil then
		self.networker:destroy()
		self.networker = nil
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
		self.dirtyCellQueue:destroy()
	end
	if self.wakeRequestPool ~= nil then
		self.wakeRequestPool:destroy()
	end
	if self.sweepResultPool ~= nil then
		self.sweepResultPool:destroy()
	end
	if self.recentChunkGrid ~= nil then
		self.recentChunkGrid:clear()
	end
	if self.debug ~= nil then
		self.debug:destroy()
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
	networker: Networker.Server?,
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
