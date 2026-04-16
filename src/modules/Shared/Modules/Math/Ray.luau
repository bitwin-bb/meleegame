--!strict
-- Ray sampling and closest-point queries.

local Vec = require(script.Parent.Vec)

local Ray = {}

export type Ray = {
	origin: Vector3,
	direction: Vector3,
}

function Ray.New(origin: Vector3, direction: Vector3): Ray
	return {
		origin = origin,
		direction = direction,
	}
end

function Ray.At(ray: Ray, distance: number): Vector3
	return ray.origin + ray.direction * distance
end

function Ray.ClosestT(ray: Ray, point: Vector3): number
	local denominator = ray.direction:Dot(ray.direction)
	if denominator == 0 then
		return 0
	end
	return math.max(0, (point - ray.origin):Dot(ray.direction) / denominator)
end

function Ray.ClosestPoint(ray: Ray, point: Vector3): Vector3
	return Ray.At(ray, Ray.ClosestT(ray, point))
end

function Ray.DistanceSqToPoint(ray: Ray, point: Vector3): number
	return Vec.distanceSq(point, Ray.ClosestPoint(ray, point))
end

function Ray.DistanceToPoint(ray: Ray, point: Vector3): number
	return math.sqrt(Ray.DistanceSqToPoint(ray, point))
end

Ray.new = Ray.New
Ray.at = Ray.At
Ray.closestT = Ray.ClosestT
Ray.closestPoint = Ray.ClosestPoint
Ray.distanceSqToPoint = Ray.DistanceSqToPoint
Ray.distanceToPoint = Ray.DistanceToPoint

return Ray
