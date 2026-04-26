--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local CancelToken = loader("CancelToken")
local Maid = loader("Maid")
local ObservableMap = loader("ObservableMap")
local ObservableSet = loader("ObservableSet")
local Promise = loader("Promise")
local PromiseMaidUtils = loader("PromiseMaidUtils")
local Rx = loader("Rx")
local RxSignal = loader("RxSignal")
local Signal = loader("Signal")
local ValueObject = loader("ValueObject")
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local EyeOfCthulhuConfig = require(script:FindFirstAncestor("game").Shared.Classes.Boss.EyeOfCthulhu.Config)
local EyeOfCthulhuController = require(script:FindFirstAncestor("game").Shared.Classes.Boss.EyeOfCthulhu)
local HpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpServiceServer)
local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerServiceServer)
local ServerBinderSupport = require(script:FindFirstAncestor("game").Server.Binders.ServerBinderSupport)
local WeatherServiceServer = require(script:FindFirstAncestor("game").Server.Services.WeatherServiceServer)
local WorldGenerationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldGenerationServiceServer)

type BossId = BossServiceUtils.BossId
type BossSnapshot = BossServiceUtils.BossSnapshot
type BossServiceState = BossServiceUtils.BossServiceState
type BossRegistryEntry = BossServiceUtils.BossRegistryEntry
type BossSpawnRequest = BossServiceUtils.BossSpawnRequest

type BossObject = any
type MaidClass = {
	Add: <T>(self: MaidClass, task: T) -> T,
	GiveTask: (self: MaidClass, task: any) -> number,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type ObservableObject = {
	Subscribe: (
		self: ObservableObject,
		onFire: (...any) -> (),
		onFail: ((...any) -> ())?,
		onComplete: ((...any) -> ())?
	) -> any,
	Pipe: (self: ObservableObject, transformers: { any }) -> ObservableObject,
}

type RxSignalObject = {
	Connect: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Once: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Wait: (self: RxSignalObject) -> ...any,
}

type PromiseObject = {
	Then: (self: PromiseObject, onFulfilled: ((...any) -> ...any)?, onRejected: ((...any) -> ...any)?) -> PromiseObject,
	Catch: (self: PromiseObject, onRejected: ((...any) -> ...any)?) -> PromiseObject,
	Finally: (self: PromiseObject, callback: ((...any) -> ...any)?) -> PromiseObject,
	Yield: (self: PromiseObject) -> (boolean, ...any),
	Destroy: (self: PromiseObject) -> (),
}

type ObservableMapClass = {
	Set: (self: ObservableMapClass, key: string, value: BossObject?) -> () -> (),
	Remove: (self: ObservableMapClass, key: string) -> (),
	Get: (self: ObservableMapClass, key: string) -> BossObject?,
	ObservePairsBrio: (self: ObservableMapClass) -> ObservableObject,
	ObserveAtKey: (self: ObservableMapClass, key: string) -> ObservableObject,
	Destroy: (self: ObservableMapClass) -> (),
}

type ObservableSetClass = {
	Add: (self: ObservableSetClass, item: Player) -> () -> (),
	Remove: (self: ObservableSetClass, item: Player) -> boolean,
	GetList: (self: ObservableSetClass) -> { Player },
	ObserveItemsBrio: (self: ObservableSetClass) -> ObservableObject,
	Destroy: (self: ObservableSetClass) -> (),
}

type ValueObjectClass<T> = {
	Value: T,
	Observe: (self: ValueObjectClass<T>) -> ObservableObject,
	Destroy: (self: ValueObjectClass<T>) -> (),
}

type HpServiceServerObject = {
	damagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
}

type WeatherServiceServerObject = {
	getState: (self: WeatherServiceServerObject) -> { clockTime: number },
}

type WorldGenerationServiceServerObject = {
	getWorld: (self: WorldGenerationServiceServerObject) -> any,
}

type PendingNaturalSpawn = {
	bossId: BossId,
	targetPlayer: Player,
	encounterChannel: string,
	delayRemaining: number,
	announcement: string,
}

local BossServiceServer = {}

local CONTROLLER_CONSTRUCTORS = {
	EyeOfCthulhu = function(
		service: BossServiceServer,
		definition: BossRegistryEntry,
		spawnRequest: BossSpawnRequest
	): BossObject
		return EyeOfCthulhuController.new(service, definition, spawnRequest)
	end,
}

local DEFAULT_STATE_PUSH_INTERVAL = BossServiceUtils.DEFAULT_STATE_PUSH_INTERVAL
local DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL = BossServiceUtils.DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL
local DEFAULT_BOX_QUERY_MAX_PARTS = 96

local function resolveBossSettingsSource(): { [string]: any }
	if typeof(Configs) ~= "table" then
		return {}
	end

	local bossSettings = (Configs :: any).bossSettings
	if typeof(bossSettings) ~= "table" then
		return {}
	end

	return bossSettings :: { [string]: any }
end

local function resolveEyeConfigSource(): { [string]: any }?
	local bossSettings = resolveBossSettingsSource()
	local eyeConfig = (bossSettings :: any).eyeOfCthulhu
	if typeof(eyeConfig) == "table" then
		return eyeConfig
	end
	return nil
end

local function trim(valueRaw: any): string
	return BossServiceUtils.trim(valueRaw)
end

local function resolveModelBindingMaidKey(runtimeId: string): string
	return ("modelBinding_%s"):format(runtimeId)
end

local function resolveBossId(boss: BossObject): string
	if typeof(boss) == "table" and typeof(boss.id) == "string" then
		return boss.id
	end
	return ""
end

local function destroyBossSafely(bossRaw: any)
	if typeof(bossRaw) ~= "table" then
		return
	end

	local destroy = (bossRaw :: any).destroy
	if typeof(destroy) ~= "function" then
		return
	end

	pcall(function()
		destroy(bossRaw)
	end)
end

local function getOrCreateObservable(
	self: BossServiceServer,
	key: string,
	factory: () -> ObservableObject
): ObservableObject
	local cached = self.observableCache[key]
	if cached ~= nil then
		return cached
	end

	local created = factory()
	self.observableCache[key] = created
	return created
end

local function getOrCreateRxSignal(self: BossServiceServer, key: string, factory: () -> RxSignalObject): RxSignalObject
	local cached = self.rxSignalCache[key]
	if cached ~= nil then
		return cached
	end

	local created = factory()
	self.rxSignalCache[key] = created
	return created
end

local function resolveCancelToken(cancelTokenRaw: any): any?
	if CancelToken.isCancelToken(cancelTokenRaw) then
		return cancelTokenRaw
	end
	return nil
end

function BossServiceServer.SetPendingNaturalSpawn(self: BossServiceServer, pendingNaturalSpawn: PendingNaturalSpawn?)
	self.pendingNaturalSpawn = pendingNaturalSpawn
	if self.pendingNaturalSpawnValue ~= nil then
		self.pendingNaturalSpawnValue.Value = pendingNaturalSpawn
	end
end

function BossServiceServer.EmitStateChanged(self: BossServiceServer)
	if self._stateChangedSignal ~= nil then
		self._stateChangedSignal:Fire(self:createStateSnapshot())
	end
end

function BossServiceServer.EmitControllerAdded(self: BossServiceServer, snapshot: BossSnapshot, boss: BossObject)
	if self._controllerAddedSignal ~= nil then
		self._controllerAddedSignal:Fire(snapshot, boss)
	end
end

function BossServiceServer.EmitControllerUpdated(self: BossServiceServer, snapshot: BossSnapshot, boss: BossObject)
	if self._controllerUpdatedSignal ~= nil then
		self._controllerUpdatedSignal:Fire(snapshot, boss)
	end
end

function BossServiceServer.EmitControllerRemoved(
	self: BossServiceServer,
	runtimeId: string,
	boss: BossObject?,
	reasonRaw: any?
)
	if self._controllerRemovedSignal == nil then
		return
	end

	self._controllerRemovedSignal:Fire({
		id = runtimeId,
		bossId = if boss ~= nil then boss.bossId else nil,
		reason = trim(reasonRaw),
		updatedAt = self:getNow(),
	}, boss)
end

function BossServiceServer.BindController(self: BossServiceServer, runtimeId: string, boss: BossObject, maid: MaidClass)
	self:refreshControllerModelBinding(boss)

	local function syncNow()
		if self.controllersById[runtimeId] ~= boss then
			return
		end

		self:refreshControllerModelBinding(boss)
		self:syncControllerSnapshot(boss, true)
	end

	maid:GiveTask(boss:observeStateChanged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:observeTargetChanged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:observeDamaged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:observeDied():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:observeModelChanged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:observeRemoved():Subscribe(function(reason)
		if self.controllersById[runtimeId] ~= boss then
			return
		end

		self:removeController(runtimeId, reason)
	end))
	maid:GiveTask(boss:observeDestroying():Subscribe(function()
		if self.controllersById[runtimeId] ~= boss then
			return
		end

		self:removeController(runtimeId, "controller_destroyed")
	end))
end

function BossServiceServer.InitReactiveState(self: BossServiceServer)
	self.observableCache = {}
	self.rxSignalCache = {}
	self._stateChangedSignal = Signal.new()
	self._controllerAddedSignal = Signal.new()
	self._controllerUpdatedSignal = Signal.new()
	self._controllerRemovedSignal = Signal.new()
	self._announcementSignal = Signal.new()
	self.controllerMap = ObservableMap.new() :: ObservableMapClass
	self.trackedPlayers = ObservableSet.new() :: ObservableSetClass
	self.pendingNaturalSpawnValue = ValueObject.new(nil) :: ValueObjectClass<PendingNaturalSpawn?>

	self.stateChangedSignal = RxSignal.new(function()
		return self:observeState()
	end) :: RxSignalObject
	self.controllerAddedSignal = RxSignal.new(function()
		return self:observeControllerAdded()
	end) :: RxSignalObject
	self.controllerUpdatedSignal = RxSignal.new(function()
		return self:observeControllerUpdated()
	end) :: RxSignalObject
	self.controllerRemovedSignal = RxSignal.new(function()
		return self:observeControllerRemoved()
	end) :: RxSignalObject
	self.controllersSignal = RxSignal.new(function()
		return self:observeControllersBrio()
	end) :: RxSignalObject
	self.announcementSignal = RxSignal.new(function()
		return self:observeAnnouncement()
	end) :: RxSignalObject
	self.pendingNaturalSpawnSignal = RxSignal.new(function()
		return self:observePendingNaturalSpawn()
	end) :: RxSignalObject

	self.maid:GiveTask(self._stateChangedSignal)
	self.maid:GiveTask(self._controllerAddedSignal)
	self.maid:GiveTask(self._controllerUpdatedSignal)
	self.maid:GiveTask(self._controllerRemovedSignal)
	self.maid:GiveTask(self._announcementSignal)
	self.maid:GiveTask(self.controllerMap)
	self.maid:GiveTask(self.trackedPlayers)
	self.maid:GiveTask(self.pendingNaturalSpawnValue)
	self.maid:GiveTask(self:observeControllersBrio():Subscribe(function(brio)
		local lifetimeMaid, runtimeId, boss = brio:ToMaidAndValue()
		if typeof(runtimeId) ~= "string" or runtimeId == "" then
			return
		end
		if boss == nil then
			return
		end

		self:bindController(runtimeId, boss, lifetimeMaid)
	end))
end

function BossServiceServer.GetNow(self: BossServiceServer): number
	return os.clock()
end

function BossServiceServer.GetClockTime(self: BossServiceServer): number
	local weatherService = self.weatherService
	if weatherService == nil then
		return 12
	end

	local ok, stateOrError = pcall(function()
		return weatherService:getState()
	end)
	if not ok or typeof(stateOrError) ~= "table" then
		return 12
	end

	return BossServiceUtils.sanitizeNumber((stateOrError :: any).clockTime, 12, 0, 24)
end

function BossServiceServer.IsNightTime(self: BossServiceServer): boolean
	return BossServiceUtils.isNightClockTime(self:getClockTime())
end

function BossServiceServer.GetWorld(self: BossServiceServer): any?
	local worldGenerationService = self.worldGenerationService
	if worldGenerationService == nil then
		return nil
	end

	local ok, worldOrError = pcall(function()
		return worldGenerationService:getWorld()
	end)
	if not ok then
		return nil
	end

	if worldOrError ~= self.world then
		self.world = worldOrError
	end
	return self.world
end

function BossServiceServer.GetSurfaceYAtWorldPosition(self: BossServiceServer, worldPosition: Vector3): number?
	local world = self:getWorld()
	if typeof(world) ~= "table" then
		return nil
	end

	local worldOrigin = if typeof((world :: any).worldOrigin) == "Vector3"
		then (world :: any).worldOrigin
		else Vector3.zero
	local tileSize = if typeof((world :: any).tileSize) == "number" and (world :: any).tileSize > 0
		then (world :: any).tileSize
		else 2
	local biomeGenerator = (world :: any).biomeGenerator
	if typeof(biomeGenerator) ~= "table" or typeof((biomeGenerator :: any).getColumnProfile) ~= "function" then
		return nil
	end

	local tileX = math.floor((worldPosition.Z - worldOrigin.Z) / tileSize)
	local ok, columnOrError = pcall(function()
		return (biomeGenerator :: any):getColumnProfile(tileX)
	end)
	if not ok or typeof(columnOrError) ~= "table" then
		return nil
	end

	local surfaceTileY = (columnOrError :: any).surfaceY
	if typeof(surfaceTileY) ~= "number" or surfaceTileY ~= surfaceTileY then
		return nil
	end

	return worldOrigin.Y + surfaceTileY * tileSize
end

function BossServiceServer.IsPlayerAboveSurface(self: BossServiceServer, playerRaw: any): boolean
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return false
	end

	local rootPart = BossServiceUtils.resolveCharacterRootPart(playerRaw)
	if rootPart == nil then
		return false
	end

	local surfaceY = self:getSurfaceYAtWorldPosition(rootPart.Position)
	if surfaceY == nil then
		return true
	end

	return rootPart.Position.Y >= surfaceY
end

function BossServiceServer.DamagePlayer(
	self: BossServiceServer,
	playerRaw: any,
	damageRaw: any,
	_controllerRaw: any?
): number?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local hpService = self.hpService
	if hpService == nil then
		return nil
	end

	local damage = BossServiceUtils.sanitizeNumber(damageRaw, 0, 0, 10 ^ 6)
	if damage <= 0 then
		return nil
	end

	return hpService:damagePlayer(playerRaw, damage)
end

function BossServiceServer.EnsureOrderedId(self: BossServiceServer, runtimeId: string)
	for _, existingId in self.state.orderedIds do
		if existingId == runtimeId then
			return
		end
	end

	table.insert(self.state.orderedIds, runtimeId)
end

function BossServiceServer.RemoveOrderedId(self: BossServiceServer, runtimeId: string)
	local nextOrderedIds = {}
	for _, existingId in self.state.orderedIds do
		if existingId ~= runtimeId then
			table.insert(nextOrderedIds, existingId)
		end
	end
	self.state.orderedIds = nextOrderedIds
end

function BossServiceServer.CreateSnapshot(self: BossServiceServer, boss: BossObject): BossSnapshot
	local existingSnapshot = self.state.byId[resolveBossId(boss)]
	local snapshot = BossServiceUtils.sanitizeSnapshot({
		id = boss.id,
		bossId = boss.bossId,
		displayName = boss.displayName,
		encounterChannel = boss.encounterChannel,
		state = boss.state,
		phase = boss.phase,
		hp = boss.hp,
		maxHp = boss.maxHp,
		isAlive = boss.isAlive,
		position = boss.position,
		velocity = boss.velocity,
		facing = boss.facing,
		stateTime = boss.stateTime,
		chargeIndex = boss.chargeIndex,
		targetUserId = boss.targetUserId,
		updatedAt = self:getNow(),
		lastReason = boss.lastReason,
		presentation = boss.presentation,
		motion = boss.motion,
	}, existingSnapshot)

	if snapshot == nil then
		error("[BossService] Failed to build snapshot")
	end

	return snapshot
end

function BossServiceServer.UpsertControllerState(self: BossServiceServer, boss: BossObject): BossSnapshot
	local snapshot = self:createSnapshot(boss)
	self.state.byId[snapshot.id] = snapshot
	self:ensureOrderedId(snapshot.id)
	self.state.updatedAt = self:getNow()
	boss.snapshotDirty = false
	boss.lastSnapshotAt = self.state.updatedAt
	self:emitStateChanged()
	return snapshot
end

function BossServiceServer.CreateStateSnapshot(self: BossServiceServer): BossServiceState
	return BossServiceUtils.cloneState(self.state)
end

function BossServiceServer.Broadcast(self: BossServiceServer, methodName: string, ...: any)
	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self.networker:fire(player, methodName, ...)
		end
	end
end

function BossServiceServer.PushState(self: BossServiceServer, playerRaw: any?)
	local snapshot = self:createStateSnapshot()
	if playerRaw ~= nil then
		if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then
			self.networker:fire(playerRaw, BossServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
		end
		return
	end

	self:broadcast(BossServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
end

function BossServiceServer.RequestSync(self: BossServiceServer, player: Player)
	self:pushState(player)
end

function BossServiceServer.ResolveSpawnRequest(
	self: BossServiceServer,
	requestRaw: any
): (BossSpawnRequest?, BossRegistryEntry?, string?)
	local request = BossServiceUtils.sanitizeSpawnRequest(requestRaw, nil)
	if request == nil then
		return nil, nil, "invalid_request"
	end

	local definition = BossServiceUtils.getRegistryEntryById(request.bossId)
	if definition == nil then
		return nil, nil, "unknown_boss"
	end

	request.encounterChannel = if typeof(request.encounterChannel) == "string"
			and request.encounterChannel ~= ""
		then request.encounterChannel
		else definition.encounterChannel
	return request, definition, nil
end

function BossServiceServer.IsEncounterChannelBusy(self: BossServiceServer, encounterChannelRaw: any): boolean
	local encounterChannel = trim(encounterChannelRaw)
	if encounterChannel == "" then
		return false
	end

	return self.controllersByChannel[encounterChannel] ~= nil
end

function BossServiceServer.ResolveControllerConstructor(
	self: BossServiceServer,
	definition: BossRegistryEntry
): ((
	BossServiceServer,
	BossRegistryEntry,
	BossSpawnRequest
) -> BossObject)?
	local constructor = CONTROLLER_CONSTRUCTORS[definition.controllerId]
	if typeof(constructor) == "function" then
		return constructor
	end
	return nil
end

function BossServiceServer.RefreshControllerModelBinding(self: BossServiceServer, boss: BossObject)
	local runtimeId = resolveBossId(boss)
	if runtimeId == "" then
		return
	end

	local currentModel = boss.model
	local boundModel = self.boundModelsById[runtimeId]
	if boundModel == currentModel then
		return
	end

	local modelBindingMaidKey = resolveModelBindingMaidKey(runtimeId)
	local modelBindingMaid = (self.maid :: any)[modelBindingMaidKey]
	if modelBindingMaid == nil then
		modelBindingMaid = Maid.new() :: MaidClass
		(self.maid :: any)[modelBindingMaidKey] = modelBindingMaid
	end
	modelBindingMaid:DoCleaning()
	self.boundModelsById[runtimeId] = currentModel

	if currentModel == nil then
		return
	end

	local modelBindingState = modelBindingMaid :: any
	modelBindingState.destroyingConnection = currentModel.Destroying:Connect(function()
		if boss.model ~= currentModel then
			return
		end
		boss:requestRemoval("ModelDestroyed")
	end)
end

function BossServiceServer.TrackController(self: BossServiceServer, boss: BossObject)
	self.controllersById[boss.id] = boss
	self.controllersByChannel[boss.encounterChannel] = boss
	if self.controllerMap ~= nil then
		self.controllerMap:Set(boss.id, boss)
	end
	self:refreshControllerModelBinding(boss)
end

function BossServiceServer.UntrackController(self: BossServiceServer, boss: BossObject)
	local runtimeId = resolveBossId(boss)
	if runtimeId == "" then
		return
	end

	self.controllersById[runtimeId] = nil
	if self.controllersByChannel[boss.encounterChannel] == boss then
		self.controllersByChannel[boss.encounterChannel] = nil
	end
	if self.controllerMap ~= nil then
		self.controllerMap:Remove(runtimeId)
	end

	local maid = self.maid :: any
	maid[resolveModelBindingMaidKey(runtimeId)] = nil
	self.boundModelsById[runtimeId] = nil
end

function BossServiceServer.SyncControllerSnapshot(
	self: BossServiceServer,
	boss: BossObject,
	forceRaw: any?
): BossSnapshot?
	local force = forceRaw == true
	local now = self:getNow()
	if not force then
		if boss.snapshotDirty ~= true then
			return nil
		end
		if now - boss.lastSnapshotAt < self.statePushInterval then
			return nil
		end
	end

	local snapshot = self:upsertControllerState(boss)
	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_UPDATED, snapshot)
	self:emitControllerUpdated(snapshot, boss)
	return snapshot
end

function BossServiceServer.RemoveController(self: BossServiceServer, runtimeIdRaw: any, reasonRaw: any?)
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return
	end

	local boss = self.controllersById[runtimeId]
	if boss == nil then
		return
	end

	local reason = trim(reasonRaw)
	if reason ~= "" then
		boss.lastReason = reason
	end

	self:untrackController(boss)
	self.state.byId[runtimeId] = nil
	self:removeOrderedId(runtimeId)
	self.state.updatedAt = self:getNow()
	self:emitStateChanged()

	boss:destroy()
	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_REMOVED, runtimeId)
	self:emitControllerRemoved(runtimeId, boss, if reason ~= "" then reason else boss.lastReason)
end

function BossServiceServer.SpawnBoss(self: BossServiceServer, requestRaw: any): (BossObject?, string?)
	local request, definition, requestError = self:resolveSpawnRequest(requestRaw)
	if request == nil or definition == nil then
		return nil, requestError
	end

	if definition.singletonPerChannel and self:isEncounterChannelBusy(request.encounterChannel) then
		return nil, "encounter_channel_busy"
	end

	if definition.nightOnlySummon and request.spawnSource ~= "DebugCommand" and not self:isNightTime() then
		return nil, "night_only"
	end

	local constructor = self:resolveControllerConstructor(definition)
	if constructor == nil then
		return nil, "missing_controller_constructor"
	end

	local constructOk, bossOrError = pcall(function()
		return constructor(self, definition, request)
	end)
	if not constructOk then
		return nil, "controller_construction_error"
	end

	local boss = bossOrError
	if boss == nil then
		return nil, "controller_construction_failed"
	end

	local spawnOk, spawnError = pcall(function()
		boss:spawn()
	end)
	if not spawnOk then
		destroyBossSafely(boss)
		return nil, "controller_spawn_failed"
	end

	self:trackController(boss)
	self:refreshControllerModelBinding(boss)

	local afterSpawn = (boss :: any).afterSpawn
	if typeof(afterSpawn) == "function" then
		local afterSpawnOk, afterSpawnError = pcall(function()
			afterSpawn(boss)
		end)
		if not afterSpawnOk then
			self:untrackController(boss)
			destroyBossSafely(boss)
			return nil, "controller_after_spawn_failed"
		end
	end

	local snapshot = self:upsertControllerState(boss)
	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_ADDED, snapshot)
	self:emitControllerAdded(snapshot, boss)
	return boss, nil
end

function BossServiceServer.ResolveEncounterTarget(self: BossServiceServer, boss: BossObject): Player?
	local currentTarget = boss.targetPlayer
	if currentTarget ~= nil and BossServiceUtils.isPlayerAlive(currentTarget) then
		return currentTarget
	end

	local bossPosition = boss.position
	local nearestPlayer = nil :: Player?
	local nearestDistance = math.huge
	for _, player in Players:GetPlayers() do
		if not BossServiceUtils.isPlayerAlive(player) then
			continue
		end
		local rootPart = BossServiceUtils.resolveCharacterRootPart(player)
		if rootPart == nil then
			continue
		end

		local distance = (BossServiceUtils.projectPositionToPlaneX(rootPart.Position, boss.planeX) - bossPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearestPlayer = player
		end
	end

	return nearestPlayer
end

function BossServiceServer.ResolveControllerFromInstance(self: BossServiceServer, instanceRaw: any): BossObject?
	local runtimeId = BossServiceUtils.resolveRuntimeIdFromInstance(instanceRaw)
	if runtimeId == nil then
		return nil
	end

	return self.controllersById[runtimeId]
end

function BossServiceServer.DamageBossFromHitPart(
	self: BossServiceServer,
	hitPartRaw: any,
	damageRaw: any,
	sourceRaw: any?,
	damageContextRaw: any?
): number
	local boss = self:resolveControllerFromInstance(hitPartRaw)
	if boss == nil then
		return 0
	end

	local appliedDamage = boss:takeDamage(damageRaw, sourceRaw, damageContextRaw)
	if appliedDamage > 0 then
		self:syncControllerSnapshot(boss, true)
	end
	return appliedDamage
end

function BossServiceServer.DamageBossesInBox(
	self: BossServiceServer,
	queryCFrameRaw: any,
	querySizeRaw: any,
	damageRaw: any,
	sourceRaw: any?,
	damageContextRaw: any?
): number
	if typeof(queryCFrameRaw) ~= "CFrame" or typeof(querySizeRaw) ~= "Vector3" then
		return 0
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.MaxParts = DEFAULT_BOX_QUERY_MAX_PARTS

	local ok, partsOrError = pcall(function()
		return Workspace:GetPartBoundsInBox(queryCFrameRaw, querySizeRaw, overlapParams)
	end)
	if not ok or typeof(partsOrError) ~= "table" then
		return 0
	end

	local totalAppliedDamage = 0
	local seenIds = {}
	for _, part in partsOrError do
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
			continue
		end

		local runtimeId = BossServiceUtils.resolveRuntimeIdFromInstance(part)
		if runtimeId == nil or seenIds[runtimeId] == true then
			continue
		end
		seenIds[runtimeId] = true

		local boss = self.controllersById[runtimeId]
		if boss == nil then
			continue
		end

		local appliedDamage = boss:takeDamage(damageRaw, sourceRaw, damageContextRaw)
		if appliedDamage > 0 then
			totalAppliedDamage += appliedDamage
			self:syncControllerSnapshot(boss, true)
		end
	end

	return totalAppliedDamage
end

function BossServiceServer.CreateUniqueDebugEncounterChannel(
	self: BossServiceServer,
	bossId: BossId,
	player: Player,
	indexRaw: any
): string
	local index = math.max(1, math.floor(BossServiceUtils.sanitizeNumber(indexRaw, 1, 1, 10 ^ 6)))
	return ("debug.%s.%d.%d.%d"):format(
		BossServiceUtils.normalizeToken(bossId),
		player.UserId,
		math.floor(self:getNow() * 1000 + 0.5),
		index
	)
end

function BossServiceServer.BroadcastAnnouncement(self: BossServiceServer, textRaw: any, bossIdRaw: any?)
	local text = trim(textRaw)
	if text == "" then
		return
	end

	local payload = {
		text = text,
		bossId = bossIdRaw,
		updatedAt = self:getNow(),
	}
	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_ANNOUNCEMENT, payload)
	if self._announcementSignal ~= nil then
		self._announcementSignal:Fire(payload)
	end
end

function BossServiceServer.ResolveNaturalSpawnTargetPlayer(self: BossServiceServer): Player?
	local alivePlayers = {}
	local trackedPlayers = if self.trackedPlayers ~= nil then self.trackedPlayers:GetList() else Players:GetPlayers()
	for _, player in trackedPlayers do
		if BossServiceUtils.isPlayerAlive(player) then
			table.insert(alivePlayers, player)
		end
	end

	if #alivePlayers <= 0 then
		return nil
	end

	return alivePlayers[self.random:NextInteger(1, #alivePlayers)]
end

function BossServiceServer.ScheduleNaturalSpawn(self: BossServiceServer, definition: BossRegistryEntry)
	if self.pendingNaturalSpawn ~= nil then
		return
	end

	local targetPlayer = self:resolveNaturalSpawnTargetPlayer()
	if targetPlayer == nil then
		return
	end

	local defaultConfig = self.defaultConfigByBossId[definition.id]
	if typeof(defaultConfig) ~= "table" or defaultConfig.naturalSpawnEnabled ~= true then
		return
	end

	local spawnChance = BossServiceUtils.sanitizeNumber(defaultConfig.naturalSpawnChancePerNight, 0, 0, 1)
	if spawnChance <= 0 then
		return
	end
	if self.random:NextNumber() > spawnChance then
		return
	end

	local announcement = if definition.naturalSpawnAnnouncement ~= nil
		then definition.naturalSpawnAnnouncement
		else ("A %s is approaching..."):format(definition.displayName)
	self.pendingNaturalSpawn = {
		bossId = definition.id,
		targetPlayer = targetPlayer,
		encounterChannel = definition.encounterChannel,
		delayRemaining = BossServiceUtils.sanitizeNumber(defaultConfig.naturalSpawnAnnouncementDelay, 2, 0, 30),
		announcement = announcement,
	}
	self:setPendingNaturalSpawn(self.pendingNaturalSpawn)
	self:broadcastAnnouncement(announcement, definition.id)
end

function BossServiceServer.StepNaturalSpawns(
	self: BossServiceServer,
	dt: number,
	previousClockTime: number,
	currentClockTime: number
)
	if BossServiceUtils.didClockPass(previousClockTime, currentClockTime, BossServiceUtils.NIGHT_START_CLOCK_TIME) then
		for _, definition in BossServiceUtils.getRegistryEntries() do
			if definition.supportsNaturalSpawn and not self:isEncounterChannelBusy(definition.encounterChannel) then
				self:scheduleNaturalSpawn(definition)
			end
		end
	end

	local pending = self.pendingNaturalSpawn
	if pending == nil then
		return
	end

	if not self:isNightTime() then
		self:setPendingNaturalSpawn(nil)
		return
	end

	if not BossServiceUtils.isPlayerAlive(pending.targetPlayer) then
		self:setPendingNaturalSpawn(nil)
		return
	end

	pending.delayRemaining -= dt
	if pending.delayRemaining > 0 then
		return
	end

	if not self:isPlayerAboveSurface(pending.targetPlayer) then
		return
	end

	local controller, reason = self:spawnBoss({
		bossId = pending.bossId,
		targetPlayer = pending.targetPlayer,
		spawnSource = "NaturalSpawn",
		encounterChannel = pending.encounterChannel,
	})

	if controller ~= nil or reason ~= "encounter_channel_busy" then
		self:setPendingNaturalSpawn(nil)
	end
end

function BossServiceServer.SummonBossForPlayer(
	self: BossServiceServer,
	playerRaw: any,
	bossTokenRaw: any,
	optionsRaw: any?
): (BossObject?, string?)
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil, "invalid_player"
	end

	local definition = BossServiceUtils.getRegistryEntryByToken(bossTokenRaw)
	if definition == nil then
		return nil, "unknown_boss"
	end

	if definition.nightOnlySummon and not self:isNightTime() then
		return nil, "night_only"
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	return self:spawnBoss({
		bossId = definition.id,
		targetPlayer = playerRaw,
		spawnSource = "ManualSummon",
		simulationSpeed = (options :: any).simulationSpeed,
		aggressiveness = (options :: any).aggressiveness,
		expertBehaviorEnabled = (options :: any).expertBehaviorEnabled,
	})
end

function BossServiceServer.RequestManualSummon(
	self: BossServiceServer,
	player: Player,
	bossTokenRaw: any,
	optionsRaw: any?
)
	if self.allowClientManualSummon ~= true then
		return
	end

	self:summonBossForPlayer(player, bossTokenRaw, optionsRaw)
end

function BossServiceServer.GetState(self: BossServiceServer): BossServiceState
	return self:createStateSnapshot()
end

function BossServiceServer.ObserveState(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "state", function()
		return Rx.fromSignal(self._stateChangedSignal):Pipe({
			Rx.startWith({ self:getState() }),
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObserveControllerAdded(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "controllerAdded", function()
		return Rx.fromSignal(self._controllerAddedSignal):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObserveControllerUpdated(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "controllerUpdated", function()
		return Rx.fromSignal(self._controllerUpdatedSignal):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObserveControllerRemoved(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "controllerRemoved", function()
		return Rx.fromSignal(self._controllerRemovedSignal):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObserveControllersBrio(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "controllersBrio", function()
		return self.controllerMap:ObservePairsBrio():Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObserveControllerAtId(self: BossServiceServer, runtimeIdRaw: any): ObservableObject
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return Rx.of(nil) :: ObservableObject
	end

	return getOrCreateObservable(self, ("controllerAtId_%s"):format(runtimeId), function()
		return self.controllerMap:ObserveAtKey(runtimeId):Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObserveTrackedPlayersBrio(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "trackedPlayersBrio", function()
		return self.trackedPlayers:ObserveItemsBrio():Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObserveAnnouncement(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "announcement", function()
		return Rx.fromSignal(self._announcementSignal):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function BossServiceServer.ObservePendingNaturalSpawn(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "pendingNaturalSpawn", function()
		return self.pendingNaturalSpawnValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function BossServiceServer.GetStateChangedSignal(self: BossServiceServer): RxSignalObject
	return self.stateChangedSignal
end

function BossServiceServer.GetControllerAddedSignal(self: BossServiceServer): RxSignalObject
	return self.controllerAddedSignal
end

function BossServiceServer.GetControllerUpdatedSignal(self: BossServiceServer): RxSignalObject
	return self.controllerUpdatedSignal
end

function BossServiceServer.GetControllerRemovedSignal(self: BossServiceServer): RxSignalObject
	return self.controllerRemovedSignal
end

function BossServiceServer.GetControllersSignal(self: BossServiceServer): RxSignalObject
	return self.controllersSignal
end

function BossServiceServer.GetAnnouncementSignal(self: BossServiceServer): RxSignalObject
	return self.announcementSignal
end

function BossServiceServer.GetPendingNaturalSpawnSignal(self: BossServiceServer): RxSignalObject
	return self.pendingNaturalSpawnSignal
end

function BossServiceServer.WaitForControllerPromise(
	self: BossServiceServer,
	runtimeIdRaw: any,
	cancelTokenRaw: any?
): PromiseObject
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return Promise.resolved(nil) :: PromiseObject
	end

	local existing = self.controllersById[runtimeId]
	if existing ~= nil then
		return Promise.resolved(existing) :: PromiseObject
	end

	return Rx.toPromise(
		self:observeControllerAtId(runtimeId):Pipe({
			Rx.where(function(boss)
				return boss ~= nil
			end),
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function BossServiceServer.WaitForControllerRemovalPromise(
	self: BossServiceServer,
	runtimeIdRaw: any,
	cancelTokenRaw: any?
): PromiseObject
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return Promise.rejected("invalid_runtime_id") :: PromiseObject
	end
	if self.controllersById[runtimeId] == nil then
		return Promise.resolved({
			id = runtimeId,
			bossId = nil,
			reason = "already_removed",
			updatedAt = self:getNow(),
		}) :: PromiseObject
	end

	return Rx.toPromise(
		self:observeControllerRemoved():Pipe({
			Rx.where(function(payload)
				return typeof(payload) == "table" and (payload :: any).id == runtimeId
			end),
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function BossServiceServer.SpawnBossPromise(
	self: BossServiceServer,
	requestRaw: any,
	cancelTokenRaw: any?
): PromiseObject
	local cancelToken = resolveCancelToken(cancelTokenRaw)
	local promise = Promise.spawn(function(resolve, reject)
		if cancelToken ~= nil and cancelToken:IsCancelled() then
			reject("cancelled")
			return
		end

		local boss, reason = self:spawnBoss(requestRaw)
		if cancelToken ~= nil and cancelToken:IsCancelled() then
			if boss ~= nil then
				self:removeController(boss.id, "spawn_cancelled")
			end
			reject("cancelled")
			return
		end

		resolve(boss, reason)
	end) :: PromiseObject

	PromiseMaidUtils.whilePromise(promise, function(maid: MaidClass)
		if cancelToken ~= nil then
			maid:GiveTask(cancelToken.Cancelled:Connect(function()
				promise:Destroy()
			end))
		end
	end)

	return promise
end

function BossServiceServer.SummonBossForPlayerPromise(
	self: BossServiceServer,
	playerRaw: any,
	bossTokenRaw: any,
	optionsRaw: any?,
	cancelTokenRaw: any?
): PromiseObject
	local cancelToken = resolveCancelToken(cancelTokenRaw)
	local promise = Promise.spawn(function(resolve, reject)
		if cancelToken ~= nil and cancelToken:IsCancelled() then
			reject("cancelled")
			return
		end

		resolve(self:summonBossForPlayer(playerRaw, bossTokenRaw, optionsRaw))
	end) :: PromiseObject

	PromiseMaidUtils.whilePromise(promise, function(maid: MaidClass)
		if cancelToken ~= nil then
			maid:GiveTask(cancelToken.Cancelled:Connect(function()
				promise:Destroy()
			end))
		end
	end)

	return promise
end

function BossServiceServer.OnHeartbeat(self: BossServiceServer, dtRaw: any)
	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end

	local previousClockTime = self.previousClockTime
	local currentClockTime = self:getClockTime()
	self.naturalSpawnAccumulator += dt
	if self.naturalSpawnAccumulator >= self.naturalSpawnCheckInterval then
		self.naturalSpawnAccumulator = 0
		self:stepNaturalSpawns(dt, previousClockTime, currentClockTime)
	end
	self.previousClockTime = currentClockTime

	local orderedIds = Sift.Dictionary.copy(self.state.orderedIds)
	for _, runtimeId in orderedIds do
		local boss = self.controllersById[runtimeId]
		if boss == nil then
			continue
		end

		if boss.removeRequested == true then
			self:removeController(runtimeId, boss.removeReason)
			continue
		end

		local simulationSpeed = 1
		local getSimulationSpeed = (boss :: any).getSimulationSpeed
		if typeof(getSimulationSpeed) == "function" then
			simulationSpeed = BossServiceUtils.sanitizeNumber(getSimulationSpeed(boss), 1, 0.05, 5)
		end

		boss:step(dt * simulationSpeed)
		self:refreshControllerModelBinding(boss)

		if boss.removeRequested == true then
			self:removeController(runtimeId, boss.removeReason)
			continue
		end

		self:syncControllerSnapshot(boss, false)
	end
end

function BossServiceServer.TrackPlayer(self: BossServiceServer, player: Player)
	if self.trackedPlayers ~= nil then
		self.trackedPlayers:Add(player)
	end
	self:pushState(player)
end

function BossServiceServer.UntrackPlayer(self: BossServiceServer, player: Player)
	if self.trackedPlayers ~= nil then
		self.trackedPlayers:Remove(player)
	end
end

function BossServiceServer.Init(self: BossServiceServer)
	self.maid = Maid.new() :: MaidClass
	self.networker = Networker.server.new("BossService", self, {
		self.RequestSync,
		self.RequestManualSummon,
	})
	self.maid:GiveTask(function()
		if self.networker ~= nil then
			self.networker:destroy()
			self.networker = nil
		end
	end)
	self.hpService = HpServiceServer :: HpServiceServerObject
	self.weatherService = WeatherServiceServer :: WeatherServiceServerObject
	self.worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.controllersById = {}
	self.controllersByChannel = {}
	self.boundModelsById = {}
	self.state = BossServiceUtils.createDefaultState()
	self.statePushInterval = DEFAULT_STATE_PUSH_INTERVAL
	self.naturalSpawnCheckInterval = DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL
	self.naturalSpawnAccumulator = 0
	self.random = Random.new()
	self.world = nil
	self.pendingNaturalSpawn = nil
	self.allowClientManualSummon = false
	self.defaultConfigByBossId = {
		EyeOfCthulhu = EyeOfCthulhuConfig.resolve(resolveEyeConfigSource()),
	}
	self.previousClockTime = self:getClockTime()
	self.binders = NevermoreSupport.getService(ServerBinderSupport)
	self:initReactiveState()

	self.maid:GiveTask(Rx.fromSignal(Players.PlayerAdded)
		:Pipe({
			Rx.startFrom(function()
				return Players:GetPlayers()
			end),
		})
		:Subscribe(function(player: Player)
			if PlayerServiceServer:isGameplayActiveForPlayer(player) then
				self:trackPlayer(player)
			end
		end))
	self.maid:GiveTask(Rx.fromSignal(Players.PlayerRemoving):Subscribe(function(player: Player)
		self:untrackPlayer(player)
	end))
	self.maid:GiveTask(Rx.fromSignal(RunService.Heartbeat):Subscribe(function(dt: number)
		self:onHeartbeat(dt)
	end))
end

function BossServiceServer.Destroy(self: BossServiceServer)
	local runtimeIds = Sift.Dictionary.copy(self.state.orderedIds)
	for _, runtimeId in runtimeIds do
		self:removeController(runtimeId, "service_destroy")
	end

	self.maid:Destroy()
end

BossServiceServer.getNow = BossServiceServer.GetNow
BossServiceServer.getClockTime = BossServiceServer.GetClockTime
BossServiceServer.isNightTime = BossServiceServer.IsNightTime
BossServiceServer.getWorld = BossServiceServer.GetWorld
BossServiceServer.getSurfaceYAtWorldPosition = BossServiceServer.GetSurfaceYAtWorldPosition
BossServiceServer.isPlayerAboveSurface = BossServiceServer.IsPlayerAboveSurface
BossServiceServer.damagePlayer = BossServiceServer.DamagePlayer
BossServiceServer.setPendingNaturalSpawn = BossServiceServer.SetPendingNaturalSpawn
BossServiceServer.emitStateChanged = BossServiceServer.EmitStateChanged
BossServiceServer.emitControllerAdded = BossServiceServer.EmitControllerAdded
BossServiceServer.emitControllerUpdated = BossServiceServer.EmitControllerUpdated
BossServiceServer.emitControllerRemoved = BossServiceServer.EmitControllerRemoved
BossServiceServer.bindController = BossServiceServer.BindController
BossServiceServer.initReactiveState = BossServiceServer.InitReactiveState
BossServiceServer.ensureOrderedId = BossServiceServer.EnsureOrderedId
BossServiceServer.removeOrderedId = BossServiceServer.RemoveOrderedId
BossServiceServer.createSnapshot = BossServiceServer.CreateSnapshot
BossServiceServer.upsertControllerState = BossServiceServer.UpsertControllerState
BossServiceServer.createStateSnapshot = BossServiceServer.CreateStateSnapshot
BossServiceServer.broadcast = BossServiceServer.Broadcast
BossServiceServer.pushState = BossServiceServer.PushState
BossServiceServer.requestSync = BossServiceServer.RequestSync
BossServiceServer.resolveSpawnRequest = BossServiceServer.ResolveSpawnRequest
BossServiceServer.isEncounterChannelBusy = BossServiceServer.IsEncounterChannelBusy
BossServiceServer.resolveControllerConstructor = BossServiceServer.ResolveControllerConstructor
BossServiceServer.refreshControllerModelBinding = BossServiceServer.RefreshControllerModelBinding
BossServiceServer.trackController = BossServiceServer.TrackController
BossServiceServer.untrackController = BossServiceServer.UntrackController
BossServiceServer.syncControllerSnapshot = BossServiceServer.SyncControllerSnapshot
BossServiceServer.removeController = BossServiceServer.RemoveController
BossServiceServer.spawnBoss = BossServiceServer.SpawnBoss
BossServiceServer.resolveEncounterTarget = BossServiceServer.ResolveEncounterTarget
BossServiceServer.resolveControllerFromInstance = BossServiceServer.ResolveControllerFromInstance
BossServiceServer.damageBossFromHitPart = BossServiceServer.DamageBossFromHitPart
BossServiceServer.damageBossesInBox = BossServiceServer.DamageBossesInBox
BossServiceServer.createUniqueDebugEncounterChannel = BossServiceServer.CreateUniqueDebugEncounterChannel
BossServiceServer.broadcastAnnouncement = BossServiceServer.BroadcastAnnouncement
BossServiceServer.resolveNaturalSpawnTargetPlayer = BossServiceServer.ResolveNaturalSpawnTargetPlayer
BossServiceServer.scheduleNaturalSpawn = BossServiceServer.ScheduleNaturalSpawn
BossServiceServer.stepNaturalSpawns = BossServiceServer.StepNaturalSpawns
BossServiceServer.summonBossForPlayer = BossServiceServer.SummonBossForPlayer
BossServiceServer.requestManualSummon = BossServiceServer.RequestManualSummon
BossServiceServer.getState = BossServiceServer.GetState
BossServiceServer.observeState = BossServiceServer.ObserveState
BossServiceServer.observeControllerAdded = BossServiceServer.ObserveControllerAdded
BossServiceServer.observeControllerUpdated = BossServiceServer.ObserveControllerUpdated
BossServiceServer.observeControllerRemoved = BossServiceServer.ObserveControllerRemoved
BossServiceServer.observeControllersBrio = BossServiceServer.ObserveControllersBrio
BossServiceServer.observeControllerAtId = BossServiceServer.ObserveControllerAtId
BossServiceServer.observeTrackedPlayersBrio = BossServiceServer.ObserveTrackedPlayersBrio
BossServiceServer.observeAnnouncement = BossServiceServer.ObserveAnnouncement
BossServiceServer.observePendingNaturalSpawn = BossServiceServer.ObservePendingNaturalSpawn
BossServiceServer.getStateChangedSignal = BossServiceServer.GetStateChangedSignal
BossServiceServer.getControllerAddedSignal = BossServiceServer.GetControllerAddedSignal
BossServiceServer.getControllerUpdatedSignal = BossServiceServer.GetControllerUpdatedSignal
BossServiceServer.getControllerRemovedSignal = BossServiceServer.GetControllerRemovedSignal
BossServiceServer.getControllersSignal = BossServiceServer.GetControllersSignal
BossServiceServer.getAnnouncementSignal = BossServiceServer.GetAnnouncementSignal
BossServiceServer.getPendingNaturalSpawnSignal = BossServiceServer.GetPendingNaturalSpawnSignal
BossServiceServer.waitForControllerPromise = BossServiceServer.WaitForControllerPromise
BossServiceServer.waitForControllerRemovalPromise = BossServiceServer.WaitForControllerRemovalPromise
BossServiceServer.spawnBossPromise = BossServiceServer.SpawnBossPromise
BossServiceServer.summonBossForPlayerPromise = BossServiceServer.SummonBossForPlayerPromise
BossServiceServer.onHeartbeat = BossServiceServer.OnHeartbeat
BossServiceServer.trackPlayer = BossServiceServer.TrackPlayer
BossServiceServer.untrackPlayer = BossServiceServer.UntrackPlayer
BossServiceServer.init = BossServiceServer.Init
BossServiceServer.destroy = BossServiceServer.Destroy

type BossServiceServer = typeof(BossServiceServer) & {
	maid: MaidClass,
	networker: Networker.Server,
	hpService: HpServiceServerObject,
	weatherService: WeatherServiceServerObject,
	worldGenerationService: WorldGenerationServiceServerObject,
	controllersById: { [string]: BossObject },
	controllersByChannel: { [string]: BossObject },
	controllerMap: ObservableMapClass,
	trackedPlayers: ObservableSetClass,
	boundModelsById: { [string]: Model? },
	state: BossServiceState,
	statePushInterval: number,
	naturalSpawnCheckInterval: number,
	naturalSpawnAccumulator: number,
	random: Random,
	world: any?,
	pendingNaturalSpawn: PendingNaturalSpawn?,
	pendingNaturalSpawnValue: ValueObjectClass<PendingNaturalSpawn?>,
	allowClientManualSummon: boolean,
	defaultConfigByBossId: { [BossId]: { [string]: any } },
	previousClockTime: number,
	observableCache: { [string]: ObservableObject },
	rxSignalCache: { [string]: RxSignalObject },
	_stateChangedSignal: SignalObject,
	_controllerAddedSignal: SignalObject,
	_controllerUpdatedSignal: SignalObject,
	_controllerRemovedSignal: SignalObject,
	_announcementSignal: SignalObject,
	stateChangedSignal: RxSignalObject,
	controllerAddedSignal: RxSignalObject,
	controllerUpdatedSignal: RxSignalObject,
	controllerRemovedSignal: RxSignalObject,
	controllersSignal: RxSignalObject,
	announcementSignal: RxSignalObject,
	pendingNaturalSpawnSignal: RxSignalObject,
}

return BossServiceServer :: BossServiceServer
