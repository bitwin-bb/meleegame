--!strict

local DropChance = require(script.Parent.DropChance)

local ReforgeRarity = {}

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type RarityWeight = {
	value: Rarity,
	weight: number,
}

local DEFAULT_WEIGHTS: { RarityWeight } = {
	{ value = "Common", weight = 44 },
	{ value = "Uncommon", weight = 28 },
	{ value = "Rare", weight = 16 },
	{ value = "Epic", weight = 8 },
	{ value = "Legendary", weight = 3 },
	{ value = "Mythic", weight = 1 },
}

local RARITY_RANK: { [Rarity]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
}

function ReforgeRarity.GetRank(rarityRaw: any): number
	if typeof(rarityRaw) ~= "string" then
		return 0
	end
	return (RARITY_RANK :: any)[rarityRaw] or 0
end

function ReforgeRarity.Compare(leftRaw: any, rightRaw: any): number
	return ReforgeRarity.GetRank(leftRaw) - ReforgeRarity.GetRank(rightRaw)
end

function ReforgeRarity.Roll(randomOrSeedRaw: any?, weightsRaw: { RarityWeight }?): (Rarity, number?)
	local value, nextSeed = DropChance.pickWeighted((weightsRaw :: any) or DEFAULT_WEIGHTS, randomOrSeedRaw)
	return (value or "Common") :: Rarity, nextSeed
end

function ReforgeRarity.GetDefaultWeights(): { RarityWeight }
	return table.clone(DEFAULT_WEIGHTS)
end

ReforgeRarity.getRank = ReforgeRarity.GetRank
ReforgeRarity.compare = ReforgeRarity.Compare
ReforgeRarity.roll = ReforgeRarity.Roll
ReforgeRarity.getDefaultWeights = ReforgeRarity.GetDefaultWeights

return ReforgeRarity
