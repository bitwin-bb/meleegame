--!strict
-- Ray sampling and closest-point queries.

local Vec = require(script.Parent.Vec)

local Ray = {}

export type Ray = {
	origin: Vector3,
	direction: Vector3,
}

function Ray.new(origin: Vector3, direction: Vector3): Ray
	return {
		origin = origin,
		direction = direction,
	}
end

function Ray.at(ray: Ray, distance: number): Vector3
	return ray.origin + ray.direction * distance
end

function Ray.closestT(ray: Ray, point: Vector3): number
	local denominator = ray.direction:Dot(ray.direction)
	if denominator == 0 then
		return 0
	end
	return math.max(0, (point - ray.origin):Dot(ray.direction) / denominator)
end

function Ray.closestPoint(ray: Ray, point: Vector3): Vector3
	return Ray.at(ray, Ray.closestT(ray, point))
end

function Ray.distanceSqToPoint(ray: Ray, point: Vector3): number
	return Vec.distanceSq(point, Ray.closestPoint(ray, point))
end

function Ray.distanceToPoint(ray: Ray, point: Vector3): number
	return math.sqrt(Ray.distanceSqToPoint(ray, point))
end

return Ray
