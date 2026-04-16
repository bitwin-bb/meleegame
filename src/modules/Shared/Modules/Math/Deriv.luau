--!strict
-- Lightweight numerical derivative helpers.

local Deriv = {}

export type Sample = number | Vector2 | Vector3

local function zeroLike<T>(value: T): T
	local kind = typeof(value)
	if kind == "number" then
		return (0 :: any) :: T
	end
	if kind == "Vector2" then
		return (Vector2.zero :: any) :: T
	end
	return (Vector3.zero :: any) :: T
end

local function add<T>(a: T, b: T): T
	return (((a :: any) + (b :: any)) :: any) :: T
end

local function sub<T>(a: T, b: T): T
	return (((a :: any) - (b :: any)) :: any) :: T
end

local function mul<T>(value: T, scalar: number): T
	return (((value :: any) * scalar) :: any) :: T
end

function Deriv.rate<T>(current: T, previous: T, dt: number): T
	if dt == 0 then
		return zeroLike(current)
	end
	return mul(sub(current, previous), 1 / dt)
end

function Deriv.central<T>(previous: T, nextValue: T, dt: number): T
	local span = dt * 2
	if span == 0 then
		return zeroLike(previous)
	end
	return mul(sub(nextValue, previous), 1 / span)
end

function Deriv.second<T>(previous: T, current: T, nextValue: T, dt: number): T
	if dt == 0 then
		return zeroLike(current)
	end

	local numerator = add(add(previous, nextValue), mul(current, -2))
	return mul(numerator, 1 / (dt * dt))
end

function Deriv.SampleForward(sample: (number) -> number, x: number, step: number?): number
	local h = math.max(math.abs(step or 1e-3), 1e-8)
	return (sample(x + h) - sample(x)) / h
end

function Deriv.SampleCentral(sample: (number) -> number, x: number, step: number?): number
	local h = math.max(math.abs(step or 1e-3), 1e-8)
	return (sample(x + h) - sample(x - h)) / (2 * h)
end

Deriv.sampleForward = Deriv.SampleForward
Deriv.sampleCentral = Deriv.SampleCentral

return Deriv
