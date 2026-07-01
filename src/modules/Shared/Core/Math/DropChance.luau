
local require = require(script.Parent.loader).load(script)

local Rand = require("Rand")

local DropChance = {}

export type DropEntry<T> = {
	value: T,
	weight: number?,
	chance: number?,
}

local function CoerceChance(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return math.clamp(fallback, 0, 1)
	end
	return math.clamp(valueRaw, 0, 1)
end

local function CoerceWeight(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.max(0, valueRaw)
end

function DropChance.Roll(chanceRaw: any, randomOrSeedRaw: any?): (boolean, number, number?)
	local chance = CoerceChance(chanceRaw, 0)
	if typeof(randomOrSeedRaw) == "number" then
		local nextSeed, roll = Rand.Number(randomOrSeedRaw)
		return roll <= chance, roll, nextSeed
	end

	local randomObject = if typeof(randomOrSeedRaw) == "Random" then randomOrSeedRaw :: Random else Random.new()
	local roll = randomObject:NextNumber()
	return roll <= chance, roll, nil
end

function DropChance.PickWeighted<T>(entries: { DropEntry<T> }, randomOrSeedRaw: any?): (T?, number?)
	if #entries == 0 then
		return nil, if typeof(randomOrSeedRaw) == "number" then randomOrSeedRaw else nil
	end

	local weightedEntries = {}
	for _, entry in entries do
		local weight = CoerceWeight(entry.weight or entry.chance)
		if weight > 0 then
			weightedEntries[#weightedEntries + 1] = {
				value = entry.value,
				weight = weight,
			}
		end
	end

	if #weightedEntries == 0 then
		return entries[1].value, if typeof(randomOrSeedRaw) == "number" then randomOrSeedRaw else nil
	end

	if typeof(randomOrSeedRaw) == "number" then
		local nextSeed, value = Rand.weighted(randomOrSeedRaw, weightedEntries)
		return value, nextSeed
	end

	local randomObject = if typeof(randomOrSeedRaw) == "Random" then randomOrSeedRaw :: Random else Random.new()
	local totalWeight = 0
	for _, entry in weightedEntries do
		totalWeight += entry.weight
	end

	local roll = randomObject:NextNumber(0, totalWeight)
	local running = 0
	for _, entry in weightedEntries do
		running += entry.weight
		if roll <= running then
			return entry.value, nil
		end
	end

	return weightedEntries[#weightedEntries].value, nil
end
return DropChance
