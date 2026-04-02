--!strict
-- Plane construction, distances, projections, and intersections.

local Vec = require(script.Parent.Vec)

local Plane = {}

export type Plane = {
	normal: Vector3,
	distance: number,
}

export type Intersection = {
	t: number,
	point: Vector3,
}

local EPSILON = 1e-8
local Y_AXIS = Vector3.new(0, 1, 0)

function Plane.new(normal: Vector3, distance: number): Plane
	local unitNormal = Vec.unit(normal, Y_AXIS)
	return {
		normal = unitNormal,
		distance = distance,
	}
end

function Plane.fromPointNormal(point: Vector3, normal: Vector3): Plane
	local unitNormal = Vec.unit(normal, Y_AXIS)
	return {
		normal = unitNormal,
		distance = unitNormal:Dot(point),
	}
end

function Plane.fromPoints(a: Vector3, b: Vector3, c: Vector3): Plane
	local unitNormal = Vec.unit((b - a):Cross(c - a), Y_AXIS)
	return {
		normal = unitNormal,
		distance = unitNormal:Dot(a),
	}
end

function Plane.signedDistance(plane: Plane, point: Vector3): number
	return plane.normal:Dot(point) - plane.distance
end

function Plane.closestPoint(plane: Plane, point: Vector3): Vector3
	return point - plane.normal * Plane.signedDistance(plane, point)
end

function Plane.projectPoint(plane: Plane, point: Vector3): Vector3
	return Plane.closestPoint(plane, point)
end

function Plane.reflectPoint(plane: Plane, point: Vector3): Vector3
	local signedDistance = Plane.signedDistance(plane, point)
	return point - plane.normal * (2 * signedDistance)
end

function Plane.intersectLine(plane: Plane, origin: Vector3, direction: Vector3): Intersection?
	local denominator = plane.normal:Dot(direction)
	if math.abs(denominator) <= EPSILON then
		return nil
	end

	local t = (plane.distance - plane.normal:Dot(origin)) / denominator
	return {
		t = t,
		point = origin + direction * t,
	}
end

function Plane.raycast(plane: Plane, origin: Vector3, direction: Vector3): Intersection?
	local hit = Plane.intersectLine(plane, origin, direction)
	if hit == nil or hit.t < 0 then
		return nil
	end
	return hit
end

return Plane
