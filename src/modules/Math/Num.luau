--!strict
-- Core scalar helpers.

local Num = {}

local DEFAULT_EPSILON = 1e-5

local function sortBounds(minValue: number, maxValue: number): (number, number)
	if minValue <= maxValue then
		return minValue, maxValue
	end
	return maxValue, minValue
end

local function roundInteger(value: number): number
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

function Num.isFinite(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Num.clamp(value: number, minValue: number, maxValue: number): number
	local low, high = sortBounds(minValue, maxValue)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

function Num.saturate(value: number): number
	return Num.clamp(value, 0, 1)
end

function Num.sign(value: number): number
	if value > 0 then
		return 1
	end
	if value < 0 then
		return -1
	end
	return 0
end

function Num.nearlyEqual(a: number, b: number, epsilon: number?): boolean
	if a == b then
		return true
	end

	local tolerance = math.max(epsilon or DEFAULT_EPSILON, 0)
	local difference = math.abs(a - b)
	if difference <= tolerance then
		return true
	end

	local scale = math.max(1, math.abs(a), math.abs(b))
	return difference <= tolerance * scale
end

function Num.round(value: number, digits: number?): number
	local places = math.floor(digits or 0)
	if places == 0 then
		return roundInteger(value)
	end

	local factor = 10 ^ math.abs(places)
	if places > 0 then
		return roundInteger(value * factor) / factor
	end
	return roundInteger(value / factor) * factor
end

function Num.snap(value: number, step: number, origin: number?): number
	local interval = math.abs(step)
	if interval == 0 then
		return value
	end

	local offset = origin or 0
	return offset + Num.round((value - offset) / interval) * interval
end

function Num.inverseLerp(a: number, b: number, value: number): number
	local delta = b - a
	if delta == 0 then
		return 0
	end
	return (value - a) / delta
end

function Num.remap(
	value: number,
	fromMin: number,
	fromMax: number,
	toMin: number,
	toMax: number
): number
	return toMin + (toMax - toMin) * Num.inverseLerp(fromMin, fromMax, value)
end

function Num.safeDiv(numerator: number, denominator: number, fallback: number?): number
	if denominator == 0 then
		return fallback or 0
	end
	return numerator / denominator
end

function Num.fract(value: number): number
	return value - math.floor(value)
end

return Num
