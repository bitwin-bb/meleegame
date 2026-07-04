local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossServiceUtils = require("BossServiceUtils")
local CancelToken = require("CancelToken")
local EyeOfCthulhuRoot = require("EyeOfCthulhuRoot")
local Maid = require("Maid")
local Promise: any = require("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end
local QueenBeeRoot = require("QueenBeeRoot")
local Rx: any = require("Rx")
local RxSignal: any = require("RxSignal")
local Signal = require("Signal")
local ValueObject: any = require("ValueObject")
local WorkspaceFolders = require("WorkspaceFolders")

type BossId = BossServiceUtils.BossId
type BossEncounterState = BossServiceUtils.BossEncounterState
type BossRegistryEntry = BossServiceUtils.BossRegistryEntry
type BossMotionState = BossServiceUtils.BossMotionState
type BossPresentationState = BossServiceUtils.BossPresentationState
type BossSnapshot = BossServiceUtils.BossSnapshot
type BossSpawnRequest = BossServiceUtils.BossSpawnRequest

type MaidClass = any

type SignalObject = Signal.Signal<...any>

type ObservableObject = any

type PromiseObject = any

type RxSignalObject = any

type ValueObjectClass<T> = any

type BossSignals = {
	stateChanged: SignalObject,
	targetChanged: SignalObject,
	damaged: SignalObject,
	removed: SignalObject,
	died: SignalObject,
	spawned: SignalObject,
	modelChanged: SignalObject,
	snapshotDirty: SignalObject,
	destroying: SignalObject,
}

local Boss = {}
Boss.__index = Boss

export type Boss = typeof(setmetatable(
	{} :: {
		service: any,
		definition: BossRegistryEntry,
		id: string,
		bossId: BossId,
		displayName: string,
		encounterChannel: string,
		spawnSource: BossServiceUtils.BossSpawnSource,
		modelTemplate: Model?,
		model: Model?,
		rootPart: BasePart?,
		planeX: number?,
		isSpawned: boolean,
		isAlive: boolean,
		isDestroyed: boolean,
		removeRequested: boolean,
		removeReason: string,
		lastReason: string,
		state: BossEncounterState,
		stateTime: number,
		phase: number,
		hp: number,
		maxHp: number,
		defense: number,
		baseDefense: number,
		contactDamage: number,
		baseContactDamage: number,
		offenseEnabled: boolean,
		contactDamageActive: boolean,
		contactDamageRadius: number,
		contactDamageCooldown: number,
		faceVelocityWhenMoving: boolean,
		faceTargetWhenIdle: boolean,
		chargeIndex: number,
		position: Vector3,
		velocity: Vector3,
		facing: Vector3,
		targetPlayer: Player?,
		targetUserId: number?,
		targetLostTime: number,
		lastSnapshotAt: number,
		snapshotDirty: boolean,
		presentation: BossPresentationState,
		motion: BossMotionState,
		config: { [string]: any },
		spawnRequest: BossSpawnRequest,
		damageCooldownByUserId: { [number]: number },
		maid: MaidClass,
		signals: BossSignals,
		stateValue: ValueObjectClass<BossEncounterState>,
		phaseValue: ValueObjectClass<number>,
		targetValue: ValueObjectClass<Player?>,
		modelValue: ValueObjectClass<Model?>,
		healthValue: ValueObjectClass<number>,
		aliveValue: ValueObjectClass<boolean>,
		spawnedValue: ValueObjectClass<boolean>,
		destroyedValue: ValueObjectClass<boolean>,
		removeRequestedValue: ValueObjectClass<boolean>,
		observableCache: { [string]: ObservableObject },
		rxSignalCache: { [string]: RxSignalObject },
	},
	Boss
))
local DEFAULT_BOSS_FOLDER_NAME = "BossRuntime"
local MISSING_ASSET_ERROR = "no asset found!"
local MODEL_TEMPLATE_FACTORIES = {
	EyeOfCthulhu = function(phaseModel: string): Model
		return EyeOfCthulhuRoot.CreateModel({
			phaseModel = phaseModel,
		})
	end,
	QueenBee = function(phaseModel: string): Model
		return QueenBeeRoot.CreateModel({
			phaseModel = phaseModel,
		})
	end,
}

local function trim(valueRaw: any): string
	return BossServiceUtils.Trim(valueRaw)
end

local function GetBossAssetRoot(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets == nil then
		return nil
	end

	local npcs = assets:FindFirstChild("Npcs")
	if npcs == nil then
		return assets
	end

	local bosses = npcs:FindFirstChild("Bosses")
	if bosses ~= nil then
		return bosses
	end

	return npcs
end

local function GetFirstModel(instance: Instance?): Model?
	if instance == nil then
		return nil
	end

	if instance:IsA("Model") then
		return instance
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Model") then
			return descendant
		end
	end

	return nil
end

local function findChildCaseInsensitive(parent: Instance?, childNameRaw: any): Instance?
	if parent == nil then
		return nil
	end

	local childName = trim(childNameRaw)
	if childName == "" then
		return nil
	end

	local direct = parent:FindFirstChild(childName)
	if direct ~= nil then
		return direct
	end

	local lowered = string.lower(childName)
	for _, child in parent:GetChildren() do
		if string.lower(child.Name) == lowered then
			return child
		end
	end

	return nil
end

local function GetPhaseModelFromContainer(phaseContainer: Instance?, definition: BossRegistryEntry): Model?
	if phaseContainer == nil then
		return nil
	end

	local exactById = findChildCaseInsensitive(phaseContainer, definition.id)
	local exactByDisplayName = findChildCaseInsensitive(phaseContainer, definition.displayName)
	local exactModel = GetFirstModel(exactById) or GetFirstModel(exactByDisplayName)
	if exactModel ~= nil then
		return exactModel
	end

	return GetFirstModel(phaseContainer)
end

local function splitPathTokens(pathRaw: any): { string }
	local path = trim(pathRaw)
	if path == "" then
		return {}
	end

	local normalized = string.gsub(path, "\\", "/")
	normalized = string.gsub(normalized, "%.", "/")

	local out = {}
	for token in string.gmatch(normalized, "[^/]+") do
		if token ~= "" then
			table.insert(out, token)
		end
	end
	return out
end

local function GetBossModelTemplate(definition: BossRegistryEntry, phaseModelNameRaw: any?): Model?
	local root = GetBossAssetRoot()
	local phaseModelName = trim(phaseModelNameRaw)
	if root ~= nil then
		local cursor: Instance? = root
		for _, token in splitPathTokens(definition.modelHierarchy) do
			cursor = findChildCaseInsensitive(cursor, token)
			if cursor == nil then
				break
			end
		end

		if cursor ~= nil and phaseModelName ~= "" then
			local phaseContainer = findChildCaseInsensitive(cursor, phaseModelName)
			local phaseModel = GetPhaseModelFromContainer(phaseContainer, definition)
			if phaseModel ~= nil then
				return phaseModel
			end
		end

		local Got = GetFirstModel(cursor)
		if Got ~= nil then
			return Got
		end

		local normalizedBossName = BossServiceUtils.NormalizeToken(definition.id)
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Model") and BossServiceUtils.NormalizeToken(descendant.Name) == normalizedBossName then
				return descendant
			end
		end
	end

	local factory = MODEL_TEMPLATE_FACTORIES[definition.id]
	if factory ~= nil then
		return factory(if phaseModelName ~= "" then phaseModelName else "Phase1")
	end

	error(MISSING_ASSET_ERROR, 0)
end

local function configureModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function nowClock(): number
	return os.clock()
end

local function getOrCreateObservable(self: Boss, key: string, factory: () -> ObservableObject): ObservableObject
	local cached = self.observableCache[key]
	if cached ~= nil then
		return cached
	end

	local created = factory()
	self.observableCache[key] = created
	return created
end

local function getOrCreateRxSignal(self: Boss, key: string, factory: () -> RxSignalObject): RxSignalObject
	local cached = self.rxSignalCache[key]
	if cached ~= nil then
		return cached
	end

	local created = factory()
	self.rxSignalCache[key] = created
	return created
end

local function GetCancelToken(cancelTokenRaw: any): any?
	if CancelToken.isCancelToken(cancelTokenRaw) then
		return cancelTokenRaw
	end
	return nil
end

function Boss.New(
	service: any,
	definition: BossRegistryEntry,
	spawnRequest: BossSpawnRequest,
	configRaw: { [string]: any }
): Boss
	local config = if typeof(configRaw) == "table" then configRaw else {} :: any
	local modelTemplate = GetBossModelTemplate(definition, "Phase1")
	local spawnPosition = if typeof(spawnRequest.spawnPosition) == "Vector3"
		then spawnRequest.spawnPosition
		else Vector3.zero
	local maid = Maid.new() :: MaidClass
	local maxHp = BossServiceUtils.CoerceNumber(config.maxHp, 1, 1, 10 ^ 9)
	local targetPlayer = if typeof(spawnRequest.targetPlayer) == "Instance"
			and spawnRequest.targetPlayer:IsA("Player")
		then spawnRequest.targetPlayer
		else nil
	local signals = {
		stateChanged = Signal.new(),
		targetChanged = Signal.new(),
		damaged = Signal.new(),
		removed = Signal.new(),
		died = Signal.new(),
		spawned = Signal.new(),
		modelChanged = Signal.new(),
		snapshotDirty = Signal.new(),
		destroying = Signal.new(),
	}
	local stateValue =
		ValueObject.new("Dormant" :: BossEncounterState, "string") :: ValueObjectClass<BossEncounterState>
	local phaseValue = ValueObject.new(0, "number") :: ValueObjectClass<number>
	local targetValue = ValueObject.new(targetPlayer) :: ValueObjectClass<Player?>
	local modelValue = ValueObject.new(nil) :: ValueObjectClass<Model?>
	local healthValue = ValueObject.new(maxHp, "number") :: ValueObjectClass<number>
	local aliveValue = ValueObject.new(true, "boolean") :: ValueObjectClass<boolean>
	local spawnedValue = ValueObject.new(false, "boolean") :: ValueObjectClass<boolean>
	local destroyedValue = ValueObject.new(false, "boolean") :: ValueObjectClass<boolean>
	local removeRequestedValue = ValueObject.new(false, "boolean") :: ValueObjectClass<boolean>

	maid:GiveTask(signals.stateChanged)
	maid:GiveTask(signals.targetChanged)
	maid:GiveTask(signals.damaged)
	maid:GiveTask(signals.removed)
	maid:GiveTask(signals.died)
	maid:GiveTask(signals.spawned)
	maid:GiveTask(signals.modelChanged)
	maid:GiveTask(signals.snapshotDirty)
	maid:GiveTask(signals.destroying)
	maid:GiveTask(stateValue)
	maid:GiveTask(phaseValue)
	maid:GiveTask(targetValue)
	maid:GiveTask(modelValue)
	maid:GiveTask(healthValue)
	maid:GiveTask(aliveValue)
	maid:GiveTask(spawnedValue)
	maid:GiveTask(destroyedValue)
	maid:GiveTask(removeRequestedValue)

	local self = setmetatable({
		service = service,
		definition = definition,
		id = HttpService:GenerateGUID(false),
		bossId = definition.id,
		displayName = definition.displayName,
		encounterChannel = if spawnRequest.encounterChannel ~= nil
			then spawnRequest.encounterChannel
			else definition.encounterChannel,
		spawnSource = spawnRequest.spawnSource,
		modelTemplate = modelTemplate,
		model = nil,
		rootPart = nil,
		planeX = spawnRequest.planeX,
		isSpawned = false,
		isAlive = true,
		isDestroyed = false,
		removeRequested = false,
		removeReason = "",
		lastReason = "spawn",
		state = "Dormant" :: BossEncounterState,
		stateTime = 0,
		phase = 0,
		hp = maxHp,
		maxHp = maxHp,
		defense = BossServiceUtils.CoerceNumber(config.defense, 0, 0, 10 ^ 6),
		baseDefense = BossServiceUtils.CoerceNumber(config.defense, 0, 0, 10 ^ 6),
		contactDamage = BossServiceUtils.CoerceNumber(config.contactDamage, 0, 0, 10 ^ 6),
		baseContactDamage = BossServiceUtils.CoerceNumber(config.contactDamage, 0, 0, 10 ^ 6),
		offenseEnabled = true,
		contactDamageActive = false,
		contactDamageRadius = BossServiceUtils.CoerceNumber(config.contactDamageRadius, 8, 0, 512),
		contactDamageCooldown = BossServiceUtils.CoerceNumber(config.contactDamageCooldown, 0.35, 0, 30),
		faceVelocityWhenMoving = BossServiceUtils.CoerceBoolean(config.faceVelocityWhenMoving, true),
		faceTargetWhenIdle = BossServiceUtils.CoerceBoolean(config.faceTargetWhenIdle, true),
		chargeIndex = 0,
		position = BossServiceUtils.ProjectPositionToPlaneX(spawnPosition, spawnRequest.planeX),
		velocity = Vector3.zero,
		facing = Vector3.zAxis,
		targetPlayer = targetPlayer,
		targetUserId = BossServiceUtils.GetTargetPlayerUserId(targetPlayer),
		targetLostTime = 0,
		lastSnapshotAt = nowClock(),
		snapshotDirty = true,
		presentation = BossServiceUtils.CreateDefaultPresentation(),
		motion = BossServiceUtils.CreateDefaultMotionState(),
		config = config,
		spawnRequest = spawnRequest,
		damageCooldownByUserId = {},
		maid = maid,
		signals = signals,
		stateValue = stateValue,
		phaseValue = phaseValue,
		targetValue = targetValue,
		modelValue = modelValue,
		healthValue = healthValue,
		aliveValue = aliveValue,
		spawnedValue = spawnedValue,
		destroyedValue = destroyedValue,
		removeRequestedValue = removeRequestedValue,
		observableCache = {},
		rxSignalCache = {},
	}, Boss)

	return self
end

function Boss.GetModelTemplate(self: Boss, phaseModelNameRaw: any?): Model?
	local modelTemplate = GetBossModelTemplate(self.definition, phaseModelNameRaw)
	if modelTemplate ~= nil then
		self.modelTemplate = modelTemplate
		return modelTemplate
	end

	return self.modelTemplate
end

function Boss.GetOrCreateRuntimeFolder(_self: Boss): Folder
	return WorkspaceFolders.GetOrCreateFolderInGame(DEFAULT_BOSS_FOLDER_NAME)
end

function Boss.MarkSnapshotDirty(self: Boss)
	if not self.snapshotDirty then
		self.snapshotDirty = true
	end

	self.signals.snapshotDirty:Fire()
end

function Boss.SetTarget(self: Boss, targetPlayerRaw: any?): boolean
	local targetPlayer = if typeof(targetPlayerRaw) == "Instance" and targetPlayerRaw:IsA("Player")
		then targetPlayerRaw
		else nil

	if targetPlayer ~= nil and not BossServiceUtils.IsPlayerAlive(targetPlayer) then
		targetPlayer = nil
	end

	if self.targetPlayer == targetPlayer then
		return targetPlayer ~= nil
	end

	local previousTarget = self.targetPlayer
	self.targetPlayer = targetPlayer
	self.targetUserId = BossServiceUtils.GetTargetPlayerUserId(targetPlayer)
	self.targetLostTime = 0
	self.targetValue.Value = targetPlayer
	self:MarkSnapshotDirty()
	self.signals.targetChanged:Fire(targetPlayer, previousTarget)
	return targetPlayer ~= nil
end

function Boss.ClearTarget(self: Boss)
	self:SetTarget(nil)
end

function Boss.GetTargetRootPart(self: Boss): BasePart?
	return BossServiceUtils.GetCharacterRootPart(self.targetPlayer)
end

function Boss.GetTargetPosition(self: Boss): Vector3?
	local rootPart = self:GetTargetRootPart()
	if rootPart == nil then
		return nil
	end
	return BossServiceUtils.ProjectPositionToPlaneX(rootPart.Position, self.planeX)
end

function Boss.GetTargetVelocity(self: Boss): Vector3
	if self.targetPlayer == nil then
		return Vector3.zero
	end
	return BossServiceUtils.ProjectVectorToPlaneX(
		BossServiceUtils.GetCharacterVelocity(self.targetPlayer),
		self.planeX
	)
end

function Boss.GetHealthRatio(self: Boss): number
	if self.maxHp <= 0 then
		return 0
	end
	return math.clamp(self.hp / self.maxHp, 0, 1)
end

function Boss.ChangeState(self: Boss, nextStateRaw: any, reasonRaw: any?)
	local nextState = if typeof(nextStateRaw) == "string" then nextStateRaw else "Dormant"
	local reason = trim(reasonRaw)
	if reason == "" then
		reason = "stateChange"
	end

	if self.state == nextState then
		self.lastReason = reason
		return
	end

	local previousState = self.state
	self.state = nextState :: BossEncounterState
	self.stateTime = 0
	self.lastReason = reason
	self.motion.state = self.state
	self.stateValue.Value = self.state
	self:MarkSnapshotDirty()
	self.signals.stateChanged:Fire(self.state, previousState, reason)

	local onStateChanged = (self :: any).OnStateChanged
	if typeof(onStateChanged) == "function" then
		onStateChanged(self, self.state, previousState, reason)
	end
end

function Boss.SetPhase(self: Boss, nextPhaseRaw: any, phaseModelRaw: any?)
	local nextPhase = math.max(0, math.floor(BossServiceUtils.CoerceNumber(nextPhaseRaw, self.phase, 0, 32)))
	local phaseModel = if typeof(phaseModelRaw) == "string" and phaseModelRaw ~= ""
		then phaseModelRaw
		else if nextPhase <= 1 then "Phase1" else "Phase2"

	local phaseChanged = self.phase ~= nextPhase
	local modelChanged = self.presentation.phaseModel ~= phaseModel

	if not phaseChanged and not modelChanged then
		return
	end

	self.phase = nextPhase
	self.presentation.phaseModel = phaseModel
	self.phaseValue.Value = self.phase
	self:MarkSnapshotDirty()

	if modelChanged and self.isSpawned then
		self:ReplaceModel(phaseModel)
	end
end

function Boss.IncrementPresentationToken(self: Boss, tokenName: string)
	local currentValue = (self.presentation :: any)[tokenName]
	if typeof(currentValue) ~= "number" then
		return
	end
	(self.presentation :: any)[tokenName] = currentValue + 1
	self:MarkSnapshotDirty()
end

function Boss.SetPresentationFlag(self: Boss, flagName: string, enabledRaw: any)
	local enabled = enabledRaw == true
	local currentValue = (self.presentation :: any)[flagName]
	if typeof(currentValue) ~= "boolean" or currentValue == enabled then
		return
	end

	(self.presentation :: any)[flagName] = enabled
	self:MarkSnapshotDirty()
end

function Boss.SetMotionState(self: Boss, motionRaw: any)
	self.motion = BossServiceUtils.CoerceMotionState(motionRaw, self.motion)
	self:MarkSnapshotDirty()
end

function Boss.ProjectToPlane(self: Boss, position: Vector3): Vector3
	return BossServiceUtils.ProjectPositionToPlaneX(position, self.planeX)
end

function Boss.SetPosition(self: Boss, positionRaw: any)
	if typeof(positionRaw) ~= "Vector3" then
		return
	end

	self.position = self:ProjectToPlane(positionRaw)
	self:MarkSnapshotDirty()
end

function Boss.SetVelocity(self: Boss, velocityRaw: any)
	if typeof(velocityRaw) ~= "Vector3" then
		self.velocity = Vector3.zero
	else
		self.velocity = BossServiceUtils.ProjectVectorToPlaneX(velocityRaw, self.planeX)
	end
	self:MarkSnapshotDirty()
end

function Boss.SetFacing(self: Boss, facingRaw: any)
	if typeof(facingRaw) ~= "Vector3" then
		return
	end

	local planarFacing = BossServiceUtils.ProjectVectorToPlaneX(facingRaw, self.planeX)
	self.facing = BossServiceUtils.ComputeFacingVector(self.position, planarFacing, self.facing)
	self:MarkSnapshotDirty()
end

function Boss.LookAt(self: Boss, targetPositionRaw: any)
	if typeof(targetPositionRaw) ~= "Vector3" then
		return
	end
	self:SetFacing(targetPositionRaw - self.position)
end

function Boss.AccelerateTowardVelocity(self: Boss, desiredVelocityRaw: any, accelerationRaw: any, dtRaw: any)
	if typeof(desiredVelocityRaw) ~= "Vector3" then
		return
	end

	local desiredVelocity = BossServiceUtils.ProjectVectorToPlaneX(desiredVelocityRaw, self.planeX)
	local acceleration = BossServiceUtils.CoerceNumber(accelerationRaw, 0, 0, 10 ^ 6)
	local dt = BossServiceUtils.CoerceNumber(dtRaw, 0, 0, 1)
	self.velocity = BossServiceUtils.MoveTowardsVector(self.velocity, desiredVelocity, acceleration * dt)
	self:MarkSnapshotDirty()
end

function Boss.DampVelocity(self: Boss, dampingPerSecondRaw: any, dtRaw: any)
	local dampingPerSecond = BossServiceUtils.CoerceNumber(dampingPerSecondRaw, 0, 0, 10 ^ 6)
	local dt = BossServiceUtils.CoerceNumber(dtRaw, 0, 0, 1)
	local alpha = math.clamp(1 - dampingPerSecond * dt, 0, 1)
	self.velocity *= alpha
	self:MarkSnapshotDirty()
end

function Boss.MoveTowardPoint(
	self: Boss,
	targetPositionRaw: any,
	maxSpeedRaw: any,
	accelerationRaw: any,
	dampingRaw: any,
	dtRaw: any
): boolean
	if typeof(targetPositionRaw) ~= "Vector3" then
		return false
	end

	local targetPosition = self:ProjectToPlane(targetPositionRaw)
	local offset = targetPosition - self.position
	local desiredVelocity = if offset.Magnitude > 1e-4
		then offset.Unit * BossServiceUtils.CoerceNumber(maxSpeedRaw, 0, 0, 10 ^ 6)
		else Vector3.zero

	self:AccelerateTowardVelocity(desiredVelocity, accelerationRaw, dtRaw)
	self:DampVelocity(dampingRaw, dtRaw)
	return true
end

function Boss.IntegrateMotion(self: Boss, dtRaw: any)
	local dt = BossServiceUtils.CoerceNumber(dtRaw, 0, 0, 1)
	self.position = self:ProjectToPlane(self.position + self.velocity * dt)
	self.motion.position = self.position
	self.motion.velocity = self.velocity
	self:MarkSnapshotDirty()
end

function Boss.ApplyContactDamage(self: Boss, damageRaw: any?, radiusRaw: any?, cooldownRaw: any?)
	if not self.offenseEnabled or not self.contactDamageActive then
		return
	end

	local damage = BossServiceUtils.CoerceNumber(damageRaw, self.contactDamage, 0, 10 ^ 6)
	if damage <= 0 then
		return
	end

	local radius = BossServiceUtils.CoerceNumber(radiusRaw, self.contactDamageRadius, 0, 512)
	local cooldown = BossServiceUtils.CoerceNumber(cooldownRaw, self.contactDamageCooldown, 0, 30)
	local currentTime = self.service:GetNow()

	for _, player in Players:GetPlayers() do
		if not BossServiceUtils.IsPlayerAlive(player) then
			continue
		end

		local rootPart = BossServiceUtils.GetCharacterRootPart(player)
		if rootPart == nil then
			continue
		end

		if (self.position - self:ProjectToPlane(rootPart.Position)).Magnitude > radius then
			continue
		end

		local lastDamageAt = self.damageCooldownByUserId[player.UserId] or -math.huge
		if currentTime - lastDamageAt < cooldown then
			continue
		end

		if self.service:DamagePlayer(player, damage, self) ~= nil then
			self.damageCooldownByUserId[player.UserId] = currentTime
		end
	end
end

function Boss.UpdateModelPivot(self: Boss)
	local model = self.model
	if model == nil then
		return
	end

	model:PivotTo(BossServiceUtils.SideViewLookCFrame(self.position, self.facing))
	configureModel(model)
	self.rootPart = BossServiceUtils.GetRootPart(model)
	if self.rootPart ~= nil and model.PrimaryPart == nil then
		model.PrimaryPart = self.rootPart
	end
end

function Boss.ReplaceModel(self: Boss, phaseModelRaw: any?): Model?
	if self.isDestroyed then
		return nil
	end

	local previousModel = self.model
	local modelTemplate = self:GetModelTemplate(phaseModelRaw)
	if modelTemplate == nil then
		error(MISSING_ASSET_ERROR, 0)
	end

	local nextModel = modelTemplate:Clone()
	nextModel.Name = self.displayName
	nextModel.Parent = self:GetOrCreateRuntimeFolder()
	configureModel(nextModel)

	local nextRootPart = BossServiceUtils.GetRootPart(nextModel)
	if nextRootPart ~= nil and nextModel.PrimaryPart == nil then
		nextModel.PrimaryPart = nextRootPart
	end

	nextModel:PivotTo(BossServiceUtils.SideViewLookCFrame(self.position, self.facing))
	BossServiceUtils.ApplyRuntimeModelAttributes(
		nextModel,
		self.id,
		self.bossId,
		self.displayName,
		self.encounterChannel
	)

	self.model = nextModel
	self.rootPart = nextRootPart
	self.isSpawned = true
	self.modelValue.Value = nextModel
	self.spawnedValue.Value = true
	local maid = self.maid :: any
	maid.runtimeModel = nextModel
	self:MarkSnapshotDirty()
	self.signals.modelChanged:Fire(nextModel, previousModel)

	return nextModel
end

function Boss.Spawn(self: Boss, spawnCFrameRaw: any?): Model
	if self.isDestroyed then
		error("[Boss] Cannot spawn destroyed instance")
	end
	if self.isSpawned and self.model ~= nil then
		return self.model
	end

	local modelTemplate = self.modelTemplate
	if modelTemplate == nil then
		modelTemplate = self:GetModelTemplate(self.presentation.phaseModel)
	end
	if modelTemplate == nil then
		error(MISSING_ASSET_ERROR, 0)
	end

	local model = modelTemplate:Clone()
	model.Name = self.displayName
	model.Parent = self:GetOrCreateRuntimeFolder()
	configureModel(model)

	self.model = model
	self.rootPart = BossServiceUtils.GetRootPart(model)
	if self.rootPart ~= nil and model.PrimaryPart == nil then
		model.PrimaryPart = self.rootPart
	end

	local spawnCFrame = if typeof(spawnCFrameRaw) == "CFrame"
		then spawnCFrameRaw
		else BossServiceUtils.LookCFrame(self.position, self.facing)
	self.position = self:ProjectToPlane(spawnCFrame.Position)
	self:SetFacing(spawnCFrame.LookVector)
	self.isSpawned = true
	self.modelValue.Value = model
	self.spawnedValue.Value = true
	local maid = self.maid :: any
	maid.runtimeModel = model

	self:UpdateModelPivot()
	BossServiceUtils.ApplyRuntimeModelAttributes(model, self.id, self.bossId, self.displayName, self.encounterChannel)
	self:MarkSnapshotDirty()
	self.signals.spawned:Fire(model)
	self.signals.modelChanged:Fire(model, nil)

	return model
end

function Boss.TakeDamage(self: Boss, damageRaw: any, sourceRaw: any?, _contextRaw: any?): number
	if self.isDestroyed or not self.isAlive then
		return 0
	end
	if self.state == "Death" then
		return 0
	end

	local incomingDamage = BossServiceUtils.CoerceNumber(damageRaw, 0, 0, 10 ^ 9)
	if incomingDamage <= 0 then
		return 0
	end

	local appliedDamage = math.max(1, math.floor(incomingDamage - self.defense + 0.5))
	self.hp = math.max(0, self.hp - appliedDamage)
	self.healthValue.Value = self.hp
	self:IncrementPresentationToken("damagePulseToken")
	self.signals.damaged:Fire(appliedDamage, sourceRaw, self.hp)
	self:MarkSnapshotDirty()

	if typeof(sourceRaw) == "Instance" and sourceRaw:IsA("Player") then
		self:SetTarget(sourceRaw)
	end

	local onDamageTaken = (self :: any).OnDamageTaken
	if typeof(onDamageTaken) == "function" then
		onDamageTaken(self, appliedDamage, sourceRaw, self.hp)
	end

	if self.hp <= 0 then
		self:Die("DamageDepleted", sourceRaw)
	end

	return appliedDamage
end

function Boss.Die(self: Boss, reasonRaw: any?, killerRaw: any?)
	if self.state == "Death" then
		return
	end

	self.isAlive = false
	self.hp = 0
	self.healthValue.Value = self.hp
	self.aliveValue.Value = false
	self.offenseEnabled = false
	self.contactDamageActive = false
	self:SetPresentationFlag("isDying", true)
	self:IncrementPresentationToken("deathPulseToken")
	self:ChangeState("Death", reasonRaw or "death")
	self.signals.died:Fire(killerRaw)

	local onDeath = (self :: any).OnDeath
	if typeof(onDeath) == "function" then
		onDeath(self, killerRaw)
	end
end

function Boss.Despawn(self: Boss, reasonRaw: any?)
	self.offenseEnabled = false
	self.contactDamageActive = false
	self:SetPresentationFlag("isDespawning", true)
	self:ChangeState("Despawn", reasonRaw or "despawn")
end

function Boss.RequestRemoval(self: Boss, reasonRaw: any?)
	self.removeRequested = true
	self.removeReason = trim(reasonRaw)
	if self.removeReason == "" then
		self.removeReason = "removeRequested"
	end
	self.removeRequestedValue.Value = true
	self.signals.removed:Fire(self.removeReason)
end

function Boss.GetClockTime(self: Boss): number
	return self.service:GetClockTime()
end

function Boss.IsNightTime(self: Boss): boolean
	return BossServiceUtils.IsNightClockTime(self:GetClockTime())
end

function Boss.IsDayTime(self: Boss): boolean
	return not self:IsNightTime()
end

function Boss.GetSurfaceYAt(self: Boss, worldPosition: Vector3): number?
	return self.service:GetSurfaceYAtWorldPosition(worldPosition)
end

function Boss.IsPlayerAboveSurface(self: Boss, player: Player): boolean
	return self.service:IsPlayerAboveSurface(player)
end

function Boss.CreateSnapshot(self: Boss): BossSnapshot
	local createSnapshot = (self.service :: any).CreateSnapshot
	if typeof(createSnapshot) ~= "function" then
		error("[Boss] Service must expose CreateSnapshot() before snapshot observation can be used")
	end

	return createSnapshot(self.service, self)
end

function Boss.ObserveState(self: Boss): ObservableObject
	return getOrCreateObservable(self, "state", function()
		return self.stateValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObservePhase(self: Boss): ObservableObject
	return getOrCreateObservable(self, "phase", function()
		return self.phaseValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveHealth(self: Boss): ObservableObject
	return getOrCreateObservable(self, "health", function()
		return self.healthValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveHealthRatio(self: Boss): ObservableObject
	return getOrCreateObservable(self, "healthRatio", function()
		return self:ObserveHealth():Pipe({
			Rx.map(function()
				return self:GetHealthRatio()
			end),
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveTarget(self: Boss): ObservableObject
	return getOrCreateObservable(self, "target", function()
		return self.targetValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveModel(self: Boss): ObservableObject
	return getOrCreateObservable(self, "model", function()
		return self.modelValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveModelBrio(self: Boss): ObservableObject
	return getOrCreateObservable(self, "modelBrio", function()
		return self.modelValue
			:ObserveBrio(function(model)
				return model ~= nil
			end)
			:Pipe({
				Rx.share(),
			}) :: ObservableObject
	end)
end

function Boss.ObserveSpawned(self: Boss): ObservableObject
	return getOrCreateObservable(self, "spawned", function()
		return self.spawnedValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveAlive(self: Boss): ObservableObject
	return getOrCreateObservable(self, "alive", function()
		return self.aliveValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveDestroyed(self: Boss): ObservableObject
	return getOrCreateObservable(self, "destroyed", function()
		return self.destroyedValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveRemovalRequested(self: Boss): ObservableObject
	return getOrCreateObservable(self, "removeRequested", function()
		return self.removeRequestedValue:Observe():Pipe({
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveStateChanged(self: Boss): ObservableObject
	return getOrCreateObservable(self, "stateChangedEvent", function()
		return Rx.fromSignal(self.signals.stateChanged):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveTargetChanged(self: Boss): ObservableObject
	return getOrCreateObservable(self, "targetChangedEvent", function()
		return Rx.fromSignal(self.signals.targetChanged):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveDamaged(self: Boss): ObservableObject
	return getOrCreateObservable(self, "damagedEvent", function()
		return Rx.fromSignal(self.signals.damaged):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveRemoved(self: Boss): ObservableObject
	return getOrCreateObservable(self, "removedEvent", function()
		return Rx.fromSignal(self.signals.removed):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveDied(self: Boss): ObservableObject
	return getOrCreateObservable(self, "diedEvent", function()
		return Rx.fromSignal(self.signals.died):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveSpawnedEvent(self: Boss): ObservableObject
	return getOrCreateObservable(self, "spawnedEvent", function()
		return Rx.fromSignal(self.signals.spawned):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveModelChanged(self: Boss): ObservableObject
	return getOrCreateObservable(self, "modelChangedEvent", function()
		return Rx.fromSignal(self.signals.modelChanged):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveSnapshotDirty(self: Boss): ObservableObject
	return getOrCreateObservable(self, "snapshotDirtyEvent", function()
		return Rx.fromSignal(self.signals.snapshotDirty):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.ObserveSnapshot(self: Boss): ObservableObject
	return getOrCreateObservable(self, "snapshot", function()
		return Rx.fromSignal(self.signals.snapshotDirty):Pipe({
			Rx.startWith({ self:CreateSnapshot() }),
			Rx.map(function()
				return self:CreateSnapshot()
			end),
			Rx.shareReplay(1),
		}) :: ObservableObject
	end)
end

function Boss.ObserveDestroying(self: Boss): ObservableObject
	return getOrCreateObservable(self, "destroyingEvent", function()
		return Rx.fromSignal(self.signals.destroying):Pipe({
			Rx.share(),
		}) :: ObservableObject
	end)
end

function Boss.GetStateSignal(self: Boss): RxSignalObject
	return getOrCreateRxSignal(self, "stateSignal", function()
		return RxSignal.new(function()
			return self:ObserveState()
		end) :: RxSignalObject
	end)
end

function Boss.GetModelSignal(self: Boss): RxSignalObject
	return getOrCreateRxSignal(self, "modelSignal", function()
		return RxSignal.new(function()
			return self:ObserveModel()
		end) :: RxSignalObject
	end)
end

function Boss.GetRemovedSignal(self: Boss): RxSignalObject
	return getOrCreateRxSignal(self, "removedSignal", function()
		return RxSignal.new(function()
			return self:ObserveRemoved()
		end) :: RxSignalObject
	end)
end

function Boss.GetSnapshotSignal(self: Boss): RxSignalObject
	return getOrCreateRxSignal(self, "snapshotSignal", function()
		return RxSignal.new(function()
			return self:ObserveSnapshot()
		end) :: RxSignalObject
	end)
end

function Boss.PromiseState(self: Boss, desiredStateRaw: any, cancelTokenRaw: any?): PromiseObject
	local desiredState = if typeof(desiredStateRaw) == "string" and desiredStateRaw ~= ""
		then desiredStateRaw
		else self.state
	if self.state == desiredState then
		return fulfilledPromise(self.state, self.state, self.lastReason) :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveStateChanged():Pipe({
			Rx.where(function(nextState)
				return nextState == desiredState
			end),
			Rx.take(1),
		}),
		GetCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseModel(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.model ~= nil then
		return fulfilledPromise(self.model) :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveModel():Pipe({
			Rx.where(function(model)
				return model ~= nil
			end),
			Rx.take(1),
		}),
		GetCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseSpawned(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.model ~= nil then
		return fulfilledPromise(self.model) :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveSpawnedEvent():Pipe({
			Rx.take(1),
		}),
		GetCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseDied(self: Boss, cancelTokenRaw: any?): PromiseObject
	if not self.isAlive or self.state == "Death" then
		return fulfilledPromise() :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveDied():Pipe({
			Rx.take(1),
		}),
		GetCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseRemoved(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.removeRequested then
		return fulfilledPromise(self.removeReason) :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveRemoved():Pipe({
			Rx.take(1),
		}),
		GetCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseDestroyed(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.isDestroyed then
		return fulfilledPromise() :: PromiseObject
	end

	return Rx.toPromise(
		self:ObserveDestroying():Pipe({
			Rx.take(1),
		}),
		GetCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.SpawnPromise(self: Boss, spawnCFrameRaw: any?): PromiseObject
	return Promise.spawn(function(fulfill, reject)
		local ok, result = pcall(function()
			return self:Spawn(spawnCFrameRaw)
		end)
		if ok then
			fulfill(result)
		else
			reject(result)
		end
	end) :: PromiseObject
end

function Boss.ReplaceModelPromise(self: Boss, phaseModelRaw: any?): PromiseObject
	return Promise.spawn(function(fulfill, reject)
		local ok, result = pcall(function()
			return self:ReplaceModel(phaseModelRaw)
		end)
		if ok then
			fulfill(result)
		else
			reject(result)
		end
	end) :: PromiseObject
end

function Boss.Step(self: Boss, dtRaw: any)
	if self.isDestroyed then
		return
	end

	local dt = BossServiceUtils.CoerceNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end

	self.stateTime += dt

	local targetPlayer = self.targetPlayer
	if targetPlayer ~= nil then
		if not BossServiceUtils.IsPlayerAlive(targetPlayer) then
			self.targetLostTime += dt
			if self.targetLostTime >= BossServiceUtils.CoerceNumber(self.config.targetLostGraceSeconds, 4, 0, 60) then
				self:ClearTarget()
			end
		else
			self.targetLostTime = 0
		end
	end

	local onStep = (self :: any).OnStep
	if typeof(onStep) == "function" then
		onStep(self, dt)
	end

	self:IntegrateMotion(dt)

	if self.faceVelocityWhenMoving and self.velocity.Magnitude > 1e-4 then
		self:SetFacing(self.velocity)
	elseif self.faceTargetWhenIdle and self.targetPlayer ~= nil then
		local targetPosition = self:GetTargetPosition()
		if targetPosition ~= nil then
			self:LookAt(targetPosition)
		end
	end

	self:UpdateModelPivot()
	self:ApplyContactDamage(self.contactDamage, self.contactDamageRadius, self.contactDamageCooldown)
end

function Boss.Destroy(self: Boss)
	if self.isDestroyed then
		return
	end

	self.isDestroyed = true
	self.isSpawned = false
	self.isAlive = false
	self.aliveValue.Value = false
	self.destroyedValue.Value = true
	self.spawnedValue.Value = false
	self.modelValue.Value = nil
	self.signals.destroying:Fire()

	self.model = nil
	self.rootPart = nil
	self.maid:Destroy()
end
return Boss
