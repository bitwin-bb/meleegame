--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vec = require(script:FindFirstAncestor("game").Shared.Modules.Math.Vec)

local Predict = {}
Predict.__index = Predict

export type PredictionConfig = {
	enabled: boolean?,
	leadTime: number?,
	maxLeadTime: number?,
	minimumSpeed: number?,
	maximumDistance: number?,
	derivedVelocityWeight: number?,
}

export type PredictionResult = {
	active: boolean,
	position: Vector3?,
	basePosition: Vector3?,
	velocity: Vector3,
	speed: number,
	leadTime: number,
	offset: Vector3,
}

export type Predict = typeof(setmetatable(
	{} :: {
		enabled: boolean,
		leadTime: number,
		maxLeadTime: number,
		minimumSpeed: number,
		maximumDistance: number,
		derivedVelocityWeight: number,
	},
	Predict
))

local DEFAULT_CONFIG: PredictionConfig = {
	enabled = false,
	leadTime = 0.08,
	maxLeadTime = 0.18,
	minimumSpeed = 2,
	maximumDistance = 18,
	derivedVelocityWeight = 0.35,
}

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function sanitizeConfig(configRaw: any, fallbackRaw: PredictionConfig?): PredictionConfig
	local source = if typeof(configRaw) == "table" then configRaw else {}
	local fallback = if typeof(fallbackRaw) == "table" then fallbackRaw else DEFAULT_CONFIG

	local leadTime = sanitizeNumber((source :: any).leadTime, fallback.leadTime or 0.08, 0, 1)
	local maxLeadTime = sanitizeNumber((source :: any).maxLeadTime, fallback.maxLeadTime or leadTime, leadTime, 1)

	return {
		enabled = if typeof((source :: any).enabled) == "boolean"
			then (source :: any).enabled
			else fallback.enabled ~= false,
		leadTime = leadTime,
		maxLeadTime = maxLeadTime,
		minimumSpeed = sanitizeNumber((source :: any).minimumSpeed, fallback.minimumSpeed or 2, 0, 1024),
		maximumDistance = sanitizeNumber((source :: any).maximumDistance, fallback.maximumDistance or 18, 0, 4096),
		derivedVelocityWeight = sanitizeNumber(
			(source :: any).derivedVelocityWeight,
			fallback.derivedVelocityWeight or 0.35,
			0,
			1
		),
	}
end

local function buildResult(
	active: boolean,
	position: Vector3?,
	basePosition: Vector3?,
	velocity: Vector3,
	leadTime: number,
	offset: Vector3
): PredictionResult
	return {
		active = active,
		position = position,
		basePosition = basePosition,
		velocity = velocity,
		speed = velocity.Magnitude,
		leadTime = leadTime,
		offset = offset,
	}
end

function Predict.New(configRaw: PredictionConfig?): Predict
	local config = sanitizeConfig(configRaw, DEFAULT_CONFIG)
	return setmetatable({
		enabled = config.enabled ~= false,
		leadTime = config.leadTime or 0.08,
		maxLeadTime = config.maxLeadTime or 0.18,
		minimumSpeed = config.minimumSpeed or 2,
		maximumDistance = config.maximumDistance or 18,
		derivedVelocityWeight = config.derivedVelocityWeight or 0.35,
	}, Predict)
end

function Predict.ApplyConfig(self: Predict, configRaw: PredictionConfig?)
	local config = sanitizeConfig(configRaw, {
		enabled = self.enabled,
		leadTime = self.leadTime,
		maxLeadTime = self.maxLeadTime,
		minimumSpeed = self.minimumSpeed,
		maximumDistance = self.maximumDistance,
		derivedVelocityWeight = self.derivedVelocityWeight,
	})

	self.enabled = config.enabled ~= false
	self.leadTime = config.leadTime or self.leadTime
	self.maxLeadTime = config.maxLeadTime or self.maxLeadTime
	self.minimumSpeed = config.minimumSpeed or self.minimumSpeed
	self.maximumDistance = config.maximumDistance or self.maximumDistance
	self.derivedVelocityWeight = config.derivedVelocityWeight or self.derivedVelocityWeight
end

function Predict.Resolve(self: Predict, targetRaw: any, cacheRaw: any?, optionsRaw: any?): PredictionResult
	local target = if typeof(targetRaw) == "table" then targetRaw else nil
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local configOverride = sanitizeConfig((options :: any).config, {
		enabled = self.enabled,
		leadTime = self.leadTime,
		maxLeadTime = self.maxLeadTime,
		minimumSpeed = self.minimumSpeed,
		maximumDistance = self.maximumDistance,
		derivedVelocityWeight = self.derivedVelocityWeight,
	})

	if target == nil or typeof((target :: any).position) ~= "Vector3" then
		return buildResult(false, nil, nil, Vector3.zero, 0, Vector3.zero)
	end

	local basePosition = (target :: any).position :: Vector3
	local fallbackVelocity = if typeof((target :: any).velocity) == "Vector3" then (target :: any).velocity else Vector3.zero
	local derivedVelocity = fallbackVelocity
	local cache = if typeof(cacheRaw) == "table" then cacheRaw else nil
	local subjectKey = if typeof((target :: any).cacheKey) == "string" then (target :: any).cacheKey else nil

	if cache ~= nil and subjectKey ~= nil and typeof((cache :: any).resolveDerivedVelocity) == "function" then
		derivedVelocity = (cache :: any):resolveDerivedVelocity(
			subjectKey,
			basePosition,
			(options :: any).now,
			fallbackVelocity
		)
	end

	local blendAlpha = configOverride.derivedVelocityWeight or 0.35
	local velocity = fallbackVelocity + ((derivedVelocity - fallbackVelocity) * blendAlpha)
	if fallbackVelocity.Magnitude <= 1e-4 then
		velocity = derivedVelocity
	end

	local speed = velocity.Magnitude
	local leadTime = sanitizeNumber(
		(options :: any).leadTime,
		configOverride.leadTime or 0.08,
		0,
		configOverride.maxLeadTime or 0.18
	)
	if configOverride.enabled == false or speed < (configOverride.minimumSpeed or 2) or leadTime <= 0 then
		return buildResult(false, basePosition, basePosition, velocity, 0, Vector3.zero)
	end

	local offset = Vec.clampMagnitude(velocity * leadTime, configOverride.maximumDistance or 18)
	if offset.Magnitude <= 1e-4 then
		return buildResult(false, basePosition, basePosition, velocity, leadTime, Vector3.zero)
	end

	return buildResult(true, basePosition + offset, basePosition, velocity, leadTime, offset)
end

Predict.new = Predict.New
Predict.applyConfig = Predict.ApplyConfig
Predict.resolve = Predict.Resolve

return Predict
