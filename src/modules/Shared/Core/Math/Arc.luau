--!strict
-- Circular arc sampling and orbit helpers.

local Vec = require(script.Parent.Vec)
local Trig = require(script.Parent.Trig)

local Arc = {}

function Arc.Length(radius: number, angleRadians: number): number
	return math.abs(radius * angleRadians)
end

function Arc.AngleFromLength(length: number, radius: number): number
	if radius == 0 then
		return 0
	end
	return length / radius
end

function Arc.Chord(radius: number, angleRadians: number): number
	return 2 * math.abs(radius) * math.sin(math.abs(angleRadians) * 0.5)
end

function Arc.Point2(center: Vector2, radius: number, angleRadians: number): Vector2
	local sinValue, cosValue = Trig.sinCos(angleRadians)
	return center + Vector2.new(cosValue, sinValue) * radius
end

function Arc.Tangent2(radius: number, angleRadians: number): Vector2
	local sinValue, cosValue = Trig.sinCos(angleRadians)
	return Vector2.new(-sinValue, cosValue) * radius
end

function Arc.Orbit2(center: Vector2, radius: number, angleRadians: number, angularVelocity: number?): (Vector2, Vector2)
	local velocityScale = angularVelocity or 1
	local position = Arc.Point2(center, radius, angleRadians)
	local velocity = Arc.Tangent2(radius, angleRadians) * velocityScale
	return position, velocity
end

function Arc.Point3(
	center: Vector3,
	radius: number,
	angleRadians: number,
	xAxis: Vector3,
	yAxis: Vector3
): Vector3
	local sinValue, cosValue = Trig.sinCos(angleRadians)
	local tangentX = Vec.unit(xAxis, Vector3.new(1, 0, 0))
	local tangentY = Vec.unit(yAxis, Vector3.new(0, 1, 0))
	return center + tangentX * (cosValue * radius) + tangentY * (sinValue * radius)
end

function Arc.Tangent3(radius: number, angleRadians: number, xAxis: Vector3, yAxis: Vector3): Vector3
	local sinValue, cosValue = Trig.sinCos(angleRadians)
	local tangentX = Vec.unit(xAxis, Vector3.new(1, 0, 0))
	local tangentY = Vec.unit(yAxis, Vector3.new(0, 1, 0))
	return (-tangentX * sinValue + tangentY * cosValue) * radius
end

function Arc.Orbit3(
	center: Vector3,
	radius: number,
	angleRadians: number,
	xAxis: Vector3,
	yAxis: Vector3,
	angularVelocity: number?
): (Vector3, Vector3)
	local velocityScale = angularVelocity or 1
	local position = Arc.Point3(center, radius, angleRadians, xAxis, yAxis)
	local velocity = Arc.Tangent3(radius, angleRadians, xAxis, yAxis) * velocityScale
	return position, velocity
end

Arc.length = Arc.Length
Arc.angleFromLength = Arc.AngleFromLength
Arc.chord = Arc.Chord
Arc.point2 = Arc.Point2
Arc.tangent2 = Arc.Tangent2
Arc.orbit2 = Arc.Orbit2
Arc.point3 = Arc.Point3
Arc.tangent3 = Arc.Tangent3
Arc.orbit3 = Arc.Orbit3

return Arc
