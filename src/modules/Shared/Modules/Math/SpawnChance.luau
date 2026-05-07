--!strict

local Rand = require(script.Parent.Rand)

local SpawnChance = {}

export type SpawnRoll = {
	spawned: boolean,
	roll: number,
	probability: number,
	seed: number?,
}

local function sanitizeProbability(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return math.clamp(fallback, 0, 1)
	end
	return math.clamp(valueRaw, 0, 1)
end

function SpawnChance.ResolveProbability(chanceRaw: any, multiplierRaw: any?): number
	local chance = sanitizeProbability(chanceRaw, 0)
	local multiplier = if typeof(multiplierRaw) == "number" and multiplierRaw == multiplierRaw then multiplierRaw else 1
	return math.clamp(chance * math.max(0, multiplier), 0, 1)
end

function SpawnChance.Roll(chanceRaw: any, randomOrSeedRaw: any?, multiplierRaw: any?): SpawnRoll
	local probability = SpawnChance.ResolveProbability(chanceRaw, multiplierRaw)
	if typeof(randomOrSeedRaw) == "number" then
		local nextSeed, didSpawn = Rand.chance(randomOrSeedRaw, probability)
		local _, roll = Rand.number(randomOrSeedRaw)
		return {
			spawned = didSpawn,
			roll = roll,
			probability = probability,
			seed = nextSeed,
		}
	end

	local randomObject = if typeof(randomOrSeedRaw) == "Random" then randomOrSeedRaw :: Random else Random.new()
	local roll = randomObject:NextNumber()
	return {
		spawned = roll <= probability,
		roll = roll,
		probability = probability,
		seed = nil,
	}
end

SpawnChance.resolveProbability = SpawnChance.ResolveProbability
SpawnChance.roll = SpawnChance.Roll

return SpawnChance
