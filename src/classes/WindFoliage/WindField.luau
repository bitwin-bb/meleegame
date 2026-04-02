--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeterministicRNG = require(ReplicatedStorage.Shared.Modules.Core.DeterministicRNG)
local Noise = require(ReplicatedStorage.Shared.Modules.Math.Noise)
local Trig = require(ReplicatedStorage.Shared.Modules.Math.Trig)
local Vec = require(ReplicatedStorage.Shared.Modules.Math.Vec)

local WindField = {}
WindField.__index = WindField

export type WindSample = {
	vector: Vector3,
	direction: Vector3,
	strength: number,
	gustAlpha: number,
	detailAlpha: number,
	detailVector: Vector3,
	flutter: number,
}

export type WindField = typeof(setmetatable({} :: any, WindField))

export type Config = {
	seed: any?,
	baseDirection: Vector3?,
	strengthMultiplier: number?,
	baseStrength: number?,
	gustStrength: number?,
	detailStrength: number?,
	gustSpatialScale: number?,
	gustTimeScale: number?,
	detailSpatialScale: number?,
	detailTimeScale: number?,
	directionJitterDegrees: number?,
	gustOctaves: number?,
	detailOctaves: number?,
}

local ZERO = Vector3.zero
local DEFAULT_DIRECTION = Vector3.new(1, 0, 0.25)

local function clampNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

local function sanitizeDirection(directionRaw: any): Vector3
	local direction = if typeof(directionRaw) == "Vector3" then directionRaw else DEFAULT_DIRECTION
	return Vec.unit(Vec.flattenY(direction), Vec.unit(DEFAULT_DIRECTION, Vector3.xAxis))
end

local function remapNoise(sample: number): number
	return Noise.toSigned(sample)
end

function WindField.new(configRaw: Config?): WindField
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local seed = DeterministicRNG.seedFrom(config.seed or "WindFoliage")

	local self = setmetatable({
		baseDirection = sanitizeDirection(config.baseDirection),
		strengthMultiplier = clampNumber(config.strengthMultiplier, 1, 0, 10),
		baseStrength = clampNumber(config.baseStrength, 0.62, 0, 10),
		gustStrength = clampNumber(config.gustStrength, 0.9, 0, 10),
		detailStrength = clampNumber(config.detailStrength, 0.2, 0, 10),
		gustSpatialScale = clampNumber(config.gustSpatialScale, 140, 1, 5000),
		gustTimeScale = clampNumber(config.gustTimeScale, 0.16, 0.001, 20),
		detailSpatialScale = clampNumber(config.detailSpatialScale, 22, 1, 2000),
		detailTimeScale = clampNumber(config.detailTimeScale, 1.55, 0.001, 60),
		directionJitterRadians = Trig.degToRad(clampNumber(config.directionJitterDegrees, 18, 0, 180)),
		gustOctaves = math.floor(clampNumber(config.gustOctaves, 4, 1, 8)),
		detailOctaves = math.floor(clampNumber(config.detailOctaves, 3, 1, 8)),
		gustNoise = DeterministicRNG.createNoise(seed),
		directionNoise = DeterministicRNG.createNoise(seed + 73),
		detailNoise = DeterministicRNG.createNoise(seed + 181),
		flutterNoise = DeterministicRNG.createNoise(seed + 997),
	}, WindField)

	return self
end

function WindField.sample(
	self: WindField,
	worldPosition: Vector3,
	timeSecondsRaw: any,
	phaseOffsetRaw: any?,
	amplitudeScaleRaw: any?
): WindSample
	local timeSeconds = if typeof(timeSecondsRaw) == "number" and timeSecondsRaw == timeSecondsRaw then timeSecondsRaw else 0
	local phaseOffset = if typeof(phaseOffsetRaw) == "number" and phaseOffsetRaw == phaseOffsetRaw then phaseOffsetRaw else 0
	local amplitudeScale = clampNumber(amplitudeScaleRaw, 1, 0, 10)
	local strengthMultiplier = self.strengthMultiplier

	local x = worldPosition.X
	local z = worldPosition.Z

	local phaseX = math.cos(phaseOffset) * 31.73
	local phaseZ = math.sin(phaseOffset) * 27.11

	local gustField = remapNoise(
		self.gustNoise:fbm3D(
			(x + phaseX) / self.gustSpatialScale,
			timeSeconds * self.gustTimeScale,
			(z + phaseZ) / self.gustSpatialScale,
			self.gustOctaves,
			0.55,
			2
		)
	)
	local sweepField = remapNoise(
		self.gustNoise:fbm3D(
			(x - phaseZ * 0.4) / (self.gustSpatialScale * 0.7),
			timeSeconds * (self.gustTimeScale * 0.75),
			(z + phaseX * 0.45) / (self.gustSpatialScale * 0.7),
			math.max(2, self.gustOctaves - 1),
			0.5,
			2.1
		)
	)
	local gustAlpha = math.clamp(0.55 + gustField * 0.35 + sweepField * 0.2, 0, 1.6)

	local directionJitter = remapNoise(
		self.directionNoise:fbm3D(
			(x + phaseX * 0.2) / (self.gustSpatialScale * 0.85),
			timeSeconds * (self.gustTimeScale * 0.55),
			(z + phaseZ * 0.2) / (self.gustSpatialScale * 0.85),
			3,
			0.5,
			2
		)
	) * self.directionJitterRadians

	local baseHeading = math.atan2(self.baseDirection.Z, self.baseDirection.X) + directionJitter
	local direction = Vector3.new(math.cos(baseHeading), 0, math.sin(baseHeading))
	if direction.Magnitude <= 1e-5 then
		direction = self.baseDirection
	end
	direction = Vec.unit(direction, self.baseDirection)

	local detailX = remapNoise(
		self.detailNoise:fbm3D(
			(x + phaseX * 0.7) / self.detailSpatialScale,
			timeSeconds * self.detailTimeScale,
			(z + phaseZ * 0.7) / self.detailSpatialScale,
			self.detailOctaves,
			0.58,
			2
		)
	)
	local detailZ = remapNoise(
		self.detailNoise:fbm3D(
			(x - phaseZ * 0.55) / self.detailSpatialScale,
			timeSeconds * (self.detailTimeScale * 0.92),
			(z + phaseX * 0.55) / self.detailSpatialScale,
			self.detailOctaves,
			0.58,
			2
		)
	)
	local detailVector = Vector3.new(detailX, 0, detailZ)
	local detailMagnitude = detailVector.Magnitude
	if detailMagnitude > 1e-5 then
		detailVector *= 1 / math.max(1, detailMagnitude)
	end

	local flutter = remapNoise(
		self.flutterNoise:fbm3D(
			(x + phaseX * 1.2) / (self.detailSpatialScale * 0.5),
			timeSeconds * (self.detailTimeScale * 1.35),
			(z - phaseZ * 1.2) / (self.detailSpatialScale * 0.5),
			2,
			0.65,
			2.2
		)
	)

	local scalarStrength =
		(self.baseStrength + self.gustStrength * gustAlpha + self.detailStrength * math.min(1, detailMagnitude))
		* amplitudeScale
		* strengthMultiplier
	local vector =
		direction * (self.baseStrength + self.gustStrength * gustAlpha) * amplitudeScale * strengthMultiplier
		+ detailVector * self.detailStrength * amplitudeScale * strengthMultiplier

	return {
		vector = vector,
		direction = direction,
		strength = scalarStrength,
		gustAlpha = gustAlpha,
		detailAlpha = math.min(1.5, detailMagnitude),
		detailVector = detailVector,
		flutter = flutter,
	}
end

WindField.ZeroSample = {
	vector = ZERO,
	direction = DEFAULT_DIRECTION.Unit,
	strength = 0,
	gustAlpha = 0,
	detailAlpha = 0,
	detailVector = ZERO,
	flutter = 0,
} :: WindSample

return WindField
