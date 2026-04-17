--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local BossBase = require(script.Parent)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossService.BossServiceUtils)
local EyeOfCthulhuConfig = require(script.Config)
local EyeOfCthulhuMotion = require(script.Motion)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)

type Boss = BossBase.Boss
type BossRegistryEntry = BossServiceUtils.BossRegistryEntry
type BossSpawnRequest = BossServiceUtils.BossSpawnRequest
type EyeConfig = EyeOfCthulhuConfig.EyeOfCthulhuConfig
type ChargeLock = EyeOfCthulhuMotion.ChargeLock
type MotionRuntimeState = EyeOfCthulhuMotion.MotionRuntimeState
type MotionSolveResult = EyeOfCthulhuMotion.MotionSolveResult
type MotionTargetSnapshot = EyeOfCthulhuMotion.MotionTargetSnapshot

type ServantRuntime = {
	part: BasePart,
	position: Vector3,
	velocity: Vector3,
	age: number,
	damageCooldownByUserId: { [number]: number },
}

local EyeOfCthulhuController = {}
EyeOfCthulhuController.__index = EyeOfCthulhuController
setmetatable(EyeOfCthulhuController, { __index = BossBase })

export type EyeOfCthulhuController = Boss & {
	_eyeConfig: EyeConfig,
	_sideSign: number,
	_lockedCharge: ChargeLock?,
	_servants: { [number]: ServantRuntime },
	_nextServantId: number,
	_servantBurstRemaining: number,
	_servantBurstNextAt: number,
	_servantBurstFinishAt: number,
	_rapidChainMode: string,
	_rapidChainRemaining: number,
	_rapidChainTimer: number,
	_servantFolder: Folder?,
	_nextChargeDelay: number,
	_nextPhase2AttackDelay: number,
	_chargeCountInSet: number,
	_phase2ChargeCountInSet: number,
	_phase2IdleCyclesSinceRapidChain: number,
	_phase1BurstPending: boolean,
	_servantBurstElapsed: number,
	_servantsToSpawn: number,
	_servantsSpawned: number,
	_didInitializeBurst: boolean,
	_transformBaseFacing: Vector3,
}

local DEFAULT_SERVANT_FOLDER_NAME = "BossServants"
local LEGACY_PATH_MARKED = false

local function getServantFolder(): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(DEFAULT_SERVANT_FOLDER_NAME)
end

local function countActiveServants(self: EyeOfCthulhuController): number
	local count = 0
	for _ in self._servants do
		count += 1
	end
	return count
end

local function getControllerRandom(self: EyeOfCthulhuController): Random?
	local serviceRandom = (self.service :: any).random
	return if serviceRandom ~= nil then serviceRandom else nil
end

local function rollPhase1ChargeDelay(self: EyeOfCthulhuController): number
	local minimumDelay = self._eyeConfig.phase1ChargeSetDelayMin
	local maximumDelay = self._eyeConfig.phase1ChargeSetDelayMax
	local rng = getControllerRandom(self)
	if rng ~= nil then
		return rng:NextNumber(minimumDelay, maximumDelay)
	end
	return minimumDelay + (maximumDelay - minimumDelay) * math.random()
end

local function rollPhase2AttackDelay(self: EyeOfCthulhuController): number
	local minimumDelay = self._eyeConfig.phase2AttackDelayMin
	local maximumDelay = self._eyeConfig.phase2AttackDelayMax
	local rng = getControllerRandom(self)
	if rng ~= nil then
		return rng:NextNumber(minimumDelay, maximumDelay)
	end
	return minimumDelay + (maximumDelay - minimumDelay) * math.random()
end

local function rollServantBurstCount(self: EyeOfCthulhuController): number
	local rng = getControllerRandom(self)
	if rng ~= nil then
		return rng:NextInteger(self._eyeConfig.servantBurstCountMin, self._eyeConfig.servantBurstCountMax)
	end
	return math.random(self._eyeConfig.servantBurstCountMin, self._eyeConfig.servantBurstCountMax)
end

local function rollServantSpawnInterval(self: EyeOfCthulhuController): number
	local minimumInterval = self._eyeConfig.servantBurstIntervalMin
	local maximumInterval = self._eyeConfig.servantBurstIntervalMax
	local rng = getControllerRandom(self)
	if rng ~= nil then
		return rng:NextNumber(minimumInterval, maximumInterval)
	end
	return minimumInterval + (maximumInterval - minimumInterval) * math.random()
end

local function markLegacyEyePathDisabled()
	if LEGACY_PATH_MARKED then
		return
	end
	LEGACY_PATH_MARKED = true

	local gameRoot = script:FindFirstAncestor("game")
	local shared = if gameRoot ~= nil then gameRoot:FindFirstChild("Shared") else nil
	local classes = if shared ~= nil then shared:FindFirstChild("Classes") else nil
	local npcFolder = if classes ~= nil then classes:FindFirstChild("Npc") else nil
	local bossFolder = if npcFolder ~= nil then npcFolder:FindFirstChild("Boss") else nil
	local bossAiTypes = if bossFolder ~= nil then bossFolder:FindFirstChild("BossAiTypes") else nil
	local legacyEye = if bossAiTypes ~= nil then bossAiTypes:FindFirstChild("eyeOfCthulhu") else nil

	if legacyEye ~= nil then
		legacyEye:SetAttribute("DisabledByBossService", true)
	end
end

local function beginPhase1Cycle(self: EyeOfCthulhuController)
	self._chargeCountInSet = 0
	self.chargeIndex = 0
	self._nextChargeDelay = rollPhase1ChargeDelay(self)
	self._phase1BurstPending = self._eyeConfig.servantBurstCountMax > 0
	self._servantBurstElapsed = 0
	self._servantsToSpawn = 0
	self._servantsSpawned = 0
	self._didInitializeBurst = false
	self._servantBurstRemaining = 0
	self._servantBurstNextAt = 0
	self._servantBurstFinishAt = 0
end

local function beginPhase1ServantBurst(self: EyeOfCthulhuController)
	local activeServants = countActiveServants(self)
	local remainingCapacity = math.max(0, self._eyeConfig.maxActiveServants - activeServants)

	self._phase1BurstPending = false
	self._servantBurstElapsed = 0
	self._servantsSpawned = 0
	self._servantsToSpawn = math.min(rollServantBurstCount(self), remainingCapacity)
	self._servantBurstNextAt = 0
	self._servantBurstFinishAt = if self._servantsToSpawn > 0 then math.huge else 0.1
	self._didInitializeBurst = true
	self._servantBurstRemaining = math.max(0, self._servantsToSpawn - self._servantsSpawned)
end

local function beginPhase2HoverIdleCycle(self: EyeOfCthulhuController)
	self._phase2ChargeCountInSet = 0
	self._nextPhase2AttackDelay = rollPhase2AttackDelay(self)
	self.chargeIndex = 0
end

local function shouldTriggerPhase2RapidChain(self: EyeOfCthulhuController): boolean
	if not self._eyeConfig.expertBehaviorEnabled or not self._eyeConfig.rapidChainEnabled then
		self._phase2IdleCyclesSinceRapidChain = 0
		return false
	end

	local threshold = self._eyeConfig.rapidChainHealthThreshold
	local healthRatio = self:getHealthRatio()
	if healthRatio > threshold then
		self._phase2IdleCyclesSinceRapidChain = 0
		return false
	end

	local pressureAlpha = math.clamp((threshold - healthRatio) / math.max(threshold, 0.01), 0, 1)
	local setsPerRapidChain = if pressureAlpha >= 0.7 then 1 else if pressureAlpha >= 0.35 then 2 else 3
	self._phase2IdleCyclesSinceRapidChain += 1
	if self._phase2IdleCyclesSinceRapidChain < setsPerRapidChain then
		return false
	end

	self._phase2IdleCyclesSinceRapidChain = 0
	return true
end

local function shouldRunPhase1ServantBurst(self: EyeOfCthulhuController): boolean
	if not self._phase1BurstPending then
		return false
	end
	if self._eyeConfig.servantBurstCountMax <= 0 then
		return false
	end
	return countActiveServants(self) < self._eyeConfig.maxActiveServants
end

local function chooseSideSign(spawnRequest: BossSpawnRequest): number
	local targetPlayer = spawnRequest.targetPlayer
	if targetPlayer == nil then
		return 1
	end

	local velocity = BossServiceUtils.resolveCharacterVelocity(targetPlayer)
	if velocity.Z < -1e-3 then
		return -1
	end
	if velocity.Z > 1e-3 then
		return 1
	end
	return if math.random() < 0.5 then -1 else 1
end

local function resolveInitialSpawnRequest(spawnRequest: BossSpawnRequest, config: EyeConfig): BossSpawnRequest
	local resolved = Sift.Dictionary.copy(spawnRequest)
	if resolved.targetPlayer ~= nil then
		local rootPart = BossServiceUtils.resolveCharacterRootPart(resolved.targetPlayer)
		if rootPart ~= nil then
			if resolved.planeX == nil then
				resolved.planeX = rootPart.Position.X
			end
			if resolved.spawnPosition == nil then
				local sideSign = chooseSideSign(resolved)
				resolved.spawnPosition = EyeOfCthulhuMotion.computeIntroSpawnPosition(
					rootPart.Position,
					resolved.planeX,
					sideSign,
					config.introHeight,
					config.introDistance
				)
			end
		end
	end
	return resolved
end

local function getTargetPosition(self: EyeOfCthulhuController): Vector3?
	local targetPosition = self:resolveTargetPosition()
	if targetPosition ~= nil then
		return targetPosition
	end
	return nil
end

local function getTargetVelocity(self: EyeOfCthulhuController): Vector3
	return self:resolveTargetVelocity()
end

local function getPhaseAggressiveness(self: EyeOfCthulhuController): number
	return self._eyeConfig.aggressiveness
end

local function scaleDuration(self: EyeOfCthulhuController, baseDuration: number): number
	return EyeOfCthulhuMotion.resolveAggressiveDuration(baseDuration, getPhaseAggressiveness(self))
end

local function scaleSpeed(self: EyeOfCthulhuController, baseSpeed: number): number
	return EyeOfCthulhuMotion.resolveAggressiveSpeed(baseSpeed, getPhaseAggressiveness(self))
end

local function setPhase1Stats(self: EyeOfCthulhuController)
	self.defense = self._eyeConfig.defensePhase1
	self.contactDamage = self._eyeConfig.contactDamagePhase1
	self.contactDamageRadius = self._eyeConfig.contactDamageRadiusPhase1
	self:setPhase(1, "Phase1")
end

local function setPhase2Stats(self: EyeOfCthulhuController)
	self.defense = self._eyeConfig.defensePhase2
	self.contactDamage = self._eyeConfig.contactDamagePhase2
	self.contactDamageRadius = self._eyeConfig.contactDamageRadiusPhase2
	self:setPhase(2, "Phase2")
end

local function createTargetSnapshot(self: EyeOfCthulhuController): MotionTargetSnapshot
	return {
		position = getTargetPosition(self),
		velocity = getTargetVelocity(self),
	}
end

local function createMotionContext(self: EyeOfCthulhuController): MotionRuntimeState
	return {
		state = self.state,
		stateTime = self.stateTime,
		position = self.position,
		velocity = self.velocity,
		facing = self.facing,
		planeX = self.planeX,
		sideSign = self._sideSign,
		transformBaseFacing = self._transformBaseFacing,
		lockedCharge = self._lockedCharge,
	}
end

local function applyCurrentMotionDebugAttributes(self: EyeOfCthulhuController)
	local model = self.model
	if model == nil then
		return
	end

	local motion = self.motion
	model:SetAttribute("BossMotionState", motion.state)
	model:SetAttribute("BossMotionOwner", motion.motionOwner)
	model:SetAttribute("BossMotionPosition", motion.position)
	model:SetAttribute("BossMotionVelocity", motion.velocity)
	model:SetAttribute("BossHoverAnchor", motion.hoverAnchor)
	model:SetAttribute("BossDistanceToAnchor", motion.distanceToAnchor)
	model:SetAttribute("BossLockedChargeDirection", motion.lockedChargeDirection)
	model:SetAttribute("BossChargeTimeRemaining", motion.chargeTimeRemaining)
	model:SetAttribute("BossStateTime", self.stateTime)
	model:SetAttribute("BossPhase2ChargeCountInSet", self._phase2ChargeCountInSet)
	model:SetAttribute("BossNextPhase2AttackDelay", self._nextPhase2AttackDelay)
	model:SetAttribute("BossTransitionReason", self.lastReason)
end

local function applyMotionResult(self: EyeOfCthulhuController, result: MotionSolveResult)
	self:setVelocity(result.velocity)
	self:setFacing(result.facing)
	self:setMotionState(result.debug)
	applyCurrentMotionDebugAttributes(self)
end

local function clearLockedCharge(self: EyeOfCthulhuController)
	self._lockedCharge = nil
end

local function lockCharge(
	self: EyeOfCthulhuController,
	predictionTime: number,
	chargeSpeed: number,
	chargeDuration: number
)
	local targetSnapshot = createTargetSnapshot(self)
	self._lockedCharge = EyeOfCthulhuMotion.createChargeLock(
		self.position,
		targetSnapshot.position,
		targetSnapshot.velocity,
		self.planeX,
		predictionTime,
		0,
		chargeSpeed,
		chargeDuration,
		self._sideSign
	)
end

local function resolveServantSpawnPosition(self: EyeOfCthulhuController): Vector3
	local model = self.model
	if model ~= nil then
		local spawnPart =
			BossServiceUtils.findFirstDescendantByNormalizedName(model, { "Pupil", "Iris", "Eye", "RootPart" })
		if spawnPart ~= nil and spawnPart:IsA("BasePart") then
			return BossServiceUtils.projectPositionToPlaneX((spawnPart :: BasePart).Position, self.planeX)
		end
	end
	return self.position
end

local function spawnServant(self: EyeOfCthulhuController): boolean
	if not self.isSpawned then
		return false
	end
	if countActiveServants(self) >= self._eyeConfig.maxActiveServants then
		return false
	end

	local part = Instance.new("Part")
	part.Name = "ServantOfCthulhu"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.6, 2.6, 2.6)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(186, 43, 43)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = getServantFolder()

	local servantId = self._nextServantId
	self._nextServantId += 1

	local spawnPosition = resolveServantSpawnPosition(self)
	part.CFrame = BossServiceUtils.lookCFrame(spawnPosition, self.facing)
	self._servants[servantId] = {
		part = part,
		position = spawnPosition,
		velocity = self.facing * 18 + Vector3.new(0, 6, 0),
		age = 0,
		damageCooldownByUserId = {},
	}

	self:incrementPresentationToken("servantPulseToken")
	return true
end

local function clearServants(self: EyeOfCthulhuController)
	for servantId, servant in self._servants do
		if servant.part.Parent ~= nil then
			servant.part:Destroy()
		end
		self._servants[servantId] = nil
	end
end

local function stepServants(self: EyeOfCthulhuController, dt: number)
	local currentTime = self.service:getNow()
	local servantDamage = self._eyeConfig.servantDamage

	for servantId, servant in self._servants do
		if servant.part.Parent == nil then
			self._servants[servantId] = nil
			continue
		end

		servant.age += dt
		if servant.age >= self._eyeConfig.servantLifetime then
			servant.part:Destroy()
			self._servants[servantId] = nil
			continue
		end

		local targetPosition = getTargetPosition(self)
		if targetPosition ~= nil then
			local desiredDirection =
				BossServiceUtils.projectVectorToPlaneX(targetPosition - servant.position, self.planeX)
			if desiredDirection.Magnitude > 1e-4 then
				local desiredVelocity = desiredDirection.Unit * scaleSpeed(self, self._eyeConfig.servantSpeed)
				servant.velocity = BossServiceUtils.moveTowardsVector(
					servant.velocity,
					desiredVelocity,
					self._eyeConfig.servantTurnRate * dt * self._eyeConfig.servantSpeed
				)
			end
		end

		servant.position =
			BossServiceUtils.projectPositionToPlaneX(servant.position + servant.velocity * dt, self.planeX)
		servant.part.CFrame = BossServiceUtils.lookCFrame(servant.position, servant.velocity)

		for _, player in game:GetService("Players"):GetPlayers() do
			if not BossServiceUtils.isPlayerAlive(player) then
				continue
			end
			local rootPart = BossServiceUtils.resolveCharacterRootPart(player)
			if rootPart == nil then
				continue
			end
			if
				(BossServiceUtils.projectPositionToPlaneX(rootPart.Position, self.planeX) - servant.position).Magnitude
				> self._eyeConfig.servantRadius
			then
				continue
			end
			local lastDamageAt = servant.damageCooldownByUserId[player.UserId] or -math.huge
			if currentTime - lastDamageAt < self._eyeConfig.servantCooldown then
				continue
			end
			if self.service:damagePlayer(player, servantDamage, self) ~= nil then
				servant.damageCooldownByUserId[player.UserId] = currentTime
			end
		end
	end
end

local function beginRapidChain(self: EyeOfCthulhuController)
	self._rapidChainMode = "Windup"
	self._rapidChainRemaining = self._eyeConfig.rapidChainCount
	self._rapidChainTimer = 0
	self.contactDamageActive = false
	self.chargeIndex = 0
end

function EyeOfCthulhuController.New(
	service: any,
	definition: BossRegistryEntry,
	spawnRequestRaw: BossSpawnRequest
): EyeOfCthulhuController
	local config = EyeOfCthulhuConfig.resolve({
		simulationSpeed = spawnRequestRaw.simulationSpeed,
		aggressiveness = spawnRequestRaw.aggressiveness,
		expertBehaviorEnabled = spawnRequestRaw.expertBehaviorEnabled,
	})
	local spawnRequest = resolveInitialSpawnRequest(spawnRequestRaw, config)
	local base = BossBase.new(service, definition, spawnRequest, {
		maxHp = config.maxHp,
		defense = config.defensePhase1,
		contactDamage = config.contactDamagePhase1,
		contactDamageRadius = config.contactDamageRadiusPhase1,
		contactDamageCooldown = config.contactDamageCooldown,
		faceVelocityWhenMoving = false,
		faceTargetWhenIdle = false,
		targetLostGraceSeconds = config.targetLostGraceSeconds,
	})
	local self = setmetatable(base :: any, EyeOfCthulhuController) :: EyeOfCthulhuController

	self._eyeConfig = config
	self._sideSign = chooseSideSign(spawnRequest)
	self._lockedCharge = nil
	self._servants = {}
	self._nextServantId = 1
	self._servantBurstRemaining = 0
	self._servantBurstNextAt = 0
	self._servantBurstFinishAt = 0
	self._rapidChainMode = "Windup"
	self._rapidChainRemaining = 0
	self._rapidChainTimer = 0
	self._servantFolder = nil
	self._nextChargeDelay = 0
	self._nextPhase2AttackDelay = 0
	self._chargeCountInSet = 0
	self._phase2ChargeCountInSet = 0
	self._phase2IdleCyclesSinceRapidChain = 0
	self._phase1BurstPending = true
	self._servantBurstElapsed = 0
	self._servantsToSpawn = 0
	self._servantsSpawned = 0
	self._didInitializeBurst = false
	self._transformBaseFacing = self.facing

	setPhase1Stats(self)
	self.hp = config.maxHp
	self.maxHp = config.maxHp

	return self
end

function EyeOfCthulhuController:GetSimulationSpeed(): number
	return self._eyeConfig.simulationSpeed
end

function EyeOfCthulhuController:AfterSpawn()
	self._servantFolder = getServantFolder()
	assert(getmetatable(self) == EyeOfCthulhuController, "[BossService] Eye controller metatable mismatch")
	markLegacyEyePathDisabled()
	self:changeState("SpawnIntro", self.spawnSource)
	self:incrementPresentationToken("roarPulseToken")
end

function EyeOfCthulhuController:OnStateChanged(
	nextState: BossServiceUtils.BossEncounterState,
	previousState: BossServiceUtils.BossEncounterState,
	_reason: string
)
	self.contactDamageActive = false
	self:setPresentationFlag("isHurtWindowActive", false)
	self:setPresentationFlag("isTransforming", nextState == "Transform")
	self:setPresentationFlag("isRoaring", false)

	if nextState == "SpawnIntro" then
		clearLockedCharge(self)
		setPhase1Stats(self)
		return
	end

	if nextState == "Phase1Hover" then
		clearLockedCharge(self)
		setPhase1Stats(self)
		beginPhase1Cycle(self)
		return
	end

	if nextState == "Phase1ServantBurst" then
		clearLockedCharge(self)
		beginPhase1ServantBurst(self)
		return
	end

	if nextState == "Phase1ChargeWindup" then
		lockCharge(
			self,
			self._eyeConfig.phase1PredictionTime,
			scaleSpeed(self, self._eyeConfig.phase1ChargeSpeed),
			scaleDuration(self, self._eyeConfig.phase1ChargeDuration)
		)
		return
	end

	if nextState == "Phase1Charge" then
		self.contactDamageActive = true
		self:setPresentationFlag("isHurtWindowActive", true)
		self:incrementPresentationToken("dashPulseToken")
		return
	end

	if nextState == "Transform" then
		clearLockedCharge(self)
		self:setVelocity(Vector3.zero)
		local targetPosition = getTargetPosition(self)
		if targetPosition ~= nil then
			self:lookAt(targetPosition)
		end
		self._transformBaseFacing = self.facing
		self:setPresentationFlag("isTransforming", true)
		self:incrementPresentationToken("transformPulseToken")
		if self._eyeConfig.expertBehaviorEnabled and self._eyeConfig.servantBonusBurstOnTransform then
			for _ = 1, self._eyeConfig.servantExpertBonusCount do
				spawnServant(self)
			end
		end
		return
	end

	if nextState == "Phase2HoverIdle" or nextState == "Phase2Hover" then
		clearLockedCharge(self)
		setPhase2Stats(self)
		beginPhase2HoverIdleCycle(self)
		if previousState == "Transform" then
			self:incrementPresentationToken("roarPulseToken")
		end
		return
	end

	if nextState == "Phase2ChargeWindup" then
		lockCharge(
			self,
			self._eyeConfig.phase2PredictionTime,
			scaleSpeed(self, self._eyeConfig.phase2ChargeSpeed),
			scaleDuration(self, self._eyeConfig.phase2ChargeDuration)
		)
		return
	end

	if nextState == "Phase2Charge" then
		self.contactDamageActive = true
		self:setPresentationFlag("isHurtWindowActive", true)
		self:setPresentationFlag("isRoaring", true)
		self:incrementPresentationToken("dashPulseToken")
		self:incrementPresentationToken("roarPulseToken")
		return
	end

	if nextState == "Phase1Recovery" then
		return
	end

	if nextState == "Phase2RapidChain" then
		clearLockedCharge(self)
		beginRapidChain(self)
		return
	end

	if nextState == "Death" then
		clearLockedCharge(self)
		clearServants(self)
		self:setVelocity(Vector3.zero)
		return
	end

	if nextState == "Despawn" then
		clearLockedCharge(self)
		self.offenseEnabled = false
		return
	end
end

function EyeOfCthulhuController:OnDamageTaken(_damage: number, sourceRaw: any?, _hp: number)
	if typeof(sourceRaw) == "Instance" and sourceRaw:IsA("Player") then
		self:setTarget(sourceRaw)
	end
end

function EyeOfCthulhuController:OnDeath(_killerRaw: any?)
	clearServants(self)
end

function EyeOfCthulhuController:StepSpawnIntro(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	if targetSnapshot.position == nil then
		self:despawn("MissingTarget")
		return
	end

	local result = EyeOfCthulhuMotion.solveSpawnIntroMotion(createMotionContext(self), targetSnapshot, {
		introDuration = scaleDuration(self, self._eyeConfig.introDuration),
		introHeight = self._eyeConfig.introHeight,
		introDistance = self._eyeConfig.introDistance,
		phase1HoverHeight = self._eyeConfig.phase1HoverHeight,
		phase1SideOffset = self._eyeConfig.phase1SideOffset,
		phase1LeadMultiplier = self._eyeConfig.phase1LeadMultiplier,
		phase1BobAmplitude = self._eyeConfig.phase1BobAmplitude,
		phase1BobSpeed = self._eyeConfig.phase1BobSpeed,
		phase1HoverSpeed = scaleSpeed(self, self._eyeConfig.phase1HoverSpeed),
		phase1HoverAcceleration = scaleSpeed(self, self._eyeConfig.phase1HoverAcceleration),
		phase1HoverDamping = self._eyeConfig.phase1HoverDamping,
	}, dt)
	applyMotionResult(self, result)

	if result.finished then
		self:changeState("Phase1Hover", "SpawnIntroComplete")
	end
end

function EyeOfCthulhuController:StepPhase1Hover(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	if targetSnapshot.position == nil then
		self:despawn("MissingTarget")
		return
	end

	local result = EyeOfCthulhuMotion.solvePhase1HoverMotion(createMotionContext(self), targetSnapshot, {
		phase1HoverHeight = self._eyeConfig.phase1HoverHeight,
		phase1SideOffset = self._eyeConfig.phase1SideOffset,
		phase1LeadMultiplier = self._eyeConfig.phase1LeadMultiplier,
		phase1BobAmplitude = self._eyeConfig.phase1BobAmplitude,
		phase1BobSpeed = self._eyeConfig.phase1BobSpeed,
		phase1HoverSpeed = scaleSpeed(self, self._eyeConfig.phase1HoverSpeed),
		phase1HoverAcceleration = scaleSpeed(self, self._eyeConfig.phase1HoverAcceleration),
		phase1HoverDamping = self._eyeConfig.phase1HoverDamping,
	}, dt)
	applyMotionResult(self, result)

	if self.stateTime < self._nextChargeDelay then
		return
	end

	if shouldRunPhase1ServantBurst(self) then
		self:changeState("Phase1ServantBurst", "Phase1ChargeSetReady")
		return
	end

	self._phase1BurstPending = false
	self:changeState("Phase1ChargeWindup", "Phase1ChargeSetReady")
end

function EyeOfCthulhuController:StepPhase1ServantBurst(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	if targetSnapshot.position == nil then
		self:despawn("MissingTarget")
		return
	end

	local result = EyeOfCthulhuMotion.solveServantBurstMotion(createMotionContext(self), targetSnapshot, {
		phase1HoverHeight = self._eyeConfig.phase1HoverHeight,
		phase1SideOffset = self._eyeConfig.phase1SideOffset,
		phase1LeadMultiplier = self._eyeConfig.phase1LeadMultiplier,
		phase1BobAmplitude = self._eyeConfig.phase1BobAmplitude,
		phase1BobSpeed = self._eyeConfig.phase1BobSpeed,
		phase1HoverSpeed = scaleSpeed(self, self._eyeConfig.phase1HoverSpeed),
		phase1HoverAcceleration = scaleSpeed(self, self._eyeConfig.phase1HoverAcceleration),
		phase1HoverDamping = self._eyeConfig.phase1HoverDamping,
	}, dt)
	applyMotionResult(self, result)

	if not self._didInitializeBurst then
		beginPhase1ServantBurst(self)
	end

	self._servantBurstElapsed += dt

	if self._servantsSpawned < self._servantsToSpawn and self._servantBurstElapsed >= self._servantBurstNextAt then
		if spawnServant(self) then
			self._servantsSpawned += 1
			self._servantBurstRemaining = math.max(0, self._servantsToSpawn - self._servantsSpawned)
			if self._servantsSpawned >= self._servantsToSpawn then
				self._servantBurstFinishAt = self._servantBurstElapsed + 0.12
			else
				self._servantBurstNextAt = self._servantBurstElapsed + rollServantSpawnInterval(self)
			end
		else
			self._servantsToSpawn = self._servantsSpawned
			self._servantBurstRemaining = 0
			self._servantBurstFinishAt = self._servantBurstElapsed
		end
	end

	if self._servantsSpawned >= self._servantsToSpawn and self._servantBurstElapsed >= self._servantBurstFinishAt then
		self:changeState("Phase1ChargeWindup", "ServantBurstComplete")
	end
end

function EyeOfCthulhuController:StepPhase1ChargeWindup(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	local result = EyeOfCthulhuMotion.solveChargeWindupMotion(createMotionContext(self), targetSnapshot, {
		duration = scaleDuration(self, self._eyeConfig.phase1ChargeWindupDuration),
		brakeAcceleration = scaleSpeed(self, self._eyeConfig.phase1HoverAcceleration * 1.45),
		brakeDamping = self._eyeConfig.phase1HoverDamping + 1.15,
	}, dt)
	result.motionOwner = "Phase1ChargeWindup"
	result.debug.motionOwner = "Phase1ChargeWindup"
	applyMotionResult(self, result)

	if result.finished then
		self:changeState("Phase1Charge", "WindupComplete")
	end
end

function EyeOfCthulhuController:StepPhase1Charge(dt: number)
	local result = EyeOfCthulhuMotion.solveCommittedChargeMotion(
		createMotionContext(self),
		createTargetSnapshot(self),
		self._eyeConfig,
		dt
	)
	result.motionOwner = "Phase1Charge"
	result.debug.motionOwner = "Phase1Charge"
	applyMotionResult(self, result)

	if result.finished then
		self.contactDamageActive = false
		self:setPresentationFlag("isHurtWindowActive", false)
		self._chargeCountInSet += 1
		self.chargeIndex = self._chargeCountInSet
		self._sideSign *= -1
		self:changeState("Phase1Recovery", "ChargeComplete")
	end
end

function EyeOfCthulhuController:StepPhase1Recovery(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	local result = EyeOfCthulhuMotion.solveRecoveryMotion(createMotionContext(self), targetSnapshot, {
		duration = scaleDuration(self, self._eyeConfig.phase1ChargeRecoveryDuration),
		speed = scaleSpeed(self, self._eyeConfig.phase1ChargeRecoverySpeed),
		acceleration = scaleSpeed(self, self._eyeConfig.phase1ChargeRecoveryAcceleration),
		damping = self._eyeConfig.phase1ChargeRecoveryDamping,
	}, dt)
	result.motionOwner = "Phase1Recovery"
	result.debug.motionOwner = "Phase1Recovery"
	applyMotionResult(self, result)

	if not result.finished then
		return
	end

	if self._chargeCountInSet >= self._eyeConfig.phase1ChargeCount then
		self:changeState("Phase1Hover", "ChargeCycleComplete")
		return
	end

	self:changeState("Phase1ChargeWindup", "RecoveryComplete")
end

function EyeOfCthulhuController:StepTransform(dt: number)
	local result = EyeOfCthulhuMotion.solveTransformMotion(createMotionContext(self), createTargetSnapshot(self), {
		transformDuration = scaleDuration(self, self._eyeConfig.transformDuration),
		transformSpinTurns = self._eyeConfig.transformSpinTurns,
		transformPauseLift = self._eyeConfig.transformPauseLift,
	}, dt)
	applyMotionResult(self, result)

	if result.finished then
		self:changeState("Phase2HoverIdle", "TransformComplete")
	end
end

function EyeOfCthulhuController:StepPhase2HoverIdle(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	if targetSnapshot.position == nil then
		self:despawn("MissingTarget")
		return
	end

	local result = EyeOfCthulhuMotion.solvePhase2HoverIdleMotion(createMotionContext(self), targetSnapshot, {
		phase2HoverHeight = self._eyeConfig.phase2HoverHeight,
		phase2SideOffset = self._eyeConfig.phase2SideOffset,
		phase2LeadMultiplier = self._eyeConfig.phase2LeadMultiplier,
		phase2BobAmplitude = self._eyeConfig.phase2BobAmplitude,
		phase2BobSpeed = self._eyeConfig.phase2BobSpeed,
		phase2HoverSpeed = scaleSpeed(self, self._eyeConfig.phase2HoverSpeed),
		phase2HoverAcceleration = scaleSpeed(self, self._eyeConfig.phase2HoverAcceleration),
		phase2HoverDamping = self._eyeConfig.phase2HoverDamping,
	}, dt)
	result.motionOwner = "Phase2HoverIdle"
	result.debug.motionOwner = "Phase2HoverIdle"
	applyMotionResult(self, result)

	if self.stateTime < scaleDuration(self, self._nextPhase2AttackDelay) then
		return
	end

	if shouldTriggerPhase2RapidChain(self) then
		self:changeState("Phase2RapidChain", "Phase2HoverIdleRapidChain")
		return
	end

	self:changeState("Phase2ChargeWindup", "Phase2HoverIdleComplete")
end

function EyeOfCthulhuController:StepPhase2ChargeWindup(dt: number)
	if self._phase2ChargeCountInSet >= self._eyeConfig.phase2ChargeCount then
		self:changeState("Phase2HoverIdle", "Phase2ChargeSetGuard")
		return
	end

	local targetSnapshot = createTargetSnapshot(self)
	local result = EyeOfCthulhuMotion.solveChargeWindupMotion(createMotionContext(self), targetSnapshot, {
		duration = scaleDuration(self, self._eyeConfig.phase2ChargeWindupDuration),
		brakeAcceleration = scaleSpeed(self, self._eyeConfig.phase2HoverAcceleration * 1.85),
		brakeDamping = self._eyeConfig.phase2HoverDamping + 1.4,
	}, dt)
	result.motionOwner = "Phase2ChargeWindup"
	result.debug.motionOwner = "Phase2ChargeWindup"
	applyMotionResult(self, result)

	if result.finished then
		self:changeState("Phase2Charge", "WindupComplete")
	end
end

function EyeOfCthulhuController:StepPhase2Charge(dt: number)
	local result = EyeOfCthulhuMotion.solvePhase2ChargeMotion(
		createMotionContext(self),
		createTargetSnapshot(self),
		self._eyeConfig,
		dt
	)
	applyMotionResult(self, result)

	if result.finished then
		self.contactDamageActive = false
		self:setPresentationFlag("isHurtWindowActive", false)
		self._phase2ChargeCountInSet += 1
		self.chargeIndex = self._phase2ChargeCountInSet
		self._sideSign *= -1
		self:changeState("Phase2Recovery", "ChargeComplete")
	end
end

function EyeOfCthulhuController:StepPhase2Recovery(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	local result = EyeOfCthulhuMotion.solveRecoveryMotion(createMotionContext(self), targetSnapshot, {
		duration = scaleDuration(self, self._eyeConfig.phase2ChargeRecoveryDuration),
		speed = scaleSpeed(self, self._eyeConfig.phase2ChargeRecoverySpeed),
		acceleration = scaleSpeed(self, self._eyeConfig.phase2ChargeRecoveryAcceleration),
		damping = self._eyeConfig.phase2ChargeRecoveryDamping,
	}, dt)
	result.motionOwner = "Phase2Recovery"
	result.debug.motionOwner = "Phase2Recovery"
	applyMotionResult(self, result)

	if not result.finished then
		return
	end

	if self._phase2ChargeCountInSet >= self._eyeConfig.phase2ChargeCount then
		self:changeState("Phase2HoverIdle", "Phase2ChargeSetComplete")
		return
	end

	self:changeState("Phase2ChargeWindup", "Phase2RecoveryContinue")
end

function EyeOfCthulhuController:StepRapidChain(dt: number)
	local targetSnapshot = createTargetSnapshot(self)
	if targetSnapshot.position == nil then
		self:despawn("MissingTarget")
		return
	end

	local rapidChargeDuration = math.max(0.08, scaleDuration(self, self._eyeConfig.phase2ChargeDuration * 0.72))
	local rapidWindupDuration = scaleDuration(self, self._eyeConfig.rapidChainWindupDuration)
	local rapidRecoveryDuration = scaleDuration(self, self._eyeConfig.rapidChainRecoveryDuration)
	local rapidSpeed = EyeOfCthulhuMotion.computeRapidChainSpeed(
		self:getHealthRatio(),
		scaleSpeed(self, self._eyeConfig.rapidChainBaseSpeed),
		scaleSpeed(self, self._eyeConfig.rapidChainTopSpeed)
	)

	self._rapidChainTimer += dt
	local context = createMotionContext(self)
	context.state = ("Phase2RapidChain%s"):format(self._rapidChainMode)
	context.stateTime = self._rapidChainTimer

	if self._rapidChainMode == "Windup" then
		if self._lockedCharge == nil then
			lockCharge(self, self._eyeConfig.rapidChainPredictionTime, rapidSpeed, rapidChargeDuration)
			context.lockedCharge = self._lockedCharge
		end

		local result = EyeOfCthulhuMotion.solveChargeWindupMotion(context, targetSnapshot, {
			duration = rapidWindupDuration,
			brakeAcceleration = scaleSpeed(self, self._eyeConfig.phase2HoverAcceleration * 1.65),
			brakeDamping = self._eyeConfig.phase2HoverDamping + 1.4,
		}, dt)
		applyMotionResult(self, result)

		if result.finished then
			self._rapidChainMode = "Charge"
			self._rapidChainTimer = 0
			self.contactDamageActive = true
			self:setPresentationFlag("isHurtWindowActive", true)
			self:setPresentationFlag("isRoaring", true)
			self:incrementPresentationToken("dashPulseToken")
			self:incrementPresentationToken("roarPulseToken")
		end
		return
	end

	if self._rapidChainMode == "Charge" then
		local result = EyeOfCthulhuMotion.solvePhase2ChargeMotion(context, targetSnapshot, self._eyeConfig, dt)
		applyMotionResult(self, result)

		if result.finished then
			self.contactDamageActive = false
			self:setPresentationFlag("isHurtWindowActive", false)
			self._rapidChainMode = "Recovery"
			self._rapidChainTimer = 0
			self._rapidChainRemaining -= 1
			self._sideSign *= -1
		end
		return
	end

	local result = EyeOfCthulhuMotion.solveRecoveryMotion(context, targetSnapshot, {
		duration = rapidRecoveryDuration,
		speed = scaleSpeed(self, self._eyeConfig.phase2ChargeRecoverySpeed * 0.72),
		acceleration = scaleSpeed(self, self._eyeConfig.phase2ChargeRecoveryAcceleration),
		damping = self._eyeConfig.phase2ChargeRecoveryDamping,
	}, dt)
	applyMotionResult(self, result)

	if not result.finished then
		return
	end

	if self._rapidChainRemaining > 0 then
		clearLockedCharge(self)
		self._rapidChainMode = "Windup"
		self._rapidChainTimer = 0
		return
	end

	self.contactDamageActive = false
	self:setPresentationFlag("isHurtWindowActive", false)
	self:setPresentationFlag("isRoaring", false)
	clearLockedCharge(self)
	self:changeState("Phase2HoverIdle", "RapidChainComplete")
end

function EyeOfCthulhuController:StepDespawn(dt: number)
	local result = EyeOfCthulhuMotion.solveDespawnMotion(
		createMotionContext(self),
		createTargetSnapshot(self),
		self._eyeConfig,
		dt
	)
	applyMotionResult(self, result)

	if result.finished then
		self:requestRemoval("DespawnComplete")
	end
end

function EyeOfCthulhuController:StepDeath(dt: number)
	self:dampVelocity(4.5, dt)
	self:setMotionState({
		state = self.state,
		position = self.position,
		velocity = self.velocity,
		hoverAnchor = nil,
		distanceToAnchor = nil,
		lockedChargeDirection = nil,
		chargeTimeRemaining = nil,
		motionOwner = "Death",
		localPresentationOffset = nil,
	})
	applyCurrentMotionDebugAttributes(self)
	self:setPresentationFlag("isDying", true)
	if self.stateTime >= self._eyeConfig.deathDuration then
		self:requestRemoval("DeathComplete")
	end
end

function EyeOfCthulhuController:OnStep(dt: number)
	stepServants(self, dt)

	if self.targetPlayer == nil then
		self:setTarget(self.service:resolveEncounterTarget(self))
	end

	local allowDebugPersistence = self.spawnSource == "DebugCommand"
	if not allowDebugPersistence and self.state ~= "Death" and self.state ~= "Despawn" and self:isDayTime() then
		self:despawn("Daybreak")
	end

	if self.targetPlayer == nil and self.state ~= "Death" and self.state ~= "Despawn" then
		self:despawn("NoTarget")
	end

	if
		self.phase <= 1
		and self.state ~= "Transform"
		and self.state ~= "Death"
		and self.state ~= "Despawn"
		and self:getHealthRatio() <= self._eyeConfig.transformHealthThreshold
	then
		self:changeState("Transform", "HealthThreshold")
	end

	if self.state == "SpawnIntro" then
		self:stepSpawnIntro(dt)
		return
	end

	if self.state == "Phase1Hover" then
		self:stepPhase1Hover(dt)
		return
	end

	if self.state == "Phase1ServantBurst" then
		self:stepPhase1ServantBurst(dt)
		return
	end

	if self.state == "Phase1ChargeWindup" then
		self:stepPhase1ChargeWindup(dt)
		return
	end

	if self.state == "Phase1Charge" then
		self:stepPhase1Charge(dt)
		return
	end

	if self.state == "Phase1Recovery" then
		self:stepPhase1Recovery(dt)
		return
	end

	if self.state == "Transform" then
		self:stepTransform(dt)
		return
	end

	if self.state == "Phase2HoverIdle" or self.state == "Phase2Hover" then
		self:stepPhase2HoverIdle(dt)
		return
	end

	if self.state == "Phase2ChargeWindup" then
		self:stepPhase2ChargeWindup(dt)
		return
	end

	if self.state == "Phase2Charge" then
		self:stepPhase2Charge(dt)
		return
	end

	if self.state == "Phase2Recovery" then
		self:stepPhase2Recovery(dt)
		return
	end

	if self.state == "Phase2RapidChain" then
		self:stepRapidChain(dt)
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

function EyeOfCthulhuController:Destroy()
	clearServants(self)
	BossBase.destroy(self)
end

EyeOfCthulhuController.new = EyeOfCthulhuController.New
EyeOfCthulhuController.getSimulationSpeed = EyeOfCthulhuController.GetSimulationSpeed
EyeOfCthulhuController.afterSpawn = EyeOfCthulhuController.AfterSpawn
EyeOfCthulhuController.onStateChanged = EyeOfCthulhuController.OnStateChanged
EyeOfCthulhuController.onDamageTaken = EyeOfCthulhuController.OnDamageTaken
EyeOfCthulhuController.onDeath = EyeOfCthulhuController.OnDeath
EyeOfCthulhuController.stepSpawnIntro = EyeOfCthulhuController.StepSpawnIntro
EyeOfCthulhuController.stepPhase1Hover = EyeOfCthulhuController.StepPhase1Hover
EyeOfCthulhuController.stepPhase1ServantBurst = EyeOfCthulhuController.StepPhase1ServantBurst
EyeOfCthulhuController.stepPhase1ChargeWindup = EyeOfCthulhuController.StepPhase1ChargeWindup
EyeOfCthulhuController.stepPhase1Charge = EyeOfCthulhuController.StepPhase1Charge
EyeOfCthulhuController.stepPhase1Recovery = EyeOfCthulhuController.StepPhase1Recovery
EyeOfCthulhuController.stepTransform = EyeOfCthulhuController.StepTransform
EyeOfCthulhuController.stepPhase2HoverIdle = EyeOfCthulhuController.StepPhase2HoverIdle
EyeOfCthulhuController.stepPhase2ChargeWindup = EyeOfCthulhuController.StepPhase2ChargeWindup
EyeOfCthulhuController.stepPhase2Charge = EyeOfCthulhuController.StepPhase2Charge
EyeOfCthulhuController.stepPhase2Recovery = EyeOfCthulhuController.StepPhase2Recovery
EyeOfCthulhuController.stepRapidChain = EyeOfCthulhuController.StepRapidChain
EyeOfCthulhuController.stepDespawn = EyeOfCthulhuController.StepDespawn
EyeOfCthulhuController.stepDeath = EyeOfCthulhuController.StepDeath
EyeOfCthulhuController.onStep = EyeOfCthulhuController.OnStep
EyeOfCthulhuController.destroy = EyeOfCthulhuController.Destroy

return EyeOfCthulhuController
