local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift: any = require(ReplicatedStorage.Packages.Sift)

local BreathServiceUtils = {}

BreathServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"

BreathServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
BreathServiceUtils.CLIENT_METHOD_ON_EVENT = "onEvent"

BreathServiceUtils.EVENT_BREATH_DEPLETED = "breathDepleted"

export type BreathServiceConfig = {
	maxBreathSeconds: number,
	graceDuration: number,
	recoveryDelay: number,
	recoveryDuration: number,
	drowningTickRate: number,
	drowningDamage: number,
	updateRate: number,
	statePushInterval: number,
}

export type BreathServiceState = {
	ready: boolean,
	maxBreath: number,
	breath: number,
	graceRemaining: number,
	isUnderwater: boolean,
	isBreathingBlocked: boolean,
	isDrowning: boolean,
	submersionRatio: number,
	breathingLiquidType: number,
	updatedAt: number,
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function CoerceNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function CoerceBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

function BreathServiceUtils.CreateDefaultConfig(): BreathServiceConfig
	return {
		maxBreathSeconds = 8,
		graceDuration = 0.8,
		recoveryDelay = 0.45,
		recoveryDuration = 1.8,
		drowningTickRate = 0.2,
		drowningDamage = 2,
		updateRate = 8,
		statePushInterval = 0.12,
	}
end

function BreathServiceUtils.CoerceConfig(configRaw: any, fallbackRaw: BreathServiceConfig?): BreathServiceConfig
	local fallback = if fallbackRaw ~= nil then fallbackRaw else BreathServiceUtils.CreateDefaultConfig()
	local source = if typeof(configRaw) == "table" then configRaw else {} :: any
	return {
		maxBreathSeconds = CoerceNumber(source.maxBreathSeconds, 1, 120, fallback.maxBreathSeconds),
		graceDuration = CoerceNumber(source.graceDuration, 0, 10, fallback.graceDuration),
		recoveryDelay = CoerceNumber(source.recoveryDelay, 0, 10, fallback.recoveryDelay),
		recoveryDuration = CoerceNumber(source.recoveryDuration, 0.1, 30, fallback.recoveryDuration),
		drowningTickRate = CoerceNumber(source.drowningTickRate, 0.05, 5, fallback.drowningTickRate),
		drowningDamage = CoerceNumber(source.drowningDamage, 0, 100, fallback.drowningDamage),
		updateRate = CoerceNumber(source.updateRate, 1, 60, fallback.updateRate),
		statePushInterval = CoerceNumber(source.statePushInterval, 0.03, 2, fallback.statePushInterval),
	}
end

function BreathServiceUtils.CreateDefaultState(): BreathServiceState
	return {
		ready = false,
		maxBreath = 8,
		breath = 8,
		graceRemaining = 0,
		isUnderwater = false,
		isBreathingBlocked = false,
		isDrowning = false,
		submersionRatio = 0,
		breathingLiquidType = 0,
		updatedAt = os.clock(),
	}
end

function BreathServiceUtils.CreateState(stateRaw: any, fallbackRaw: BreathServiceState?): BreathServiceState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else BreathServiceUtils.CreateDefaultState()
	local source = if typeof(stateRaw) == "table" then stateRaw else {} :: any
	local maxBreath = CoerceNumber(source.maxBreath, 1, 120, fallback.maxBreath)
	return {
		ready = CoerceBoolean(source.ready, fallback.ready),
		maxBreath = maxBreath,
		breath = CoerceNumber(source.breath, 0, maxBreath, fallback.breath),
		graceRemaining = CoerceNumber(source.graceRemaining, 0, 30, fallback.graceRemaining),
		isUnderwater = CoerceBoolean(source.isUnderwater, fallback.isUnderwater),
		isBreathingBlocked = CoerceBoolean(source.isBreathingBlocked, fallback.isBreathingBlocked),
		isDrowning = CoerceBoolean(source.isDrowning, fallback.isDrowning),
		submersionRatio = CoerceNumber(source.submersionRatio, 0, 1, fallback.submersionRatio),
		breathingLiquidType = if isFiniteNumber(source.breathingLiquidType)
			then math.max(0, math.floor(source.breathingLiquidType))
			else fallback.breathingLiquidType,
		updatedAt = os.clock(),
	}
end

function BreathServiceUtils.CloneState(state: BreathServiceState): BreathServiceState
	return Sift.Dictionary.copy(state) :: BreathServiceState
end
return BreathServiceUtils
