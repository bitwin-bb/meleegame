--!strict
-- Focused analytic solvers and simple ray intersection helpers.

local Solve = {}

export type QuadraticRoots = {
	count: number,
	discriminant: number,
	min: number?,
	max: number?,
}

export type RayHit = {
	t: number,
	point: Vector3,
}

local EPSILON = 1e-8

function Solve.Linear(a: number, b: number): number?
	if math.abs(a) <= EPSILON then
		return nil
	end
	return -b / a
end

function Solve.Quadratic(a: number, b: number, c: number): QuadraticRoots
	if math.abs(a) <= EPSILON then
		local root = Solve.Linear(b, c)
		if root == nil then
			return {
				count = 0,
				discriminant = 0,
			}
		end
		return {
			count = 1,
			discriminant = 0,
			min = root,
			max = root,
		}
	end

	local discriminant = b * b - 4 * a * c
	if discriminant < -EPSILON then
		return {
			count = 0,
			discriminant = discriminant,
		}
	end

	if math.abs(discriminant) <= EPSILON then
		local root = -b / (2 * a)
		return {
			count = 1,
			discriminant = 0,
			min = root,
			max = root,
		}
	end

	local sqrtDiscriminant = math.sqrt(discriminant)
	local rootA = (-b - sqrtDiscriminant) / (2 * a)
	local rootB = (-b + sqrtDiscriminant) / (2 * a)
	local minRoot = math.min(rootA, rootB)
	local maxRoot = math.max(rootA, rootB)
	return {
		count = 2,
		discriminant = discriminant,
		min = minRoot,
		max = maxRoot,
	}
end

function Solve.SmallestPositiveQuadratic(a: number, b: number, c: number, minimum: number?): number?
	local threshold = minimum or 0
	local roots = Solve.Quadratic(a, b, c)
	if roots.count == 0 then
		return nil
	end

	if roots.min ~= nil and roots.min >= threshold then
		return roots.min
	end
	if roots.max ~= nil and roots.max >= threshold then
		return roots.max
	end
	return nil
end

function Solve.RayPlane(origin: Vector3, direction: Vector3, planePoint: Vector3, planeNormal: Vector3): RayHit?
	local denominator = planeNormal:Dot(direction)
	if math.abs(denominator) <= EPSILON then
		return nil
	end

	local t = planeNormal:Dot(planePoint - origin) / denominator
	if t < 0 then
		return nil
	end

	return {
		t = t,
		point = origin + direction * t,
	}
end

function Solve.RaySphere(origin: Vector3, direction: Vector3, center: Vector3, radius: number): RayHit?
	local offset = origin - center
	local a = direction:Dot(direction)
	if a <= EPSILON then
		return nil
	end

	local b = 2 * direction:Dot(offset)
	local c = offset:Dot(offset) - radius * radius
	local t = Solve.SmallestPositiveQuadratic(a, b, c, 0)
	if t == nil then
		return nil
	end

	return {
		t = t,
		point = origin + direction * t,
	}
end

Solve.linear = Solve.Linear
Solve.quadratic = Solve.Quadratic
Solve.smallestPositiveQuadratic = Solve.SmallestPositiveQuadratic
Solve.rayPlane = Solve.RayPlane
Solve.raySphere = Solve.RaySphere

return Solve
