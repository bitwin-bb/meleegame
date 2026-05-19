--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Table = loader("Table")

local Configs = {}

export type QueenBeeState =
	"AcquireTarget"
	| "ChooseAttack"
	| "ChargeReposition"
	| "ChargeWindup"
	| "Charge"
	| "PostChargeRecover"
	| "StingerHover"
	| "BeeSummonHover"
	| "Despawn"

export type QueenBeePhase = number

export type EnrageContext = {
	queenBee: any?,
	model: Model?,
	rootPart: BasePart?,
	targetPlayer: Player?,
	phase: number,
	healthRatio: number,
	state: QueenBeeState,
	services: any?,
}

export type QueenBeeConfig = {
	Phase2HealthRatio: number,
	Phase3HealthRatio: number,
	AggroRange: number,
	DespawnRange: number,
	TargetLostGraceTime: number,
	HoverSideDistance: number,
	HoverAboveOffset: number,
	HoverArriveRadius: number,
	HoverSpeedByPhase: { [number]: number },
	HoverAccelerationByPhase: { [number]: number },
	HoverDamping: number,
	ChargeRepositionMaxTimeByPhase: { [number]: number },
	ChargePredictionTime: number,
	ChargeWindupByPhase: { [number]: number },
	ChargeSpeedByPhase: { [number]: number },
	ChargeDurationByPhase: { [number]: number },
	ChargePassDistance: number,
	PostChargeRecoverTime: number,
	ChargesPerComboByPhase: { [number]: number },
	StingerHoverDuration: number,
	StingerSideDistance: number,
	StingerAboveOffset: number,
	StingerHoverSpeedMultiplier: number,
	StingerFireIntervalByPhase: { [number]: number },
	StingerSpeed: number,
	StingerLifetime: number,
	StingerSpreadDegreesByPhase: { [number]: number },
	StingerDamage: number,
	StingerHitRadius: number,
	BeeSummonDuration: number,
	BeeSummonSideDistance: number,
	BeeSummonAboveOffset: number,
	BeeSummonHoverSpeedMultiplier: number,
	BeeSpawnIntervalByPhase: { [number]: number },
	BeeBurstCountByPhase: { [number]: number },
	BeeLifetime: number,
	BeeScatterDuration: number,
	BeeScatterSpeed: number,
	BeeSpeedByPhase: { [number]: number },
	BeeAccelerationByPhase: { [number]: number },
	BeeDashSpeedByPhase: { [number]: number },
	BeeDamage: number,
	BeeHitRadius: number,
	ContactDamage: number,
	ContactHitRadius: number,
	ContactCooldown: number,
	DespawnSpeed: number,
	DespawnAcceleration: number,
	DespawnDuration: number,
	MaxDt: number,
	Debug: boolean,
	EnrageSpeedMultiplier: number,
	EnrageCadenceMultiplier: number,
	IsEnraged: (context: EnrageContext) -> boolean,
}

local STATES: { [string]: QueenBeeState } = table.freeze(Table.copy({
	AcquireTarget = "AcquireTarget" :: QueenBeeState,
	ChooseAttack = "ChooseAttack" :: QueenBeeState,
	ChargeReposition = "ChargeReposition" :: QueenBeeState,
	ChargeWindup = "ChargeWindup" :: QueenBeeState,
	Charge = "Charge" :: QueenBeeState,
	PostChargeRecover = "PostChargeRecover" :: QueenBeeState,
	StingerHover = "StingerHover" :: QueenBeeState,
	BeeSummonHover = "BeeSummonHover" :: QueenBeeState,
	Despawn = "Despawn" :: QueenBeeState,
})) :: any

local function defaultIsEnraged(_context: EnrageContext): boolean
	return false
end

local DEFAULTS: QueenBeeConfig = {
	Phase2HealthRatio = 0.66,
	Phase3HealthRatio = 0.33,
	AggroRange = 360,
	DespawnRange = 520,
	TargetLostGraceTime = 3.5,
	HoverSideDistance = 54,
	HoverAboveOffset = 22,
	HoverArriveRadius = 4.5,
	HoverSpeedByPhase = {
		[1] = 36,
		[2] = 45,
		[3] = 58,
	},
	HoverAccelerationByPhase = {
		[1] = 165,
		[2] = 220,
		[3] = 290,
	},
	HoverDamping = 5.2,
	ChargeRepositionMaxTimeByPhase = {
		[1] = 1.45,
		[2] = 1.2,
		[3] = 0.95,
	},
	ChargePredictionTime = 0.18,
	ChargeWindupByPhase = {
		[1] = 0.52,
		[2] = 0.4,
		[3] = 0.28,
	},
	ChargeSpeedByPhase = {
		[1] = 118,
		[2] = 145,
		[3] = 176,
	},
	ChargeDurationByPhase = {
		[1] = 0.72,
		[2] = 0.64,
		[3] = 0.56,
	},
	ChargePassDistance = 18,
	PostChargeRecoverTime = 0.28,
	ChargesPerComboByPhase = {
		[1] = 3,
		[2] = 4,
		[3] = 6,
	},
	StingerHoverDuration = 4.0,
	StingerSideDistance = 42,
	StingerAboveOffset = 18,
	StingerHoverSpeedMultiplier = 0.82,
	StingerFireIntervalByPhase = {
		[1] = 0.56,
		[2] = 0.42,
		[3] = 0.3,
	},
	StingerSpeed = 124,
	StingerLifetime = 4.2,
	StingerSpreadDegreesByPhase = {
		[1] = 3.5,
		[2] = 5,
		[3] = 7,
	},
	StingerDamage = 18,
	StingerHitRadius = 2.5,
	BeeSummonDuration = 3.2,
	BeeSummonSideDistance = 12,
	BeeSummonAboveOffset = 32,
	BeeSummonHoverSpeedMultiplier = 0.64,
	BeeSpawnIntervalByPhase = {
		[1] = 0.86,
		[2] = 0.68,
		[3] = 0.52,
	},
	BeeBurstCountByPhase = {
		[1] = 2,
		[2] = 3,
		[3] = 4,
	},
	BeeLifetime = 7,
	BeeScatterDuration = 0.34,
	BeeScatterSpeed = 32,
	BeeSpeedByPhase = {
		[1] = 44,
		[2] = 54,
		[3] = 66,
	},
	BeeAccelerationByPhase = {
		[1] = 135,
		[2] = 170,
		[3] = 220,
	},
	BeeDashSpeedByPhase = {
		[1] = 78,
		[2] = 94,
		[3] = 112,
	},
	BeeDamage = 11,
	BeeHitRadius = 3.2,
	ContactDamage = 28,
	ContactHitRadius = 8.5,
	ContactCooldown = 0.45,
	DespawnSpeed = 118,
	DespawnAcceleration = 260,
	DespawnDuration = 2.4,
	MaxDt = 1 / 20,
	Debug = false,
	EnrageSpeedMultiplier = 1.18,
	EnrageCadenceMultiplier = 0.72,
	IsEnraged = defaultIsEnraged,
}

Configs.States = STATES
Configs.DEFAULTS = DEFAULTS

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

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	return math.floor(sanitizeNumber(valueRaw, fallback, minimum, maximum))
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function cloneNumberMap(source: { [number]: number }): { [number]: number }
	local copy = Table.copy(source)
	return {
		[1] = sanitizeNumber(copy[1], source[1] or 0, 0, nil),
		[2] = sanitizeNumber(copy[2], source[2] or source[1] or 0, 0, nil),
		[3] = sanitizeNumber(copy[3], source[3] or source[2] or source[1] or 0, 0, nil),
	}
end

local function resolveNumberMap(
	source: { [any]: any },
	key: string,
	fallback: { [number]: number },
	minimum: number,
	maximum: number?
): { [number]: number }
	local raw = source[key]
	if typeof(raw) ~= "table" then
		return cloneNumberMap(fallback)
	end

	return {
		[1] = sanitizeNumber((raw :: any)[1], fallback[1], minimum, maximum),
		[2] = sanitizeNumber((raw :: any)[2], fallback[2], minimum, maximum),
		[3] = sanitizeNumber((raw :: any)[3], fallback[3], minimum, maximum),
	}
end

local function cloneDefaults(): QueenBeeConfig
	return {
		Phase2HealthRatio = DEFAULTS.Phase2HealthRatio,
		Phase3HealthRatio = DEFAULTS.Phase3HealthRatio,
		AggroRange = DEFAULTS.AggroRange,
		DespawnRange = DEFAULTS.DespawnRange,
		TargetLostGraceTime = DEFAULTS.TargetLostGraceTime,
		HoverSideDistance = DEFAULTS.HoverSideDistance,
		HoverAboveOffset = DEFAULTS.HoverAboveOffset,
		HoverArriveRadius = DEFAULTS.HoverArriveRadius,
		HoverSpeedByPhase = cloneNumberMap(DEFAULTS.HoverSpeedByPhase),
		HoverAccelerationByPhase = cloneNumberMap(DEFAULTS.HoverAccelerationByPhase),
		HoverDamping = DEFAULTS.HoverDamping,
		ChargeRepositionMaxTimeByPhase = cloneNumberMap(DEFAULTS.ChargeRepositionMaxTimeByPhase),
		ChargePredictionTime = DEFAULTS.ChargePredictionTime,
		ChargeWindupByPhase = cloneNumberMap(DEFAULTS.ChargeWindupByPhase),
		ChargeSpeedByPhase = cloneNumberMap(DEFAULTS.ChargeSpeedByPhase),
		ChargeDurationByPhase = cloneNumberMap(DEFAULTS.ChargeDurationByPhase),
		ChargePassDistance = DEFAULTS.ChargePassDistance,
		PostChargeRecoverTime = DEFAULTS.PostChargeRecoverTime,
		ChargesPerComboByPhase = cloneNumberMap(DEFAULTS.ChargesPerComboByPhase),
		StingerHoverDuration = DEFAULTS.StingerHoverDuration,
		StingerSideDistance = DEFAULTS.StingerSideDistance,
		StingerAboveOffset = DEFAULTS.StingerAboveOffset,
		StingerHoverSpeedMultiplier = DEFAULTS.StingerHoverSpeedMultiplier,
		StingerFireIntervalByPhase = cloneNumberMap(DEFAULTS.StingerFireIntervalByPhase),
		StingerSpeed = DEFAULTS.StingerSpeed,
		StingerLifetime = DEFAULTS.StingerLifetime,
		StingerSpreadDegreesByPhase = cloneNumberMap(DEFAULTS.StingerSpreadDegreesByPhase),
		StingerDamage = DEFAULTS.StingerDamage,
		StingerHitRadius = DEFAULTS.StingerHitRadius,
		BeeSummonDuration = DEFAULTS.BeeSummonDuration,
		BeeSummonSideDistance = DEFAULTS.BeeSummonSideDistance,
		BeeSummonAboveOffset = DEFAULTS.BeeSummonAboveOffset,
		BeeSummonHoverSpeedMultiplier = DEFAULTS.BeeSummonHoverSpeedMultiplier,
		BeeSpawnIntervalByPhase = cloneNumberMap(DEFAULTS.BeeSpawnIntervalByPhase),
		BeeBurstCountByPhase = cloneNumberMap(DEFAULTS.BeeBurstCountByPhase),
		BeeLifetime = DEFAULTS.BeeLifetime,
		BeeScatterDuration = DEFAULTS.BeeScatterDuration,
		BeeScatterSpeed = DEFAULTS.BeeScatterSpeed,
		BeeSpeedByPhase = cloneNumberMap(DEFAULTS.BeeSpeedByPhase),
		BeeAccelerationByPhase = cloneNumberMap(DEFAULTS.BeeAccelerationByPhase),
		BeeDashSpeedByPhase = cloneNumberMap(DEFAULTS.BeeDashSpeedByPhase),
		BeeDamage = DEFAULTS.BeeDamage,
		BeeHitRadius = DEFAULTS.BeeHitRadius,
		ContactDamage = DEFAULTS.ContactDamage,
		ContactHitRadius = DEFAULTS.ContactHitRadius,
		ContactCooldown = DEFAULTS.ContactCooldown,
		DespawnSpeed = DEFAULTS.DespawnSpeed,
		DespawnAcceleration = DEFAULTS.DespawnAcceleration,
		DespawnDuration = DEFAULTS.DespawnDuration,
		MaxDt = DEFAULTS.MaxDt,
		Debug = DEFAULTS.Debug,
		EnrageSpeedMultiplier = DEFAULTS.EnrageSpeedMultiplier,
		EnrageCadenceMultiplier = DEFAULTS.EnrageCadenceMultiplier,
		IsEnraged = DEFAULTS.IsEnraged,
	}
end

function Configs.GetDefaults(): QueenBeeConfig
	return cloneDefaults()
end

function Configs.Resolve(configRaw: any): QueenBeeConfig
	local config = cloneDefaults()
	local source = (if typeof(configRaw) == "table" then configRaw else {}) :: any

	config.Phase2HealthRatio = sanitizeNumber(source.Phase2HealthRatio, config.Phase2HealthRatio, 0.05, 0.95)
	config.Phase3HealthRatio =
		sanitizeNumber(source.Phase3HealthRatio, config.Phase3HealthRatio, 0.01, config.Phase2HealthRatio)
	config.AggroRange = sanitizeNumber(source.AggroRange, config.AggroRange, 0, 10 ^ 5)
	config.DespawnRange = sanitizeNumber(source.DespawnRange, config.DespawnRange, config.AggroRange, 10 ^ 5)
	config.TargetLostGraceTime = sanitizeNumber(source.TargetLostGraceTime, config.TargetLostGraceTime, 0, 60)
	config.HoverSideDistance = sanitizeNumber(source.HoverSideDistance, config.HoverSideDistance, 0, 10 ^ 5)
	config.HoverAboveOffset = sanitizeNumber(source.HoverAboveOffset, config.HoverAboveOffset, -10 ^ 5, 10 ^ 5)
	config.HoverArriveRadius = sanitizeNumber(source.HoverArriveRadius, config.HoverArriveRadius, 0, 10 ^ 5)
	config.HoverSpeedByPhase = resolveNumberMap(source, "HoverSpeedByPhase", config.HoverSpeedByPhase, 0, 10 ^ 5)
	config.HoverAccelerationByPhase =
		resolveNumberMap(source, "HoverAccelerationByPhase", config.HoverAccelerationByPhase, 0, 10 ^ 5)
	config.HoverDamping = sanitizeNumber(source.HoverDamping, config.HoverDamping, 0, 1000)
	config.ChargeRepositionMaxTimeByPhase =
		resolveNumberMap(source, "ChargeRepositionMaxTimeByPhase", config.ChargeRepositionMaxTimeByPhase, 0.01, 60)
	config.ChargePredictionTime = sanitizeNumber(source.ChargePredictionTime, config.ChargePredictionTime, 0, 5)
	config.ChargeWindupByPhase = resolveNumberMap(source, "ChargeWindupByPhase", config.ChargeWindupByPhase, 0.01, 10)
	config.ChargeSpeedByPhase = resolveNumberMap(source, "ChargeSpeedByPhase", config.ChargeSpeedByPhase, 0, 10 ^ 5)
	config.ChargeDurationByPhase =
		resolveNumberMap(source, "ChargeDurationByPhase", config.ChargeDurationByPhase, 0.01, 10)
	config.ChargePassDistance = sanitizeNumber(source.ChargePassDistance, config.ChargePassDistance, 0, 10 ^ 5)
	config.PostChargeRecoverTime = sanitizeNumber(source.PostChargeRecoverTime, config.PostChargeRecoverTime, 0, 10)
	config.ChargesPerComboByPhase =
		resolveNumberMap(source, "ChargesPerComboByPhase", config.ChargesPerComboByPhase, 1, 16)
	config.ChargesPerComboByPhase[1] = sanitizeInteger(config.ChargesPerComboByPhase[1], 3, 1, 16)
	config.ChargesPerComboByPhase[2] = sanitizeInteger(config.ChargesPerComboByPhase[2], 4, 1, 16)
	config.ChargesPerComboByPhase[3] = sanitizeInteger(config.ChargesPerComboByPhase[3], 6, 1, 16)
	config.StingerHoverDuration = sanitizeNumber(source.StingerHoverDuration, config.StingerHoverDuration, 0.05, 30)
	config.StingerSideDistance = sanitizeNumber(source.StingerSideDistance, config.StingerSideDistance, 0, 10 ^ 5)
	config.StingerAboveOffset = sanitizeNumber(source.StingerAboveOffset, config.StingerAboveOffset, -10 ^ 5, 10 ^ 5)
	config.StingerHoverSpeedMultiplier =
		sanitizeNumber(source.StingerHoverSpeedMultiplier, config.StingerHoverSpeedMultiplier, 0, 10)
	config.StingerFireIntervalByPhase =
		resolveNumberMap(source, "StingerFireIntervalByPhase", config.StingerFireIntervalByPhase, 0.01, 30)
	config.StingerSpeed = sanitizeNumber(source.StingerSpeed, config.StingerSpeed, 0, 10 ^ 5)
	config.StingerLifetime = sanitizeNumber(source.StingerLifetime, config.StingerLifetime, 0.05, 30)
	config.StingerSpreadDegreesByPhase =
		resolveNumberMap(source, "StingerSpreadDegreesByPhase", config.StingerSpreadDegreesByPhase, 0, 90)
	config.StingerDamage = sanitizeNumber(source.StingerDamage, config.StingerDamage, 0, 10 ^ 6)
	config.StingerHitRadius = sanitizeNumber(source.StingerHitRadius, config.StingerHitRadius, 0, 256)
	config.BeeSummonDuration = sanitizeNumber(source.BeeSummonDuration, config.BeeSummonDuration, 0.05, 30)
	config.BeeSummonSideDistance = sanitizeNumber(source.BeeSummonSideDistance, config.BeeSummonSideDistance, 0, 10 ^ 5)
	config.BeeSummonAboveOffset =
		sanitizeNumber(source.BeeSummonAboveOffset, config.BeeSummonAboveOffset, -10 ^ 5, 10 ^ 5)
	config.BeeSummonHoverSpeedMultiplier =
		sanitizeNumber(source.BeeSummonHoverSpeedMultiplier, config.BeeSummonHoverSpeedMultiplier, 0, 10)
	config.BeeSpawnIntervalByPhase =
		resolveNumberMap(source, "BeeSpawnIntervalByPhase", config.BeeSpawnIntervalByPhase, 0.01, 30)
	config.BeeBurstCountByPhase = resolveNumberMap(source, "BeeBurstCountByPhase", config.BeeBurstCountByPhase, 0, 32)
	config.BeeBurstCountByPhase[1] = sanitizeInteger(config.BeeBurstCountByPhase[1], 2, 0, 32)
	config.BeeBurstCountByPhase[2] = sanitizeInteger(config.BeeBurstCountByPhase[2], 3, 0, 32)
	config.BeeBurstCountByPhase[3] = sanitizeInteger(config.BeeBurstCountByPhase[3], 4, 0, 32)
	config.BeeLifetime = sanitizeNumber(source.BeeLifetime, config.BeeLifetime, 0.05, 60)
	config.BeeScatterDuration = sanitizeNumber(source.BeeScatterDuration, config.BeeScatterDuration, 0, 10)
	config.BeeScatterSpeed = sanitizeNumber(source.BeeScatterSpeed, config.BeeScatterSpeed, 0, 10 ^ 5)
	config.BeeSpeedByPhase = resolveNumberMap(source, "BeeSpeedByPhase", config.BeeSpeedByPhase, 0, 10 ^ 5)
	config.BeeAccelerationByPhase =
		resolveNumberMap(source, "BeeAccelerationByPhase", config.BeeAccelerationByPhase, 0, 10 ^ 5)
	config.BeeDashSpeedByPhase = resolveNumberMap(source, "BeeDashSpeedByPhase", config.BeeDashSpeedByPhase, 0, 10 ^ 5)
	config.BeeDamage = sanitizeNumber(source.BeeDamage, config.BeeDamage, 0, 10 ^ 6)
	config.BeeHitRadius = sanitizeNumber(source.BeeHitRadius, config.BeeHitRadius, 0, 256)
	config.ContactDamage = sanitizeNumber(source.ContactDamage, config.ContactDamage, 0, 10 ^ 6)
	config.ContactHitRadius = sanitizeNumber(source.ContactHitRadius, config.ContactHitRadius, 0, 256)
	config.ContactCooldown = sanitizeNumber(source.ContactCooldown, config.ContactCooldown, 0, 30)
	config.DespawnSpeed = sanitizeNumber(source.DespawnSpeed, config.DespawnSpeed, 0, 10 ^ 5)
	config.DespawnAcceleration = sanitizeNumber(source.DespawnAcceleration, config.DespawnAcceleration, 0, 10 ^ 5)
	config.DespawnDuration = sanitizeNumber(source.DespawnDuration, config.DespawnDuration, 0.05, 30)
	config.MaxDt = sanitizeNumber(source.MaxDt, config.MaxDt, 1 / 240, 1)
	config.Debug = sanitizeBoolean(source.Debug, config.Debug)
	config.EnrageSpeedMultiplier = sanitizeNumber(source.EnrageSpeedMultiplier, config.EnrageSpeedMultiplier, 0.01, 10)
	config.EnrageCadenceMultiplier =
		sanitizeNumber(source.EnrageCadenceMultiplier, config.EnrageCadenceMultiplier, 0.05, 10)

	if typeof(source.IsEnraged) == "function" then
		config.IsEnraged = source.IsEnraged :: (EnrageContext) -> boolean
	end

	return config
end

function Configs.ResolvePhase(healthRaw: any, maxHealthRaw: any, configRaw: QueenBeeConfig?): QueenBeePhase
	local config = if configRaw ~= nil then configRaw else DEFAULTS
	local maxHealth = sanitizeNumber(maxHealthRaw, 1, 1, 10 ^ 9)
	local health = sanitizeNumber(healthRaw, maxHealth, 0, maxHealth)
	local ratio = math.clamp(health / maxHealth, 0, 1)

	if ratio <= config.Phase3HealthRatio then
		return 3
	end
	if ratio <= config.Phase2HealthRatio then
		return 2
	end
	return 1
end

Configs.getDefaults = Configs.GetDefaults
Configs.resolve = Configs.Resolve
Configs.resolvePhase = Configs.ResolvePhase

return Configs
