--!strict
-- Interval helpers for wrapping, normalization, and overlap tests.

local Num = require(script.Parent.Num)

local Range = {}

export type Interval = {
	min: number,
	max: number,
}

local function sortBounds(minValue: number, maxValue: number): (number, number)
	if minValue <= maxValue then
		return minValue, maxValue
	end
	return maxValue, minValue
end

function Range.New(minValue: number, maxValue: number): Interval
	local low, high = sortBounds(minValue, maxValue)
	return {
		min = low,
		max = high,
	}
end

function Range.Span(minValue: number, maxValue: number): number
	local low, high = sortBounds(minValue, maxValue)
	return high - low
end

function Range.Center(minValue: number, maxValue: number): number
	local low, high = sortBounds(minValue, maxValue)
	return (low + high) * 0.5
end

function Range.Normalize(value: number, minValue: number, maxValue: number): number
	local low, high = sortBounds(minValue, maxValue)
	return Num.inverseLerp(low, high, value)
end

function Range.NormalizeClamped(value: number, minValue: number, maxValue: number): number
	return Num.saturate(Range.Normalize(value, minValue, maxValue))
end

function Range.Wrap(value: number, minValue: number, maxValue: number): number
	local low, high = sortBounds(minValue, maxValue)
	local span = high - low
	if span == 0 then
		return low
	end

	local wrapped = (value - low) % span
	if wrapped < 0 then
		wrapped = wrapped + span
	end
	return low + wrapped
end

function Range.Contains(value: number, minValue: number, maxValue: number, inclusive: boolean?): boolean
	local low, high = sortBounds(minValue, maxValue)
	if inclusive == false then
		return value > low and value < high
	end
	return value >= low and value <= high
end

function Range.Overlaps(
	aMin: number,
	aMax: number,
	bMin: number,
	bMax: number,
	inclusive: boolean?
): boolean
	local aLow, aHigh = sortBounds(aMin, aMax)
	local bLow, bHigh = sortBounds(bMin, bMax)
	if inclusive == false then
		return aLow < bHigh and bLow < aHigh
	end
	return aLow <= bHigh and bLow <= aHigh
end

function Range.Intersection(aMin: number, aMax: number, bMin: number, bMax: number): Interval?
	local aLow, aHigh = sortBounds(aMin, aMax)
	local bLow, bHigh = sortBounds(bMin, bMax)
	local low = math.max(aLow, bLow)
	local high = math.min(aHigh, bHigh)
	if low > high then
		return nil
	end
	return {
		min = low,
		max = high,
	}
end

Range.new = Range.New
Range.span = Range.Span
Range.center = Range.Center
Range.normalize = Range.Normalize
Range.normalizeClamped = Range.NormalizeClamped
Range.wrap = Range.Wrap
Range.contains = Range.Contains
Range.overlaps = Range.Overlaps
Range.intersection = Range.Intersection

return Range
