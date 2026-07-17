local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuildServiceUtils = require("BuildServiceUtils")
local CropTypes = require("CropTypes")

local TILE_ID = BuildServiceUtils.TILE_ID

local CropDefinitions = {}

local SYSTEM_CONFIG = {
	randomUpdateInterval = 0.75,
	samplesPerChunk = 6,
	maxChunksPerTick = 24,
	maxRandomUpdatesPerTick = 192,
	maxTerrainMutationsPerFlush = 512,
	deltaBatchMax = 256,
	lightScanHeight = 16,
	waterScanRadius = 2,
	requestInterval = 0.1,
}

local SPREAD_OFFSETS = {
	{ x = -1, y = -1 },
	{ x = 0, y = -1 },
	{ x = 1, y = -1 },
	{ x = -1, y = 0 },
	{ x = 1, y = 0 },
	{ x = -1, y = 1 },
	{ x = 0, y = 1 },
	{ x = 1, y = 1 },
}

local DEFINITIONS = {
	ForestGrass = {
		id = "ForestGrass",
		kind = CropTypes.Kind.Grass,
		seedItemId = "GrassSeeds",
		placement = {
			mode = CropTypes.PlacementMode.ReplaceSoil,
			targetTileIds = { TILE_ID.DIRT },
			resultTileId = TILE_ID.GRASS,
			requireOpenAbove = true,
		},
		stages = {
			{ id = "Grass" },
		},
		growthRequirements = {
			minLight = 0.35,
		},
		spread = {
			chance = 0.16,
			offsets = SPREAD_OFFSETS,
			targetTileIds = { TILE_ID.DIRT },
			resultTileId = TILE_ID.GRASS,
			requireOpenAbove = true,
			decorativeChance = 0.08,
			decorativeCropIds = { "TallGrass" },
			requirements = {
				minLight = 0.35,
			},
		},
		randomUpdateTileIds = { TILE_ID.GRASS },
	},
	TallGrass = {
		id = "TallGrass",
		kind = CropTypes.Kind.Decorative,
		placement = {
			mode = CropTypes.PlacementMode.AboveSoil,
			soilOffsetY = -1,
			soilTileIds = { TILE_ID.GRASS, TILE_ID.JUNGLE_GRASS },
		},
		stages = {
			{ id = "Mature" },
		},
	},
	Daybloom = {
		id = "Daybloom",
		kind = CropTypes.Kind.Herb,
		seedItemId = "DaybloomSeeds",
		placement = {
			mode = CropTypes.PlacementMode.AboveSoil,
			soilOffsetY = -1,
			soilTileIds = { TILE_ID.DIRT, TILE_ID.GRASS },
		},
		stages = {
			{
				id = "Seedling",
				growthChance = 0.34,
			},
			{
				id = "Growing",
				growthChance = 0.28,
				requirements = {
					dayParts = { "Dawn", "Day" },
					minLight = 0.55,
				},
			},
			{
				id = "Bloom",
				requirements = {
					dayParts = { "Dawn", "Day" },
					minLight = 0.55,
				},
			},
		},
		growthRequirements = {
			soilTileIds = { TILE_ID.DIRT, TILE_ID.GRASS },
			clearanceAbove = 1,
			maxWater = 0.8,
		},
		harvestRequirements = {
			dayParts = { "Dawn", "Day" },
			minLight = 0.55,
		},
		harvestDrops = {
			{ itemId = "Daybloom", minAmount = 1, maxAmount = 1, chance = 1 },
			{ itemId = "DaybloomSeeds", minAmount = 1, maxAmount = 3, chance = 1 },
		},
	},
	ForestTree = {
		id = "ForestTree",
		kind = CropTypes.Kind.Tree,
		seedItemId = "Acorn",
		placement = {
			mode = CropTypes.PlacementMode.AboveSoil,
			soilOffsetY = -1,
			soilTileIds = { TILE_ID.DIRT, TILE_ID.GRASS },
		},
		stages = {
			{ id = "Sapling" },
			{ id = "Mature" },
		},
		growthRequirements = {
			soilTileIds = { TILE_ID.DIRT, TILE_ID.GRASS },
			minLight = 0.4,
		},
		harvestDrops = {
			{ itemId = "Wood", minAmount = 4, maxAmount = 8, chance = 1 },
			{ itemId = "Acorn", minAmount = 1, maxAmount = 3, chance = 0.75 },
		},
		tree = {
			growthChance = 0.045,
			soilTileIds = { TILE_ID.DIRT, TILE_ID.GRASS },
			minHeight = 6,
			maxHeight = 10,
			verticalClearance = 13,
			horizontalClearance = 3,
			nearbyBlockerRadius = 4,
			branchChance = 0.62,
			minBranchHeight = 3,
			maxBranchLength = 2,
			foliageRadius = 2,
		},
	},
}

function CropDefinitions.Get(cropIdRaw: any): any?
	local cropId = CropTypes.CoerceCropId(cropIdRaw)
	if cropId == nil then
		return nil
	end

	local direct = DEFINITIONS[cropId]
	if direct ~= nil then
		return Table.deepCopy(direct)
	end

	local normalized = string.lower(cropId)
	for id, definition in DEFINITIONS do
		if string.lower(id) == normalized then
			return Table.deepCopy(definition)
		end
	end
	return nil
end

function CropDefinitions.GetAll(): { [string]: any }
	return Table.deepCopy(DEFINITIONS)
end

function CropDefinitions.GetSystemConfig(): any
	return table.clone(SYSTEM_CONFIG)
end

table.freeze(SYSTEM_CONFIG)

return Table.readonly(CropDefinitions)
