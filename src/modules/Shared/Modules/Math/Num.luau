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

function Num.IsFinite(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Num.Clamp(value: number, minValue: number, maxValue: number): number
	local low, high = sortBounds(minValue, maxValue)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

function Num.Saturate(value: number): number
	return Num.Clamp(value, 0, 1)
end

function Num.Sign(value: number): number
	if value > 0 then
		return 1
	end
	if value < 0 then
		return -1
	end
	return 0
end

function Num.NearlyEqual(a: number, b: number, epsilon: number?): boolean
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

function Num.Round(value: number, digits: number?): number
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

function Num.Snap(value: number, step: number, origin: number?): number
	local interval = math.abs(step)
	if interval == 0 then
		return value
	end

	local offset = origin or 0
	return offset + Num.Round((value - offset) / interval) * interval
end

function Num.InverseLerp(a: number, b: number, value: number): number
	local delta = b - a
	if delta == 0 then
		return 0
	end
	return (value - a) / delta
end

function Num.Remap(
	value: number,
	fromMin: number,
	fromMax: number,
	toMin: number,
	toMax: number
): number
	return toMin + (toMax - toMin) * Num.InverseLerp(fromMin, fromMax, value)
end

function Num.SafeDiv(numerator: number, denominator: number, fallback: number?): number
	if denominator == 0 then
		return fallback or 0
	end
	return numerator / denominator
end

function Num.Fract(value: number): number
	return value - math.floor(value)
end

Num.isFinite = Num.IsFinite
Num.clamp = Num.Clamp
Num.saturate = Num.Saturate
Num.sign = Num.Sign
Num.nearlyEqual = Num.NearlyEqual
Num.round = Num.Round
Num.snap = Num.Snap
Num.inverseLerp = Num.InverseLerp
Num.remap = Num.Remap
Num.safeDiv = Num.SafeDiv
Num.fract = Num.Fract

return Num
