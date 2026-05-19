--!strict
-- Projection, rejection, reflection, and closest-point helpers.

local Num = require(script.Parent.Num)
local Vec = require(script.Parent.Vec)

local Proj = {}

function Proj.Scalar(vector: Vector3, onto: Vector3): number
	local axis = Vec.unit(onto)
	if axis == Vector3.zero then
		return 0
	end
	return vector:Dot(axis)
end

function Proj.Vector(vector: Vector3, onto: Vector3): Vector3
	local denominator = onto:Dot(onto)
	if denominator == 0 then
		return Vector3.zero
	end
	return onto * (vector:Dot(onto) / denominator)
end

function Proj.Reject(vector: Vector3, onto: Vector3): Vector3
	return vector - Proj.Vector(vector, onto)
end

function Proj.OntoPlane(vector: Vector3, planeNormal: Vector3): Vector3
	return vector - Proj.Vector(vector, planeNormal)
end

function Proj.Reflect(vector: Vector3, normal: Vector3): Vector3
	local unitNormal = Vec.unit(normal)
	if unitNormal == Vector3.zero then
		return vector
	end
	return vector - unitNormal * (2 * vector:Dot(unitNormal))
end

function Proj.PointOnLine(point: Vector3, lineOrigin: Vector3, lineDirection: Vector3): Vector3
	local denominator = lineDirection:Dot(lineDirection)
	if denominator == 0 then
		return lineOrigin
	end

	local t = (point - lineOrigin):Dot(lineDirection) / denominator
	return lineOrigin + lineDirection * t
end

function Proj.PointOnRay(point: Vector3, rayOrigin: Vector3, rayDirection: Vector3): Vector3
	local denominator = rayDirection:Dot(rayDirection)
	if denominator == 0 then
		return rayOrigin
	end

	local t = math.max(0, (point - rayOrigin):Dot(rayDirection) / denominator)
	return rayOrigin + rayDirection * t
end

function Proj.PointOnSegment(point: Vector3, a: Vector3, b: Vector3): Vector3
	local segment = b - a
	local denominator = segment:Dot(segment)
	if denominator == 0 then
		return a
	end

	local t = Num.clamp((point - a):Dot(segment) / denominator, 0, 1)
	return a + segment * t
end

Proj.scalar = Proj.Scalar
Proj.vector = Proj.Vector
Proj.reject = Proj.Reject
Proj.ontoPlane = Proj.OntoPlane
Proj.reflect = Proj.Reflect
Proj.pointOnLine = Proj.PointOnLine
Proj.pointOnRay = Proj.PointOnRay
Proj.pointOnSegment = Proj.PointOnSegment

return Proj
