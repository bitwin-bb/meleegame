--!strict
-- Mean and moving-average helpers.

local Num = require(script.Parent.Num)

local Avg = {}

export type WeightedValue = {
	value: number,
	weight: number,
}

function Avg.mean(values: { number }): number
	local count = #values
	if count == 0 then
		return 0
	end

	local total = 0
	for _, value in values do
		total = total + value
	end
	return total / count
end

function Avg.weighted(values: { WeightedValue }): number
	local weightedTotal = 0
	local totalWeight = 0

	for _, entry in values do
		if entry.weight > 0 then
			weightedTotal = weightedTotal + entry.value * entry.weight
			totalWeight = totalWeight + entry.weight
		end
	end

	if totalWeight == 0 then
		return 0
	end
	return weightedTotal / totalWeight
end

function Avg.moving(previousAverage: number, sample: number, alpha: number): number
	local blend = Num.saturate(alpha)
	return previousAverage + (sample - previousAverage) * blend
end

function Avg.running(previousAverage: number, previousCount: number, sample: number): (number, number)
	local count = math.max(0, math.floor(previousCount)) + 1
	local average = previousAverage + (sample - previousAverage) / count
	return average, count
end

function Avg.sliding(previousAverage: number, windowSize: number, outgoingSample: number, incomingSample: number): number
	local size = math.max(1, math.floor(windowSize))
	return previousAverage + (incomingSample - outgoingSample) / size
end

return Avg
