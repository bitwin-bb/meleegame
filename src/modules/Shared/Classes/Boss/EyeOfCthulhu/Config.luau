--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossService.BossServiceUtils)

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
	defensePhase2 = 0,
	contactDamagePhase1 = 15,
	contactDamagePhase2 = 23,
	contactDamageRadiusPhase1 = 10.5,
	contactDamageRadiusPhase2 = 12.5,
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
	servantSpeed = 40,
	servantTurnRate = 6.5,
	servantDamage = 11,
	servantRadius = 3,
	servantCooldown = 1.5,
	transformDuration = 2.25,
	transformSpinTurns = 8,
	transformPauseLift = 8,
	phase2HoverHeight = 13,
	phase2LeadMultiplier = 0.22,
	phase2SideOffset = 7,
	phase2HoverDuration = 4,
	phase2AttackDelayMin = 2.0,
	phase2AttackDelayMax = 4.0,
	phase2HoverSpeed = 17,
	phase2HoverAcceleration = 168,
	phase2HoverDamping = 0.38,
	phase2BobAmplitude = 1.7,
	phase2BobSpeed = 6.4,
	phase2ChargeCount = 3,
	phase2ChargeWindupDuration = 0.18,
	phase2ChargeSpeed = 30,
	phase2ChargeDuration = 1.4,
	phase2ChargeRecoveryDuration = 0.2,
	phase2ChargeRecoverySpeed = 58,
	phase2ChargeRecoveryAcceleration = 188,
	phase2ChargeRecoveryDamping = 0.9,
	phase2PredictionTime = 0.18,
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

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	return math.floor(BossServiceUtils.sanitizeNumber(valueRaw, fallback, minimum, maximum))
end

function EyeOfCthulhuConfig.GetDefaults(): EyeOfCthulhuConfig
	return cloneDefaults()
end

function EyeOfCthulhuConfig.Resolve(configRaw: any): EyeOfCthulhuConfig
	local config = cloneDefaults()
	local source = if typeof(configRaw) == "table" then configRaw else {}

	config.maxHp = sanitizeInteger((source :: any).maxHp, config.maxHp, 1, 10 ^ 9)
	config.defensePhase1 =
		BossServiceUtils.sanitizeNumber((source :: any).defensePhase1, config.defensePhase1, 0, 10 ^ 6)
	config.defensePhase2 =
		BossServiceUtils.sanitizeNumber((source :: any).defensePhase2, config.defensePhase2, 0, 10 ^ 6)
	config.contactDamagePhase1 =
		BossServiceUtils.sanitizeNumber((source :: any).contactDamagePhase1, config.contactDamagePhase1, 0, 10 ^ 6)
	config.contactDamagePhase2 =
		BossServiceUtils.sanitizeNumber((source :: any).contactDamagePhase2, config.contactDamagePhase2, 0, 10 ^ 6)
	config.contactDamageRadiusPhase1 = BossServiceUtils.sanitizeNumber(
		(source :: any).contactDamageRadiusPhase1,
		config.contactDamageRadiusPhase1,
		0,
		256
	)
	config.contactDamageRadiusPhase2 = BossServiceUtils.sanitizeNumber(
		(source :: any).contactDamageRadiusPhase2,
		config.contactDamageRadiusPhase2,
		0,
		256
	)
	config.contactDamageCooldown =
		BossServiceUtils.sanitizeNumber((source :: any).contactDamageCooldown, config.contactDamageCooldown, 0, 30)
	config.transformHealthThreshold = BossServiceUtils.sanitizeNumber(
		(source :: any).transformHealthThreshold,
		config.transformHealthThreshold,
		0.05,
		0.95
	)
	config.introDuration = BossServiceUtils.sanitizeNumber((source :: any).introDuration, config.introDuration, 0.1, 20)
	config.introHeight = BossServiceUtils.sanitizeNumber((source :: any).introHeight, config.introHeight, 0, 512)
	config.introDistance = BossServiceUtils.sanitizeNumber((source :: any).introDistance, config.introDistance, 8, 512)
	config.introDriftAmplitude =
		BossServiceUtils.sanitizeNumber((source :: any).introDriftAmplitude, config.introDriftAmplitude, 0, 128)
	config.introDriftSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).introDriftSpeed, config.introDriftSpeed, 0, 30)
	config.phase1HoverHeight =
		BossServiceUtils.sanitizeNumber((source :: any).phase1HoverHeight, config.phase1HoverHeight, 0, 512)
	config.phase1LeadMultiplier =
		BossServiceUtils.sanitizeNumber((source :: any).phase1LeadMultiplier, config.phase1LeadMultiplier, 0, 4)
	config.phase1SideOffset =
		BossServiceUtils.sanitizeNumber((source :: any).phase1SideOffset, config.phase1SideOffset, 0, 256)
	config.phase1HoverDuration =
		BossServiceUtils.sanitizeNumber((source :: any).phase1HoverDuration, config.phase1HoverDuration, 0.05, 10)
	config.phase1ChargeSetDelayMin = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1ChargeSetDelayMin,
		config.phase1ChargeSetDelayMin,
		0.25,
		10
	)
	config.phase1ChargeSetDelayMax = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1ChargeSetDelayMax,
		config.phase1ChargeSetDelayMax,
		config.phase1ChargeSetDelayMin,
		10
	)
	config.phase1HoverSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).phase1HoverSpeed, config.phase1HoverSpeed, 0, 10 ^ 5)
	config.phase1HoverAcceleration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1HoverAcceleration,
		config.phase1HoverAcceleration,
		0,
		10 ^ 5
	)
	config.phase1HoverDamping =
		BossServiceUtils.sanitizeNumber((source :: any).phase1HoverDamping, config.phase1HoverDamping, 0, 50)
	config.phase1BobAmplitude =
		BossServiceUtils.sanitizeNumber((source :: any).phase1BobAmplitude, config.phase1BobAmplitude, 0, 64)
	config.phase1BobSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).phase1BobSpeed, config.phase1BobSpeed, 0, 50)
	config.phase1ChargeWindupDuration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1ChargeWindupDuration,
		config.phase1ChargeWindupDuration,
		0.01,
		10
	)
	config.phase1ChargeSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).phase1ChargeSpeed, config.phase1ChargeSpeed, 0, 10 ^ 5)
	config.phase1ChargeDuration =
		BossServiceUtils.sanitizeNumber((source :: any).phase1ChargeDuration, config.phase1ChargeDuration, 0.01, 10)
	config.phase1ChargeRecoveryDuration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1ChargeRecoveryDuration,
		config.phase1ChargeRecoveryDuration,
		0.01,
		10
	)
	config.phase1ChargeRecoverySpeed = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1ChargeRecoverySpeed,
		config.phase1ChargeRecoverySpeed,
		0,
		10 ^ 5
	)
	config.phase1ChargeRecoveryAcceleration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1ChargeRecoveryAcceleration,
		config.phase1ChargeRecoveryAcceleration,
		0,
		10 ^ 5
	)
	config.phase1ChargeRecoveryDamping = BossServiceUtils.sanitizeNumber(
		(source :: any).phase1ChargeRecoveryDamping,
		config.phase1ChargeRecoveryDamping,
		0,
		50
	)
	config.phase1ChargeCount = sanitizeInteger((source :: any).phase1ChargeCount, config.phase1ChargeCount, 1, 10)
	config.phase1PredictionTime =
		BossServiceUtils.sanitizeNumber((source :: any).phase1PredictionTime, config.phase1PredictionTime, 0, 4)
	config.servantBurstCountMin =
		sanitizeInteger((source :: any).servantBurstCountMin, config.servantBurstCountMin, 0, 32)
	config.servantBurstCountMax = sanitizeInteger(
		(source :: any).servantBurstCountMax,
		config.servantBurstCountMax,
		config.servantBurstCountMin,
		32
	)
	config.servantBurstInterval =
		BossServiceUtils.sanitizeNumber((source :: any).servantBurstInterval, config.servantBurstInterval, 0.01, 10)
	config.servantBurstIntervalMin = BossServiceUtils.sanitizeNumber(
		(source :: any).servantBurstIntervalMin,
		config.servantBurstIntervalMin,
		0.01,
		10
	)
	config.servantBurstIntervalMax = BossServiceUtils.sanitizeNumber(
		(source :: any).servantBurstIntervalMax,
		config.servantBurstIntervalMax,
		config.servantBurstIntervalMin,
		10
	)
	config.servantBonusBurstOnTransform = BossServiceUtils.sanitizeBoolean(
		(source :: any).servantBonusBurstOnTransform,
		config.servantBonusBurstOnTransform
	)
	config.servantExpertBonusCount =
		sanitizeInteger((source :: any).servantExpertBonusCount, config.servantExpertBonusCount, 0, 32)
	config.servantLimit = sanitizeInteger((source :: any).servantLimit, config.servantLimit, 0, 64)
	config.maxActiveServants = sanitizeInteger(
		(source :: any).maxActiveServants,
		if (source :: any).servantLimit ~= nil then config.servantLimit else config.maxActiveServants,
		0,
		64
	)
	config.servantLifetime =
		BossServiceUtils.sanitizeNumber((source :: any).servantLifetime, config.servantLifetime, 0.1, 60)
	config.servantSpeed = BossServiceUtils.sanitizeNumber((source :: any).servantSpeed, config.servantSpeed, 0, 10 ^ 5)
	config.servantTurnRate =
		BossServiceUtils.sanitizeNumber((source :: any).servantTurnRate, config.servantTurnRate, 0, 100)
	config.servantDamage =
		BossServiceUtils.sanitizeNumber((source :: any).servantDamage, config.servantDamage, 0, 10 ^ 5)
	config.servantRadius = BossServiceUtils.sanitizeNumber((source :: any).servantRadius, config.servantRadius, 0, 64)
	config.servantCooldown =
		BossServiceUtils.sanitizeNumber((source :: any).servantCooldown, config.servantCooldown, 0, 10)
	config.transformDuration =
		BossServiceUtils.sanitizeNumber((source :: any).transformDuration, config.transformDuration, 0.1, 20)
	config.transformSpinTurns =
		BossServiceUtils.sanitizeNumber((source :: any).transformSpinTurns, config.transformSpinTurns, 0, 32)
	config.transformPauseLift =
		BossServiceUtils.sanitizeNumber((source :: any).transformPauseLift, config.transformPauseLift, 0, 128)
	config.phase2HoverHeight =
		BossServiceUtils.sanitizeNumber((source :: any).phase2HoverHeight, config.phase2HoverHeight, 0, 512)
	config.phase2LeadMultiplier =
		BossServiceUtils.sanitizeNumber((source :: any).phase2LeadMultiplier, config.phase2LeadMultiplier, 0, 4)
	config.phase2SideOffset =
		BossServiceUtils.sanitizeNumber((source :: any).phase2SideOffset, config.phase2SideOffset, 0, 256)
	config.phase2HoverDuration =
		BossServiceUtils.sanitizeNumber((source :: any).phase2HoverDuration, config.phase2HoverDuration, 0.01, 10)
	config.phase2AttackDelayMin = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2AttackDelayMin,
		if (source :: any).phase2HoverDuration ~= nil then config.phase2HoverDuration else config.phase2AttackDelayMin,
		0.01,
		10
	)
	config.phase2AttackDelayMax = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2AttackDelayMax,
		if (source :: any).phase2HoverDuration ~= nil then config.phase2AttackDelayMin else config.phase2AttackDelayMax,
		config.phase2AttackDelayMin,
		10
	)
	config.phase2HoverSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).phase2HoverSpeed, config.phase2HoverSpeed, 0, 10 ^ 5)
	config.phase2HoverAcceleration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2HoverAcceleration,
		config.phase2HoverAcceleration,
		0,
		10 ^ 5
	)
	config.phase2HoverDamping =
		BossServiceUtils.sanitizeNumber((source :: any).phase2HoverDamping, config.phase2HoverDamping, 0, 50)
	config.phase2BobAmplitude =
		BossServiceUtils.sanitizeNumber((source :: any).phase2BobAmplitude, config.phase2BobAmplitude, 0, 64)
	config.phase2BobSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).phase2BobSpeed, config.phase2BobSpeed, 0, 50)
	config.phase2ChargeCount = sanitizeInteger((source :: any).phase2ChargeCount, config.phase2ChargeCount, 1, 10)
	config.phase2ChargeWindupDuration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2ChargeWindupDuration,
		config.phase2ChargeWindupDuration,
		0.01,
		10
	)
	config.phase2ChargeSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).phase2ChargeSpeed, config.phase2ChargeSpeed, 0, 10 ^ 5)
	config.phase2ChargeDuration =
		BossServiceUtils.sanitizeNumber((source :: any).phase2ChargeDuration, config.phase2ChargeDuration, 0.01, 10)
	config.phase2ChargeRecoveryDuration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2ChargeRecoveryDuration,
		config.phase2ChargeRecoveryDuration,
		0.01,
		10
	)
	config.phase2ChargeRecoverySpeed = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2ChargeRecoverySpeed,
		config.phase2ChargeRecoverySpeed,
		0,
		10 ^ 5
	)
	config.phase2ChargeRecoveryAcceleration = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2ChargeRecoveryAcceleration,
		config.phase2ChargeRecoveryAcceleration,
		0,
		10 ^ 5
	)
	config.phase2ChargeRecoveryDamping = BossServiceUtils.sanitizeNumber(
		(source :: any).phase2ChargeRecoveryDamping,
		config.phase2ChargeRecoveryDamping,
		0,
		50
	)
	config.phase2PredictionTime =
		BossServiceUtils.sanitizeNumber((source :: any).phase2PredictionTime, config.phase2PredictionTime, 0, 4)
	config.rapidChainEnabled =
		BossServiceUtils.sanitizeBoolean((source :: any).rapidChainEnabled, config.rapidChainEnabled)
	config.rapidChainHealthThreshold = BossServiceUtils.sanitizeNumber(
		(source :: any).rapidChainHealthThreshold,
		config.rapidChainHealthThreshold,
		0.01,
		0.95
	)
	config.rapidChainCount = sanitizeInteger((source :: any).rapidChainCount, config.rapidChainCount, 1, 16)
	config.rapidChainWindupDuration = BossServiceUtils.sanitizeNumber(
		(source :: any).rapidChainWindupDuration,
		config.rapidChainWindupDuration,
		0.01,
		10
	)
	config.rapidChainRecoveryDuration = BossServiceUtils.sanitizeNumber(
		(source :: any).rapidChainRecoveryDuration,
		config.rapidChainRecoveryDuration,
		0,
		10
	)
	config.rapidChainBaseSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).rapidChainBaseSpeed, config.rapidChainBaseSpeed, 0, 10 ^ 5)
	config.rapidChainTopSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).rapidChainTopSpeed, config.rapidChainTopSpeed, 0, 10 ^ 5)
	config.rapidChainPredictionTime =
		BossServiceUtils.sanitizeNumber((source :: any).rapidChainPredictionTime, config.rapidChainPredictionTime, 0, 4)
	config.targetLostGraceSeconds =
		BossServiceUtils.sanitizeNumber((source :: any).targetLostGraceSeconds, config.targetLostGraceSeconds, 0, 60)
	config.despawnRiseSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).despawnRiseSpeed, config.despawnRiseSpeed, 0, 10 ^ 5)
	config.despawnForwardSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).despawnForwardSpeed, config.despawnForwardSpeed, 0, 10 ^ 5)
	config.despawnAcceleration =
		BossServiceUtils.sanitizeNumber((source :: any).despawnAcceleration, config.despawnAcceleration, 0, 10 ^ 5)
	config.deathDuration = BossServiceUtils.sanitizeNumber((source :: any).deathDuration, config.deathDuration, 0.1, 30)
	config.naturalSpawnEnabled =
		BossServiceUtils.sanitizeBoolean((source :: any).naturalSpawnEnabled, config.naturalSpawnEnabled)
	config.naturalSpawnChancePerNight = BossServiceUtils.sanitizeNumber(
		(source :: any).naturalSpawnChancePerNight,
		config.naturalSpawnChancePerNight,
		0,
		1
	)
	config.naturalSpawnAnnouncementDelay = BossServiceUtils.sanitizeNumber(
		(source :: any).naturalSpawnAnnouncementDelay,
		config.naturalSpawnAnnouncementDelay,
		0,
		30
	)
	config.simulationSpeed =
		BossServiceUtils.sanitizeNumber((source :: any).simulationSpeed, config.simulationSpeed, 0.05, 5)
	config.aggressiveness =
		BossServiceUtils.sanitizeNumber((source :: any).aggressiveness, config.aggressiveness, 0.1, 3)
	config.expertBehaviorEnabled =
		BossServiceUtils.sanitizeBoolean((source :: any).expertBehaviorEnabled, config.expertBehaviorEnabled)

	return config
end

EyeOfCthulhuConfig.getDefaults = EyeOfCthulhuConfig.GetDefaults
EyeOfCthulhuConfig.resolve = EyeOfCthulhuConfig.Resolve

return EyeOfCthulhuConfig
