--!strict
-- Angle wrapping, shortest deltas, and signed-angle helpers.

local Num = require(script.Parent.Num)
local Trig = require(script.Parent.Trig)

local Angle = {}

local X_AXIS = Vector3.new(1, 0, 0)
local Y_AXIS = Vector3.new(0, 1, 0)
local ZERO_2 = Vector2.zero
local TWO_PI = Trig.TAU

local function safeUnit2(vector: Vector2): Vector2
	local magnitude = vector.Magnitude
	if magnitude == 0 then
		return ZERO_2
	end
	return vector / magnitude
end

local function safeUnit3(vector: Vector3, fallback: Vector3): Vector3
	local magnitude = vector.Magnitude
	if magnitude == 0 then
		return fallback
	end
	return vector / magnitude
end

function Angle.wrapRadians(angleRadians: number): number
	local wrapped = (angleRadians + math.pi) % TWO_PI
	if wrapped < 0 then
		wrapped = wrapped + TWO_PI
	end
	return wrapped - math.pi
end

function Angle.wrapDegrees(angleDegrees: number): number
	local wrapped = (angleDegrees + 180) % 360
	if wrapped < 0 then
		wrapped = wrapped + 360
	end
	return wrapped - 180
end

function Angle.deltaRadians(fromAngle: number, toAngle: number): number
	return Angle.wrapRadians(toAngle - fromAngle)
end

function Angle.deltaDegrees(fromAngle: number, toAngle: number): number
	return Angle.wrapDegrees(toAngle - fromAngle)
end

function Angle.lerpRadians(fromAngle: number, toAngle: number, alpha: number): number
	return fromAngle + Angle.deltaRadians(fromAngle, toAngle) * alpha
end

function Angle.lerpDegrees(fromAngle: number, toAngle: number, alpha: number): number
	return fromAngle + Angle.deltaDegrees(fromAngle, toAngle) * alpha
end

function Angle.fromVector2(direction: Vector2): number
	if direction == ZERO_2 then
		return 0
	end
	return math.atan2(direction.Y, direction.X)
end

function Angle.signed2D(fromDirection: Vector2, toDirection: Vector2): number
	local fromUnit = safeUnit2(fromDirection)
	local toUnit = safeUnit2(toDirection)
	if fromUnit == ZERO_2 or toUnit == ZERO_2 then
		return 0
	end

	local cross = fromUnit.X * toUnit.Y - fromUnit.Y * toUnit.X
	local dot = Num.clamp(fromUnit:Dot(toUnit), -1, 1)
	return math.atan2(cross, dot)
end

function Angle.signed3D(fromDirection: Vector3, toDirection: Vector3, axis: Vector3): number
	local axisUnit = safeUnit3(axis, Y_AXIS)
	local fromUnit = safeUnit3(fromDirection, X_AXIS)
	local toUnit = safeUnit3(toDirection, fromUnit)
	local cross = fromUnit:Cross(toUnit)
	local dot = Num.clamp(fromUnit:Dot(toUnit), -1, 1)
	return math.atan2(axisUnit:Dot(cross), dot)
end

function Angle.unsigned3D(fromDirection: Vector3, toDirection: Vector3): number
	local fromMagnitude = fromDirection.Magnitude
	local toMagnitude = toDirection.Magnitude
	if fromMagnitude == 0 or toMagnitude == 0 then
		return 0
	end

	local dot = Num.clamp(fromDirection:Dot(toDirection) / (fromMagnitude * toMagnitude), -1, 1)
	return math.acos(dot)
end

return Angle
