--!strict
-- Core Vector3 helpers.

local Vec = {}

local ZERO = Vector3.zero
local X_AXIS = Vector3.new(1, 0, 0)
local Y_AXIS = Vector3.new(0, 1, 0)

function Vec.magnitudeSq(vector: Vector3): number
	return vector:Dot(vector)
end

function Vec.distanceSq(a: Vector3, b: Vector3): number
	local delta = b - a
	return delta:Dot(delta)
end

function Vec.distance(a: Vector3, b: Vector3): number
	return math.sqrt(Vec.distanceSq(a, b))
end

function Vec.unit(vector: Vector3, fallback: Vector3?): Vector3
	local magnitude = vector.Magnitude
	if magnitude == 0 then
		return fallback or ZERO
	end
	return vector / magnitude
end

function Vec.withMagnitude(vector: Vector3, magnitude: number, fallback: Vector3?): Vector3
	local direction = Vec.unit(vector, fallback)
	return direction * magnitude
end

function Vec.clampMagnitude(vector: Vector3, maxMagnitude: number): Vector3
	local limit = math.abs(maxMagnitude)
	local magnitudeSq = Vec.magnitudeSq(vector)
	if magnitudeSq == 0 or magnitudeSq <= limit * limit then
		return vector
	end
	return vector / math.sqrt(magnitudeSq) * limit
end

function Vec.moveTowards(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local step = math.max(maxDelta, 0)
	if step == 0 then
		return current
	end

	local delta = target - current
	local distanceSq = delta:Dot(delta)
	if distanceSq == 0 or distanceSq <= step * step then
		return target
	end

	return current + delta / math.sqrt(distanceSq) * step
end

function Vec.midpoint(a: Vector3, b: Vector3): Vector3
	return (a + b) * 0.5
end

function Vec.min(a: Vector3, b: Vector3): Vector3
	return Vector3.new(
		math.min(a.X, b.X),
		math.min(a.Y, b.Y),
		math.min(a.Z, b.Z)
	)
end

function Vec.max(a: Vector3, b: Vector3): Vector3
	return Vector3.new(
		math.max(a.X, b.X),
		math.max(a.Y, b.Y),
		math.max(a.Z, b.Z)
	)
end

function Vec.abs(vector: Vector3): Vector3
	return Vector3.new(
		math.abs(vector.X),
		math.abs(vector.Y),
		math.abs(vector.Z)
	)
end

function Vec.flattenX(vector: Vector3): Vector3
	return Vector3.new(0, vector.Y, vector.Z)
end

function Vec.flattenY(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

function Vec.flattenZ(vector: Vector3): Vector3
	return Vector3.new(vector.X, vector.Y, 0)
end

function Vec.isNearlyZero(vector: Vector3, epsilon: number?): boolean
	local tolerance = math.max(epsilon or 1e-5, 0)
	return Vec.magnitudeSq(vector) <= tolerance * tolerance
end

function Vec.nearlyEqual(a: Vector3, b: Vector3, epsilon: number?): boolean
	local tolerance = math.max(epsilon or 1e-5, 0)
	return Vec.distanceSq(a, b) <= tolerance * tolerance
end

function Vec.orthogonal(vector: Vector3): Vector3
	local unitVector = Vec.unit(vector, Y_AXIS)
	local reference = if math.abs(unitVector.Y) < 0.999 then Y_AXIS else X_AXIS
	return Vec.unit(reference:Cross(unitVector), X_AXIS)
end

return Vec
