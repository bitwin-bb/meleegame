--!strict

local Rand = require(script.Parent.Rand)

local RandomNumber = {}

function RandomNumber.Between(minValueRaw: any, maxValueRaw: any, randomOrSeedRaw: any?): (number, number?)
	local minValue = if typeof(minValueRaw) == "number" and minValueRaw == minValueRaw then minValueRaw else 1
	local maxValue = if typeof(maxValueRaw) == "number" and maxValueRaw == maxValueRaw then maxValueRaw else 100

	if typeof(randomOrSeedRaw) == "number" then
		local nextSeed, value = Rand.integer(randomOrSeedRaw, minValue, maxValue)
		return value, nextSeed
	end

	local randomObject = if typeof(randomOrSeedRaw) == "Random" then randomOrSeedRaw :: Random else Random.new()
	return randomObject:NextInteger(math.floor(minValue), math.floor(maxValue)), nil
end

function RandomNumber.Unit(randomOrSeedRaw: any?): (number, number?)
	if typeof(randomOrSeedRaw) == "number" then
		local nextSeed, value = Rand.number(randomOrSeedRaw)
		return value, nextSeed
	end

	local randomObject = if typeof(randomOrSeedRaw) == "Random" then randomOrSeedRaw :: Random else Random.new()
	return randomObject:NextNumber(), nil
end

RandomNumber.between = RandomNumber.Between
RandomNumber.unit = RandomNumber.Unit

return RandomNumber
