local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local Sift: any = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BossServiceUtils = require("BossServiceUtils")
local CancelToken = require("CancelToken")
local Configs = require("CoreConfigs")
local EyeOfCthulhuController = require("EyeOfCthulhuBoss")
local bossClasses = script.Parent:WaitForChild("Classes"):WaitForChild("Boss")
local EyeOfCthulhuConfig = require(bossClasses:WaitForChild("EyeOfCthulhuBoss"):WaitForChild("EyeOfCthulhuConfig"))
local Maid = require("Maid")
local ObservableMap: any = require("ObservableMap")
local ObservableSet: any = require("ObservableSet")
local Promise: any = require("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end
local HpServiceServer = require("HpServiceServer")
local PacketPayload = require("PacketPayload")
local PromiseMaidUtils = require("PromiseMaidUtils")
local QueenBeeConfig = require("QueenBeeConfigs")
local QueenBeeController = require("QueenBeeBoss")
local Rx: any = require("Rx")
local RxSignal: any = require("RxSignal")
local Signal = require("Signal")
local ValueObject: any = require("ValueObject")
local BossServicePackets = require("NetPacketsShared").BossService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = BossServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BossService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = BossServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BossService`)
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
	bindPacket(self, "requestManualSummon")
	bindPacket(self, "requestSync")
end

local BinderSupportServer = require("BinderSupportServer")
local PlayerServiceServer = require("PlayerServiceServer")
local WeatherServiceServer = require("WeatherServiceServer")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")

type BossId = BossServiceUtils.BossId
type BossSnapshot = BossServiceUtils.BossSnapshot
type BossServiceState = BossServiceUtils.BossServiceState
type BossRegistryEntry = BossServiceUtils.BossRegistryEntry
type BossSpawnRequest = BossServiceUtils.BossSpawnRequest

type BossObject = any
type MaidClass = any

type SignalObject = Signal.Signal<...any>

type ObservableObject = any

type RxSignalObject = any

type PromiseObject = any

type ObservableMapClass = any

type ObservableSetClass = any

type ValueObjectClass<T> = any

type HpServiceServerObject = {
	DamagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
}

type WeatherServiceServerObject = {
	GetState: (self: WeatherServiceServerObject) -> { clockTime: number },
}

type WorldGenerationServiceServerObject = {
	GetWorld: (self: WorldGenerationServiceServerObject) -> any,
}

type PendingNaturalSpawn = {
	bossId: BossId,
	targetPlayer: Player,
	encounterChannel: string,
	delayRemaining: number,
	announcement: string,
}

local BossServiceServer = {}
BossServiceServer.ServiceName = "BossServiceServer"

local CONTROLLER_CONSTRUCTORS = {
	EyeOfCthulhu = function(
		service: BossServiceServer,
		definition: BossRegistryEntry,
		spawnRequest: BossSpawnRequest
	): BossObject
		return EyeOfCthulhuController.New(service, definition, spawnRequest)
	end,
	QueenBee = function(
		service: BossServiceServer,
		definition: BossRegistryEntry,
		spawnRequest: BossSpawnRequest
	): BossObject
		return QueenBeeController.CreateBossController(service, definition, spawnRequest)
	end,
}

local DEFAULT_STATE_PUSH_INTERVAL = BossServiceUtils.DEFAULT_STATE_PUSH_INTERVAL
local DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL = BossServiceUtils.DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL
local DEFAULT_BOX_QUERY_MAX_PARTS = 96

local function getBossSettingsSource(): { [string]: any }
	if typeof(Configs) ~= "table" then
		return {}
	end

	local bossSettings = (Configs :: any).bossSettings
	if typeof(bossSettings) ~= "table" then
		return {}
	end

	return bossSettings :: { [string]: any }
end

local function getEyeConfigSource(): { [string]: any }?
	local bossSettings = getBossSettingsSource()
	local eyeConfig = (bossSettings :: any).eyeOfCthulhu
	if typeof(eyeConfig) == "table" then
		return eyeConfig
	end
	return nil
end

local function getQueenBeeConfigSource(): { [string]: any }?
	local bossSettings = getBossSettingsSource()
	local queenBeeConfig = (bossSettings :: any).queenBee
	if typeof(queenBeeConfig) == "table" then
		return queenBeeConfig
	end
	return nil
end

local function trim(valueRaw: any): string
	return BossServiceUtils.Trim(valueRaw)
end

local function getModelBindingMaidKey(runtimeId: string): string
	return ("modelBinding_%s"):format(runtimeId)
end

local function getBossId(boss: BossObject): string
	if typeof(boss) == "table" and typeof(boss.id) == "string" then
		return boss.id
	end
	return ""
end

local function destroyBossSafely(bossRaw: any)
	if typeof(bossRaw) ~= "table" then
		return
	end

	local destroy = (bossRaw :: any).Destroy
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

local function getCancelToken(cancelTokenRaw: any): any?
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
		self._stateChangedSignal:Fire(self:CreateStateSnapshot())
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
		updatedAt = self:GetNow(),
	}, boss)
end

function BossServiceServer.BindController(self: BossServiceServer, runtimeId: string, boss: BossObject, maid: MaidClass)
	self:RefreshControllerModelBinding(boss)

	local function syncNow()
		if self.controllersById[runtimeId] ~= boss then
			return
		end

		self:RefreshControllerModelBinding(boss)
		self:SyncControllerSnapshot(boss, true)
	end

	maid:GiveTask(boss:ObserveStateChanged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:ObserveTargetChanged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:ObserveDamaged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:ObserveDied():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:ObserveModelChanged():Subscribe(function()
		syncNow()
	end))
	maid:GiveTask(boss:ObserveRemoved():Subscribe(function(reason)
		if self.controllersById[runtimeId] ~= boss then
			return
		end

		self:RemoveController(runtimeId, reason)
	end))
	maid:GiveTask(boss:ObserveDestroying():Subscribe(function()
		if self.controllersById[runtimeId] ~= boss then
			return
		end

		self:RemoveController(runtimeId, "controller_destroyed")
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
		return self:ObserveState()
	end) :: RxSignalObject
	self.controllerAddedSignal = RxSignal.new(function()
		return self:ObserveControllerAdded()
	end) :: RxSignalObject
	self.controllerUpdatedSignal = RxSignal.new(function()
		return self:ObserveControllerUpdated()
	end) :: RxSignalObject
	self.controllerRemovedSignal = RxSignal.new(function()
		return self:ObserveControllerRemoved()
	end) :: RxSignalObject
	self.controllersSignal = RxSignal.new(function()
		return self:ObserveControllersBrio()
	end) :: RxSignalObject
	self.announcementSignal = RxSignal.new(function()
		return self:ObserveAnnouncement()
	end) :: RxSignalObject
	self.pendingNaturalSpawnSignal = RxSignal.new(function()
		return self:ObservePendingNaturalSpawn()
	end) :: RxSignalObject

	self.maid:GiveTask(self._stateChangedSignal)
	self.maid:GiveTask(self._controllerAddedSignal)
	self.maid:GiveTask(self._controllerUpdatedSignal)
	self.maid:GiveTask(self._controllerRemovedSignal)
	self.maid:GiveTask(self._announcementSignal)
	self.maid:GiveTask(self.controllerMap)
	self.maid:GiveTask(self.trackedPlayers)
	self.maid:GiveTask(self.pendingNaturalSpawnValue)
	self.maid:GiveTask(self:ObserveControllersBrio():Subscribe(function(brio)
		local lifetimeMaid, runtimeId, boss = brio:ToMaidAndValue()
		if typeof(runtimeId) ~= "string" or runtimeId == "" then
			return
		end
		if boss == nil then
			return
		end

		self:BindController(runtimeId, boss, lifetimeMaid)
	end))
end

function BossServiceServer.GetNow(_self: BossServiceServer): number
	return os.clock()
end

function BossServiceServer.GetClockTime(self: BossServiceServer): number
	local weatherService = self.weatherService
	if weatherService == nil then
		return 12
	end

	local ok, stateOrError = pcall(function()
		return weatherService:GetState()
	end)
	if not ok or typeof(stateOrError) ~= "table" then
		return 12
	end

	return BossServiceUtils.CoerceNumber((stateOrError :: any).clockTime, 12, 0, 24)
end

function BossServiceServer.IsNightTime(self: BossServiceServer): boolean
	return BossServiceUtils.IsNightClockTime(self:GetClockTime())
end

function BossServiceServer.GetWorld(self: BossServiceServer): any?
	local worldGenerationService = self.worldGenerationService
	if worldGenerationService == nil then
		return nil
	end

	local ok, worldOrError = pcall(function()
		return worldGenerationService:GetWorld()
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
	local world = self:GetWorld()
	if typeof(world) ~= "table" then
		return nil
	end

	local worldOrigin = if typeof((world :: any).worldOrigin) == "Vector3"
		then (world :: any).worldOrigin
		else Vector3.zero
	local tileSize = if typeof((world :: any).tileSize) == "number" and (world :: any).tileSize > 0
		then (world :: any).tileSize
		else 4
	local biomeGenerator = (world :: any).biomeGenerator
	if typeof(biomeGenerator) ~= "table" or typeof((biomeGenerator :: any).GetColumnProfile) ~= "function" then
		return nil
	end

	local tileX = math.floor((worldPosition.Z - worldOrigin.Z) / tileSize)
	local ok, columnOrError = pcall(function()
		return (biomeGenerator :: any):GetColumnProfile(tileX)
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

	local rootPart = BossServiceUtils.GetCharacterRootPart(playerRaw)
	if rootPart == nil then
		return false
	end

	local surfaceY = self:GetSurfaceYAtWorldPosition(rootPart.Position)
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

	local damage = BossServiceUtils.CoerceNumber(damageRaw, 0, 0, 10 ^ 6)
	if damage <= 0 then
		return nil
	end

	return hpService:DamagePlayer(playerRaw, damage)
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
	local existingSnapshot = self.state.byId[getBossId(boss)]
	local snapshot = BossServiceUtils.CoerceSnapshot({
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
		updatedAt = self:GetNow(),
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
	local snapshot = self:CreateSnapshot(boss)
	self.state.byId[snapshot.id] = snapshot
	self:EnsureOrderedId(snapshot.id)
	self.state.updatedAt = self:GetNow()
	boss.snapshotDirty = false
	boss.lastSnapshotAt = self.state.updatedAt
	self:EmitStateChanged()
	return snapshot
end

function BossServiceServer.CreateStateSnapshot(self: BossServiceServer): BossServiceState
	return BossServiceUtils.CloneState(self.state)
end

function BossServiceServer.Broadcast(_self: BossServiceServer, methodName: string, ...: any)
	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
			sendPacket(player, methodName, ...)
		end
	end
end

function BossServiceServer.PushState(self: BossServiceServer, playerRaw: any?)
	local snapshot = self:CreateStateSnapshot()
	if playerRaw ~= nil then
		if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then
			sendPacket(playerRaw, BossServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
		end
		return
	end

	self:Broadcast(BossServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
end

function BossServiceServer.RequestSync(self: BossServiceServer, player: Player)
	self:PushState(player)
end

function BossServiceServer.GetSpawnRequest(
	_self: BossServiceServer,
	requestRaw: any
): (BossSpawnRequest?, BossRegistryEntry?, string?)
	local request = BossServiceUtils.CoerceSpawnRequest(requestRaw, nil)
	if request == nil then
		return nil, nil, "invalid_request"
	end

	local definition = BossServiceUtils.GetRegistryEntryById(request.bossId)
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

function BossServiceServer.GetControllerConstructor(
	_self: BossServiceServer,
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
	local runtimeId = getBossId(boss)
	if runtimeId == "" then
		return
	end

	local currentModel = boss.model
	local boundModel = self.boundModelsById[runtimeId]
	if boundModel == currentModel then
		return
	end

	local modelBindingMaidKey = getModelBindingMaidKey(runtimeId)
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
		boss:RequestRemoval("ModelDestroyed")
	end)
end

function BossServiceServer.TrackController(self: BossServiceServer, boss: BossObject)
	self.controllersById[boss.id] = boss
	self.controllersByChannel[boss.encounterChannel] = boss
	if self.controllerMap ~= nil then
		self.controllerMap:Set(boss.id, boss)
	end
	self:RefreshControllerModelBinding(boss)
end

function BossServiceServer.UntrackController(self: BossServiceServer, boss: BossObject)
	local runtimeId = getBossId(boss)
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
	maid[getModelBindingMaidKey(runtimeId)] = nil
	self.boundModelsById[runtimeId] = nil
end

function BossServiceServer.SyncControllerSnapshot(
	self: BossServiceServer,
	boss: BossObject,
	forceRaw: any?
): BossSnapshot?
	local force = forceRaw == true
	local now = self:GetNow()
	if not force then
		if boss.snapshotDirty ~= true then
			return nil
		end
		if now - boss.lastSnapshotAt < self.statePushInterval then
			return nil
		end
	end

	local snapshot = self:UpsertControllerState(boss)
	self:Broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_UPDATED, snapshot)
	self:EmitControllerUpdated(snapshot, boss)
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

	self:UntrackController(boss)
	self.state.byId[runtimeId] = nil
	self:RemoveOrderedId(runtimeId)
	self.state.updatedAt = self:GetNow()
	self:EmitStateChanged()

	boss:Destroy()
	self:Broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_REMOVED, runtimeId)
	self:EmitControllerRemoved(runtimeId, boss, if reason ~= "" then reason else boss.lastReason)
end

function BossServiceServer.SpawnBoss(self: BossServiceServer, requestRaw: any): (BossObject?, string?)
	local request, definition, requestError = self:GetSpawnRequest(requestRaw)
	if request == nil or definition == nil then
		return nil, requestError
	end

	if definition.singletonPerChannel and self:IsEncounterChannelBusy(request.encounterChannel) then
		return nil, "encounter_channel_busy"
	end

	if definition.nightOnlySummon and request.spawnSource ~= "DebugCommand" and not self:IsNightTime() then
		return nil, "night_only"
	end

	local constructor = self:GetControllerConstructor(definition)
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

	local spawnOk = pcall(function()
		boss:Spawn()
	end)
	if not spawnOk then
		destroyBossSafely(boss)
		return nil, "controller_spawn_failed"
	end

	self:TrackController(boss)
	self:RefreshControllerModelBinding(boss)

	local afterSpawn = (boss :: any).AfterSpawn
	if typeof(afterSpawn) == "function" then
		local afterSpawnOk = pcall(function()
			afterSpawn(boss)
		end)
		if not afterSpawnOk then
			self:UntrackController(boss)
			destroyBossSafely(boss)
			return nil, "controller_after_spawn_failed"
		end
	end

	local snapshot = self:UpsertControllerState(boss)
	self:Broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_ADDED, snapshot)
	self:EmitControllerAdded(snapshot, boss)
	return boss, nil
end

function BossServiceServer.GetEncounterTarget(_self: BossServiceServer, boss: BossObject): Player?
	local currentTarget = boss.targetPlayer
	if currentTarget ~= nil and BossServiceUtils.IsPlayerAlive(currentTarget) then
		return currentTarget
	end

	local bossPosition = boss.position
	local nearestPlayer = nil :: Player?
	local nearestDistance = math.huge
	for _, player in Players:GetPlayers() do
		if not BossServiceUtils.IsPlayerAlive(player) then
			continue
		end
		local rootPart = BossServiceUtils.GetCharacterRootPart(player)
		if rootPart == nil then
			continue
		end

		local distance = (BossServiceUtils.ProjectPositionToPlaneX(rootPart.Position, boss.planeX) - bossPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearestPlayer = player
		end
	end

	return nearestPlayer
end

function BossServiceServer.GetControllerFromInstance(self: BossServiceServer, instanceRaw: any): BossObject?
	local runtimeId = BossServiceUtils.GetRuntimeIdFromInstance(instanceRaw)
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
	local boss = self:GetControllerFromInstance(hitPartRaw)
	if boss == nil then
		return 0
	end

	local appliedDamage = boss:TakeDamage(damageRaw, sourceRaw, damageContextRaw)
	if appliedDamage > 0 then
		self:SyncControllerSnapshot(boss, true)
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

		local runtimeId = BossServiceUtils.GetRuntimeIdFromInstance(part)
		if runtimeId == nil or seenIds[runtimeId] == true then
			continue
		end
		seenIds[runtimeId] = true

		local boss = self.controllersById[runtimeId]
		if boss == nil then
			continue
		end

		local appliedDamage = boss:TakeDamage(damageRaw, sourceRaw, damageContextRaw)
		if appliedDamage > 0 then
			totalAppliedDamage += appliedDamage
			self:SyncControllerSnapshot(boss, true)
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
	local index = math.max(1, math.floor(BossServiceUtils.CoerceNumber(indexRaw, 1, 1, 10 ^ 6)))
	return ("debug.%s.%d.%d.%d"):format(
		BossServiceUtils.NormalizeToken(bossId),
		player.UserId,
		math.floor(self:GetNow() * 1000 + 0.5),
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
		updatedAt = self:GetNow(),
	}
	self:Broadcast(BossServiceUtils.CLIENT_METHOD_ON_ANNOUNCEMENT, payload)
	if self._announcementSignal ~= nil then
		self._announcementSignal:Fire(payload)
	end
end

function BossServiceServer.GetNaturalSpawnTargetPlayer(self: BossServiceServer): Player?
	local alivePlayers = {}
	local trackedPlayers = if self.trackedPlayers ~= nil then self.trackedPlayers:GetList() else Players:GetPlayers()
	for _, player in trackedPlayers do
		if BossServiceUtils.IsPlayerAlive(player) then
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

	local targetPlayer = self:GetNaturalSpawnTargetPlayer()
	if targetPlayer == nil then
		return
	end

	local defaultConfig = self.defaultConfigByBossId[definition.id]
	if typeof(defaultConfig) ~= "table" or defaultConfig.naturalSpawnEnabled ~= true then
		return
	end

	local spawnChance = BossServiceUtils.CoerceNumber(defaultConfig.naturalSpawnChancePerNight, 0, 0, 1)
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
		delayRemaining = BossServiceUtils.CoerceNumber(defaultConfig.naturalSpawnAnnouncementDelay, 2, 0, 30),
		announcement = announcement,
	}
	self:SetPendingNaturalSpawn(self.pendingNaturalSpawn)
	self:BroadcastAnnouncement(announcement, definition.id)
end

function BossServiceServer.StepNaturalSpawns(
	self: BossServiceServer,
	dt: number,
	previousClockTime: number,
	currentClockTime: number
)
	if BossServiceUtils.DidClockPass(previousClockTime, currentClockTime, BossServiceUtils.NIGHT_START_CLOCK_TIME) then
		for _, definition in BossServiceUtils.GetRegistryEntries() do
			if definition.supportsNaturalSpawn and not self:IsEncounterChannelBusy(definition.encounterChannel) then
				self:ScheduleNaturalSpawn(definition)
			end
		end
	end

	local pending = self.pendingNaturalSpawn
	if pending == nil then
		return
	end

	if not self:IsNightTime() then
		self:SetPendingNaturalSpawn(nil)
		return
	end

	if not BossServiceUtils.IsPlayerAlive(pending.targetPlayer) then
		self:SetPendingNaturalSpawn(nil)
		return
	end

	pending.delayRemaining -= dt
	if pending.delayRemaining > 0 then
		return
	end

	if not self:IsPlayerAboveSurface(pending.targetPlayer) then
		return
	end

	local controller, reason = self:SpawnBoss({
		bossId = pending.bossId,
		targetPlayer = pending.targetPlayer,
		spawnSource = "NaturalSpawn",
		encounterChannel = pending.encounterChannel,
	})

	if controller ~= nil or reason ~= "encounter_channel_busy" then
		self:SetPendingNaturalSpawn(nil)
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

	local definition = BossServiceUtils.GetRegistryEntryByToken(bossTokenRaw)
	if definition == nil then
		return nil, "unknown_boss"
	end

	if definition.nightOnlySummon and not self:IsNightTime() then
		return nil, "night_only"
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {} :: any
	return self:SpawnBoss({
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

	self:SummonBossForPlayer(player, bossTokenRaw, optionsRaw)
end

function BossServiceServer.GetState(self: BossServiceServer): BossServiceState
	return self:CreateStateSnapshot()
end

function BossServiceServer.ObserveState(self: BossServiceServer): ObservableObject
	return getOrCreateObservable(self, "state", function()
		return Rx.fromSignal(self._stateChangedSignal):Pipe({
			Rx.startWith({ self:GetState() }),
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
		return fulfilledPromise(nil) :: PromiseObject
	end

	local existing = self.controllersById[runtimeId]
	if existing ~= nil then
		return fulfilledPromise(existing) :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveControllerAtId(runtimeId):Pipe({
			Rx.where(function(boss)
				return boss ~= nil
			end),
			Rx.take(1),
		}),
		getCancelToken(cancelTokenRaw)
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
		return fulfilledPromise({
			id = runtimeId,
			bossId = nil,
			reason = "already_removed",
			updatedAt = self:GetNow(),
		}) :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveControllerRemoved():Pipe({
			Rx.where(function(payload)
				return typeof(payload) == "table" and (payload :: any).id == runtimeId
			end),
			Rx.take(1),
		}),
		getCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function BossServiceServer.SpawnBossPromise(
	self: BossServiceServer,
	requestRaw: any,
	cancelTokenRaw: any?
): PromiseObject
	local cancelToken = getCancelToken(cancelTokenRaw)
	local promise = Promise.spawn(function(fulfill, reject)
		if cancelToken ~= nil and cancelToken:IsCancelled() then
			reject("cancelled")
			return
		end

		local boss, reason = self:SpawnBoss(requestRaw)
		if cancelToken ~= nil and cancelToken:IsCancelled() then
			if boss ~= nil then
				self:RemoveController(boss.id, "spawn_cancelled")
			end
			reject("cancelled")
			return
		end

		fulfill(boss, reason)
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
	local cancelToken = getCancelToken(cancelTokenRaw)
	local promise = Promise.spawn(function(fulfill, reject)
		if cancelToken ~= nil and cancelToken:IsCancelled() then
			reject("cancelled")
			return
		end

		fulfill(self:SummonBossForPlayer(playerRaw, bossTokenRaw, optionsRaw))
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
	local dt = BossServiceUtils.CoerceNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end

	local previousClockTime = self.previousClockTime
	local currentClockTime = self:GetClockTime()
	self.naturalSpawnAccumulator += dt
	if self.naturalSpawnAccumulator >= self.naturalSpawnCheckInterval then
		self.naturalSpawnAccumulator = 0
		self:StepNaturalSpawns(dt, previousClockTime, currentClockTime)
	end
	self.previousClockTime = currentClockTime

	local orderedIds = Sift.Dictionary.copy(self.state.orderedIds)
	for _, runtimeId in orderedIds do
		local boss = self.controllersById[runtimeId]
		if boss == nil then
			continue
		end

		if boss.removeRequested == true then
			self:RemoveController(runtimeId, boss.removeReason)
			continue
		end

		local simulationSpeed = 1
		local getSimulationSpeed = (boss :: any).GetSimulationSpeed
		if typeof(getSimulationSpeed) == "function" then
			simulationSpeed = BossServiceUtils.CoerceNumber(getSimulationSpeed(boss), 1, 0.05, 5)
		end

		local simulationDt = dt * simulationSpeed
		local maxSimulationStep = simulationDt
		local getMaxSimulationStep = (boss :: any).GetMaxSimulationStep
		if typeof(getMaxSimulationStep) == "function" then
			maxSimulationStep =
				BossServiceUtils.CoerceNumber(getMaxSimulationStep(boss), simulationDt, 1 / 240, simulationDt)
		end

		local remainingDt = simulationDt
		while remainingDt > 0 do
			local stepDt = math.min(remainingDt, maxSimulationStep)
			boss:Step(stepDt)
			remainingDt -= stepDt
			if boss.removeRequested == true then
				break
			end
		end
		self:RefreshControllerModelBinding(boss)

		if boss.removeRequested == true then
			self:RemoveController(runtimeId, boss.removeReason)
			continue
		end

		self:SyncControllerSnapshot(boss, false)
	end
end

function BossServiceServer.TrackPlayer(self: BossServiceServer, player: Player)
	if self.trackedPlayers ~= nil then
		self.trackedPlayers:Add(player)
	end
	self:PushState(player)
end

function BossServiceServer.UntrackPlayer(self: BossServiceServer, player: Player)
	if self.trackedPlayers ~= nil then
		self.trackedPlayers:Remove(player)
	end
end

function BossServiceServer.Init(self: BossServiceServer, serviceBag: any)
	self.maid = Maid.new() :: MaidClass
	bindPackets(self)
	self.hpService = HpServiceServer :: any
	self.weatherService = WeatherServiceServer :: any
	self.worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.controllersById = {}
	self.controllersByChannel = {}
	self.boundModelsById = {}
	self.state = BossServiceUtils.CreateDefaultState()
	self.statePushInterval = DEFAULT_STATE_PUSH_INTERVAL
	self.naturalSpawnCheckInterval = DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL
	self.naturalSpawnAccumulator = 0
	self.random = Random.new()
	self.world = nil
	self.pendingNaturalSpawn = nil
	self.allowClientManualSummon = false
	self.defaultConfigByBossId = {
		EyeOfCthulhu = EyeOfCthulhuConfig.Get(getEyeConfigSource()),
		QueenBee = QueenBeeConfig.Get(getQueenBeeConfigSource()),
	}
	self.previousClockTime = self:GetClockTime();
	(self :: any).binders = serviceBag:GetService(BinderSupportServer)
	self:InitReactiveState()

	self.maid:GiveTask(Rx.fromSignal(Players.PlayerAdded)
		:Pipe({
			Rx.startFrom(function()
				return Players:GetPlayers()
			end),
		})
		:Subscribe(function(player: Player)
			if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
				self:TrackPlayer(player)
			end
		end))
	self.maid:GiveTask(Rx.fromSignal(Players.PlayerRemoving):Subscribe(function(player: Player)
		self:UntrackPlayer(player)
	end))
	self.maid:GiveTask(Rx.fromSignal(RunService.Heartbeat):Subscribe(function(dt: number)
		self:OnHeartbeat(dt)
	end))
end

function BossServiceServer.Destroy(self: BossServiceServer)
	local runtimeIds = Sift.Dictionary.copy(self.state.orderedIds)
	for _, runtimeId in runtimeIds do
		self:RemoveController(runtimeId, "service_destroy")
	end

	self.maid:Destroy()
end
type BossServiceServer = typeof(BossServiceServer) & {
	maid: MaidClass,
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
