
local require = require(script.Parent.loader).load(script)

local BossServiceUtils = require("BossServiceUtils")

local EyeOfCthulhuConfig = {}

export type EyeOfCthulhuConfig = {
	maxHp: number,
	defensePhase1: number,
	defensePhase2: number,
	contactDamagePhase1: number,
	contactDamagePhase2: number,
	contactDamageRadiusPhase1: number,
	contactDamageRadiusPhase2: number,
	contactDamageCooldown: number,
	transformHealthThreshold: number,
	introDuration: number,
	introHeight: number,
	introDistance: number,
	introDriftAmplitude: number,
	introDriftSpeed: number,
	phase1HoverHeight: number,
	phase1LeadMultiplier: number,
	phase1SideOffset: number,
	phase1HoverDuration: number,
	phase1ChargeSetDelayMin: number,
	phase1ChargeSetDelayMax: number,
	phase1HoverSpeed: number,
	phase1HoverAcceleration: number,
	phase1HoverDamping: number,
	phase1BobAmplitude: number,
	phase1BobSpeed: number,
	phase1ChargeWindupDuration: number,
	phase1ChargeSpeed: number,
	phase1ChargeDuration: number,
	phase1ChargeRecoveryDuration: number,
	phase1ChargeRecoverySpeed: number,
	phase1ChargeRecoveryAcceleration: number,
	phase1ChargeRecoveryDamping: number,
	phase1ChargeCount: number,
	phase1PredictionTime: number,
	servantBurstCountMin: number,
	servantBurstCountMax: number,
	servantBurstInterval: number,
	servantBurstIntervalMin: number,
	servantBurstIntervalMax: number,
	servantBonusBurstOnTransform: boolean,
	servantExpertBonusCount: number,
	servantLimit: number,
	maxActiveServants: number,
	servantLifetime: number,
	servantSpeed: number,
	servantTurnRate: number,
	servantDamage: number,
	servantRadius: number,
	servantCooldown: number,
	transformDuration: number,
	transformSpinTurns: number,
	transformPauseLift: number,
	phase2HoverHeight: number,
	phase2LeadMultiplier: number,
	phase2SideOffset: number,
	phase2HoverDuration: number,
	phase2AttackDelayMin: number,
	phase2AttackDelayMax: number,
	phase2HoverSpeed: number,
	phase2HoverAcceleration: number,
	phase2HoverDamping: number,
	phase2BobAmplitude: number,
	phase2BobSpeed: number,
	phase2ChargeCount: number,
	phase2ChargeWindupDuration: number,
	phase2ChargeSpeed: number,
	phase2ChargeDuration: number,
	phase2ChargeRecoveryDuration: number,
	phase2ChargeRecoverySpeed: number,
	phase2ChargeRecoveryAcceleration: number,
	phase2ChargeRecoveryDamping: number,
	phase2PredictionTime: number,
	rapidChainEnabled: boolean,
	rapidChainHealthThreshold: number,
	rapidChainCount: number,
	rapidChainWindupDuration: number,
	rapidChainRecoveryDuration: number,
	rapidChainBaseSpeed: number,
	rapidChainTopSpeed: number,
	rapidChainPredictionTime: number,
	targetLostGraceSeconds: number,
	despawnRiseSpeed: number,
	despawnForwardSpeed: number,
	despawnAcceleration: number,
	deathDuration: number,
	naturalSpawnEnabled: boolean,
	naturalSpawnChancePerNight: number,
	naturalSpawnAnnouncementDelay: number,
	simulationSpeed: number,
	aggressiveness: number,
	expertBehaviorEnabled: boolean,
}

local DEFAULTS: EyeOfCthulhuConfig = {
	maxHp = 2800,
	defensePhase1 = 12,
	defensePhase2 = 12,
	contactDamagePhase1 = 15,
	contactDamagePhase2 = 15,
	contactDamageRadiusPhase1 = 10.5,
	contactDamageRadiusPhase2 = 10.5,
	contactDamageCooldown = 0.35,
	transformHealthThreshold = 0.5,
	introDuration = 2.4,
	introHeight = 50,
	introDistance = 70,
	introDriftAmplitude = 8,
	introDriftSpeed = 1.8,
	phase1HoverHeight = 24,
	phase1LeadMultiplier = 0.32,
	phase1SideOffset = 14,
	phase1HoverDuration = 4,
	phase1ChargeSetDelayMin = 2.0,
	phase1ChargeSetDelayMax = 4.0,
	phase1HoverSpeed = 17,
	phase1HoverAcceleration = 70,
	phase1HoverDamping = 0.5,
	phase1BobAmplitude = 3,
	phase1BobSpeed = 4.2,
	phase1ChargeWindupDuration = 0.4,
	phase1ChargeSpeed = 30,
	phase1ChargeDuration = 1.5,
	phase1ChargeRecoveryDuration = 1.5,
	phase1ChargeRecoverySpeed = 10,
	phase1ChargeRecoveryAcceleration = 20,
	phase1ChargeRecoveryDamping = 1.1,
	phase1ChargeCount = 3,
	phase1PredictionTime = 0.16,
	servantBurstCountMin = 3,
	servantBurstCountMax = 4,
	servantBurstInterval = 1.5,
	servantBurstIntervalMin = 0.35,
	servantBurstIntervalMax = 0.6,
	servantBonusBurstOnTransform = true,
	servantExpertBonusCount = 2,
	servantLimit = 8,
	maxActiveServants = 8,
	servantLifetime = 3,
	servantSpeed = 13,
	servantTurnRate = 6.5,
	servantDamage = 11,
	servantRadius = 3,
	servantCooldown = 1.5,
	transformDuration = 2.25,
	transformSpinTurns = 8,
	transformPauseLift = 8,
	phase2HoverHeight = 24,
	phase2LeadMultiplier = 0.32,
	phase2SideOffset = 14,
	phase2HoverDuration = 4,
	phase2AttackDelayMin = 2.0,
	phase2AttackDelayMax = 4.0,
	phase2HoverSpeed = 17,
	phase2HoverAcceleration = 70,
	phase2HoverDamping = 0.5,
	phase2BobAmplitude = 3,
	phase2BobSpeed = 4.2,
	phase2ChargeCount = 3,
	phase2ChargeWindupDuration = 0.4,
	phase2ChargeSpeed = 30,
	phase2ChargeDuration = 1.5,
	phase2ChargeRecoveryDuration = 1.5,
	phase2ChargeRecoverySpeed = 10,
	phase2ChargeRecoveryAcceleration = 20,
	phase2ChargeRecoveryDamping = 1.1,
	phase2PredictionTime = 0.16,
	rapidChainEnabled = true,
	rapidChainHealthThreshold = 0.34,
	rapidChainCount = 4,
	rapidChainWindupDuration = 0.12,
	rapidChainRecoveryDuration = 0.08,
	rapidChainBaseSpeed = 110,
	rapidChainTopSpeed = 154,
	rapidChainPredictionTime = 0.12,
	targetLostGraceSeconds = 5,
	despawnRiseSpeed = 120,
	despawnForwardSpeed = 42,
	despawnAcceleration = 240,
	deathDuration = 2.2,
	naturalSpawnEnabled = true,
	naturalSpawnChancePerNight = 0.35,
	naturalSpawnAnnouncementDelay = 2.25,
	simulationSpeed = 1.5,
	aggressiveness = 1,
	expertBehaviorEnabled = true,
}

local function cloneDefaults(): EyeOfCthulhuConfig
	local clone = {}
	for key, value in DEFAULTS do
		(clone :: any)[key] = value
	end
	return clone :: EyeOfCthulhuConfig
end

local function coerceInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	return math.floor(BossServiceUtils.CoerceNumber(valueRaw, fallback, minimum, maximum))
end

function EyeOfCthulhuConfig.GetDefaults(): EyeOfCthulhuConfig
	return cloneDefaults()
end

function EyeOfCthulhuConfig.Get(configRaw: any): EyeOfCthulhuConfig
	local config = cloneDefaults()
	local source = if typeof(configRaw) == "table" then configRaw else {} :: any

	config.maxHp = coerceInteger((source :: any).maxHp, config.maxHp, 1, 10 ^ 9)
	config.defensePhase1 =
		BossServiceUtils.CoerceNumber((source :: any).defensePhase1, config.defensePhase1, 0, 10 ^ 6)
	config.defensePhase2 =
		BossServiceUtils.CoerceNumber((source :: any).defensePhase2, config.defensePhase1, 0, 10 ^ 6)
	config.contactDamagePhase1 =
		BossServiceUtils.CoerceNumber((source :: any).contactDamagePhase1, config.contactDamagePhase1, 0, 10 ^ 6)
	config.contactDamagePhase2 =
		BossServiceUtils.CoerceNumber((source :: any).contactDamagePhase2, config.contactDamagePhase1, 0, 10 ^ 6)
	config.contactDamageRadiusPhase1 = BossServiceUtils.CoerceNumber(
		(source :: any).contactDamageRadiusPhase1,
		config.contactDamageRadiusPhase1,
		0,
		256
	)
	config.contactDamageRadiusPhase2 = BossServiceUtils.CoerceNumber(
		(source :: any).contactDamageRadiusPhase2,
		config.contactDamageRadiusPhase1,
		0,
		256
	)
	config.contactDamageCooldown =
		BossServiceUtils.CoerceNumber((source :: any).contactDamageCooldown, config.contactDamageCooldown, 0, 30)
	config.transformHealthThreshold = BossServiceUtils.CoerceNumber(
		(source :: any).transformHealthThreshold,
		config.transformHealthThreshold,
		0.05,
		0.95
	)
	config.introDuration = BossServiceUtils.CoerceNumber((source :: any).introDuration, config.introDuration, 0.1, 20)
	config.introHeight = BossServiceUtils.CoerceNumber((source :: any).introHeight, config.introHeight, 0, 512)
	config.introDistance = BossServiceUtils.CoerceNumber((source :: any).introDistance, config.introDistance, 8, 512)
	config.introDriftAmplitude =
		BossServiceUtils.CoerceNumber((source :: any).introDriftAmplitude, config.introDriftAmplitude, 0, 128)
	config.introDriftSpeed =
		BossServiceUtils.CoerceNumber((source :: any).introDriftSpeed, config.introDriftSpeed, 0, 30)
	config.phase1HoverHeight =
		BossServiceUtils.CoerceNumber((source :: any).phase1HoverHeight, config.phase1HoverHeight, 0, 512)
	config.phase1LeadMultiplier =
		BossServiceUtils.CoerceNumber((source :: any).phase1LeadMultiplier, config.phase1LeadMultiplier, 0, 4)
	config.phase1SideOffset =
		BossServiceUtils.CoerceNumber((source :: any).phase1SideOffset, config.phase1SideOffset, 0, 256)
	config.phase1HoverDuration =
		BossServiceUtils.CoerceNumber((source :: any).phase1HoverDuration, config.phase1HoverDuration, 0.05, 10)
	config.phase1ChargeSetDelayMin = BossServiceUtils.CoerceNumber(
		(source :: any).phase1ChargeSetDelayMin,
		config.phase1ChargeSetDelayMin,
		0.25,
		10
	)
	config.phase1ChargeSetDelayMax = BossServiceUtils.CoerceNumber(
		(source :: any).phase1ChargeSetDelayMax,
		config.phase1ChargeSetDelayMax,
		config.phase1ChargeSetDelayMin,
		10
	)
	config.phase1HoverSpeed =
		BossServiceUtils.CoerceNumber((source :: any).phase1HoverSpeed, config.phase1HoverSpeed, 0, 10 ^ 5)
	config.phase1HoverAcceleration = BossServiceUtils.CoerceNumber(
		(source :: any).phase1HoverAcceleration,
		config.phase1HoverAcceleration,
		0,
		10 ^ 5
	)
	config.phase1HoverDamping =
		BossServiceUtils.CoerceNumber((source :: any).phase1HoverDamping, config.phase1HoverDamping, 0, 50)
	config.phase1BobAmplitude =
		BossServiceUtils.CoerceNumber((source :: any).phase1BobAmplitude, config.phase1BobAmplitude, 0, 64)
	config.phase1BobSpeed =
		BossServiceUtils.CoerceNumber((source :: any).phase1BobSpeed, config.phase1BobSpeed, 0, 50)
	config.phase1ChargeWindupDuration = BossServiceUtils.CoerceNumber(
		(source :: any).phase1ChargeWindupDuration,
		config.phase1ChargeWindupDuration,
		0.01,
		10
	)
	config.phase1ChargeSpeed =
		BossServiceUtils.CoerceNumber((source :: any).phase1ChargeSpeed, config.phase1ChargeSpeed, 0, 10 ^ 5)
	config.phase1ChargeDuration =
		BossServiceUtils.CoerceNumber((source :: any).phase1ChargeDuration, config.phase1ChargeDuration, 0.01, 10)
	config.phase1ChargeRecoveryDuration = BossServiceUtils.CoerceNumber(
		(source :: any).phase1ChargeRecoveryDuration,
		config.phase1ChargeRecoveryDuration,
		0.01,
		10
	)
	config.phase1ChargeRecoverySpeed = BossServiceUtils.CoerceNumber(
		(source :: any).phase1ChargeRecoverySpeed,
		config.phase1ChargeRecoverySpeed,
		0,
		10 ^ 5
	)
	config.phase1ChargeRecoveryAcceleration = BossServiceUtils.CoerceNumber(
		(source :: any).phase1ChargeRecoveryAcceleration,
		config.phase1ChargeRecoveryAcceleration,
		0,
		10 ^ 5
	)
	config.phase1ChargeRecoveryDamping = BossServiceUtils.CoerceNumber(
		(source :: any).phase1ChargeRecoveryDamping,
		config.phase1ChargeRecoveryDamping,
		0,
		50
	)
	config.phase1ChargeCount = coerceInteger((source :: any).phase1ChargeCount, config.phase1ChargeCount, 1, 10)
	config.phase1PredictionTime =
		BossServiceUtils.CoerceNumber((source :: any).phase1PredictionTime, config.phase1PredictionTime, 0, 4)
	config.servantBurstCountMin =
		coerceInteger((source :: any).servantBurstCountMin, config.servantBurstCountMin, 0, 32)
	config.servantBurstCountMax = coerceInteger(
		(source :: any).servantBurstCountMax,
		config.servantBurstCountMax,
		config.servantBurstCountMin,
		32
	)
	config.servantBurstInterval =
		BossServiceUtils.CoerceNumber((source :: any).servantBurstInterval, config.servantBurstInterval, 0.01, 10)
	config.servantBurstIntervalMin = BossServiceUtils.CoerceNumber(
		(source :: any).servantBurstIntervalMin,
		config.servantBurstIntervalMin,
		0.01,
		10
	)
	config.servantBurstIntervalMax = BossServiceUtils.CoerceNumber(
		(source :: any).servantBurstIntervalMax,
		config.servantBurstIntervalMax,
		config.servantBurstIntervalMin,
		10
	)
	config.servantBonusBurstOnTransform = BossServiceUtils.CoerceBoolean(
		(source :: any).servantBonusBurstOnTransform,
		config.servantBonusBurstOnTransform
	)
	config.servantExpertBonusCount =
		coerceInteger((source :: any).servantExpertBonusCount, config.servantExpertBonusCount, 0, 32)
	config.servantLimit = coerceInteger((source :: any).servantLimit, config.servantLimit, 0, 64)
	config.maxActiveServants = coerceInteger(
		(source :: any).maxActiveServants,
		if (source :: any).servantLimit ~= nil then config.servantLimit else config.maxActiveServants,
		0,
		64
	)
	config.servantLifetime =
		BossServiceUtils.CoerceNumber((source :: any).servantLifetime, config.servantLifetime, 0.1, 60)
	config.servantSpeed = BossServiceUtils.CoerceNumber((source :: any).servantSpeed, config.servantSpeed, 0, 10 ^ 5)
	config.servantTurnRate =
		BossServiceUtils.CoerceNumber((source :: any).servantTurnRate, config.servantTurnRate, 0, 100)
	config.servantDamage =
		BossServiceUtils.CoerceNumber((source :: any).servantDamage, config.servantDamage, 0, 10 ^ 5)
	config.servantRadius = BossServiceUtils.CoerceNumber((source :: any).servantRadius, config.servantRadius, 0, 64)
	config.servantCooldown =
		BossServiceUtils.CoerceNumber((source :: any).servantCooldown, config.servantCooldown, 0, 10)
	config.transformDuration =
		BossServiceUtils.CoerceNumber((source :: any).transformDuration, config.transformDuration, 0.1, 20)
	config.transformSpinTurns =
		BossServiceUtils.CoerceNumber((source :: any).transformSpinTurns, config.transformSpinTurns, 0, 32)
	config.transformPauseLift =
		BossServiceUtils.CoerceNumber((source :: any).transformPauseLift, config.transformPauseLift, 0, 128)
	config.phase2HoverHeight =
		BossServiceUtils.CoerceNumber((source :: any).phase2HoverHeight, config.phase1HoverHeight, 0, 512)
	config.phase2LeadMultiplier =
		BossServiceUtils.CoerceNumber((source :: any).phase2LeadMultiplier, config.phase1LeadMultiplier, 0, 4)
	config.phase2SideOffset =
		BossServiceUtils.CoerceNumber((source :: any).phase2SideOffset, config.phase1SideOffset, 0, 256)
	config.phase2HoverDuration =
		BossServiceUtils.CoerceNumber((source :: any).phase2HoverDuration, config.phase1HoverDuration, 0.01, 10)
	config.phase2AttackDelayMin = BossServiceUtils.CoerceNumber(
		(source :: any).phase2AttackDelayMin,
		if (source :: any).phase2HoverDuration ~= nil
			then config.phase2HoverDuration
			else config.phase1ChargeSetDelayMin,
		0.01,
		10
	)
	config.phase2AttackDelayMax = BossServiceUtils.CoerceNumber(
		(source :: any).phase2AttackDelayMax,
		if (source :: any).phase2HoverDuration ~= nil
			then config.phase2AttackDelayMin
			else config.phase1ChargeSetDelayMax,
		config.phase2AttackDelayMin,
		10
	)
	config.phase2HoverSpeed =
		BossServiceUtils.CoerceNumber((source :: any).phase2HoverSpeed, config.phase1HoverSpeed, 0, 10 ^ 5)
	config.phase2HoverAcceleration = BossServiceUtils.CoerceNumber(
		(source :: any).phase2HoverAcceleration,
		config.phase1HoverAcceleration,
		0,
		10 ^ 5
	)
	config.phase2HoverDamping =
		BossServiceUtils.CoerceNumber((source :: any).phase2HoverDamping, config.phase1HoverDamping, 0, 50)
	config.phase2BobAmplitude =
		BossServiceUtils.CoerceNumber((source :: any).phase2BobAmplitude, config.phase1BobAmplitude, 0, 64)
	config.phase2BobSpeed =
		BossServiceUtils.CoerceNumber((source :: any).phase2BobSpeed, config.phase1BobSpeed, 0, 50)
	config.phase2ChargeCount = coerceInteger((source :: any).phase2ChargeCount, config.phase1ChargeCount, 1, 10)
	config.phase2ChargeWindupDuration = BossServiceUtils.CoerceNumber(
		(source :: any).phase2ChargeWindupDuration,
		config.phase1ChargeWindupDuration,
		0.01,
		10
	)
	config.phase2ChargeSpeed =
		BossServiceUtils.CoerceNumber((source :: any).phase2ChargeSpeed, config.phase1ChargeSpeed, 0, 10 ^ 5)
	config.phase2ChargeDuration =
		BossServiceUtils.CoerceNumber((source :: any).phase2ChargeDuration, config.phase1ChargeDuration, 0.01, 10)
	config.phase2ChargeRecoveryDuration = BossServiceUtils.CoerceNumber(
		(source :: any).phase2ChargeRecoveryDuration,
		config.phase1ChargeRecoveryDuration,
		0.01,
		10
	)
	config.phase2ChargeRecoverySpeed = BossServiceUtils.CoerceNumber(
		(source :: any).phase2ChargeRecoverySpeed,
		config.phase1ChargeRecoverySpeed,
		0,
		10 ^ 5
	)
	config.phase2ChargeRecoveryAcceleration = BossServiceUtils.CoerceNumber(
		(source :: any).phase2ChargeRecoveryAcceleration,
		config.phase1ChargeRecoveryAcceleration,
		0,
		10 ^ 5
	)
	config.phase2ChargeRecoveryDamping = BossServiceUtils.CoerceNumber(
		(source :: any).phase2ChargeRecoveryDamping,
		config.phase1ChargeRecoveryDamping,
		0,
		50
	)
	config.phase2PredictionTime =
		BossServiceUtils.CoerceNumber((source :: any).phase2PredictionTime, config.phase1PredictionTime, 0, 4)
	config.rapidChainEnabled =
		BossServiceUtils.CoerceBoolean((source :: any).rapidChainEnabled, config.rapidChainEnabled)
	config.rapidChainHealthThreshold = BossServiceUtils.CoerceNumber(
		(source :: any).rapidChainHealthThreshold,
		config.rapidChainHealthThreshold,
		0.01,
		0.95
	)
	config.rapidChainCount = coerceInteger((source :: any).rapidChainCount, config.rapidChainCount, 1, 16)
	config.rapidChainWindupDuration = BossServiceUtils.CoerceNumber(
		(source :: any).rapidChainWindupDuration,
		config.rapidChainWindupDuration,
		0.01,
		10
	)
	config.rapidChainRecoveryDuration = BossServiceUtils.CoerceNumber(
		(source :: any).rapidChainRecoveryDuration,
		config.rapidChainRecoveryDuration,
		0,
		10
	)
	config.rapidChainBaseSpeed =
		BossServiceUtils.CoerceNumber((source :: any).rapidChainBaseSpeed, config.rapidChainBaseSpeed, 0, 10 ^ 5)
	config.rapidChainTopSpeed =
		BossServiceUtils.CoerceNumber((source :: any).rapidChainTopSpeed, config.rapidChainTopSpeed, 0, 10 ^ 5)
	config.rapidChainPredictionTime =
		BossServiceUtils.CoerceNumber((source :: any).rapidChainPredictionTime, config.rapidChainPredictionTime, 0, 4)
	config.targetLostGraceSeconds =
		BossServiceUtils.CoerceNumber((source :: any).targetLostGraceSeconds, config.targetLostGraceSeconds, 0, 60)
	config.despawnRiseSpeed =
		BossServiceUtils.CoerceNumber((source :: any).despawnRiseSpeed, config.despawnRiseSpeed, 0, 10 ^ 5)
	config.despawnForwardSpeed =
		BossServiceUtils.CoerceNumber((source :: any).despawnForwardSpeed, config.despawnForwardSpeed, 0, 10 ^ 5)
	config.despawnAcceleration =
		BossServiceUtils.CoerceNumber((source :: any).despawnAcceleration, config.despawnAcceleration, 0, 10 ^ 5)
	config.deathDuration = BossServiceUtils.CoerceNumber((source :: any).deathDuration, config.deathDuration, 0.1, 30)
	config.naturalSpawnEnabled =
		BossServiceUtils.CoerceBoolean((source :: any).naturalSpawnEnabled, config.naturalSpawnEnabled)
	config.naturalSpawnChancePerNight = BossServiceUtils.CoerceNumber(
		(source :: any).naturalSpawnChancePerNight,
		config.naturalSpawnChancePerNight,
		0,
		1
	)
	config.naturalSpawnAnnouncementDelay = BossServiceUtils.CoerceNumber(
		(source :: any).naturalSpawnAnnouncementDelay,
		config.naturalSpawnAnnouncementDelay,
		0,
		30
	)
	config.simulationSpeed =
		BossServiceUtils.CoerceNumber((source :: any).simulationSpeed, config.simulationSpeed, 0.05, 5)
	config.aggressiveness =
		BossServiceUtils.CoerceNumber((source :: any).aggressiveness, config.aggressiveness, 0.1, 3)
	config.expertBehaviorEnabled =
		BossServiceUtils.CoerceBoolean((source :: any).expertBehaviorEnabled, config.expertBehaviorEnabled)

	return config
end

return EyeOfCthulhuConfig
