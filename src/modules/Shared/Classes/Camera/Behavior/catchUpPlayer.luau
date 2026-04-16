local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)

local CatchUpPlayer = {}
CatchUpPlayer.__index = CatchUpPlayer

export type SpringOptions = {
	damping: number?,
	frequency: number?,
	mass: number?,
	tension: number?,
	friction: number?,
	position: number?,
	velocity: number?,
	impulse: number?,
	restingVelocity: number?,
	restingPosition: number?,
}

export type CatchUpPlayerConfig = {
	enabled: boolean?,
	startDistance: number?,
	maxDistance: number?,
	accelerationSeconds: number?,
	minFrequencyDivisor: number?,
	maxFrequencyDivisor: number?,
	minFrequencyMultiplier: number?,
	maxFrequencyMultiplier: number?,
}

export type CatchUpPlayer = typeof(setmetatable(
	{} :: {
		enabled: boolean,
		startDistance: number,
		maxDistance: number,
		accelerationSeconds: number,
		minFrequencyDivisor: number,
		maxFrequencyDivisor: number,
		activeDuration: number,
		peakGapDistance: number,
	},
	CatchUpPlayer
))

local DEFAULT_CONFIG = ((Configs.cameraData :: any).catchUpPlayer or {}) :: CatchUpPlayerConfig
local ACCELERATION_DISTANCE_DURATION_MULTIPLIER = 2

local function clampNumber(value: any, min: number, max: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	if value ~= value then
		return fallback
	end

	return math.clamp(value, min, max)
end

local function resolveConfiguredNumber(
	source: any,
	primaryKey: string,
	legacyKey: string?,
	min: number,
	max: number,
	fallback: number
): number
	local sourceAny = source :: any
	local value = sourceAny[primaryKey]
	if legacyKey and typeof(value) ~= "number" then
		value = sourceAny[legacyKey]
	end

	return clampNumber(value, min, max, fallback)
end

local function sanitizeConfig(config: any, fallbackConfig: CatchUpPlayerConfig?): CatchUpPlayerConfig
	local source = if typeof(config) == "table" then config else {}
	local fallback = if typeof(fallbackConfig) == "table" then fallbackConfig else {}

	local defaultEnabled = if typeof((fallback :: any).enabled) == "boolean" then (fallback :: any).enabled else true
	local startDistance =
		clampNumber((source :: any).startDistance, 0, 500, clampNumber((fallback :: any).startDistance, 0, 500, 24))
	local maxDistance =
		clampNumber((source :: any).maxDistance, 1, 2000, clampNumber((fallback :: any).maxDistance, 1, 2000, 140))
	local accelerationSeconds = clampNumber(
		(source :: any).accelerationSeconds,
		0.05,
		10,
		clampNumber((fallback :: any).accelerationSeconds, 0.05, 10, 0.9)
	)
	local minFrequencyDivisor = resolveConfiguredNumber(
		source,
		"minFrequencyDivisor",
		"minFrequencyMultiplier",
		1,
		50,
		resolveConfiguredNumber(fallback, "minFrequencyDivisor", "minFrequencyMultiplier", 1, 50, 2.2)
	)
	local maxFrequencyDivisor = resolveConfiguredNumber(
		source,
		"maxFrequencyDivisor",
		"maxFrequencyMultiplier",
		minFrequencyDivisor,
		50,
		resolveConfiguredNumber(
			fallback,
			"maxFrequencyDivisor",
			"maxFrequencyMultiplier",
			minFrequencyDivisor,
			50,
			6
		)
	)

	return {
		enabled = if typeof((source :: any).enabled) == "boolean" then (source :: any).enabled else defaultEnabled,
		startDistance = startDistance,
		maxDistance = math.max(maxDistance, startDistance + 1),
		accelerationSeconds = accelerationSeconds,
		minFrequencyDivisor = minFrequencyDivisor,
		maxFrequencyDivisor = maxFrequencyDivisor,
	}
end

local function cloneSpringOptions(baseSpring: SpringOptions): SpringOptions
	local clone: SpringOptions = {}
	for key, value in baseSpring do
		(clone :: any)[key] = value
	end

	return clone
end

local function resolveBaseFrequency(baseSpring: SpringOptions): number?
	local frequency = baseSpring.frequency
	if typeof(frequency) ~= "number" then
		return nil
	end
	if frequency ~= frequency or frequency <= 0 then
		return nil
	end

	return frequency
end

function CatchUpPlayer.New(config: CatchUpPlayerConfig?): CatchUpPlayer
	local resolvedConfig = sanitizeConfig(config, DEFAULT_CONFIG)

	return setmetatable({
		enabled = resolvedConfig.enabled == true,
		startDistance = resolvedConfig.startDistance :: number,
		maxDistance = resolvedConfig.maxDistance :: number,
		accelerationSeconds = resolvedConfig.accelerationSeconds :: number,
		minFrequencyDivisor = resolvedConfig.minFrequencyDivisor :: number,
		maxFrequencyDivisor = resolvedConfig.maxFrequencyDivisor :: number,
		activeDuration = 0,
		peakGapDistance = 0,
	}, CatchUpPlayer)
end

function CatchUpPlayer.Reset(self: CatchUpPlayer)
	self.activeDuration = 0
	self.peakGapDistance = 0
end

function CatchUpPlayer.ApplyConfig(self: CatchUpPlayer, config: CatchUpPlayerConfig?)
	local currentConfig: CatchUpPlayerConfig = {
		enabled = self.enabled,
		startDistance = self.startDistance,
		maxDistance = self.maxDistance,
		accelerationSeconds = self.accelerationSeconds,
		minFrequencyDivisor = self.minFrequencyDivisor,
		maxFrequencyDivisor = self.maxFrequencyDivisor,
	}
	local resolvedConfig = sanitizeConfig(config, currentConfig)

	self.enabled = resolvedConfig.enabled == true
	self.startDistance = resolvedConfig.startDistance :: number
	self.maxDistance = resolvedConfig.maxDistance :: number
	self.accelerationSeconds = resolvedConfig.accelerationSeconds :: number
	self.minFrequencyDivisor = resolvedConfig.minFrequencyDivisor :: number
	self.maxFrequencyDivisor = resolvedConfig.maxFrequencyDivisor :: number
	self:reset()
end

function CatchUpPlayer.ResolveSpring(
	self: CatchUpPlayer,
	baseSpring: SpringOptions,
	currentCFrame: CFrame,
	targetCFrame: CFrame,
	deltaTime: number?
): SpringOptions
	if not self.enabled then
		self:reset()
		return baseSpring
	end

	local baseFrequency = resolveBaseFrequency(baseSpring)
	if not baseFrequency then
		self:reset()
		return baseSpring
	end

	local gapDistance = (currentCFrame.Position - targetCFrame.Position).Magnitude
	if gapDistance <= self.startDistance then
		self:reset()
		return baseSpring
	end

	local dt = if typeof(deltaTime) == "number" and deltaTime > 0 then deltaTime else (1 / 60)
	self.activeDuration += dt
	self.peakGapDistance = math.max(self.peakGapDistance, gapDistance)

	local distanceAlpha = math.clamp(
		(gapDistance - self.startDistance) / math.max(self.maxDistance - self.startDistance, 0.001),
		0,
		1
	)
	local peakDistanceAlpha = math.clamp(
		(self.peakGapDistance - self.startDistance) / math.max(self.maxDistance - self.startDistance, 0.001),
		0,
		1
	)
	local accelerationDuration =
		self.accelerationSeconds * (1 + (peakDistanceAlpha * ACCELERATION_DISTANCE_DURATION_MULTIPLIER))
	local durationAlpha = math.clamp(self.activeDuration / math.max(accelerationDuration, 0.001), 0, 1)
	local minimumDivisor = 1 + ((self.minFrequencyDivisor - 1) * distanceAlpha)
	local maximumDivisor = 1 + ((self.maxFrequencyDivisor - 1) * distanceAlpha)
	local frequencyDivisor = minimumDivisor + ((maximumDivisor - minimumDivisor) * durationAlpha)

	local catchUpSpring = cloneSpringOptions(baseSpring)
	catchUpSpring.frequency = math.max(baseFrequency / math.max(frequencyDivisor, 1), 0.001)
	catchUpSpring.tension = nil
	catchUpSpring.friction = nil

	return catchUpSpring
end

CatchUpPlayer.new = CatchUpPlayer.New
CatchUpPlayer.reset = CatchUpPlayer.Reset
CatchUpPlayer.applyConfig = CatchUpPlayer.ApplyConfig
CatchUpPlayer.resolveSpring = CatchUpPlayer.ResolveSpring

return CatchUpPlayer
