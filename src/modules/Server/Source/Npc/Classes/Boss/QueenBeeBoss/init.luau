local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Maid = require("Maid")
local Rx = require("Rx")
local Signal = require("Signal")

local Bee = require(script:WaitForChild("Bee"))
local BossBase = require("Boss")
local BossServiceUtils = require("BossServiceUtils")
local Configs = require(script:WaitForChild("QueenBeeConfigs"))
local Physics = require(script:WaitForChild("Physics"))
local Render = require(script:WaitForChild("QueenBeeRender"))
local StateMachine = require("StateMachineEngine")
local Stinger = require(script:WaitForChild("Stinger"))

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

type QueenBeeAttackPattern = "HoverIdle" | "Ram" | "FakeBeeSummon" | "FakeStingerShoot"

export type QueenBeeBossController = any

local DEFAULT_MAX_HP = 3400
local DEFAULT_HP = DEFAULT_MAX_HP
local MISSING_ASSET_ERROR = "no asset found!"
local UPRIGHT_FACING = Vector3.zAxis
local PATTERN_HOVER_IDLE: QueenBeeAttackPattern = "HoverIdle"
local PATTERN_RAM: QueenBeeAttackPattern = "Ram"
local PATTERN_FAKE_BEE_SUMMON: QueenBeeAttackPattern = "FakeBeeSummon"
local PATTERN_FAKE_STINGER_SHOOT: QueenBeeAttackPattern = "FakeStingerShoot"
local DECISION_STATE_DORMANT = "Dormant"
local DECISION_STATE_HOVER_IDLE = "HoverIdle"
local DECISION_STATE_RAM_ALIGN = "RamAlign"
local DECISION_STATE_RAM_CHARGE = "RamCharge"
local DECISION_STATE_RAM_RECOVER = "RamRecover"
local DECISION_STATE_FAKE_BEE_SUMMON = "FakeBeeSummon"
local DECISION_STATE_FAKE_STINGER_SHOOT = "FakeStingerShoot"
local DECISION_EVENT_SPAWN = "spawn"
local DECISION_EVENT_HOVER_COMPLETE = "hoverComplete"
local DECISION_EVENT_RAM_ALIGNED = "ramAligned"
local DECISION_EVENT_RAM_CHARGE_COMPLETE = "ramChargeComplete"
local DECISION_EVENT_RAM_CONTINUE = "ramContinue"
local DECISION_EVENT_RAM_COMBO_COMPLETE = "ramComboComplete"
local DECISION_EVENT_FAKE_COMPLETE = "fakeComplete"
local FAKE_PATTERN_SEQUENCE: { QueenBeeAttackPattern } = table.freeze({
	PATTERN_FAKE_STINGER_SHOOT,
	PATTERN_FAKE_BEE_SUMMON,
}) :: any

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
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

local function GetHorizontalFacing(direction: Vector3, fallbackRaw: Vector3?): Vector3
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else UPRIGHT_FACING
	if math.abs(direction.Z) <= 1e-3 then
		return if fallback.Z < 0 then -Vector3.zAxis else Vector3.zAxis
	end
	return if direction.Z < 0 then -Vector3.zAxis else Vector3.zAxis
end

local function setBossSpriteFacing(self: QueenBeeBossController, direction: Vector3)
	self:SetFacing(GetHorizontalFacing(direction, self.facing))
end

local function dampVelocity(velocity: Vector3, dampingRaw: any, dtRaw: any): Vector3
	local damping = CoerceNumber(dampingRaw, 0, 0, 1000)
	local dt = CoerceNumber(dtRaw, 0, 0, 1)
	if damping <= 0 or dt <= 0 then
		return velocity
	end
	return velocity * math.exp(-damping * dt)
end

local function GetRootPart(model: Model?): BasePart?
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

local function GetModelAndRoot(config: QueenBeeNewConfig): (Model?, BasePart?, boolean)
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
		rootPart = GetRootPart(model)
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

local function GetServices(config: QueenBeeNewConfig): Services
	if typeof(config.services) == "table" then
		return config.services :: Services
	end
	return {}
end

local function GetAndom(config: QueenBeeNewConfig, services: Services): Random
	if services.random ~= nil then
		return services.random
	end

	if typeof(config.randomSeed) == "number" then
		return Random.new(config.randomSeed)
	end
	return Random.new()
end

local function GetArenaCFrame(config: QueenBeeNewConfig, rootPart: BasePart?): CFrame?
	if typeof(config.arenaCFrame) == "CFrame" then
		return config.arenaCFrame
	end
	if rootPart == nil then
		return nil
	end
	return CFrame.new(Vector3.new(rootPart.Position.X, 0, 0))
end

local function GetUntimeParent(configParent: Instance?, serviceParent: Instance?): Instance?
	if configParent ~= nil then
		return configParent
	end
	return serviceParent
end

local function GetBossDefaultConfig(serviceRaw: any, bossId: string): any?
	local defaultConfigByBossId = if typeof(serviceRaw) == "table"
		then (serviceRaw :: any).defaultConfigByBossId
		else nil
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
	local phase = math.clamp(math.floor(CoerceNumber(phaseRaw, 1, 1, 3)), 1, 3)
	return CoerceNumber(values[phase], fallback, 0, nil)
end

local function getPhaseStateName(self: QueenBeeBossController, suffix: string): string
	local phase = math.clamp(math.floor(CoerceNumber(self.phase, 1, 1, 3)), 1, 3)
	return string.format("Phase%d%s", phase, suffix)
end

local function stateHasSuffix(state: string, suffix: string): boolean
	return string.sub(state, -#suffix) == suffix
end

local function changePhaseState(self: QueenBeeBossController, suffix: string, reason: string)
	self:ChangeState(getPhaseStateName(self, suffix), reason)
end

local function GetDecisionPayload(payloadRaw: any): any
	if typeof(payloadRaw) == "table" and typeof((payloadRaw :: any).payload) == "table" then
		return (payloadRaw :: any).payload
	end
	return payloadRaw
end

local function isDecisionSyncPayload(payloadRaw: any): boolean
	local payload = GetDecisionPayload(payloadRaw)
	return typeof(payload) == "table" and (payload :: any).sync == true
end

local function GetDecisionReason(payloadRaw: any, fallback: string): string
	local payload = GetDecisionPayload(payloadRaw)
	if typeof(payload) == "table" and typeof((payload :: any).reason) == "string" and (payload :: any).reason ~= "" then
		return (payload :: any).reason
	end
	return fallback
end

local function GetDecisionStateFromBossState(state: string): string?
	if stateHasSuffix(state, "HoverIdle") then
		return DECISION_STATE_HOVER_IDLE
	end
	if stateHasSuffix(state, "RamAlign") then
		return DECISION_STATE_RAM_ALIGN
	end
	if stateHasSuffix(state, "RamCharge") then
		return DECISION_STATE_RAM_CHARGE
	end
	if stateHasSuffix(state, "RamRecover") then
		return DECISION_STATE_RAM_RECOVER
	end
	if stateHasSuffix(state, "FakeBeeSummon") then
		return DECISION_STATE_FAKE_BEE_SUMMON
	end
	if stateHasSuffix(state, "FakeStingerShoot") then
		return DECISION_STATE_FAKE_STINGER_SHOOT
	end
	return nil
end

local function GetBossSideSign(spawnRequest: BossSpawnRequest): number
	local targetPlayer = spawnRequest.targetPlayer
	if targetPlayer ~= nil then
		local velocity = BossServiceUtils.GetCharacterVelocity(targetPlayer)
		if velocity.Z < -1e-3 then
			return 1
		end
		if velocity.Z > 1e-3 then
			return -1
		end

		local rootPart = BossServiceUtils.GetCharacterRootPart(targetPlayer)
		if rootPart ~= nil and typeof(spawnRequest.spawnPosition) == "Vector3" then
			return if (spawnRequest.spawnPosition :: Vector3).Z < rootPart.Position.Z then -1 else 1
		end
	end

	return 1
end

local function GetBossInitialSpawnRequest(
	spawnRequestRaw: BossSpawnRequest,
	config: QueenBeeConfig
): BossSpawnRequest
	local Got: BossSpawnRequest = {
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

	if Got.targetPlayer == nil then
		return Got
	end

	local rootPart = BossServiceUtils.GetCharacterRootPart(Got.targetPlayer)
	if rootPart == nil then
		return Got
	end

	if Got.planeX == nil then
		Got.planeX = rootPart.Position.X
	end
	if Got.spawnPosition == nil then
		local sideSign = GetBossSideSign(Got)
		Got.spawnPosition = BossServiceUtils.ProjectPositionToPlaneX(
			rootPart.Position + Vector3.new(0, config.HoverAboveOffset + 10, config.HoverSideDistance * sideSign),
			Got.planeX
		)
	end

	return Got
end

local function GetBossAggression(self: QueenBeeBossController): number
	return math.clamp(CoerceNumber(self._aggressiveness, 1, 0.1, 3), 0.1, 3)
end

local function scaleBossSpeed(self: QueenBeeBossController, speed: number): number
	return speed * GetBossAggression(self)
end

local function scaleBossDuration(self: QueenBeeBossController, duration: number): number
	return duration / math.sqrt(GetBossAggression(self))
end

local function GetBossMaxRamCount(self: QueenBeeBossController): number
	return math.max(1, math.floor(getPhaseNumberValue(self._queenConfig.ChargesPerComboByPhase, self.phase, 3) + 0.5))
end

local function selectBossFakePattern(self: QueenBeeBossController): QueenBeeAttackPattern
	local sequenceIndex = ((self._patternCursor - 1) % #FAKE_PATTERN_SEQUENCE) + 1
	self._patternCursor += 1
	return FAKE_PATTERN_SEQUENCE[sequenceIndex]
end

local function setBossAttackPattern(
	self: QueenBeeBossController,
	pattern: QueenBeeAttackPattern,
	nextPattern: QueenBeeAttackPattern
)
	self._currentPattern = pattern
	self._nextPattern = nextPattern
	self._patternTimer = 0
	if pattern == PATTERN_RAM then
		self._ramCount = 0
		self._maxRamCount = GetBossMaxRamCount(self)
		self._comboChargeIndex = 0
	end
end

local function beginBossRamPattern(self: QueenBeeBossController, reason: string)
	setBossAttackPattern(self, PATTERN_RAM, selectBossFakePattern(self))
	self._chargeDirection = nil
	changePhaseState(self, "RamAlign", reason)
end

local function beginBossHoverIdle(self: QueenBeeBossController, reason: string)
	self._currentPattern = PATTERN_HOVER_IDLE
	self._patternTimer = 0
	self._chargeDirection = nil
	self._currentAcceleration = Vector3.zero
	changePhaseState(self, "HoverIdle", reason)
end

local function beginBossFakePattern(self: QueenBeeBossController, pattern: QueenBeeAttackPattern, reason: string)
	local suffix = if pattern == PATTERN_FAKE_BEE_SUMMON then "FakeBeeSummon" else "FakeStingerShoot"
	setBossAttackPattern(self, pattern, PATTERN_RAM)
	self._chargeDirection = nil
	self._ramCount = 0
	self._comboChargeIndex = 0
	changePhaseState(self, suffix, reason)
end

local function GetBossRamAlignAnchor(self: QueenBeeBossController): (Vector3, Vector3?)
	local config = self._queenConfig
	local targetPosition = self:GetTargetPosition()
	if targetPosition == nil then
		return self.position + self._targetDirection * config.RamAlignSideDistance, nil
	end

	return targetPosition + Vector3.new(0, 0, config.RamAlignSideDistance * self._sideSign), targetPosition
end

local function GetBossFakePatternAnchor(self: QueenBeeBossController): Vector3
	local config = self._queenConfig
	local targetPosition = self:GetTargetPosition()
	if targetPosition == nil then
		return self:ProjectToPlane(self.position)
	end

	return self:ProjectToPlane(
		targetPosition + Vector3.new(0, config.FakePatternAboveOffset, config.FakePatternSideDistance * self._sideSign)
	)
end

local function GetBossHoverIdleAnchor(self: QueenBeeBossController): (Vector3, Vector3?)
	local config = self._queenConfig
	local targetPosition = self:GetTargetPosition()
	if targetPosition == nil then
		return self:ProjectToPlane(self.position), nil
	end

	return self:ProjectToPlane(targetPosition + Vector3.yAxis * config.HoverAboveOffset), targetPosition
end

local function isBossRamAligned(self: QueenBeeBossController, targetPosition: Vector3?): boolean
	if targetPosition == nil then
		return false
	end

	local config = self._queenConfig
	local yAligned = math.abs(self.position.Y - targetPosition.Y) <= config.RamAlignToleranceY
	local sideDistance = math.abs(self.position.Z - targetPosition.Z)
	local zAligned = math.abs(sideDistance - config.RamAlignSideDistance) <= config.RamAlignToleranceZ
	return yAligned and zAligned
end

local function GetBossFakePatternDuration(self: QueenBeeBossController): number
	local config = self._queenConfig
	local durations = if self._currentPattern == PATTERN_FAKE_BEE_SUMMON
		then config.FakeBeeSummonDurationByPhase
		else config.FakeStingerShootDurationByPhase
	local fallback = if self._currentPattern == PATTERN_FAKE_BEE_SUMMON then 3.2 else 4.0
	return scaleBossDuration(self, getPhaseNumberValue(durations, self.phase, fallback))
end

local function accelerateBossTowardPoint(
	self: QueenBeeBossController,
	targetPositionRaw: Vector3,
	speedRaw: number,
	accelerationRaw: number,
	dt: number
): number
	local targetPosition = self:ProjectToPlane(targetPositionRaw)
	local offset = targetPosition - self.position
	local distance = offset.Magnitude
	local direction = safeUnit(offset, self._targetDirection)
	local speed = scaleBossSpeed(self, speedRaw)
	local acceleration = scaleBossSpeed(self, accelerationRaw)

	self._targetDirection = direction
	self._currentAcceleration = direction * acceleration
	self:AccelerateTowardVelocity(direction * speed, acceleration, dt)
	if speed > 0 and self.velocity.Magnitude > speed then
		self:SetVelocity(safeUnit(self.velocity, direction) * speed)
	end
	return distance
end

local function hoverBossTowardPoint(
	self: QueenBeeBossController,
	targetPositionRaw: Vector3,
	speedRaw: number,
	accelerationRaw: number,
	dt: number
): number
	local targetPosition = self:ProjectToPlane(targetPositionRaw)
	local offset = targetPosition - self.position
	local distance = offset.Magnitude
	local direction = safeUnit(offset, self._targetDirection)
	local speed = scaleBossSpeed(self, speedRaw)
	local acceleration = scaleBossSpeed(self, accelerationRaw)

	self._targetDirection = direction
	self._currentAcceleration = direction * acceleration
	self:SetVelocity(
		Physics.ComputeHoverVelocity(
			self.position,
			self.velocity,
			targetPosition,
			speed,
			acceleration,
			self._queenConfig.HoverDamping,
			self._queenConfig.HoverArriveRadius,
			dt
		)
	)
	return distance
end

local function faceBossTarget(self: QueenBeeBossController): boolean
	local targetPosition = self:GetTargetPosition()
	if targetPosition == nil then
		return false
	end

	local direction = Vector3.new(0, 0, targetPosition.Z - self.position.Z)
	if direction.Magnitude <= 1e-3 then
		return false
	end

	setBossSpriteFacing(self, direction)
	return true
end

local function setBossMotionDebug(
	self: QueenBeeBossController,
	motionOwner: string,
	hoverAnchor: Vector3?,
	chargeTimeRemaining: number?
)
	self:SetMotionState({
		state = self.state,
		position = self.position,
		velocity = self.velocity,
		hoverAnchor = hoverAnchor,
		distanceToAnchor = if hoverAnchor ~= nil then (hoverAnchor - self.position).Magnitude else nil,
		lockedChargeDirection = self._chargeDirection,
		targetDirection = self._targetDirection,
		acceleration = self._currentAcceleration,
		currentVelocity = self.velocity,
		currentPattern = self._currentPattern,
		patternTimer = self._patternTimer,
		ramCount = self._ramCount,
		maxRamCount = self._maxRamCount,
		nextPattern = self._nextPattern,
		chargeTimeRemaining = chargeTimeRemaining,
		comboChargeIndex = self._comboChargeIndex,
		phaseCounter = self._phaseCounter,
		motionOwner = motionOwner,
		localPresentationOffset = Vector3.zero,
	})
end

local function refreshBossPhase(self: QueenBeeBossController)
	local nextPhase = Configs.GetPhase(self.hp, self.maxHp, self._queenConfig)
	if nextPhase ~= self.phase then
		self:SetPhase(nextPhase, string.format("Phase%d", nextPhase))
		self._phaseCounter += 1
		if self._currentPattern == PATTERN_RAM then
			self._maxRamCount = GetBossMaxRamCount(self)
		end
	end
end

local function lockBossChargeDirection(self: QueenBeeBossController): Vector3
	local config = self._queenConfig
	local targetPosition = self:GetTargetPosition()
	if targetPosition == nil then
		targetPosition = self.position + self.facing * 128
	end

	local targetVelocity = self:GetTargetVelocity()
	local predictedPosition = targetPosition + Vector3.new(0, 0, targetVelocity.Z * config.ChargePredictionTime)
	-- aistyle 43 queen bee commits to a horizontal pass
	local direction = safeUnit(Vector3.new(0, 0, predictedPosition.Z - self.position.Z), self._targetDirection)
	self._chargeDirection = direction
	self._targetDirection = direction
	self._currentAcceleration = Vector3.zero
	setBossSpriteFacing(self, direction)
	return direction
end

local function beginBossCharge(self: QueenBeeBossController, reasonRaw: string?)
	local config = self._queenConfig
	local reason = if typeof(reasonRaw) == "string" and reasonRaw ~= "" then reasonRaw else "RamCharge"
	local direction = safeUnit(self._chargeDirection or lockBossChargeDirection(self), self.facing)
	self.chargeIndex += 1
	self._ramCount = math.min(self._ramCount + 1, self._maxRamCount)
	self._comboChargeIndex = self._ramCount
	setBossSpriteFacing(self, direction)
	self:SetVelocity(direction * scaleBossSpeed(self, getPhaseNumberValue(config.ChargeSpeedByPhase, self.phase, 118)))
	self:IncrementPresentationToken("dashPulseToken")
	changePhaseState(self, "RamCharge", reason)
end

local function runBossDecisionEnter(self: QueenBeeBossController, callback: () -> ())
	self._stateMachineEntering = true
	local ok, result = (pcall :: any)(callback)
	self._stateMachineEntering = false
	if not ok then
		error(result, 0)
	end
end

local function shouldSelectBossPattern(pattern: QueenBeeAttackPattern)
	return function(context: QueenBeeBossController, _eventName: string?, _payload: any?, _machine: any): boolean
		return context._nextPattern == pattern
	end
end

local function createBossStateMachine(self: QueenBeeBossController): any
	return StateMachine.New({
		{
			id = DECISION_STATE_DORMANT,
			transitions = {
				{
					event = DECISION_EVENT_SPAWN,
					to = DECISION_STATE_HOVER_IDLE,
				},
			},
		},
		{
			id = DECISION_STATE_HOVER_IDLE,
			onEnter = function(context: QueenBeeBossController, _stateId: string, _machine: any, payload: any?)
				if isDecisionSyncPayload(payload) then
					return
				end

				local reason = GetDecisionReason(payload, "HoverIdle")
				runBossDecisionEnter(context, function()
					beginBossHoverIdle(context, reason)
				end)
			end,
			transitions = {
				{
					event = DECISION_EVENT_HOVER_COMPLETE,
					to = DECISION_STATE_RAM_ALIGN,
					guard = shouldSelectBossPattern(PATTERN_RAM),
					priority = 3,
				},
				{
					event = DECISION_EVENT_HOVER_COMPLETE,
					to = DECISION_STATE_FAKE_BEE_SUMMON,
					guard = shouldSelectBossPattern(PATTERN_FAKE_BEE_SUMMON),
					priority = 2,
				},
				{
					event = DECISION_EVENT_HOVER_COMPLETE,
					to = DECISION_STATE_FAKE_STINGER_SHOOT,
					guard = shouldSelectBossPattern(PATTERN_FAKE_STINGER_SHOOT),
					priority = 2,
				},
				{
					event = DECISION_EVENT_HOVER_COMPLETE,
					to = DECISION_STATE_RAM_ALIGN,
					guard = function(
						_context: QueenBeeBossController,
						_eventName: string?,
						_payload: any?,
						_machine: any
					): boolean
						return true
					end,
					priority = -1,
				},
			},
		},
		{
			id = DECISION_STATE_RAM_ALIGN,
			onEnter = function(context: QueenBeeBossController, _stateId: string, _machine: any, payload: any?)
				if isDecisionSyncPayload(payload) then
					return
				end

				local decisionPayload = GetDecisionPayload(payload)
				local reason = GetDecisionReason(payload, "RamAlign")
				runBossDecisionEnter(context, function()
					if typeof(decisionPayload) == "table" and (decisionPayload :: any).continueCombo == true then
						changePhaseState(context, "RamAlign", reason)
					else
						beginBossRamPattern(context, reason)
					end
				end)
			end,
			transitions = {
				{
					event = DECISION_EVENT_RAM_ALIGNED,
					to = DECISION_STATE_RAM_CHARGE,
				},
			},
		},
		{
			id = DECISION_STATE_RAM_CHARGE,
			onEnter = function(context: QueenBeeBossController, _stateId: string, _machine: any, payload: any?)
				if isDecisionSyncPayload(payload) then
					return
				end

				local reason = GetDecisionReason(payload, "RamCharge")
				runBossDecisionEnter(context, function()
					beginBossCharge(context, reason)
				end)
			end,
			transitions = {
				{
					event = DECISION_EVENT_RAM_CHARGE_COMPLETE,
					to = DECISION_STATE_RAM_RECOVER,
				},
			},
		},
		{
			id = DECISION_STATE_RAM_RECOVER,
			onEnter = function(context: QueenBeeBossController, _stateId: string, _machine: any, payload: any?)
				if isDecisionSyncPayload(payload) then
					return
				end

				local reason = GetDecisionReason(payload, "RamRecover")
				runBossDecisionEnter(context, function()
					changePhaseState(context, "RamRecover", reason)
				end)
			end,
			transitions = {
				{
					event = DECISION_EVENT_RAM_CONTINUE,
					to = DECISION_STATE_RAM_ALIGN,
				},
				{
					event = DECISION_EVENT_RAM_COMBO_COMPLETE,
					to = DECISION_STATE_HOVER_IDLE,
				},
			},
		},
		{
			id = DECISION_STATE_FAKE_BEE_SUMMON,
			onEnter = function(context: QueenBeeBossController, _stateId: string, _machine: any, payload: any?)
				if isDecisionSyncPayload(payload) then
					return
				end

				local reason = GetDecisionReason(payload, "FakeBeeSummon")
				runBossDecisionEnter(context, function()
					beginBossFakePattern(context, PATTERN_FAKE_BEE_SUMMON, reason)
				end)
			end,
			transitions = {
				{
					event = DECISION_EVENT_FAKE_COMPLETE,
					to = DECISION_STATE_HOVER_IDLE,
				},
			},
		},
		{
			id = DECISION_STATE_FAKE_STINGER_SHOOT,
			onEnter = function(context: QueenBeeBossController, _stateId: string, _machine: any, payload: any?)
				if isDecisionSyncPayload(payload) then
					return
				end

				local reason = GetDecisionReason(payload, "FakeStingerShoot")
				runBossDecisionEnter(context, function()
					beginBossFakePattern(context, PATTERN_FAKE_STINGER_SHOOT, reason)
				end)
			end,
			transitions = {
				{
					event = DECISION_EVENT_FAKE_COMPLETE,
					to = DECISION_STATE_HOVER_IDLE,
				},
			},
		},
	}, DECISION_STATE_DORMANT, self)
end

local function dispatchBossDecision(self: QueenBeeBossController, eventName: string, payloadRaw: any?): boolean
	local machine = self._stateMachine
	if machine == nil then
		return false
	end

	local payload = payloadRaw
	if typeof(payload) ~= "table" then
		payload = {
			reason = if typeof(payloadRaw) == "string" and payloadRaw ~= "" then payloadRaw else eventName,
		}
	end
	return machine:Dispatch(eventName, payload)
end

local function syncBossDecisionState(self: QueenBeeBossController, bossState: string)
	if self._stateMachineEntering == true then
		return
	end

	local machine = self._stateMachine
	if machine == nil then
		return
	end

	local decisionState = GetDecisionStateFromBossState(bossState)
	if decisionState == nil or machine:GetActiveState() == decisionState then
		return
	end

	machine:TransitionTo(decisionState, { sync = true }, 1000)
end

function QueenBee.CreateBossController(
	service: any,
	definition: BossRegistryEntry,
	spawnRequestRaw: BossSpawnRequest
): QueenBeeBossController
	local config = Configs.Get(GetBossDefaultConfig(service, definition.id))
	local spawnRequest = GetBossInitialSpawnRequest(spawnRequestRaw, config)
	local base = BossBase.New(service, definition, spawnRequest, {
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
	self._simulationSpeed = CoerceNumber(spawnRequestRaw.simulationSpeed, 1, 0.05, 5)
	self._aggressiveness = CoerceNumber(spawnRequestRaw.aggressiveness, 1, 0.1, 3)
	self._sideSign = GetBossSideSign(spawnRequest)
	self._chargeDirection = nil
	self._targetDirection = Vector3.new(0, 0, self._sideSign)
	self._currentAcceleration = Vector3.zero
	self._currentPattern = PATTERN_HOVER_IDLE
	self._nextPattern = PATTERN_RAM
	self._patternTimer = 0
	self._ramCount = 0
	self._maxRamCount = GetBossMaxRamCount(self)
	self._patternCursor = 1
	self._comboChargeIndex = 0
	self._phaseCounter = 0
	self._stateMachineEntering = false
	self._stateMachine = createBossStateMachine(self)

	self:SetPhase(1, "Phase1")
	return self
end

function QueenBeeBossController.GetSimulationSpeed(self: QueenBeeBossController): number
	return self._simulationSpeed
end

function QueenBeeBossController.GetMaxSimulationStep(self: QueenBeeBossController): number
	return self._queenConfig.MaxDt
end

function QueenBeeBossController.AfterSpawn(self: QueenBeeBossController)
	self:SetTarget(self.spawnRequest.targetPlayer or self.service:GetEncounterTarget(self))
	dispatchBossDecision(self, DECISION_EVENT_SPAWN, "Spawn")
end

function QueenBeeBossController.OnStateChanged(
	self: QueenBeeBossController,
	nextState: string,
	_previousState: string,
	_reason: string
)
	if stateHasSuffix(nextState, "HoverIdle") and self._currentPattern ~= PATTERN_HOVER_IDLE then
		self._currentPattern = PATTERN_HOVER_IDLE
		self._patternTimer = 0
	elseif stateHasSuffix(nextState, "RamAlign") and self._currentPattern ~= PATTERN_RAM then
		setBossAttackPattern(self, PATTERN_RAM, selectBossFakePattern(self))
	elseif stateHasSuffix(nextState, "FakeBeeSummon") and self._currentPattern ~= PATTERN_FAKE_BEE_SUMMON then
		setBossAttackPattern(self, PATTERN_FAKE_BEE_SUMMON, PATTERN_RAM)
	elseif stateHasSuffix(nextState, "FakeStingerShoot") and self._currentPattern ~= PATTERN_FAKE_STINGER_SHOOT then
		setBossAttackPattern(self, PATTERN_FAKE_STINGER_SHOOT, PATTERN_RAM)
	end

	local isCharge = stateHasSuffix(nextState, "Charge") and not stateHasSuffix(nextState, "ChargeWindup")
	if not isCharge then
		faceBossTarget(self)
	end
	self.contactDamageActive = isCharge
	self:SetPresentationFlag("isHurtWindowActive", not isCharge and nextState ~= "Death")
	self:SetPresentationFlag("isRoaring", false)
	syncBossDecisionState(self, nextState)
end

function QueenBeeBossController.OnDamageTaken(
	self: QueenBeeBossController,
	_damage: number,
	_sourceRaw: any?,
	_hp: number
)
	refreshBossPhase(self)
end

function QueenBeeBossController.OnDeath(self: QueenBeeBossController, _killerRaw: any?)
	self._chargeDirection = nil
	self._currentAcceleration = Vector3.zero
	self:SetVelocity(Vector3.zero)
end

function QueenBeeBossController.UpdateModelPivot(self: QueenBeeBossController)
	local model = self.model
	if model == nil then
		return
	end

	model:PivotTo(CFrame.new(self.position))
	self.rootPart = BossServiceUtils.GetRootPart(model)
	if self.rootPart ~= nil and model.PrimaryPart == nil then
		model.PrimaryPart = self.rootPart
	end
end

function QueenBeeBossController.StepHoverIdle(self: QueenBeeBossController, dt: number)
	local config = self._queenConfig
	local hoverAnchor, targetPosition = GetBossHoverIdleAnchor(self)
	hoverBossTowardPoint(
		self,
		hoverAnchor,
		getPhaseNumberValue(config.HoverSpeedByPhase, self.phase, 28) * config.HoverIdleSpeedMultiplier,
		getPhaseNumberValue(config.HoverAccelerationByPhase, self.phase, 95) * config.HoverIdleAccelerationMultiplier,
		dt
	)
	if targetPosition ~= nil and not faceBossTarget(self) then
		setBossSpriteFacing(self, targetPosition - self.position)
	elseif targetPosition == nil then
		setBossSpriteFacing(self, self._targetDirection)
	end

	local duration = scaleBossDuration(self, getPhaseNumberValue(config.HoverIdleDurationByPhase, self.phase, 0.85))
	setBossMotionDebug(self, "QueenBeeHoverIdle", hoverAnchor, math.max(0, duration - self.stateTime))
	if self.stateTime >= duration then
		dispatchBossDecision(self, DECISION_EVENT_HOVER_COMPLETE, "HoverIdleComplete")
	end
end

function QueenBeeBossController.StepRamAlign(self: QueenBeeBossController, dt: number)
	local config = self._queenConfig
	local alignAnchor, targetPosition = GetBossRamAlignAnchor(self)
	-- terraria queen bee lines up beside the player before committing to a horizontal pass
	accelerateBossTowardPoint(
		self,
		alignAnchor,
		getPhaseNumberValue(config.RamAlignSpeedByPhase, self.phase, 48),
		getPhaseNumberValue(config.RamAlignAccelerationByPhase, self.phase, 210),
		dt
	)
	if not faceBossTarget(self) then
		setBossSpriteFacing(self, self._targetDirection)
	end

	local maxAlignTime = scaleBossDuration(self, getPhaseNumberValue(config.RamAlignMaxTimeByPhase, self.phase, 1.35))
	setBossMotionDebug(self, "QueenBeeRamAlign", alignAnchor, nil)

	if isBossRamAligned(self, targetPosition) or (targetPosition == nil and self.stateTime >= maxAlignTime) then
		lockBossChargeDirection(self)
		dispatchBossDecision(self, DECISION_EVENT_RAM_ALIGNED, "RamAligned")
	end
end

function QueenBeeBossController.StepRamCharge(self: QueenBeeBossController, _dt: number)
	local config = self._queenConfig
	local direction = safeUnit(self._chargeDirection or lockBossChargeDirection(self), self.facing)
	local speed = scaleBossSpeed(self, getPhaseNumberValue(config.ChargeSpeedByPhase, self.phase, 118))
	local duration = scaleBossDuration(self, getPhaseNumberValue(config.ChargeDurationByPhase, self.phase, 0.72))
	-- charge stays committed until its timer expires instead of easing toward an endpoint
	self._targetDirection = direction
	self._currentAcceleration = Vector3.zero
	self:SetVelocity(direction * speed)
	setBossSpriteFacing(self, direction)
	setBossMotionDebug(self, "QueenBeeRamCharge", nil, math.max(0, duration - self.stateTime))

	if self.stateTime >= duration then
		dispatchBossDecision(self, DECISION_EVENT_RAM_CHARGE_COMPLETE, "RamChargeComplete")
	end
end

function QueenBeeBossController.StepRamRecover(self: QueenBeeBossController, dt: number)
	self._chargeDirection = nil
	-- recovery damps dash velocity so the next state inherits momentum
	self:DampVelocity(self._queenConfig.HoverDamping, dt)
	self._currentAcceleration = Vector3.zero
	faceBossTarget(self)
	setBossMotionDebug(self, "QueenBeeRamRecover", nil, nil)
	if self.stateTime >= self._queenConfig.PostChargeRecoverTime then
		if self._ramCount < self._maxRamCount then
			self._sideSign *= -1
			dispatchBossDecision(self, DECISION_EVENT_RAM_CONTINUE, {
				reason = "RamComboContinue",
				continueCombo = true,
			})
			return
		end

		self._sideSign *= -1
		dispatchBossDecision(self, DECISION_EVENT_RAM_COMBO_COMPLETE, "RamComboComplete")
	end
end

function QueenBeeBossController.StepFakePattern(self: QueenBeeBossController, dt: number)
	local config = self._queenConfig
	local hoverAnchor = GetBossFakePatternAnchor(self)
	-- fake Terraria attack slots are invisible gates until projectile patterns are added
	hoverBossTowardPoint(
		self,
		hoverAnchor,
		getPhaseNumberValue(config.HoverSpeedByPhase, self.phase, 28) * config.FakePatternHoverSpeedMultiplier,
		getPhaseNumberValue(config.HoverAccelerationByPhase, self.phase, 95) * config.FakePatternHoverSpeedMultiplier,
		dt
	)
	if not faceBossTarget(self) then
		setBossSpriteFacing(self, self._targetDirection)
	end

	local duration = GetBossFakePatternDuration(self)
	setBossMotionDebug(self, `QueenBee{self._currentPattern}`, hoverAnchor, math.max(0, duration - self.stateTime))
	if self.stateTime >= duration then
		dispatchBossDecision(self, DECISION_EVENT_FAKE_COMPLETE, "FakePatternComplete")
	end
end

function QueenBeeBossController.StepDespawn(self: QueenBeeBossController, dt: number)
	local targetPosition = self:GetTargetPosition()
	local direction = if targetPosition ~= nil
		then safeUnit(self.position - targetPosition, self.facing)
		else self.facing
	self._targetDirection = direction
	self._currentAcceleration = direction * self._queenConfig.DespawnAcceleration
	self:AccelerateTowardVelocity(direction * self._queenConfig.DespawnSpeed, self._queenConfig.DespawnAcceleration, dt)
	setBossMotionDebug(self, "QueenBeeDespawn", nil, nil)
	if self.stateTime >= self._queenConfig.DespawnDuration then
		self:RequestRemoval("DespawnComplete")
	end
end

function QueenBeeBossController.StepDeath(self: QueenBeeBossController, dt: number)
	self:DampVelocity(4.5, dt)
	self._currentAcceleration = Vector3.zero
	setBossMotionDebug(self, "QueenBeeDeath", nil, nil)
	if self.stateTime >= 1.6 then
		self:RequestRemoval("DeathComplete")
	end
end

function QueenBeeBossController.OnStep(self: QueenBeeBossController, dt: number)
	if self.targetPlayer == nil then
		self:SetTarget(self.service:GetEncounterTarget(self))
	end

	refreshBossPhase(self)
	self._patternTimer += dt
	if self._stateMachine ~= nil then
		self._stateMachine:Update(dt)
	end

	if stateHasSuffix(self.state, "HoverIdle") then
		self:StepHoverIdle(dt)
		return
	end
	if stateHasSuffix(self.state, "RamAlign") then
		self:StepRamAlign(dt)
		return
	end
	if stateHasSuffix(self.state, "RamCharge") then
		self:StepRamCharge(dt)
		return
	end
	if stateHasSuffix(self.state, "RamRecover") then
		self:StepRamRecover(dt)
		return
	end
	if stateHasSuffix(self.state, "FakeBeeSummon") or stateHasSuffix(self.state, "FakeStingerShoot") then
		self:StepFakePattern(dt)
		return
	end
	if self.state == "Despawn" then
		self:StepDespawn(dt)
		return
	end
	if self.state == "Death" then
		self:StepDeath(dt)
		return
	end
end

function QueenBee.New(configRaw: QueenBeeNewConfig?): QueenBee
	local raw = (if typeof(configRaw) == "table" then configRaw else {} :: any) :: any
	local model, rootPart, ownsModel = GetModelAndRoot(raw)
	local services = GetServices(raw)
	local config = Configs.Get(if raw.config ~= nil then raw.config else raw)
	local maxHp = CoerceNumber(raw.maxHp, DEFAULT_MAX_HP, 1, 10 ^ 9)
	local hp = CoerceNumber(raw.hp, DEFAULT_HP, 0, maxHp)
	local spawnPosition = if rootPart ~= nil then rootPart.Position else Vector3.zero
	local arenaCFrame = GetArenaCFrame(raw, rootPart)
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
		projectileParent = GetUntimeParent(raw.projectileParent, services.projectileParent),
		beeParent = GetUntimeParent(raw.beeParent, services.beeParent),
		arenaCFrame = arenaCFrame,
		position = Physics.ProjectToCombatPlane(spawnPosition, arenaCFrame),
		velocity = Vector3.zero,
		facingSign = 1,
		targetPlayer = nil,
		targetUserId = nil,
		state = Configs.States.AcquireTarget,
		phase = Configs.GetPhase(hp, maxHp, config),
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
		random = GetAndom(raw, services),
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
	for _, instance in { self.model, self.rootPart } :: { Instance? } do
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
		local chargeDirection = Physics.GetCombatSideVector(self.arenaCFrame) * self.sideSign
		self.chargeDirection = chargeDirection
		self.chargeTargetPosition = self.position + chargeDirection * self.config.ChargePassDistance
		return
	end

	local targetVelocity = self:_getTargetVelocity()
	local predicted =
		Physics.ProjectToCombatPlane(targetCenter + targetVelocity * self.config.ChargePredictionTime, self.arenaCFrame)
	local direction = Physics.ProjectVectorToCombatPlane(predicted - self.position, self.arenaCFrame)
	self.chargeTargetPosition = predicted
	local chargeDirection = safeUnit(direction, Physics.GetCombatSideVector(self.arenaCFrame) * self.sideSign)
	self.chargeDirection = chargeDirection
	self.facingSign = if chargeDirection:Dot(Physics.GetCombatSideVector(self.arenaCFrame)) >= 0 then 1 else -1
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
			return nil :: any
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

	local dt = CoerceNumber(dtRaw, 0, 0, self.config.MaxDt)
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

	local cframe = CFrame.new(self.position)
	if self.model ~= nil then
		self.model:PivotTo(cframe)
		if self.rootPart == nil then
			self.rootPart = GetRootPart(self.model)
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

	local dt = CoerceNumber(dtRaw, 0, 0, self.config.MaxDt)
	if dt <= 0 then
		return
	end

	self:_emitHealthIfChanged()
	self:_updateEnrage()
	self.stateTime += dt

	local nextPhase = Configs.GetPhase(self.hp, self.maxHp, self.config)
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
				return Configs.GetPhase(health, maxHealth, self.config)
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
		self.maxHp = CoerceNumber(maxHealthRaw, self.maxHp, 1, 10 ^ 9)
	end
	self.hp = CoerceNumber(healthRaw, self.hp, 0, self.maxHp)
	self.healthChanged:Fire(self.hp, self.maxHp)
end

function QueenBee.TakeDamage(self: QueenBee, damageRaw: any, _sourceRaw: any?): number
	local damage = CoerceNumber(damageRaw, 0, 0, 10 ^ 9)
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
return QueenBee
