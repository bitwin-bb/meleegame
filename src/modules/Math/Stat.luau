--!strict
-- Variance and standard-deviation helpers.

local Avg = require(script.Parent.Avg)

local Stat = {}

export type WeightedValue = Avg.WeightedValue

local function varianceWithMean(values: { number }, meanValue: number, sample: boolean): number
	local count = #values
	if count == 0 then
		return 0
	end
	if sample and count < 2 then
		return 0
	end

	local total = 0
	for _, value in values do
		local delta = value - meanValue
		total = total + delta * delta
	end

	local divisor = if sample then count - 1 else count
	return total / divisor
end

function Stat.variance(values: { number }): number
	if #values == 0 then
		return 0
	end
	return varianceWithMean(values, Avg.mean(values), false)
end

function Stat.sampleVariance(values: { number }): number
	if #values < 2 then
		return 0
	end
	return varianceWithMean(values, Avg.mean(values), true)
end

function Stat.stdDev(values: { number }): number
	return math.sqrt(Stat.variance(values))
end

function Stat.sampleStdDev(values: { number }): number
	return math.sqrt(Stat.sampleVariance(values))
end

function Stat.weightedVariance(values: { WeightedValue }): number
	local meanValue = Avg.weighted(values)
	local weightedTotal = 0
	local totalWeight = 0

	for _, entry in values do
		if entry.weight > 0 then
			local delta = entry.value - meanValue
			weightedTotal = weightedTotal + delta * delta * entry.weight
			totalWeight = totalWeight + entry.weight
		end
	end

	if totalWeight == 0 then
		return 0
	end
	return weightedTotal / totalWeight
end

function Stat.weightedStdDev(values: { WeightedValue }): number
	return math.sqrt(Stat.weightedVariance(values))
end

return Stat
