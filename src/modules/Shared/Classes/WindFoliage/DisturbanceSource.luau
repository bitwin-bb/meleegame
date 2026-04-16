--!strict

local DisturbanceSource = {}

export type DisturbanceSource = {
	id: number,
	position: Vector3,
	velocity: Vector3,
	radius: number,
	strength: number,
	falloffCurve: number,
	lifetime: number,
	expiresAt: number,
	propagationDistance: number,
	propagationWeight: number,
	velocityInfluence: number,
	trackedInstance: Instance?,
}

local ZERO = Vector3.zero

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

function DisturbanceSource.Reset(source: DisturbanceSource)
	source.id = 0
	source.position = ZERO
	source.velocity = ZERO
	source.radius = 0
	source.strength = 0
	source.falloffCurve = 1
	source.lifetime = 0
	source.expiresAt = 0
	source.propagationDistance = 0
	source.propagationWeight = 0
	source.velocityInfluence = 1
	source.trackedInstance = nil
end

function DisturbanceSource.Populate(source: DisturbanceSource, paramsRaw: any, nowRaw: any, defaultLifetimeRaw: any?): DisturbanceSource
	local params = if typeof(paramsRaw) == "table" then paramsRaw else {}
	local now = if typeof(nowRaw) == "number" and nowRaw == nowRaw then nowRaw else 0
	local defaultLifetime =
		if typeof(defaultLifetimeRaw) == "number" and defaultLifetimeRaw == defaultLifetimeRaw then defaultLifetimeRaw else 0.2

	source.position = if typeof(params.position) == "Vector3" then params.position else ZERO
	source.velocity = if typeof(params.velocity) == "Vector3" then params.velocity else ZERO
	source.radius = clampNumber(params.radius, 8, 0.1, 512)
	source.strength = clampNumber(params.strength, 1, 0, 100)
	source.falloffCurve = clampNumber(params.falloffCurve, 1.5, 0.25, 8)
	source.lifetime = clampNumber(params.lifetime, defaultLifetime, 0.01, 10)
	source.expiresAt = now + source.lifetime
	source.propagationDistance = clampNumber(params.propagationDistance, source.radius * 0.4, 0, 256)
	source.propagationWeight = clampNumber(params.propagationWeight, 0.35, 0, 2)
	source.velocityInfluence = clampNumber(params.velocityInfluence, 0.5, 0, 4)
	source.trackedInstance = if typeof(params.trackedInstance) == "Instance" then params.trackedInstance else nil

	return source
end

function DisturbanceSource.IsExpired(source: DisturbanceSource, nowRaw: any): boolean
	local now = if typeof(nowRaw) == "number" and nowRaw == nowRaw then nowRaw else 0
	return now >= source.expiresAt
end

function DisturbanceSource.ComputeImpulse(source: DisturbanceSource, targetPosition: Vector3): Vector3
	if source.radius <= 0 or source.strength <= 0 then
		return ZERO
	end

	local velocity = source.velocity
	local speed = velocity.Magnitude
	local direction = if speed > 1e-4 then velocity / speed else ZERO
	local predictedCenter = source.position + direction * source.propagationDistance
	local delta = targetPosition - predictedCenter
	local distance = delta.Magnitude

	if distance >= source.radius then
		return ZERO
	end

	local away = if distance > 1e-4 then delta / distance else if speed > 1e-4 then -direction else Vector3.new(1, 0, 0)
	local radialAlpha = 1 - math.clamp(distance / source.radius, 0, 1)
	local falloff = radialAlpha ^ source.falloffCurve
	local velocityBias =
		if speed > 1e-4 then direction * (source.propagationWeight * radialAlpha * source.velocityInfluence) else ZERO
	local impulseDirection = away + velocityBias
	local impulseMagnitude = source.strength * falloff * (1 + math.min(1.5, speed / math.max(1, source.radius)) * 0.35)

	if impulseDirection.Magnitude <= 1e-4 or impulseMagnitude <= 0 then
		return ZERO
	end

	return impulseDirection.Unit * impulseMagnitude
end

function DisturbanceSource.CreateTemplate(): DisturbanceSource
	local source = {
		id = 0,
		position = ZERO,
		velocity = ZERO,
		radius = 0,
		strength = 0,
		falloffCurve = 1,
		lifetime = 0,
		expiresAt = 0,
		propagationDistance = 0,
		propagationWeight = 0,
		velocityInfluence = 1,
		trackedInstance = nil,
	} :: DisturbanceSource
	return source
end

DisturbanceSource.reset = DisturbanceSource.Reset
DisturbanceSource.populate = DisturbanceSource.Populate
DisturbanceSource.isExpired = DisturbanceSource.IsExpired
DisturbanceSource.computeImpulse = DisturbanceSource.ComputeImpulse
DisturbanceSource.createTemplate = DisturbanceSource.CreateTemplate

return DisturbanceSource
