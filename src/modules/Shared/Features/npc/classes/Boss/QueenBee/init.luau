--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Maid = loader("Maid")
local Rx = loader("Rx")
local Signal = loader("Signal")

local BossBase = require(script.Parent)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Features.npc.BossServiceUtils)
local Bee = require(script.Bee)
local Configs = require(script.Configs)
local Physics = require(script.Physics)
local Render = require(script.Render)
local Stinger = require(script.Stinger)

type Boss = BossBase.Boss
type BossRegistryEntry = BossServiceUtils.BossRegistryEntry
type BossSpawnRequest = BossServiceUtils.BossSpawnRequest
type QueenBeeConfig = Configs.QueenBeeConfig

local QueenBee = {}
QueenBee.__index = QueenBee

local QueenBeeBossController = {}
QueenBeeBossController.__index = QueenBeeBossController
setmetatable(QueenBeeBossController, { __index = BossBase })

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type Services = {
	damagePlayer: ((player: Player, damage: number, owner: any?) -> any)?,
	onRenderState: ((state: any) -> ())?,
	onDespawn: ((queenBee: any, reason: string) -> ())?,
	projectileParent: Instance?,
	beeParent: Instance?,
	random: Random?,
}

export type QueenBeeNewConfig = {
	model: Model?,
	rootPart: BasePart?,
	parent: Instance?,
	projectileParent: Instance?,
	beeParent: Instance?,
	arenaCFrame: CFrame?,
	spawnCFrame: CFrame?,
	config: any?,
	services: Services?,
	hp: number?,
	maxHp: number?,
	randomSeed: number?,
}

export type QueenBee = typeof(setmetatable(
	{} :: {
		model: Model?,
		rootPart: BasePart?,
		ownsModel: boolean,
		config: Configs.QueenBeeConfig,
		services: Services,
		projectileParent: Instance?,
		beeParent: Instance?,
		arenaCFrame: CFrame?,
		position: Vector3,
		velocity: Vector3,
		facingSign: number,
		targetPlayer: Player?,
		targetUserId: number?,
		state: Configs.QueenBeeState,
		phase: number,
		enraged: boolean,
		hp: number,
		maxHp: number,
		stateTime: number,
		started: boolean,
		destroyed: boolean,
		chargeIndex: number,
		hoverPoint: Vector3?,
		chargeDirection: Vector3?,
		chargeStartPosition: Vector3?,
		chargeTargetPosition: Vector3?,
		targetLostTime: number,
		targetValid: boolean,
		lastKnownTargetPosition: Vector3?,
		lastKnownTargetVelocity: Vector3,
		attackCursor: number,
		sideSign: number,
		sideInitialized: boolean,
		contactDamageActive: boolean,
		damageCooldownByUserId: { [number]: number },
		random: Random,
		maid: MaidClass,
		runningMaid: MaidClass,
		stateMaid: MaidClass,
		projectileMaid: MaidClass,
		beeMaid: MaidClass,
		stateChanged: SignalObject,
		phaseChanged: SignalObject,
		targetChanged: SignalObject,
		healthChanged: SignalObject,
		renderStateChanged: SignalObject,
		lastHealthSample: number,
		lastMaxHealthSample: number,
	},
	QueenBee
))

export type QueenBeeBossController = Boss & {
	_queenConfig: QueenBeeConfig,
	_simulationSpeed: number,
	_aggressiveness: number,
	_sideSign: number,
	_nextChargeDelay: number,
	_chargeDirection: Vector3?,
}

local DEFAULT_MAX_HP = 3400
local DEFAULT_HP = DEFAULT_MAX_HP
local MISSING_ASSET_ERROR = "no asset found!"
local UPRIGHT_FACING = Vector3.zAxis

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function safeUnit(vector: Vector3, fallbackRaw: Vector3?): Vector3
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else Vector3.zAxis
	if vector.Magnitude <= 1e-5 then
		if fallback.Magnitude <= 1e-5 then
			return Vector3.zAxis
		end
		return fallback.Unit
	end
	return vector.Unit
end

local function resolveHorizontalFacing(direction: Vector3, fallbackRaw: Vector3?): Vector3
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else UPRIGHT_FACING
	if math.abs(direction.Z) <= 1e-3 then
		return if fallback.Z < 0 then -Vector3.zAxis else Vector3.zAxis
	end
	return if direction.Z < 0 then -Vector3.zAxis else Vector3.zAxis
end

local function setBossSpriteFacing(self: QueenBeeBossController, direction: Vector3)
	self:setFacing(resolveHorizontalFacing(direction, self.facing))
end

local function dampVelocity(velocity: Vector3, dampingRaw: any, dtRaw: any): Vector3
	local damping = sanitizeNumber(dampingRaw, 0, 0, 1000)
	local dt = sanitizeNumber(dtRaw, 0, 0, 1)
	if damping <= 0 or dt <= 0 then
		return velocity
	end
	return velocity * math.exp(-damping * dt)
end

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local rootPart = model:FindFirstChild("RootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function resolveModelAndRoot(config: QueenBeeNewConfig): (Model?, BasePart?, boolean)
	local model = if typeof(config.model) == "Instance" and config.model:IsA("Model") then config.model else nil
	local rootPart = if typeof(config.rootPart) == "Instance" and config.rootPart:IsA("BasePart")
		then config.rootPart
		else nil

	if model == nil and rootPart ~= nil then
		local parentModel = rootPart:FindFirstAncestorOfClass("Model")
		if parentModel ~= nil then
			model = parentModel
		end
	end

	if rootPart == nil then
		rootPart = resolveRootPart(model)
	end

	if model ~= nil and rootPart ~= nil and model.PrimaryPart == nil then
		model.PrimaryPart = rootPart
	end

	if rootPart ~= nil then
		return model, rootPart, false
	end

	error(MISSING_ASSET_ERROR, 0)
end

local function getAliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

local function setAttribute(instance: Instance?, name: string, value: any)
	if instance == nil then
		return
	end
	instance:SetAttribute(name, value)
end

local function resolveServices(config: QueenBeeNewConfig): Services
	if typeof(config.services) == "table" then
		return config.services :: Services
	end
	return {}
end

local function resolveRandom(config: QueenBeeNewConfig, services: Services): Random
	if services.random ~= nil then
		return services.random
	end

	if typeof(config.randomSeed) == "number" then
		return Random.new(config.randomSeed)
	end
	return Random.new()
end

local function resolveArenaCFrame(config: QueenBeeNewConfig, rootPart: BasePart?): CFrame?
	if typeof(config.arenaCFrame) == "CFrame" then
		return config.arenaCFrame
	end
	if rootPart == nil then
		return nil
	end
	return CFrame.new(Vector3.new(rootPart.Position.X, 0, 0))
end

local function resolveRuntimeParent(configParent: Instance?, serviceParent: Instance?): Instance?
	if configParent ~= nil then
		return configParent
	end
	return serviceParent
end

local function resolveBossDefaultConfig(serviceRaw: any, bossId: string): any?
	local defaultConfigByBossId = if typeof(serviceRaw) == "table" then (serviceRaw :: any).defaultConfigByBossId else nil
	if typeof(defaultConfigByBossId) ~= "table" then
		return nil
	end

	local config = (defaultConfigByBossId :: any)[bossId]
	if typeof(config) == "table" then
		return config
	end
	return nil
end

local function getPhaseNumberValue(values: { [number]: number }, phaseRaw: any, fallback: number): number
	local phase = math.clamp(math.floor(sanitizeNumber(phaseRaw, 1, 1, 3)), 1, 3)
	return sanitizeNumber(values[phase], fallback, 0, nil)
end

local function resolveBossSideSign(spawnRequest: BossSpawnRequest): number
	local targetPlayer = spawnRequest.targetPlayer
	if targetPlayer ~= nil then
		local velocity = BossServiceUtils.resolveCharacterVelocity(targetPlayer)
		if velocity.Z < -1e-3 then
			return 1
		end
		if velocity.Z > 1e-3 then
			return -1
		end

		local rootPart = BossServiceUtils.resolveCharacterRootPart(targetPlayer)
		if rootPart ~= nil and typeof(spawnRequest.spawnPosition) == "Vector3" then
			return if (spawnRequest.spawnPosition :: Vector3).Z < rootPart.Position.Z then -1 else 1
		end
	end

	return 1
end

local function resolveBossInitialSpawnRequest(spawnRequestRaw: BossSpawnRequest, config: QueenBeeConfig): BossSpawnRequest
	local resolved: BossSpawnRequest = {
		bossId = spawnRequestRaw.bossId,
		targetPlayer = spawnRequestRaw.targetPlayer,
		spawnSource = spawnRequestRaw.spawnSource,
		encounterChannel = spawnRequestRaw.encounterChannel,
		spawnPosition = spawnRequestRaw.spawnPosition,
		planeX = spawnRequestRaw.planeX,
		simulationSpeed = spawnRequestRaw.simulationSpeed,
		aggressiveness = spawnRequestRaw.aggressiveness,
		expertBehaviorEnabled = spawnRequestRaw.expertBehaviorEnabled,
	}

	if resolved.targetPlayer == nil then
		return resolved
	end

	local rootPart = BossServiceUtils.resolveCharacterRootPart(resolved.targetPlayer)
	if rootPart == nil then
		return resolved
	end

	if resolved.planeX == nil then
		resolved.planeX = rootPart.Position.X
	end
	if resolved.spawnPosition == nil then
		local sideSign = resolveBossSideSign(resolved)
		resolved.spawnPosition = BossServiceUtils.projectPositionToPlaneX(
			rootPart.Position + Vector3.new(0, config.HoverAboveOffset + 10, config.HoverSideDistance * sideSign),
			resolved.planeX
		)
	end

	return resolved
end

local function rollBossDelay(self: QueenBeeBossController, minimum: number, maximum: number): number
	local randomObject = (self.service :: any).random
	if randomObject ~= nil then
		return randomObject:NextNumber(minimum, maximum)
	end
	return minimum + (maximum - minimum) * math.random()
end

local function resolveBossAggression(self: QueenBeeBossController): number
	return math.clamp(sanitizeNumber(self._aggressiveness, 1, 0.1, 3), 0.1, 3)
end

local function scaleBossSpeed(self: QueenBeeBossController, speed: number): number
	return speed * resolveBossAggression(self)
end

local function scaleBossDuration(self: QueenBeeBossController, duration: number): number
	return duration / math.sqrt(resolveBossAggression(self))
end

local function rollNextChargeDelay(self: QueenBeeBossController): number
	local config = self._queenConfig
	local baseDelay = getPhaseNumberValue(config.ChargeRepositionMaxTimeByPhase, self.phase, 1.2)
	return scaleBossDuration(self, rollBossDelay(self, baseDelay * 0.75, baseDelay * 1.2))
end

local function resolveBossHoverAnchor(self: QueenBeeBossController): Vector3
	local config = self._queenConfig
	local targetPosition = self:resolveTargetPosition()
	if targetPosition == nil then
		return self.position + Vector3.new(0, math.sin(self.stateTime * 2.25) * 1.2, 0)
	end

	local targetVelocity = self:resolveTargetVelocity()
	if targetVelocity.Z > 2 then
		self._sideSign = -1
	elseif targetVelocity.Z < -2 then
		self._sideSign = 1
	end

	return targetPosition
		+ Vector3.new(0, config.HoverAboveOffset, config.HoverSideDistance * self._sideSign)
end

local function setBossMotionDebug(
	self: QueenBeeBossController,
	motionOwner: string,
	hoverAnchor: Vector3?,
	chargeTimeRemaining: number?
)
	self:setMotionState({
		state = self.state,
		position = self.position,
		velocity = self.velocity,
		hoverAnchor = hoverAnchor,
		distanceToAnchor = if hoverAnchor ~= nil then (hoverAnchor - self.position).Magnitude else nil,
		lockedChargeDirection = self._chargeDirection,
		chargeTimeRemaining = chargeTimeRemaining,
		motionOwner = motionOwner,
		localPresentationOffset = Vector3.new(0, math.sin(self.stateTime * 7.5) * 0.18, 0),
	})
end

local function refreshBossPhase(self: QueenBeeBossController)
	local nextPhase = Configs.ResolvePhase(self.hp, self.maxHp, self._queenConfig)
	if nextPhase ~= self.phase then
		self:setPhase(nextPhase, "Phase1")
	end
end

local function beginBossCharge(self: QueenBeeBossController)
	local config = self._queenConfig
	local targetPosition = self:resolveTargetPosition()
	if targetPosition == nil then
		targetPosition = self.position + self.facing * 128
	end

	local targetVelocity = self:resolveTargetVelocity()
	local predictedPosition = targetPosition + targetVelocity * config.ChargePredictionTime
	local direction = safeUnit(predictedPosition - self.position, self.facing)
	self._chargeDirection = direction
	self.chargeIndex += 1
	setBossSpriteFacing(self, direction)
	self:setVelocity(direction * scaleBossSpeed(self, getPhaseNumberValue(config.ChargeSpeedByPhase, self.phase, 118)))
	self:incrementPresentationToken("dashPulseToken")
	self:changeState("Phase1Charge", "Charge")
end

function QueenBee.CreateBossController(
	service: any,
	definition: BossRegistryEntry,
	spawnRequestRaw: BossSpawnRequest
): QueenBeeBossController
	local config = Configs.Resolve(resolveBossDefaultConfig(service, definition.id))
	local spawnRequest = resolveBossInitialSpawnRequest(spawnRequestRaw, config)
	local base = BossBase.new(service, definition, spawnRequest, {
		maxHp = DEFAULT_MAX_HP,
		defense = 8,
		contactDamage = config.ContactDamage,
		contactDamageRadius = config.ContactHitRadius,
		contactDamageCooldown = config.ContactCooldown,
		faceVelocityWhenMoving = false,
		faceTargetWhenIdle = false,
		targetLostGraceSeconds = config.TargetLostGraceTime,
	})
	local self = setmetatable(base :: any, QueenBeeBossController) :: QueenBeeBossController

	self._queenConfig = config
	self._simulationSpeed = sanitizeNumber(spawnRequestRaw.simulationSpeed, 1, 0.05, 5)
	self._aggressiveness = sanitizeNumber(spawnRequestRaw.aggressiveness, 1, 0.1, 3)
	self._sideSign = resolveBossSideSign(spawnRequest)
	self._nextChargeDelay = rollNextChargeDelay(self)
	self._chargeDirection = nil

	self:setPhase(1, "Phase1")
	return self
end

function QueenBeeBossController:GetSimulationSpeed(): number
	return self._simulationSpeed
end

function QueenBeeBossController:AfterSpawn()
	self:setTarget(self.spawnRequest.targetPlayer or self.service:resolveEncounterTarget(self))
	self:changeState("Phase1Hover", "Spawn")
end

function QueenBeeBossController:OnStateChanged(nextState: string, _previousState: string, _reason: string)
	self.contactDamageActive = nextState == "Phase1Charge"
	self:setPresentationFlag("isHurtWindowActive", nextState ~= "Phase1Charge" and nextState ~= "Death")
	self:setPresentationFlag("isRoaring", nextState == "Phase1ChargeWindup")
end

function QueenBeeBossController:OnDamageTaken(_damage: number, _sourceRaw: any?, _hp: number)
	refreshBossPhase(self)
end

function QueenBeeBossController:OnDeath(_killerRaw: any?)
	self._chargeDirection = nil
	self:setVelocity(Vector3.zero)
end

function QueenBeeBossController:UpdateModelPivot()
	local model = self.model
	if model == nil then
		return
	end

	model:PivotTo(CFrame.new(self.position))
	self.rootPart = BossServiceUtils.resolveRootPart(model)
	if self.rootPart ~= nil and model.PrimaryPart == nil then
		model.PrimaryPart = self.rootPart
	end
end

function QueenBeeBossController:StepHover(dt: number)
	local config = self._queenConfig
	local hoverAnchor = resolveBossHoverAnchor(self)
	self:moveTowardPoint(
		hoverAnchor,
		scaleBossSpeed(self, getPhaseNumberValue(config.HoverSpeedByPhase, self.phase, 36)),
		scaleBossSpeed(self, getPhaseNumberValue(config.HoverAccelerationByPhase, self.phase, 165)),
		config.HoverDamping,
		dt
	)

	local targetPosition = self:resolveTargetPosition()
	setBossMotionDebug(self, "QueenBeeHover", hoverAnchor, nil)

	if targetPosition ~= nil and self.stateTime >= self._nextChargeDelay then
		self:changeState("Phase1ChargeWindup", "ChargeWindup")
	end
end

function QueenBeeBossController:StepChargeWindup(dt: number)
	self:dampVelocity(6, dt)

	local windupDuration =
		scaleBossDuration(self, getPhaseNumberValue(self._queenConfig.ChargeWindupByPhase, self.phase, 0.52))
	setBossMotionDebug(self, "QueenBeeChargeWindup", nil, math.max(0, windupDuration - self.stateTime))
	if self.stateTime >= windupDuration then
		beginBossCharge(self)
	end
end

function QueenBeeBossController:StepCharge(_dt: number)
	local config = self._queenConfig
	local direction = safeUnit(self._chargeDirection or self.facing, self.facing)
	local speed = scaleBossSpeed(self, getPhaseNumberValue(config.ChargeSpeedByPhase, self.phase, 118))
	local duration = scaleBossDuration(self, getPhaseNumberValue(config.ChargeDurationByPhase, self.phase, 0.72))
	self:setVelocity(direction * speed)
	setBossSpriteFacing(self, direction)
	setBossMotionDebug(self, "QueenBeeCharge", nil, math.max(0, duration - self.stateTime))

	if self.stateTime >= duration then
		self:changeState("Phase1Recovery", "ChargeComplete")
	end
end

function QueenBeeBossController:StepRecovery(dt: number)
	self._chargeDirection = nil
	self:dampVelocity(4.5, dt)
	setBossMotionDebug(self, "QueenBeeRecovery", nil, nil)
	if self.stateTime >= self._queenConfig.PostChargeRecoverTime then
		self._sideSign *= -1
		self._nextChargeDelay = rollNextChargeDelay(self)
		self:changeState("Phase1Hover", "RecoveryComplete")
	end
end

function QueenBeeBossController:StepDespawn(dt: number)
	local targetPosition = self:resolveTargetPosition()
	local direction = if targetPosition ~= nil then safeUnit(self.position - targetPosition, self.facing) else self.facing
	self:accelerateTowardVelocity(direction * self._queenConfig.DespawnSpeed, self._queenConfig.DespawnAcceleration, dt)
	setBossMotionDebug(self, "QueenBeeDespawn", nil, nil)
	if self.stateTime >= self._queenConfig.DespawnDuration then
		self:requestRemoval("DespawnComplete")
	end
end

function QueenBeeBossController:StepDeath(dt: number)
	self:dampVelocity(4.5, dt)
	setBossMotionDebug(self, "QueenBeeDeath", nil, nil)
	if self.stateTime >= 1.6 then
		self:requestRemoval("DeathComplete")
	end
end

function QueenBeeBossController:OnStep(dt: number)
	if self.targetPlayer == nil then
		self:setTarget(self.service:resolveEncounterTarget(self))
	end

	refreshBossPhase(self)

	if self.state == "Phase1Hover" then
		self:stepHover(dt)
		return
	end
	if self.state == "Phase1ChargeWindup" then
		self:stepChargeWindup(dt)
		return
	end
	if self.state == "Phase1Charge" then
		self:stepCharge(dt)
		return
	end
	if self.state == "Phase1Recovery" then
		self:stepRecovery(dt)
		return
	end
	if self.state == "Despawn" then
		self:stepDespawn(dt)
		return
	end
	if self.state == "Death" then
		self:stepDeath(dt)
		return
	end
end

function QueenBee.New(configRaw: QueenBeeNewConfig?): QueenBee
	local raw = (if typeof(configRaw) == "table" then configRaw else {}) :: any
	local model, rootPart, ownsModel = resolveModelAndRoot(raw)
	local services = resolveServices(raw)
	local config = Configs.Resolve(if raw.config ~= nil then raw.config else raw)
	local maxHp = sanitizeNumber(raw.maxHp, DEFAULT_MAX_HP, 1, 10 ^ 9)
	local hp = sanitizeNumber(raw.hp, DEFAULT_HP, 0, maxHp)
	local spawnPosition = if rootPart ~= nil then rootPart.Position else Vector3.zero
	local arenaCFrame = resolveArenaCFrame(raw, rootPart)
	local maid = Maid.new() :: MaidClass
	local runningMaid = Maid.new() :: MaidClass
	local stateMaid = Maid.new() :: MaidClass
	local projectileMaid = Maid.new() :: MaidClass
	local beeMaid = Maid.new() :: MaidClass
	local stateChanged = Signal.new() :: SignalObject
	local phaseChanged = Signal.new() :: SignalObject
	local targetChanged = Signal.new() :: SignalObject
	local healthChanged = Signal.new() :: SignalObject
	local renderStateChanged = Signal.new() :: SignalObject

	maid:GiveTask(runningMaid)
	maid:GiveTask(stateMaid)
	maid:GiveTask(projectileMaid)
	maid:GiveTask(beeMaid)
	maid:GiveTask(stateChanged)
	maid:GiveTask(phaseChanged)
	maid:GiveTask(targetChanged)
	maid:GiveTask(healthChanged)
	maid:GiveTask(renderStateChanged)
	if ownsModel and model ~= nil then
		maid:GiveTask(model)
	end

	local self = setmetatable({
		model = model,
		rootPart = rootPart,
		ownsModel = ownsModel,
		config = config,
		services = services,
		projectileParent = resolveRuntimeParent(raw.projectileParent, services.projectileParent),
		beeParent = resolveRuntimeParent(raw.beeParent, services.beeParent),
		arenaCFrame = arenaCFrame,
		position = Physics.ProjectToCombatPlane(spawnPosition, arenaCFrame),
		velocity = Vector3.zero,
		facingSign = 1,
		targetPlayer = nil,
		targetUserId = nil,
		state = Configs.States.AcquireTarget,
		phase = Configs.ResolvePhase(hp, maxHp, config),
		enraged = false,
		hp = hp,
		maxHp = maxHp,
		stateTime = 0,
		started = false,
		destroyed = false,
		chargeIndex = 0,
		hoverPoint = nil,
		chargeDirection = nil,
		chargeStartPosition = nil,
		chargeTargetPosition = nil,
		targetLostTime = 0,
		targetValid = false,
		lastKnownTargetPosition = nil,
		lastKnownTargetVelocity = Vector3.zero,
		attackCursor = 0,
		sideSign = 1,
		sideInitialized = false,
		contactDamageActive = false,
		damageCooldownByUserId = {},
		random = resolveRandom(raw, services),
		maid = maid,
		runningMaid = runningMaid,
		stateMaid = stateMaid,
		projectileMaid = projectileMaid,
		beeMaid = beeMaid,
		stateChanged = stateChanged,
		phaseChanged = phaseChanged,
		targetChanged = targetChanged,
		healthChanged = healthChanged,
		renderStateChanged = renderStateChanged,
		lastHealthSample = hp,
		lastMaxHealthSample = maxHp,
	}, QueenBee) :: QueenBee

	self:_applyDebugAttributes()
	return self
end

function QueenBee._configureModel(self: QueenBee)
	local model = self.model
	local rootPart = self.rootPart

	if model ~= nil then
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

	if rootPart ~= nil then
		rootPart.Anchored = true
		rootPart.CanCollide = false
		rootPart.CanTouch = false
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function QueenBee._applyDebugAttributes(self: QueenBee)
	for _, instance in { self.model, self.rootPart } do
		setAttribute(instance, "QueenBeeState", self.state)
		setAttribute(instance, "QueenBeePhase", self.phase)
		setAttribute(instance, "QueenBeeEnraged", self.enraged)
		setAttribute(instance, "QueenBeeTargetUserId", self.targetUserId)
		setAttribute(instance, "QueenBeeChargeIndex", self.chargeIndex)
	end
end

function QueenBee._emitHealthIfChanged(self: QueenBee)
	if self.hp == self.lastHealthSample and self.maxHp == self.lastMaxHealthSample then
		return
	end

	self.lastHealthSample = self.hp
	self.lastMaxHealthSample = self.maxHp
	self.healthChanged:Fire(self.hp, self.maxHp)
end

function QueenBee._setPhase(self: QueenBee, phase: number, reason: string?)
	if phase ~= 1 and phase ~= 2 and phase ~= 3 then
		return
	end

	if self.phase == phase then
		return
	end

	local previousPhase = self.phase
	self.phase = phase
	self.phaseChanged:Fire(phase, previousPhase, reason)
	self:_applyDebugAttributes()

	if self.state == Configs.States.StingerHover then
		self:_bindStingerCadence()
	elseif self.state == Configs.States.BeeSummonHover then
		self:_bindBeeSummonCadence()
	end
end

function QueenBee._setEnraged(self: QueenBee, enraged: boolean)
	if self.enraged == enraged then
		return
	end

	self.enraged = enraged
	self:_applyDebugAttributes()

	if self.state == Configs.States.StingerHover then
		self:_bindStingerCadence()
	elseif self.state == Configs.States.BeeSummonHover then
		self:_bindBeeSummonCadence()
	end
end

function QueenBee._updateEnrage(self: QueenBee)
	local healthRatio = if self.maxHp > 0 then math.clamp(self.hp / self.maxHp, 0, 1) else 0
	local ok, result = pcall(function()
		return self.config.IsEnraged({
			queenBee = self,
			model = self.model,
			rootPart = self.rootPart,
			targetPlayer = self.targetPlayer,
			phase = self.phase,
			healthRatio = healthRatio,
			state = self.state,
			services = self.services,
		})
	end)
	self:_setEnraged(ok and result == true)
end

function QueenBee._getPhaseValue(self: QueenBee, values: { [number]: number }): number
	return values[self.phase] or values[1] or 0
end

function QueenBee._speedMultiplier(self: QueenBee): number
	return if self.enraged then self.config.EnrageSpeedMultiplier else 1
end

function QueenBee._cadenceMultiplier(self: QueenBee): number
	return if self.enraged then self.config.EnrageCadenceMultiplier else 1
end

function QueenBee._scaledSpeed(self: QueenBee, speed: number): number
	return speed * self:_speedMultiplier()
end

function QueenBee._scaledAcceleration(self: QueenBee, acceleration: number): number
	return acceleration * self:_speedMultiplier()
end

function QueenBee._scaledInterval(self: QueenBee, interval: number): number
	return math.max(0.01, interval * self:_cadenceMultiplier())
end

function QueenBee._isPlayerValid(self: QueenBee, player: Player?, range: number): boolean
	if player == nil then
		return false
	end
	if getAliveHumanoid(player) == nil then
		return false
	end

	local targetCenter = Physics.GetTargetCenter(player)
	if targetCenter == nil then
		return false
	end

	local projectedTarget = Physics.ProjectToCombatPlane(targetCenter, self.arenaCFrame)
	local distance = (projectedTarget - self.position).Magnitude
	return distance <= range
end

function QueenBee._findNearestTarget(self: QueenBee, range: number): Player?
	local nearestPlayer: Player? = nil
	local nearestDistance = range

	for _, player in Players:GetPlayers() do
		if not self:_isPlayerValid(player, range) then
			continue
		end

		local targetCenter = Physics.GetTargetCenter(player)
		if targetCenter == nil then
			continue
		end

		local distance = (Physics.ProjectToCombatPlane(targetCenter, self.arenaCFrame) - self.position).Magnitude
		if distance <= nearestDistance then
			nearestDistance = distance
			nearestPlayer = player
		end
	end

	return nearestPlayer
end

function QueenBee._getTargetCenter(self: QueenBee): Vector3?
	local player = self.targetPlayer
	if player == nil then
		return nil
	end

	local center = Physics.GetTargetCenter(player)
	if center == nil then
		return nil
	end

	local projectedCenter = Physics.ProjectToCombatPlane(center, self.arenaCFrame)
	self.lastKnownTargetPosition = projectedCenter
	return projectedCenter
end

function QueenBee._getTargetVelocity(self: QueenBee): Vector3
	local player = self.targetPlayer
	if player == nil then
		return self.lastKnownTargetVelocity
	end

	local velocity = Physics.ProjectVectorToCombatPlane(Physics.GetTargetVelocity(player), self.arenaCFrame)
	self.lastKnownTargetVelocity = velocity
	return velocity
end

function QueenBee._getBestTargetCenter(self: QueenBee): Vector3?
	local center = self:_getTargetCenter()
	if center ~= nil then
		return center
	end
	return self.lastKnownTargetPosition
end

function QueenBee._chooseNextSide(self: QueenBee)
	if not self.sideInitialized then
		local targetCenter = self:_getBestTargetCenter()
		if targetCenter ~= nil then
			local sideVector = Physics.GetCombatSideVector(self.arenaCFrame)
			local sideDot = (self.position - targetCenter):Dot(sideVector)
			self.sideSign = if sideDot >= 0 then 1 else -1
		end
		self.sideInitialized = true
		return
	end

	self.sideSign *= -1
end

function QueenBee._setState(self: QueenBee, nextState: Configs.QueenBeeState, reason: string?)
	local previousState = self.state
	self.state = nextState
	self.stateTime = 0
	self.hoverPoint = nil
	self.stateMaid:DoCleaning()
	self:_applyDebugAttributes()
	self.stateChanged:Fire(nextState, previousState, reason)

	if nextState == Configs.States.ChooseAttack then
		self:_chooseAttack()
		return
	end

	if nextState == Configs.States.ChargeReposition then
		self.contactDamageActive = false
		self:_chooseNextSide()
		return
	end

	if nextState == Configs.States.ChargeWindup then
		self.contactDamageActive = false
		self:_lockChargeDirection()
		return
	end

	if nextState == Configs.States.Charge then
		self.contactDamageActive = true
		self.chargeStartPosition = self.position
		return
	end

	if nextState == Configs.States.PostChargeRecover then
		self.contactDamageActive = false
		self.chargeIndex += 1
		self:_applyDebugAttributes()
		return
	end

	if nextState == Configs.States.StingerHover then
		self.contactDamageActive = false
		self:_chooseNextSide()
		self:_bindStingerCadence()
		return
	end

	if nextState == Configs.States.BeeSummonHover then
		self.contactDamageActive = false
		self:_bindBeeSummonCadence()
		return
	end

	if nextState == Configs.States.Despawn then
		self.contactDamageActive = false
		self.targetPlayer = nil
		self.targetUserId = nil
		self:_applyDebugAttributes()
	end
end

function QueenBee._chooseAttack(self: QueenBee)
	self.attackCursor += 1

	local pattern = if self.phase >= 3
		then { "Charge", "Stinger", "Charge", "Charge", "Bee" }
		else { "Charge", "Stinger", "Charge", "Bee" }
	local selected = pattern[((self.attackCursor - 1) % #pattern) + 1]

	if selected == "Charge" then
		self.chargeIndex = 0
		self:_applyDebugAttributes()
		self:_setState(Configs.States.ChargeReposition, "ChooseChargeCombo")
	elseif selected == "Stinger" then
		self:_setState(Configs.States.StingerHover, "ChooseStingerHover")
	else
		self:_setState(Configs.States.BeeSummonHover, "ChooseBeeSummonHover")
	end
end

function QueenBee._lockChargeDirection(self: QueenBee)
	local targetCenter = self:_getBestTargetCenter()
	if targetCenter == nil then
		self.chargeDirection = Physics.GetCombatSideVector(self.arenaCFrame) * self.sideSign
		self.chargeTargetPosition = self.position + self.chargeDirection * self.config.ChargePassDistance
		return
	end

	local targetVelocity = self:_getTargetVelocity()
	local predicted =
		Physics.ProjectToCombatPlane(targetCenter + targetVelocity * self.config.ChargePredictionTime, self.arenaCFrame)
	local direction = Physics.ProjectVectorToCombatPlane(predicted - self.position, self.arenaCFrame)
	self.chargeTargetPosition = predicted
	self.chargeDirection = safeUnit(direction, Physics.GetCombatSideVector(self.arenaCFrame) * self.sideSign)
	self.facingSign = if self.chargeDirection:Dot(Physics.GetCombatSideVector(self.arenaCFrame)) >= 0 then 1 else -1
end

function QueenBee._bindStingerCadence(self: QueenBee)
	local baseInterval = self:_getPhaseValue(self.config.StingerFireIntervalByPhase)
	local interval = self:_scaledInterval(baseInterval)
	local stateMaid = self.stateMaid :: any
	stateMaid.stingerCadence = Rx.timer(0, interval):Subscribe(function()
		self:_fireStinger()
	end)
end

function QueenBee._bindBeeSummonCadence(self: QueenBee)
	local baseInterval = self:_getPhaseValue(self.config.BeeSpawnIntervalByPhase)
	local interval = self:_scaledInterval(baseInterval)
	local stateMaid = self.stateMaid :: any
	stateMaid.beeCadence = Rx.timer(0, interval):Subscribe(function()
		self:_spawnBeeBurst()
	end)
end

function QueenBee._damagePlayer(self: QueenBee, player: Player, damage: number)
	local callback = self.services.damagePlayer
	if callback ~= nil then
		pcall(function()
			callback(player, damage, self)
		end)
		return
	end

	local humanoid = getAliveHumanoid(player)
	if humanoid ~= nil then
		humanoid:TakeDamage(damage)
	end
end

function QueenBee._fireStinger(self: QueenBee)
	local targetCenter = self:_getBestTargetCenter()
	if targetCenter == nil then
		return
	end

	local origin = self.position
	local targetVelocity = self:_getTargetVelocity()
	local projectile = Stinger.Fire({
		origin = origin,
		targetPlayer = self.targetPlayer,
		targetPosition = targetCenter,
		targetVelocity = targetVelocity,
		predictionTime = self.config.ChargePredictionTime,
		spreadDegrees = self:_getPhaseValue(self.config.StingerSpreadDegreesByPhase),
		speed = self.config.StingerSpeed * self:_speedMultiplier(),
		lifetime = self.config.StingerLifetime,
		owner = self,
		damage = self.config.StingerDamage,
		hitRadius = self.config.StingerHitRadius,
		parent = self.projectileParent,
		arenaCFrame = self.arenaCFrame,
		random = self.random,
		damagePlayer = function(player: Player, damage: number)
			self:_damagePlayer(player, damage)
		end,
	})
	self.projectileMaid:GiveTask(projectile)
end

function QueenBee._spawnBeeBurst(self: QueenBee)
	local count = math.max(0, math.floor(self:_getPhaseValue(self.config.BeeBurstCountByPhase)))
	if count <= 0 then
		return
	end

	local bees = Bee.SpawnBurst({
		count = count,
		spawnRadius = math.max(5, self.config.ContactHitRadius),
		origin = self.position,
		targetPlayer = self.targetPlayer,
		parent = self.beeParent,
		arenaCFrame = self.arenaCFrame,
		owner = self,
		random = self.random,
		lifetime = self.config.BeeLifetime,
		scatterDuration = self.config.BeeScatterDuration,
		scatterSpeed = self.config.BeeScatterSpeed * self:_speedMultiplier(),
		speed = self:_getPhaseValue(self.config.BeeSpeedByPhase) * self:_speedMultiplier(),
		acceleration = self:_getPhaseValue(self.config.BeeAccelerationByPhase) * self:_speedMultiplier(),
		dashSpeed = self:_getPhaseValue(self.config.BeeDashSpeedByPhase) * self:_speedMultiplier(),
		damage = self.config.BeeDamage,
		hitRadius = self.config.BeeHitRadius,
		damagePlayer = function(player: Player, damage: number)
			self:_damagePlayer(player, damage)
		end,
	})

	for _, bee in bees do
		self.beeMaid:GiveTask(bee)
	end
end

function QueenBee._applyContactDamage(self: QueenBee)
	if not self.contactDamageActive then
		return
	end

	local damage = self.config.ContactDamage
	if damage <= 0 then
		return
	end

	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if getAliveHumanoid(player) == nil then
			continue
		end

		local center = Physics.GetTargetCenter(player)
		if center == nil then
			continue
		end

		local projectedCenter = Physics.ProjectToCombatPlane(center, self.arenaCFrame)
		if (projectedCenter - self.position).Magnitude > self.config.ContactHitRadius then
			continue
		end

		local lastHitAt = self.damageCooldownByUserId[player.UserId] or -math.huge
		if now - lastHitAt < self.config.ContactCooldown then
			continue
		end

		self.damageCooldownByUserId[player.UserId] = now
		self:_damagePlayer(player, damage)
	end
end

function QueenBee._updateTargetValidity(self: QueenBee, dtRaw: any)
	if not self.started or self.destroyed then
		return
	end

	local dt = sanitizeNumber(dtRaw, 0, 0, self.config.MaxDt)
	local valid = self:_isPlayerValid(self.targetPlayer, self.config.DespawnRange)
	self.targetValid = valid
	if valid then
		self.targetLostTime = 0
		self:_getTargetCenter()
		self:_getTargetVelocity()
		return
	end

	if self.targetPlayer == nil then
		return
	end

	self.targetLostTime += dt
	if self.targetLostTime < self.config.TargetLostGraceTime then
		return
	end

	self:SetTarget(nil)
	if self.state ~= Configs.States.Despawn then
		self:_setState(Configs.States.AcquireTarget, "TargetLost")
	end
end

function QueenBee._stepAcquireTarget(self: QueenBee)
	local target = self:_findNearestTarget(self.config.AggroRange)
	if target == nil then
		self:_setState(Configs.States.Despawn, "NoTarget")
		return
	end

	self:SetTarget(target)
	self:_setState(Configs.States.ChooseAttack, "TargetAcquired")
end

function QueenBee._stepChargeReposition(self: QueenBee, dt: number)
	local targetCenter = self:_getBestTargetCenter()
	if targetCenter == nil then
		self:_setState(Configs.States.AcquireTarget, "MissingTarget")
		return
	end

	local hoverPoint = Physics.ComputeOffsetInCombatPlane(
		targetCenter,
		self.sideSign,
		self.config.HoverSideDistance,
		self.config.HoverAboveOffset,
		self.arenaCFrame
	)
	self.hoverPoint = hoverPoint

	local speed = self:_scaledSpeed(self:_getPhaseValue(self.config.HoverSpeedByPhase))
	local acceleration = self:_scaledAcceleration(self:_getPhaseValue(self.config.HoverAccelerationByPhase))
	self.velocity = Physics.ComputeHoverVelocity(
		self.position,
		self.velocity,
		hoverPoint,
		speed,
		acceleration,
		self.config.HoverDamping,
		self.config.HoverArriveRadius,
		dt
	)

	local distance = (hoverPoint - self.position).Magnitude
	local maxTime = self:_getPhaseValue(self.config.ChargeRepositionMaxTimeByPhase)
	if distance <= self.config.HoverArriveRadius or self.stateTime >= maxTime then
		self:_setState(Configs.States.ChargeWindup, "RepositionComplete")
	end
end

function QueenBee._stepChargeWindup(self: QueenBee, dt: number)
	local targetCenter = self:_getBestTargetCenter()
	if targetCenter ~= nil then
		self.facingSign = Physics.FaceTarget(self.rootPart, targetCenter)
	end

	self.velocity = dampVelocity(self.velocity, self.config.HoverDamping + 2, dt)

	local windupTime = self:_getPhaseValue(self.config.ChargeWindupByPhase)
	if self.stateTime >= windupTime then
		self:_setState(Configs.States.Charge, "WindupComplete")
	end
end

function QueenBee._stepCharge(self: QueenBee, _dt: number)
	local direction = if self.chargeDirection ~= nil
		then self.chargeDirection
		else Physics.GetCombatSideVector(self.arenaCFrame) * self.sideSign
	local speed = self:_scaledSpeed(self:_getPhaseValue(self.config.ChargeSpeedByPhase))
	self.velocity = Physics.ComputeChargeVelocity(direction, speed)

	local targetPosition = self.chargeTargetPosition or self:_getBestTargetCenter() or (self.position + direction * 16)
	local startPosition = self.chargeStartPosition or self.position
	local finishedByTime = self.stateTime >= self:_getPhaseValue(self.config.ChargeDurationByPhase)
	local finishedByPass =
		Physics.HasPassedTarget(startPosition, self.position, targetPosition, direction, self.config.ChargePassDistance)

	if finishedByTime or finishedByPass then
		self:_setState(Configs.States.PostChargeRecover, "ChargeComplete")
	end
end

function QueenBee._stepPostChargeRecover(self: QueenBee, dt: number)
	self.velocity = dampVelocity(self.velocity, self.config.HoverDamping + 3, dt)

	if self.stateTime < self.config.PostChargeRecoverTime then
		return
	end

	local chargesPerCombo = math.max(1, math.floor(self:_getPhaseValue(self.config.ChargesPerComboByPhase)))
	if self.chargeIndex < chargesPerCombo then
		self:_setState(Configs.States.ChargeReposition, "ContinueChargeCombo")
		return
	end

	self:_setState(Configs.States.ChooseAttack, "ChargeComboComplete")
end

function QueenBee._stepStingerHover(self: QueenBee, dt: number)
	local targetCenter = self:_getBestTargetCenter()
	if targetCenter == nil then
		self:_setState(Configs.States.AcquireTarget, "MissingTarget")
		return
	end

	local hoverPoint = Physics.ComputeOffsetInCombatPlane(
		targetCenter,
		self.sideSign,
		self.config.StingerSideDistance,
		self.config.StingerAboveOffset,
		self.arenaCFrame
	)
	self.hoverPoint = hoverPoint

	local speed =
		self:_scaledSpeed(self:_getPhaseValue(self.config.HoverSpeedByPhase) * self.config.StingerHoverSpeedMultiplier)
	local acceleration = self:_scaledAcceleration(self:_getPhaseValue(self.config.HoverAccelerationByPhase))
	self.velocity = Physics.ComputeHoverVelocity(
		self.position,
		self.velocity,
		hoverPoint,
		speed,
		acceleration,
		self.config.HoverDamping,
		self.config.HoverArriveRadius,
		dt
	)

	self.facingSign = Physics.FaceTarget(self.rootPart, targetCenter)
	if self.stateTime >= self.config.StingerHoverDuration then
		self:_setState(Configs.States.ChooseAttack, "StingerHoverComplete")
	end
end

function QueenBee._stepBeeSummonHover(self: QueenBee, dt: number)
	local targetCenter = self:_getBestTargetCenter()
	if targetCenter == nil then
		self:_setState(Configs.States.AcquireTarget, "MissingTarget")
		return
	end

	local hoverPoint = Physics.ComputeOffsetInCombatPlane(
		targetCenter,
		self.sideSign,
		self.config.BeeSummonSideDistance,
		self.config.BeeSummonAboveOffset,
		self.arenaCFrame
	)
	self.hoverPoint = hoverPoint

	local speed = self:_scaledSpeed(
		self:_getPhaseValue(self.config.HoverSpeedByPhase) * self.config.BeeSummonHoverSpeedMultiplier
	)
	local acceleration = self:_scaledAcceleration(self:_getPhaseValue(self.config.HoverAccelerationByPhase) * 0.72)
	self.velocity = Physics.ComputeHoverVelocity(
		self.position,
		self.velocity,
		hoverPoint,
		speed,
		acceleration,
		self.config.HoverDamping,
		self.config.HoverArriveRadius,
		dt
	)

	self.facingSign = Physics.FaceTarget(self.rootPart, targetCenter)
	if self.stateTime >= self.config.BeeSummonDuration then
		self:_setState(Configs.States.ChooseAttack, "BeeSummonComplete")
	end
end

function QueenBee._stepDespawn(self: QueenBee, dt: number)
	local upVector = Physics.GetCombatUpVector(self.arenaCFrame)
	local sideVector = Physics.GetCombatSideVector(self.arenaCFrame)
	local awaySign = self.sideSign
	local targetPosition = self.lastKnownTargetPosition
	if targetPosition ~= nil then
		local dot = (self.position - targetPosition):Dot(sideVector)
		awaySign = if dot >= 0 then 1 else -1
	end

	local desiredVelocity = upVector * self.config.DespawnSpeed
		+ sideVector * awaySign * self.config.DespawnSpeed * 0.35
	self.velocity = Physics.ApproachVelocity(
		self.velocity,
		desiredVelocity,
		self:_scaledAcceleration(self.config.DespawnAcceleration) * dt
	)

	if self.stateTime >= self.config.DespawnDuration then
		local callback = self.services.onDespawn
		if callback ~= nil then
			pcall(function()
				callback(self, "DespawnComplete")
			end)
		end
		self:Stop()
	end
end

function QueenBee._integrate(self: QueenBee, dt: number)
	self.velocity = Physics.ProjectVectorToCombatPlane(self.velocity, self.arenaCFrame)
	self.position = Physics.ProjectToCombatPlane(self.position + self.velocity * dt, self.arenaCFrame)

	if self.velocity.Magnitude > 0.5 then
		local sideDot = self.velocity:Dot(Physics.GetCombatSideVector(self.arenaCFrame))
		if math.abs(sideDot) > 0.001 then
			self.facingSign = if sideDot >= 0 then 1 else -1
		end
	end

	local cframe = Physics.BuildFacingCFrame(self.position, self.facingSign, self.arenaCFrame)
	if self.model ~= nil then
		self.model:PivotTo(cframe)
		if self.rootPart == nil then
			self.rootPart = resolveRootPart(self.model)
		end
	elseif self.rootPart ~= nil then
		self.rootPart.CFrame = cframe
	end

	if self.rootPart ~= nil then
		self.rootPart.AssemblyLinearVelocity = self.velocity
		self.rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function QueenBee._render(self: QueenBee)
	local targetPosition = self:_getBestTargetCenter()
	local renderContext = {
		model = self.model,
		rootPart = self.rootPart,
		state = self.state,
		phase = self.phase,
		enraged = self.enraged,
		stateTime = self.stateTime,
		velocity = self.velocity,
		facingSign = self.facingSign,
		targetPosition = targetPosition,
		hoverPoint = self.hoverPoint,
		chargeDirection = self.chargeDirection,
		config = self.config,
	}

	Render.Apply(renderContext)
	self.renderStateChanged:Fire(renderContext)

	local callback = self.services.onRenderState
	if callback ~= nil then
		pcall(function()
			callback(renderContext)
		end)
	end
end

function QueenBee._step(self: QueenBee, dtRaw: any)
	if not self.started or self.destroyed then
		return
	end

	local dt = sanitizeNumber(dtRaw, 0, 0, self.config.MaxDt)
	if dt <= 0 then
		return
	end

	self:_emitHealthIfChanged()
	self:_updateEnrage()
	self.stateTime += dt

	local nextPhase = Configs.ResolvePhase(self.hp, self.maxHp, self.config)
	self:_setPhase(nextPhase, "Health")

	if self.state == Configs.States.AcquireTarget then
		self:_stepAcquireTarget()
	elseif self.state == Configs.States.ChargeReposition then
		self:_stepChargeReposition(dt)
	elseif self.state == Configs.States.ChargeWindup then
		self:_stepChargeWindup(dt)
	elseif self.state == Configs.States.Charge then
		self:_stepCharge(dt)
	elseif self.state == Configs.States.PostChargeRecover then
		self:_stepPostChargeRecover(dt)
	elseif self.state == Configs.States.StingerHover then
		self:_stepStingerHover(dt)
	elseif self.state == Configs.States.BeeSummonHover then
		self:_stepBeeSummonHover(dt)
	elseif self.state == Configs.States.Despawn then
		self:_stepDespawn(dt)
	end

	if not self.started then
		return
	end

	self:_integrate(dt)
	self:_applyContactDamage()
	self:_applyDebugAttributes()
	self:_render()
end

function QueenBee._bindReactiveStreams(self: QueenBee)
	self.runningMaid:GiveTask(Rx.fromSignal(self.healthChanged)
		:Pipe({
			Rx.startWith({ self.hp, self.maxHp }),
			Rx.map(function(health: number, maxHealth: number)
				return Configs.ResolvePhase(health, maxHealth, self.config)
			end),
			Rx.distinct(),
		})
		:Subscribe(function(phase: number)
			self:_setPhase(phase, "HealthStream")
		end))

	self.runningMaid:GiveTask(Rx.fromSignal(RunService.Heartbeat):Subscribe(function(dt: number)
		self:_updateTargetValidity(dt)
	end))

	self.runningMaid:GiveTask(Rx.fromSignal(RunService.Heartbeat):Subscribe(function(dt: number)
		self:_step(dt)
	end))
end

function QueenBee.Start(self: QueenBee)
	if self.destroyed or self.started then
		return
	end

	self.started = true
	self.runningMaid:DoCleaning()
	self.stateMaid:DoCleaning()
	self.projectileMaid:DoCleaning()
	self.beeMaid:DoCleaning()
	self:_configureModel()
	self:_bindReactiveStreams()
	self.healthChanged:Fire(self.hp, self.maxHp)
	self:_setState(Configs.States.AcquireTarget, "Start")
end

function QueenBee.Stop(self: QueenBee)
	if not self.started then
		return
	end

	self.started = false
	self.contactDamageActive = false
	self.velocity = Vector3.zero
	self.runningMaid:DoCleaning()
	self.stateMaid:DoCleaning()
	self.projectileMaid:DoCleaning()
	self.beeMaid:DoCleaning()
end

function QueenBee.Destroy(self: QueenBee)
	if self.destroyed then
		return
	end

	self:Stop()
	self.destroyed = true
	self.maid:Destroy()
end

function QueenBee.SetTarget(self: QueenBee, playerRaw: Player?): boolean
	local player = if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then playerRaw else nil
	if player ~= nil and not self:_isPlayerValid(player, self.config.DespawnRange) then
		return false
	end

	if self.targetPlayer == player then
		return player ~= nil
	end

	local previousTarget = self.targetPlayer
	self.targetPlayer = player
	self.targetUserId = if player ~= nil then player.UserId else nil
	self.targetLostTime = 0
	self.targetValid = player ~= nil
	if player ~= nil then
		self:_getTargetCenter()
		self:_getTargetVelocity()
	end
	self:_applyDebugAttributes()
	self.targetChanged:Fire(player, previousTarget)
	return player ~= nil
end

function QueenBee.GetState(self: QueenBee): Configs.QueenBeeState
	return self.state
end

function QueenBee.GetPhase(self: QueenBee): number
	return self.phase
end

function QueenBee.SetHealth(self: QueenBee, healthRaw: any, maxHealthRaw: any?)
	if maxHealthRaw ~= nil then
		self.maxHp = sanitizeNumber(maxHealthRaw, self.maxHp, 1, 10 ^ 9)
	end
	self.hp = sanitizeNumber(healthRaw, self.hp, 0, self.maxHp)
	self.healthChanged:Fire(self.hp, self.maxHp)
end

function QueenBee.TakeDamage(self: QueenBee, damageRaw: any, _sourceRaw: any?): number
	local damage = sanitizeNumber(damageRaw, 0, 0, 10 ^ 9)
	if damage <= 0 or self.destroyed then
		return 0
	end

	local nextHealth = math.max(0, self.hp - damage)
	local applied = self.hp - nextHealth
	self:SetHealth(nextHealth)
	if self.hp <= 0 then
		self:_setState(Configs.States.Despawn, "HealthDepleted")
	end
	return applied
end

QueenBee.new = QueenBee.New
QueenBee.start = QueenBee.Start
QueenBee.stop = QueenBee.Stop
QueenBee.destroy = QueenBee.Destroy
QueenBee.setTarget = QueenBee.SetTarget
QueenBee.getState = QueenBee.GetState
QueenBee.getPhase = QueenBee.GetPhase
QueenBee.setHealth = QueenBee.SetHealth
QueenBee.takeDamage = QueenBee.TakeDamage
QueenBee.createBossController = QueenBee.CreateBossController

QueenBeeBossController.getSimulationSpeed = QueenBeeBossController.GetSimulationSpeed
QueenBeeBossController.afterSpawn = QueenBeeBossController.AfterSpawn
QueenBeeBossController.onStateChanged = QueenBeeBossController.OnStateChanged
QueenBeeBossController.onDamageTaken = QueenBeeBossController.OnDamageTaken
QueenBeeBossController.onDeath = QueenBeeBossController.OnDeath
QueenBeeBossController.updateModelPivot = QueenBeeBossController.UpdateModelPivot
QueenBeeBossController.stepHover = QueenBeeBossController.StepHover
QueenBeeBossController.stepChargeWindup = QueenBeeBossController.StepChargeWindup
QueenBeeBossController.stepCharge = QueenBeeBossController.StepCharge
QueenBeeBossController.stepRecovery = QueenBeeBossController.StepRecovery
QueenBeeBossController.stepDespawn = QueenBeeBossController.StepDespawn
QueenBeeBossController.stepDeath = QueenBeeBossController.StepDeath
QueenBeeBossController.onStep = QueenBeeBossController.OnStep

return QueenBee
