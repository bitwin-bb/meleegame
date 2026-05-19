--!strict
-- Axis-aligned bounds helpers for closest points, distances, and ray hits.

local Vec = require(script.Parent.Vec)

local Bounds = {}

export type Bounds = {
	min: Vector3,
	max: Vector3,
}

export type RayIntersection = {
	tMin: number,
	tMax: number,
	point: Vector3,
}

local function resolvePadding(padding: number | Vector3): Vector3
	if typeof(padding) == "number" then
		local amount = math.abs(padding)
		return Vector3.new(amount, amount, amount)
	end
	return Vec.abs(padding)
end

local function intersectAxis(origin: number, direction: number, minValue: number, maxValue: number): (boolean, number, number)
	if direction == 0 then
		if origin < minValue or origin > maxValue then
			return false, 0, 0
		end
		return true, -math.huge, math.huge
	end

	local t0 = (minValue - origin) / direction
	local t1 = (maxValue - origin) / direction
	if t0 > t1 then
		local temporary = t0
		t0 = t1
		t1 = temporary
	end
	return true, t0, t1
end

function Bounds.New(minValue: Vector3, maxValue: Vector3): Bounds
	return {
		min = Vec.min(minValue, maxValue),
		max = Vec.max(minValue, maxValue),
	}
end

function Bounds.FromCenterSize(center: Vector3, size: Vector3): Bounds
	local halfSize = Vec.abs(size) * 0.5
	return {
		min = center - halfSize,
		max = center + halfSize,
	}
end

function Bounds.FromPoints(points: { Vector3 }): Bounds
	if #points == 0 then
		return {
			min = Vector3.zero,
			max = Vector3.zero,
		}
	end

	local minValue = points[1]
	local maxValue = points[1]
	for index = 2, #points do
		local point = points[index]
		minValue = Vec.min(minValue, point)
		maxValue = Vec.max(maxValue, point)
	end

	return {
		min = minValue,
		max = maxValue,
	}
end

function Bounds.Center(bounds: Bounds): Vector3
	return (bounds.min + bounds.max) * 0.5
end

function Bounds.Size(bounds: Bounds): Vector3
	return bounds.max - bounds.min
end

function Bounds.ContainsPoint(bounds: Bounds, point: Vector3, inclusive: boolean?): boolean
	if inclusive == false then
		return point.X > bounds.min.X
			and point.X < bounds.max.X
			and point.Y > bounds.min.Y
			and point.Y < bounds.max.Y
			and point.Z > bounds.min.Z
			and point.Z < bounds.max.Z
	end

	return point.X >= bounds.min.X
		and point.X <= bounds.max.X
		and point.Y >= bounds.min.Y
		and point.Y <= bounds.max.Y
		and point.Z >= bounds.min.Z
		and point.Z <= bounds.max.Z
end

function Bounds.ClosestPoint(bounds: Bounds, point: Vector3): Vector3
	return Vector3.new(
		math.clamp(point.X, bounds.min.X, bounds.max.X),
		math.clamp(point.Y, bounds.min.Y, bounds.max.Y),
		math.clamp(point.Z, bounds.min.Z, bounds.max.Z)
	)
end

function Bounds.DistanceSqToPoint(bounds: Bounds, point: Vector3): number
	return Vec.distanceSq(point, Bounds.ClosestPoint(bounds, point))
end

function Bounds.DistanceToPoint(bounds: Bounds, point: Vector3): number
	return math.sqrt(Bounds.DistanceSqToPoint(bounds, point))
end

function Bounds.Expand(bounds: Bounds, padding: number | Vector3): Bounds
	local resolvedPadding = resolvePadding(padding)
	return {
		min = bounds.min - resolvedPadding,
		max = bounds.max + resolvedPadding,
	}
end

function Bounds.Union(a: Bounds, b: Bounds): Bounds
	return {
		min = Vec.min(a.min, b.min),
		max = Vec.max(a.max, b.max),
	}
end

function Bounds.Intersects(a: Bounds, b: Bounds): boolean
	return a.min.X <= b.max.X
		and a.max.X >= b.min.X
		and a.min.Y <= b.max.Y
		and a.max.Y >= b.min.Y
		and a.min.Z <= b.max.Z
		and a.max.Z >= b.min.Z
end

function Bounds.IntersectRay(bounds: Bounds, origin: Vector3, direction: Vector3): RayIntersection?
	local successX, xMin, xMax = intersectAxis(origin.X, direction.X, bounds.min.X, bounds.max.X)
	if not successX then
		return nil
	end

	local successY, yMin, yMax = intersectAxis(origin.Y, direction.Y, bounds.min.Y, bounds.max.Y)
	if not successY then
		return nil
	end

	local successZ, zMin, zMax = intersectAxis(origin.Z, direction.Z, bounds.min.Z, bounds.max.Z)
	if not successZ then
		return nil
	end

	local tMin = math.max(xMin, yMin, zMin)
	local tMax = math.min(xMax, yMax, zMax)
	if tMax < math.max(tMin, 0) then
		return nil
	end

	local hitT = if tMin >= 0 then tMin else 0
	return {
		tMin = tMin,
		tMax = tMax,
		point = origin + direction * hitT,
	}
end

Bounds.new = Bounds.New
Bounds.fromCenterSize = Bounds.FromCenterSize
Bounds.fromPoints = Bounds.FromPoints
Bounds.center = Bounds.Center
Bounds.size = Bounds.Size
Bounds.containsPoint = Bounds.ContainsPoint
Bounds.closestPoint = Bounds.ClosestPoint
Bounds.distanceSqToPoint = Bounds.DistanceSqToPoint
Bounds.distanceToPoint = Bounds.DistanceToPoint
Bounds.expand = Bounds.Expand
Bounds.union = Bounds.Union
Bounds.intersects = Bounds.Intersects
Bounds.intersectRay = Bounds.IntersectRay

return Bounds
