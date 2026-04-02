--!strict
-- Finite-difference helpers for discrete samples and scalar fields.

local Diff = {}

local function sub<T>(a: T, b: T): T
	return (((a :: any) - (b :: any)) :: any) :: T
end

function Diff.delta<T>(current: T, previous: T): T
	return sub(current, previous)
end

function Diff.forward(values: { number }, index: number, step: number?): number
	local i = math.floor(index)
	if i < 1 or i >= #values then
		return 0
	end

	local h = math.max(math.abs(step or 1), 1e-8)
	return (values[i + 1] - values[i]) / h
end

function Diff.backward(values: { number }, index: number, step: number?): number
	local i = math.floor(index)
	if i <= 1 or i > #values then
		return 0
	end

	local h = math.max(math.abs(step or 1), 1e-8)
	return (values[i] - values[i - 1]) / h
end

function Diff.central(values: { number }, index: number, step: number?): number
	local i = math.floor(index)
	if i <= 1 or i >= #values then
		return 0
	end

	local h = math.max(math.abs(step or 1), 1e-8)
	return (values[i + 1] - values[i - 1]) / (2 * h)
end

function Diff.gradient2(sample: (number, number) -> number, x: number, y: number, step: number?): Vector2
	local h = math.max(math.abs(step or 1e-3), 1e-8)
	local dx = (sample(x + h, y) - sample(x - h, y)) / (2 * h)
	local dy = (sample(x, y + h) - sample(x, y - h)) / (2 * h)
	return Vector2.new(dx, dy)
end

function Diff.gradient3(sample: (number, number, number) -> number, x: number, y: number, z: number, step: number?): Vector3
	local h = math.max(math.abs(step or 1e-3), 1e-8)
	local dx = (sample(x + h, y, z) - sample(x - h, y, z)) / (2 * h)
	local dy = (sample(x, y + h, z) - sample(x, y - h, z)) / (2 * h)
	local dz = (sample(x, y, z + h) - sample(x, y, z - h)) / (2 * h)
	return Vector3.new(dx, dy, dz)
end

return Diff
