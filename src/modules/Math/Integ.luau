--!strict
-- Lightweight numerical integration and prediction helpers.

local Integ = {}

local function add<T>(a: T, b: T): T
	return (((a :: any) + (b :: any)) :: any) :: T
end

local function mul<T>(value: T, scalar: number): T
	return (((value :: any) * scalar) :: any) :: T
end

function Integ.euler<T>(value: T, rate: T, dt: number): T
	return add(value, mul(rate, dt))
end

function Integ.trapezoidStep<T>(value: T, previousRate: T, currentRate: T, dt: number): T
	return add(value, mul(add(previousRate, currentRate), 0.5 * dt))
end

function Integ.predict<T>(value: T, velocity: T, acceleration: T?, dt: number): T
	local predicted = add(value, mul(velocity, dt))
	if acceleration == nil then
		return predicted
	end
	return add(predicted, mul(acceleration, 0.5 * dt * dt))
end

function Integ.trapezoid(sample: (number) -> number, a: number, b: number, segments: number?): number
	local count = math.max(1, math.floor(segments or 16))
	local width = (b - a) / count
	local total = 0.5 * (sample(a) + sample(b))

	for index = 1, count - 1 do
		total = total + sample(a + width * index)
	end

	return total * width
end

function Integ.simpson(sample: (number) -> number, a: number, b: number, segments: number?): number
	local count = math.max(2, math.floor(segments or 32))
	if count % 2 ~= 0 then
		count = count + 1
	end

	local width = (b - a) / count
	local total = sample(a) + sample(b)

	for index = 1, count - 1 do
		local weight = if index % 2 == 0 then 2 else 4
		total = total + sample(a + width * index) * weight
	end

	return total * width / 3
end

return Integ
