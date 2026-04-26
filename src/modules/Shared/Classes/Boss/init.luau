--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local CancelToken = loader("CancelToken")
local Promise = loader("Promise")
local Rx = loader("Rx")
local RxSignal = loader("RxSignal")
local Signal = loader("Signal")
local ValueObject = loader("ValueObject")
local Maid = loader("Maid")
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)

type BossId = BossServiceUtils.BossId
type BossEncounterState = BossServiceUtils.BossEncounterState
type BossRegistryEntry = BossServiceUtils.BossRegistryEntry
type BossMotionState = BossServiceUtils.BossMotionState
type BossPresentationState = BossServiceUtils.BossPresentationState
type BossSnapshot = BossServiceUtils.BossSnapshot
type BossSpawnRequest = BossServiceUtils.BossSpawnRequest

type MaidClass = {
	Add: <T>(self: MaidClass, task: T) -> T,
	GiveTask: (self: MaidClass, task: any) -> number,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
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

type PromiseObject = {
	Then: (self: PromiseObject, onFulfilled: ((...any) -> ...any)?, onRejected: ((...any) -> ...any)?) -> PromiseObject,
	Catch: (self: PromiseObject, onRejected: ((...any) -> ...any)?) -> PromiseObject,
	Finally: (self: PromiseObject, callback: ((...any) -> ...any)?) -> PromiseObject,
	Yield: (self: PromiseObject) -> (boolean, ...any),
	Destroy: (self: PromiseObject) -> (),
}

type RxSignalObject = {
	Connect: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Once: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Wait: (self: RxSignalObject) -> ...any,
}

type ValueObjectClass<T> = {
	Value: T,
	Observe: (self: ValueObjectClass<T>) -> ObservableObject,
	ObserveBrio: (self: ValueObjectClass<T>, condition: ((T) -> boolean)?) -> ObservableObject,
	Destroy: (self: ValueObjectClass<T>) -> (),
}

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
local DEFAULT_FALLBACK_PART_SIZE = Vector3.new(8, 8, 8)
local GENERATED_FALLBACK_ASSET_WARNINGS = {}

local function trim(valueRaw: any): string
	return BossServiceUtils.trim(valueRaw)
end

local function resolveBossAssetRoot(): Instance?
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

local function getOrCreateBossAssetRoot(): Instance
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets == nil then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = ReplicatedStorage
	end

	local npcs = assets:FindFirstChild("Npcs")
	if npcs == nil then
		npcs = Instance.new("Folder")
		npcs.Name = "Npcs"
		npcs.Parent = assets
	end

	local bosses = npcs:FindFirstChild("Bosses")
	if bosses == nil then
		bosses = Instance.new("Folder")
		bosses.Name = "Bosses"
		bosses.Parent = npcs
	end

	return bosses
end

local function resolveFirstModel(instance: Instance?): Model?
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

local function resolvePhaseModelFromContainer(phaseContainer: Instance?, definition: BossRegistryEntry): Model?
	if phaseContainer == nil then
		return nil
	end

	local exactById = findChildCaseInsensitive(phaseContainer, definition.id)
	local exactByDisplayName = findChildCaseInsensitive(phaseContainer, definition.displayName)
	local resolvedExact = resolveFirstModel(exactById) or resolveFirstModel(exactByDisplayName)
	if resolvedExact ~= nil then
		return resolvedExact
	end

	return resolveFirstModel(phaseContainer)
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

local function createInvisiblePosePart(name: string, localPosition: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(localPosition)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

local function createDecorativeOrb(
	name: string,
	size: Vector3,
	localPosition: Vector3,
	color: Color3,
	transparency: number
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.CFrame = CFrame.new(localPosition)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	return part
end

local function populateEyeSegments(model: Model, segmentCount: number, radius: number)
	for index = 1, segmentCount do
		local angle = ((index - 1) / segmentCount) * math.pi * 2
		local segment = createDecorativeOrb(
			tostring(index),
			Vector3.new(1.6, 1.6, 1.6),
			Vector3.new(0, math.sin(angle) * radius, math.cos(angle) * radius * 0.5),
			Color3.fromRGB(222, 227, 231),
			0.18
		)
		segment.Parent = model
	end
end

local function populateInitialPoses(initialPosesFolder: Folder, poseCount: number, baseRadius: number)
	for index = 1, poseCount do
		local angle = ((index - 1) / math.max(1, poseCount)) * math.pi * 2
		local marker = createInvisiblePosePart(
			tostring(index),
			Vector3.new(0, math.sin(angle) * baseRadius * 0.35, math.cos(angle) * baseRadius)
		)
		marker.Parent = initialPosesFolder
	end
end

local function createBuiltInEyeOfCthulhuPhaseModel(phaseName: string): Model
	local isPhase2 = string.lower(phaseName) == "phase2"
	local rootSize = if isPhase2 then Vector3.new(16, 16, 16) else Vector3.new(14, 14, 14)
	local irisSize = if isPhase2 then Vector3.new(6.25, 6.25, 1.2) else Vector3.new(6.75, 6.75, 1.4)
	local pupilSize = if isPhase2 then Vector3.new(2.5, 2.5, 0.85) else Vector3.new(3.1, 3.1, 1)
	local poseCount = if isPhase2 then 8 else 10

	local model = Instance.new("Model")
	model.Name = "EyeOfCthulhu"

	local rootPart = createDecorativeOrb("RootPart", rootSize, Vector3.zero, Color3.fromRGB(238, 242, 245), 0)
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	local eyeShell = createDecorativeOrb(
		"Eye",
		rootSize - Vector3.new(1.2, 1.2, 1.2),
		Vector3.new(0, 0, -0.3),
		Color3.fromRGB(228, 232, 236),
		0.05
	)
	eyeShell.Parent = model

	local iris =
		createDecorativeOrb("Iris", irisSize, Vector3.new(0, 0, -(rootSize.Z * 0.46)), Color3.fromRGB(191, 55, 55), 0)
	iris.Parent = model

	local pupil =
		createDecorativeOrb("Pupil", pupilSize, Vector3.new(0, 0, -(rootSize.Z * 0.54)), Color3.fromRGB(18, 16, 16), 0)
	pupil.Parent = model

	if isPhase2 then
		local jaw = createDecorativeOrb(
			"Jaw",
			Vector3.new(7.5, 4.75, 1.35),
			Vector3.new(0, -(rootSize.Y * 0.23), -(rootSize.Z * 0.42)),
			Color3.fromRGB(132, 34, 34),
			0
		)
		jaw.Parent = model
	end

	populateEyeSegments(model, poseCount, rootSize.Y * 0.44)

	local initialPoses = Instance.new("Folder")
	initialPoses.Name = "InitialPoses"
	initialPoses.Parent = model
	populateInitialPoses(initialPoses, poseCount, rootSize.Y * 0.48)

	local animationController = Instance.new("AnimationController")
	animationController.Name = "AnimationController"
	animationController.Parent = model

	return model
end

local function ensureBuiltInBossHierarchy(definition: BossRegistryEntry, phaseModelNameRaw: any?): Model?
	if definition.id ~= "EyeOfCthulhu" then
		return nil
	end

	local bossAssetRoot = getOrCreateBossAssetRoot()
	local bossFolder = findChildCaseInsensitive(bossAssetRoot, definition.id)
	if bossFolder == nil then
		local nextFolder = Instance.new("Folder")
		nextFolder.Name = definition.id
		nextFolder.Parent = bossAssetRoot
		bossFolder = nextFolder
	end

	local phaseModelName = trim(phaseModelNameRaw)
	if phaseModelName == "" then
		phaseModelName = "Phase1"
	end

	local phaseContainer = findChildCaseInsensitive(bossFolder, phaseModelName)
	if phaseContainer == nil then
		local nextPhaseContainer = Instance.new("Folder")
		nextPhaseContainer.Name = phaseModelName
		nextPhaseContainer.Parent = bossFolder
		phaseContainer = nextPhaseContainer
	end

	local existingModel = resolvePhaseModelFromContainer(phaseContainer, definition)
	if existingModel ~= nil then
		return existingModel
	end

	local builtInModel = createBuiltInEyeOfCthulhuPhaseModel(phaseModelName)
	builtInModel.Parent = phaseContainer

	if GENERATED_FALLBACK_ASSET_WARNINGS[definition.id] ~= true then
		GENERATED_FALLBACK_ASSET_WARNINGS[definition.id] = true
	end

	return builtInModel
end

local function resolveBossModelTemplate(definition: BossRegistryEntry, phaseModelNameRaw: any?): Model?
	local root = resolveBossAssetRoot()
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
			local phaseModel = resolvePhaseModelFromContainer(phaseContainer, definition)
			if phaseModel ~= nil then
				return phaseModel
			end
		end

		local resolved = resolveFirstModel(cursor)
		if resolved ~= nil then
			return resolved
		end

		local normalizedBossName = BossServiceUtils.normalizeToken(definition.id)
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Model") and BossServiceUtils.normalizeToken(descendant.Name) == normalizedBossName then
				return descendant
			end
		end
	end

	return ensureBuiltInBossHierarchy(definition, phaseModelName)
end

local function createFallbackModel(displayName: string): Model
	local model = Instance.new("Model")
	model.Name = displayName

	local rootPart = Instance.new("Part")
	rootPart.Name = "RootPart"
	rootPart.Shape = Enum.PartType.Ball
	rootPart.Size = DEFAULT_FALLBACK_PART_SIZE
	rootPart.Color = Color3.fromRGB(201, 53, 53)
	rootPart.Material = Enum.Material.SmoothPlastic
	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = true
	rootPart.Parent = model

	model.PrimaryPart = rootPart
	return model
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

local function resolveCancelToken(cancelTokenRaw: any): any?
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
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local modelTemplate = resolveBossModelTemplate(definition, "Phase1")
	local spawnPosition = if typeof(spawnRequest.spawnPosition) == "Vector3"
		then spawnRequest.spawnPosition
		else Vector3.zero
	local maid = Maid.new() :: MaidClass
	local maxHp = BossServiceUtils.sanitizeNumber(config.maxHp, 1, 1, 10 ^ 9)
	local targetPlayer = if typeof(spawnRequest.targetPlayer) == "Instance" and spawnRequest.targetPlayer:IsA("Player")
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
	local stateValue = ValueObject.new("Dormant" :: BossEncounterState, "string") :: ValueObjectClass<BossEncounterState>
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
		defense = BossServiceUtils.sanitizeNumber(config.defense, 0, 0, 10 ^ 6),
		baseDefense = BossServiceUtils.sanitizeNumber(config.defense, 0, 0, 10 ^ 6),
		contactDamage = BossServiceUtils.sanitizeNumber(config.contactDamage, 0, 0, 10 ^ 6),
		baseContactDamage = BossServiceUtils.sanitizeNumber(config.contactDamage, 0, 0, 10 ^ 6),
		offenseEnabled = true,
		contactDamageActive = false,
		contactDamageRadius = BossServiceUtils.sanitizeNumber(config.contactDamageRadius, 8, 0, 512),
		contactDamageCooldown = BossServiceUtils.sanitizeNumber(config.contactDamageCooldown, 0.35, 0, 30),
		faceVelocityWhenMoving = BossServiceUtils.sanitizeBoolean(config.faceVelocityWhenMoving, true),
		faceTargetWhenIdle = BossServiceUtils.sanitizeBoolean(config.faceTargetWhenIdle, true),
		chargeIndex = 0,
		position = BossServiceUtils.projectPositionToPlaneX(spawnPosition, spawnRequest.planeX),
		velocity = Vector3.zero,
		facing = Vector3.zAxis,
		targetPlayer = targetPlayer,
		targetUserId = BossServiceUtils.resolveTargetPlayerUserId(targetPlayer),
		targetLostTime = 0,
		lastSnapshotAt = nowClock(),
		snapshotDirty = true,
		presentation = BossServiceUtils.createDefaultPresentation(),
		motion = BossServiceUtils.createDefaultMotionState(),
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

function Boss.ResolveModelTemplate(self: Boss, phaseModelNameRaw: any?): Model?
	local modelTemplate = resolveBossModelTemplate(self.definition, phaseModelNameRaw)
	if modelTemplate ~= nil then
		self.modelTemplate = modelTemplate
		return modelTemplate
	end

	return self.modelTemplate
end

function Boss.GetOrCreateRuntimeFolder(self: Boss): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(DEFAULT_BOSS_FOLDER_NAME)
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

	if targetPlayer ~= nil and not BossServiceUtils.isPlayerAlive(targetPlayer) then
		targetPlayer = nil
	end

	if self.targetPlayer == targetPlayer then
		return targetPlayer ~= nil
	end

	local previousTarget = self.targetPlayer
	self.targetPlayer = targetPlayer
	self.targetUserId = BossServiceUtils.resolveTargetPlayerUserId(targetPlayer)
	self.targetLostTime = 0
	self.targetValue.Value = targetPlayer
	self:markSnapshotDirty()
	self.signals.targetChanged:Fire(targetPlayer, previousTarget)
	return targetPlayer ~= nil
end

function Boss.ClearTarget(self: Boss)
	self:setTarget(nil)
end

function Boss.ResolveTargetRootPart(self: Boss): BasePart?
	return BossServiceUtils.resolveCharacterRootPart(self.targetPlayer)
end

function Boss.ResolveTargetPosition(self: Boss): Vector3?
	local rootPart = self:resolveTargetRootPart()
	if rootPart == nil then
		return nil
	end
	return BossServiceUtils.projectPositionToPlaneX(rootPart.Position, self.planeX)
end

function Boss.ResolveTargetVelocity(self: Boss): Vector3
	if self.targetPlayer == nil then
		return Vector3.zero
	end
	return BossServiceUtils.projectVectorToPlaneX(
		BossServiceUtils.resolveCharacterVelocity(self.targetPlayer),
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
	self:markSnapshotDirty()
	self.signals.stateChanged:Fire(self.state, previousState, reason)

	local onStateChanged = (self :: any).onStateChanged
	if typeof(onStateChanged) == "function" then
		onStateChanged(self, self.state, previousState, reason)
	end
end

function Boss.SetPhase(self: Boss, nextPhaseRaw: any, phaseModelRaw: any?)
	local nextPhase = math.max(0, math.floor(BossServiceUtils.sanitizeNumber(nextPhaseRaw, self.phase, 0, 32)))
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
	self:markSnapshotDirty()

	if modelChanged and self.isSpawned then
		self:replaceModel(phaseModel)
	end
end

function Boss.IncrementPresentationToken(self: Boss, tokenName: string)
	local currentValue = (self.presentation :: any)[tokenName]
	if typeof(currentValue) ~= "number" then
		return
	end
	(self.presentation :: any)[tokenName] = currentValue + 1
	self:markSnapshotDirty()
end

function Boss.SetPresentationFlag(self: Boss, flagName: string, enabledRaw: any)
	local enabled = enabledRaw == true
	local currentValue = (self.presentation :: any)[flagName]
	if typeof(currentValue) ~= "boolean" or currentValue == enabled then
		return
	end

	(self.presentation :: any)[flagName] = enabled
	self:markSnapshotDirty()
end

function Boss.SetMotionState(self: Boss, motionRaw: any)
	self.motion = BossServiceUtils.sanitizeMotionState(motionRaw, self.motion)
	self:markSnapshotDirty()
end

function Boss.ProjectToPlane(self: Boss, position: Vector3): Vector3
	return BossServiceUtils.projectPositionToPlaneX(position, self.planeX)
end

function Boss.SetPosition(self: Boss, positionRaw: any)
	if typeof(positionRaw) ~= "Vector3" then
		return
	end

	self.position = self:projectToPlane(positionRaw)
	self:markSnapshotDirty()
end

function Boss.SetVelocity(self: Boss, velocityRaw: any)
	if typeof(velocityRaw) ~= "Vector3" then
		self.velocity = Vector3.zero
	else
		self.velocity = BossServiceUtils.projectVectorToPlaneX(velocityRaw, self.planeX)
	end
	self:markSnapshotDirty()
end

function Boss.SetFacing(self: Boss, facingRaw: any)
	if typeof(facingRaw) ~= "Vector3" then
		return
	end

	self.facing = BossServiceUtils.computeFacingVector(self.position, facingRaw, self.facing)
	self:markSnapshotDirty()
end

function Boss.LookAt(self: Boss, targetPositionRaw: any)
	if typeof(targetPositionRaw) ~= "Vector3" then
		return
	end
	self:setFacing(targetPositionRaw - self.position)
end

function Boss.AccelerateTowardVelocity(self: Boss, desiredVelocityRaw: any, accelerationRaw: any, dtRaw: any)
	if typeof(desiredVelocityRaw) ~= "Vector3" then
		return
	end

	local desiredVelocity = BossServiceUtils.projectVectorToPlaneX(desiredVelocityRaw, self.planeX)
	local acceleration = BossServiceUtils.sanitizeNumber(accelerationRaw, 0, 0, 10 ^ 6)
	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
	self.velocity = BossServiceUtils.moveTowardsVector(self.velocity, desiredVelocity, acceleration * dt)
	self:markSnapshotDirty()
end

function Boss.DampVelocity(self: Boss, dampingPerSecondRaw: any, dtRaw: any)
	local dampingPerSecond = BossServiceUtils.sanitizeNumber(dampingPerSecondRaw, 0, 0, 10 ^ 6)
	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
	local alpha = math.clamp(1 - dampingPerSecond * dt, 0, 1)
	self.velocity *= alpha
	self:markSnapshotDirty()
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

	local targetPosition = self:projectToPlane(targetPositionRaw)
	local offset = targetPosition - self.position
	local desiredVelocity = if offset.Magnitude > 1e-4
		then offset.Unit * BossServiceUtils.sanitizeNumber(maxSpeedRaw, 0, 0, 10 ^ 6)
		else Vector3.zero

	self:accelerateTowardVelocity(desiredVelocity, accelerationRaw, dtRaw)
	self:dampVelocity(dampingRaw, dtRaw)
	return true
end

function Boss.IntegrateMotion(self: Boss, dtRaw: any)
	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
	self.position = self:projectToPlane(self.position + self.velocity * dt)
	self.motion.position = self.position
	self.motion.velocity = self.velocity
	self:markSnapshotDirty()
end

function Boss.ApplyContactDamage(self: Boss, damageRaw: any?, radiusRaw: any?, cooldownRaw: any?)
	if not self.offenseEnabled or not self.contactDamageActive then
		return
	end

	local damage = BossServiceUtils.sanitizeNumber(damageRaw, self.contactDamage, 0, 10 ^ 6)
	if damage <= 0 then
		return
	end

	local radius = BossServiceUtils.sanitizeNumber(radiusRaw, self.contactDamageRadius, 0, 512)
	local cooldown = BossServiceUtils.sanitizeNumber(cooldownRaw, self.contactDamageCooldown, 0, 30)
	local currentTime = self.service:getNow()

	for _, player in Players:GetPlayers() do
		if not BossServiceUtils.isPlayerAlive(player) then
			continue
		end

		local rootPart = BossServiceUtils.resolveCharacterRootPart(player)
		if rootPart == nil then
			continue
		end

		if (self.position - self:projectToPlane(rootPart.Position)).Magnitude > radius then
			continue
		end

		local lastDamageAt = self.damageCooldownByUserId[player.UserId] or -math.huge
		if currentTime - lastDamageAt < cooldown then
			continue
		end

		if self.service:damagePlayer(player, damage, self) ~= nil then
			self.damageCooldownByUserId[player.UserId] = currentTime
		end
	end
end

function Boss.UpdateModelPivot(self: Boss)
	local model = self.model
	if model == nil then
		return
	end

	model:PivotTo(BossServiceUtils.lookCFrame(self.position, self.facing))
	configureModel(model)
	self.rootPart = BossServiceUtils.resolveRootPart(model)
	if self.rootPart ~= nil and model.PrimaryPart == nil then
		model.PrimaryPart = self.rootPart
	end
end

function Boss.ReplaceModel(self: Boss, phaseModelRaw: any?): Model?
	if self.isDestroyed then
		return nil
	end

	local previousModel = self.model
	local modelTemplate = self:resolveModelTemplate(phaseModelRaw)
	if modelTemplate == nil then
		return self.model
	end

	local nextModel = modelTemplate:Clone()
	nextModel.Name = self.displayName
	nextModel.Parent = self:getOrCreateRuntimeFolder()
	configureModel(nextModel)

	local nextRootPart = BossServiceUtils.resolveRootPart(nextModel)
	if nextRootPart ~= nil and nextModel.PrimaryPart == nil then
		nextModel.PrimaryPart = nextRootPart
	end

	nextModel:PivotTo(BossServiceUtils.lookCFrame(self.position, self.facing))
	BossServiceUtils.applyRuntimeModelAttributes(
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
	self:markSnapshotDirty()
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
		modelTemplate = self:resolveModelTemplate(self.presentation.phaseModel)
	end

	local model = if modelTemplate ~= nil then modelTemplate:Clone() else createFallbackModel(self.displayName)
	model.Name = self.displayName
	model.Parent = self:getOrCreateRuntimeFolder()
	configureModel(model)

	self.model = model
	self.rootPart = BossServiceUtils.resolveRootPart(model)
	if self.rootPart ~= nil and model.PrimaryPart == nil then
		model.PrimaryPart = self.rootPart
	end

	local spawnCFrame = if typeof(spawnCFrameRaw) == "CFrame"
		then spawnCFrameRaw
		else BossServiceUtils.lookCFrame(self.position, self.facing)
	self.position = self:projectToPlane(spawnCFrame.Position)
	self.facing = spawnCFrame.LookVector
	self.isSpawned = true
	self.modelValue.Value = model
	self.spawnedValue.Value = true
	local maid = self.maid :: any
	maid.runtimeModel = model

	self:updateModelPivot()
	BossServiceUtils.applyRuntimeModelAttributes(model, self.id, self.bossId, self.displayName, self.encounterChannel)
	self:markSnapshotDirty()
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

	local incomingDamage = BossServiceUtils.sanitizeNumber(damageRaw, 0, 0, 10 ^ 9)
	if incomingDamage <= 0 then
		return 0
	end

	local appliedDamage = math.max(1, math.floor(incomingDamage - self.defense + 0.5))
	self.hp = math.max(0, self.hp - appliedDamage)
	self.healthValue.Value = self.hp
	self:incrementPresentationToken("damagePulseToken")
	self.signals.damaged:Fire(appliedDamage, sourceRaw, self.hp)
	self:markSnapshotDirty()

	if typeof(sourceRaw) == "Instance" and sourceRaw:IsA("Player") then
		self:setTarget(sourceRaw)
	end

	local onDamageTaken = (self :: any).onDamageTaken
	if typeof(onDamageTaken) == "function" then
		onDamageTaken(self, appliedDamage, sourceRaw, self.hp)
	end

	if self.hp <= 0 then
		self:die("DamageDepleted", sourceRaw)
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
	self:setPresentationFlag("isDying", true)
	self:incrementPresentationToken("deathPulseToken")
	self:changeState("Death", reasonRaw or "death")
	self.signals.died:Fire(killerRaw)

	local onDeath = (self :: any).onDeath
	if typeof(onDeath) == "function" then
		onDeath(self, killerRaw)
	end
end

function Boss.Despawn(self: Boss, reasonRaw: any?)
	self.offenseEnabled = false
	self.contactDamageActive = false
	self:setPresentationFlag("isDespawning", true)
	self:changeState("Despawn", reasonRaw or "despawn")
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
	return self.service:getClockTime()
end

function Boss.IsNightTime(self: Boss): boolean
	return BossServiceUtils.isNightClockTime(self:getClockTime())
end

function Boss.IsDayTime(self: Boss): boolean
	return not self:isNightTime()
end

function Boss.GetSurfaceYAt(self: Boss, worldPosition: Vector3): number?
	return self.service:getSurfaceYAtWorldPosition(worldPosition)
end

function Boss.IsPlayerAboveSurface(self: Boss, player: Player): boolean
	return self.service:isPlayerAboveSurface(player)
end

function Boss.CreateSnapshot(self: Boss): BossSnapshot
	local createSnapshot = (self.service :: any).createSnapshot
	if typeof(createSnapshot) ~= "function" then
		error("[Boss] Service must expose createSnapshot() before snapshot observation can be used")
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
		return self:observeHealth():Pipe({
			Rx.map(function()
				return self:getHealthRatio()
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
		return self.modelValue:ObserveBrio(function(model)
			return model ~= nil
		end):Pipe({
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
			Rx.startWith({ self:createSnapshot() }),
			Rx.map(function()
				return self:createSnapshot()
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
			return self:observeState()
		end) :: RxSignalObject
	end)
end

function Boss.GetModelSignal(self: Boss): RxSignalObject
	return getOrCreateRxSignal(self, "modelSignal", function()
		return RxSignal.new(function()
			return self:observeModel()
		end) :: RxSignalObject
	end)
end

function Boss.GetRemovedSignal(self: Boss): RxSignalObject
	return getOrCreateRxSignal(self, "removedSignal", function()
		return RxSignal.new(function()
			return self:observeRemoved()
		end) :: RxSignalObject
	end)
end

function Boss.GetSnapshotSignal(self: Boss): RxSignalObject
	return getOrCreateRxSignal(self, "snapshotSignal", function()
		return RxSignal.new(function()
			return self:observeSnapshot()
		end) :: RxSignalObject
	end)
end

function Boss.PromiseState(self: Boss, desiredStateRaw: any, cancelTokenRaw: any?): PromiseObject
	local desiredState = if typeof(desiredStateRaw) == "string" and desiredStateRaw ~= ""
		then desiredStateRaw
		else self.state
	if self.state == desiredState then
		return Promise.resolved(self.state, self.state, self.lastReason) :: PromiseObject
	end

	return Rx.toPromise(
		self:observeStateChanged():Pipe({
			Rx.where(function(nextState)
				return nextState == desiredState
			end),
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseModel(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.model ~= nil then
		return Promise.resolved(self.model) :: PromiseObject
	end

	return Rx.toPromise(
		self:observeModel():Pipe({
			Rx.where(function(model)
				return model ~= nil
			end),
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseSpawned(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.model ~= nil then
		return Promise.resolved(self.model) :: PromiseObject
	end

	return Rx.toPromise(
		self:observeSpawnedEvent():Pipe({
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseDied(self: Boss, cancelTokenRaw: any?): PromiseObject
	if not self.isAlive or self.state == "Death" then
		return Promise.resolved() :: PromiseObject
	end

	return Rx.toPromise(
		self:observeDied():Pipe({
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseRemoved(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.removeRequested then
		return Promise.resolved(self.removeReason) :: PromiseObject
	end

	return Rx.toPromise(
		self:observeRemoved():Pipe({
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.PromiseDestroyed(self: Boss, cancelTokenRaw: any?): PromiseObject
	if self.isDestroyed then
		return Promise.resolved() :: PromiseObject
	end

	return Rx.toPromise(
		self:observeDestroying():Pipe({
			Rx.take(1),
		}),
		resolveCancelToken(cancelTokenRaw)
	) :: PromiseObject
end

function Boss.SpawnPromise(self: Boss, spawnCFrameRaw: any?): PromiseObject
	return Promise.spawn(function(resolve, reject)
		local ok, result = pcall(function()
			return self:spawn(spawnCFrameRaw)
		end)
		if ok then
			resolve(result)
		else
			reject(result)
		end
	end) :: PromiseObject
end

function Boss.ReplaceModelPromise(self: Boss, phaseModelRaw: any?): PromiseObject
	return Promise.spawn(function(resolve, reject)
		local ok, result = pcall(function()
			return self:replaceModel(phaseModelRaw)
		end)
		if ok then
			resolve(result)
		else
			reject(result)
		end
	end) :: PromiseObject
end

function Boss.Step(self: Boss, dtRaw: any)
	if self.isDestroyed then
		return
	end

	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end

	self.stateTime += dt

	local targetPlayer = self.targetPlayer
	if targetPlayer ~= nil then
		if not BossServiceUtils.isPlayerAlive(targetPlayer) then
			self.targetLostTime += dt
			if self.targetLostTime >= BossServiceUtils.sanitizeNumber(self.config.targetLostGraceSeconds, 4, 0, 60) then
				self:clearTarget()
			end
		else
			self.targetLostTime = 0
		end
	end

	local onStep = (self :: any).onStep
	if typeof(onStep) == "function" then
		onStep(self, dt)
	end

	self:integrateMotion(dt)

	if self.faceVelocityWhenMoving and self.velocity.Magnitude > 1e-4 then
		self:setFacing(self.velocity)
	elseif self.faceTargetWhenIdle and self.targetPlayer ~= nil then
		local targetPosition = self:resolveTargetPosition()
		if targetPosition ~= nil then
			self:lookAt(targetPosition)
		end
	end

	self:updateModelPivot()
	self:applyContactDamage(self.contactDamage, self.contactDamageRadius, self.contactDamageCooldown)
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

Boss.new = Boss.New
Boss.resolveModelTemplate = Boss.ResolveModelTemplate
Boss.getOrCreateRuntimeFolder = Boss.GetOrCreateRuntimeFolder
Boss.markSnapshotDirty = Boss.MarkSnapshotDirty
Boss.setTarget = Boss.SetTarget
Boss.clearTarget = Boss.ClearTarget
Boss.resolveTargetRootPart = Boss.ResolveTargetRootPart
Boss.resolveTargetPosition = Boss.ResolveTargetPosition
Boss.resolveTargetVelocity = Boss.ResolveTargetVelocity
Boss.getHealthRatio = Boss.GetHealthRatio
Boss.changeState = Boss.ChangeState
Boss.setPhase = Boss.SetPhase
Boss.incrementPresentationToken = Boss.IncrementPresentationToken
Boss.setPresentationFlag = Boss.SetPresentationFlag
Boss.setMotionState = Boss.SetMotionState
Boss.projectToPlane = Boss.ProjectToPlane
Boss.setPosition = Boss.SetPosition
Boss.setVelocity = Boss.SetVelocity
Boss.setFacing = Boss.SetFacing
Boss.lookAt = Boss.LookAt
Boss.accelerateTowardVelocity = Boss.AccelerateTowardVelocity
Boss.dampVelocity = Boss.DampVelocity
Boss.moveTowardPoint = Boss.MoveTowardPoint
Boss.integrateMotion = Boss.IntegrateMotion
Boss.applyContactDamage = Boss.ApplyContactDamage
Boss.updateModelPivot = Boss.UpdateModelPivot
Boss.replaceModel = Boss.ReplaceModel
Boss.spawn = Boss.Spawn
Boss.takeDamage = Boss.TakeDamage
Boss.die = Boss.Die
Boss.despawn = Boss.Despawn
Boss.requestRemoval = Boss.RequestRemoval
Boss.getClockTime = Boss.GetClockTime
Boss.isNightTime = Boss.IsNightTime
Boss.isDayTime = Boss.IsDayTime
Boss.getSurfaceYAt = Boss.GetSurfaceYAt
Boss.isPlayerAboveSurface = Boss.IsPlayerAboveSurface
Boss.createSnapshot = Boss.CreateSnapshot
Boss.observeState = Boss.ObserveState
Boss.observePhase = Boss.ObservePhase
Boss.observeHealth = Boss.ObserveHealth
Boss.observeHealthRatio = Boss.ObserveHealthRatio
Boss.observeTarget = Boss.ObserveTarget
Boss.observeModel = Boss.ObserveModel
Boss.observeModelBrio = Boss.ObserveModelBrio
Boss.observeSpawned = Boss.ObserveSpawned
Boss.observeAlive = Boss.ObserveAlive
Boss.observeDestroyed = Boss.ObserveDestroyed
Boss.observeRemovalRequested = Boss.ObserveRemovalRequested
Boss.observeStateChanged = Boss.ObserveStateChanged
Boss.observeTargetChanged = Boss.ObserveTargetChanged
Boss.observeDamaged = Boss.ObserveDamaged
Boss.observeRemoved = Boss.ObserveRemoved
Boss.observeDied = Boss.ObserveDied
Boss.observeSpawnedEvent = Boss.ObserveSpawnedEvent
Boss.observeModelChanged = Boss.ObserveModelChanged
Boss.observeSnapshotDirty = Boss.ObserveSnapshotDirty
Boss.observeSnapshot = Boss.ObserveSnapshot
Boss.observeDestroying = Boss.ObserveDestroying
Boss.getStateSignal = Boss.GetStateSignal
Boss.getModelSignal = Boss.GetModelSignal
Boss.getRemovedSignal = Boss.GetRemovedSignal
Boss.getSnapshotSignal = Boss.GetSnapshotSignal
Boss.promiseState = Boss.PromiseState
Boss.promiseModel = Boss.PromiseModel
Boss.promiseSpawned = Boss.PromiseSpawned
Boss.promiseDied = Boss.PromiseDied
Boss.promiseRemoved = Boss.PromiseRemoved
Boss.promiseDestroyed = Boss.PromiseDestroyed
Boss.spawnPromise = Boss.SpawnPromise
Boss.replaceModelPromise = Boss.ReplaceModelPromise
Boss.step = Boss.Step
Boss.destroy = Boss.Destroy

return Boss
