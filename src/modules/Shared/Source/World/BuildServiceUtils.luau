local require = require(script.Parent.loader).load(script)

local Height = require("Height")
local ItemRegistry = require("ItemRegistry")
local MiningPower = require("MiningPower")
local Noise = require("Noise")
local Plane = require("Plane")
local Table = require("Table")
local Vec = require("Vec")

local BuildServiceUtils = {}

BuildServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
BuildServiceUtils.NETWORK_METHOD_REQUEST_PLACE_TILE = "requestPlaceTile"
BuildServiceUtils.NETWORK_METHOD_REQUEST_BREAK_TILE = "requestBreakTile"
BuildServiceUtils.NETWORK_METHOD_GET_TILE_AT = "getTileAt"
BuildServiceUtils.NETWORK_METHOD_CAN_PLACE_AT = "canPlaceAt"

BuildServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
BuildServiceUtils.CLIENT_METHOD_ON_TILE_DELTAS = "onTileDeltas"
BuildServiceUtils.CLIENT_METHOD_ON_ACTION_RESULT = "onActionResult"
BuildServiceUtils.CLIENT_METHOD_ON_BREAK_PROGRESS = "onBreakProgress"
BuildServiceUtils.CLIENT_METHOD_ON_TILE_FETCHED = "onTileFetched"
BuildServiceUtils.CLIENT_METHOD_ON_TREE_FELLED = "onTreeFelled"

BuildServiceUtils.ACTION_TYPE_PLACE = "place"
BuildServiceUtils.ACTION_TYPE_BREAK = "break"
BuildServiceUtils.TREE_STATE_ALIVE = "Alive"
BuildServiceUtils.TREE_STATE_FELLED = "Felled"

export type SupportMode = "None" | "Below" | "Cardinal" | "Any"

export type TileRule = {
	id: number,
	name: string,
	assetName: string,
	isSolid: boolean,
	replaceable: boolean,
	requiresSupport: boolean,
	supportMode: SupportMode,
	fallWhenUnsupported: boolean,
	hardness: number,
	breakTime: number,
	requiredToolPower: number,
	unbreakableWithoutTool: boolean,
	multiTileSizeX: number,
	multiTileSizeY: number,
	anchorOffsetX: number,
	anchorOffsetY: number,
}

export type BuildServiceConfig = {
	maxInteractionDistanceTiles: number,
	breakInputTimeout: number,
	breakProgressPushInterval: number,
	breakSupportFloodLimit: number,
	deltaBatchMax: number,
	defaultToolPower: number,
	clientBreakInputRate: number,
	clientPlaceInputRate: number,
	enableDefaultInputBinding: boolean,
}

export type BuildServiceState = {
	ready: boolean,
	tileSize: number,
	chunkSize: number,
	worldOrigin: Vector3,
	basePlaneX: number,
	maxInteractionDistanceTiles: number,
	clientBreakInputRate: number,
	clientPlaceInputRate: number,
	tileRules: { [number]: TileRule },
	updatedAt: number,
}

export type TileCoordinate = {
	tileX: number,
	tileY: number,
}

export type TileDelta = {
	tileX: number,
	tileY: number,
	tileId: number,
	reason: string?,
}

export type TilePlacementResult = {
	canPlace: boolean,
	reason: string,
	footprint: { TileCoordinate },
}

export type PlaceableItemConfig = {
	itemId: string,
	tileId: number,
	consumesOnPlace: boolean,
	animationProfile: string?,
}

export type TreeTileType = "trunk" | "leaf"
export type TreeState = string

export type TreeSnapshot = {
	treeId: string,
	chunkX: number,
	chunkY: number,
	chunkKey: string,
	rootTileX: number,
	rootTileY: number,
	variantIndex: number,
	seed: number,
	biomeType: number?,
	biomeId: number?,
	state: TreeState,
}

export type TreeFootprint = {
	rootTileX: number,
	rootTileY: number,
	heightTiles: number,
	trunkTiles: { TileCoordinate },
	leafTiles: { TileCoordinate },
	allTiles: { TileCoordinate },
	trunkLookup: { [string]: boolean },
	leafLookup: { [string]: boolean },
	maxTileY: number,
}

export type TreeHitResult = {
	tree: TreeSnapshot,
	footprint: TreeFootprint,
	tileType: TreeTileType,
}

export type TreeBreakProfile = {
	maxHealth: number,
	requiredToolType: string,
	requiredToolPower: number,
	breakHits: number,
	breakDuration: number,
	fallDuration: number,
	dropTableId: string,
}

export type TileBreakProfile = {
	requiredToolType: string,
	requiredToolPower: number,
	breakHits: number,
	tileTier: string,
}

export type TreeDropEntry = {
	itemId: string,
	amount: number,
}

export type TreeFelledPayload = {
	treeId: string,
	pivotCFrame: CFrame,
	fallDirection: number,
	height: number,
	seed: number,
	fallDuration: number,
}

local DEFAULT_MAX_INTERACTION_DISTANCE_TILES = 8
local DEFAULT_BREAK_INPUT_TIMEOUT = 0.55
local DEFAULT_BREAK_PROGRESS_PUSH_INTERVAL = 0.08
local DEFAULT_BREAK_SUPPORT_FLOOD_LIMIT = 384
local DEFAULT_TILE_BREAK_HIT_RATE = 8
local DEFAULT_DELTA_BATCH_MAX = 256
local DEFAULT_TOOL_POWER = 40
local DEFAULT_CLIENT_BREAK_INPUT_RATE = 1 / 20
local DEFAULT_CLIENT_PLACE_INPUT_RATE = 1 / 12
local DEFAULT_TREE_SCAN_CHUNK_RADIUS = 1
local DEFAULT_TREE_TRUNK_HEIGHT_MIN = 5
local DEFAULT_TREE_TRUNK_HEIGHT_MAX = 11
local DEFAULT_TREE_CANOPY_RADIUS_MIN = 1
local DEFAULT_TREE_CANOPY_RADIUS_MAX = 3
local DEFAULT_TREE_REQUIRED_TOOL_TYPE = "Axe"
local DEFAULT_TREE_REQUIRED_TOOL_POWER = 0
local TREE_REQUIRE_AXE_FOR_BREAKING = true
local DEFAULT_TILE_REQUIRED_TOOL_TYPE = "Pickaxe"
local TILE_REQUIRE_PICKAXE_FOR_BREAKING = true
local DEFAULT_TREE_BASE_HEALTH = 90
local DEFAULT_TREE_HEALTH_PER_HEIGHT = 22
local DEFAULT_TREE_BREAK_POWER_FLOOR = 7
local DEFAULT_TREE_BREAK_HIT_RATE = 8
local DEFAULT_TREE_FALL_DURATION_MIN = 0.52
local DEFAULT_TREE_FALL_DURATION_MAX = 1.25
local TREE_BIOME_TYPE_NORMAL = 1
local TREE_BIOME_TYPE_CORRUPTION = 2
local TREE_BIOME_ID_FOREST = 1
local TREE_BIOME_ID_JUNGLE = 4

local TREE_DROP_TABLES: {
	[string]: { { itemId: string, minAmount: number, maxAmount: number, chance: number, bonusPerHeight: number } },
} =
	{
		ForestTree = {
			{ itemId = "Wood", minAmount = 3, maxAmount = 6, chance = 1, bonusPerHeight = 0.45 },
			{ itemId = "Acorn", minAmount = 1, maxAmount = 2, chance = 0.55, bonusPerHeight = 0.05 },
		},
		JungleTree = {
			{ itemId = "RichMahogany", minAmount = 4, maxAmount = 7, chance = 1, bonusPerHeight = 0.5 },
			{ itemId = "Vine", minAmount = 1, maxAmount = 2, chance = 0.42, bonusPerHeight = 0.04 },
		},
		CorruptTree = {
			{ itemId = "Ebonwood", minAmount = 4, maxAmount = 7, chance = 1, bonusPerHeight = 0.5 },
		},
		DefaultTree = {
			{ itemId = "Wood", minAmount = 3, maxAmount = 6, chance = 1, bonusPerHeight = 0.4 },
		},
	}

local TILE_ID = {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	SANDSTONE = 5,
	SNOW = 6,
	ICE = 7,
	MUD = 8,
	CLAY = 9,
	COPPER_ORE = 10,
	IRON_ORE = 11,
	SILVER_ORE = 12,
	GOLD_ORE = 13,
	CORRUPT_GRASS = 14,
	CORRUPT_SOIL = 15,
	CORRUPT_STONE = 16,
	JUNGLE_GRASS = 17,
	WOOD = 18,
}

BuildServiceUtils.TILE_ID = TILE_ID
BuildServiceUtils.AIR_TILE_ID = TILE_ID.AIR
BuildServiceUtils.MIN_TILE_ID = TILE_ID.AIR
BuildServiceUtils.MAX_TILE_ID = TILE_ID.WOOD

local TILE_NAME_TO_ID = {
	air = TILE_ID.AIR,
	grass = TILE_ID.GRASS,
	dirt = TILE_ID.DIRT,
	stone = TILE_ID.STONE,
	sand = TILE_ID.SAND,
	sandstone = TILE_ID.SANDSTONE,
	snow = TILE_ID.SNOW,
	ice = TILE_ID.ICE,
	mud = TILE_ID.MUD,
	clay = TILE_ID.CLAY,
	copperore = TILE_ID.COPPER_ORE,
	ironore = TILE_ID.IRON_ORE,
	silverore = TILE_ID.SILVER_ORE,
	goldore = TILE_ID.GOLD_ORE,
	corruptgrass = TILE_ID.CORRUPT_GRASS,
	corruptsoil = TILE_ID.CORRUPT_SOIL,
	corruptstone = TILE_ID.CORRUPT_STONE,
	junglegrass = TILE_ID.JUNGLE_GRASS,
	wood = TILE_ID.WOOD,
	ebonstone = TILE_ID.CORRUPT_STONE,
}

local DEFAULT_TILE_RULE: TileRule = {
	id = TILE_ID.AIR,
	name = "Air",
	assetName = "Air",
	isSolid = false,
	replaceable = true,
	requiresSupport = false,
	supportMode = "None",
	fallWhenUnsupported = false,
	hardness = 0,
	breakTime = 0,
	requiredToolPower = 0,
	unbreakableWithoutTool = false,
	multiTileSizeX = 1,
	multiTileSizeY = 1,
	anchorOffsetX = 0,
	anchorOffsetY = 0,
}

local FIXED_TILE_BREAK_HITS_BY_TILE_ID = {
	[TILE_ID.DIRT] = 2,
	[TILE_ID.STONE] = 3,
}

local TILE_BREAK_DROP_ITEM_BY_TILE_ID = {
	[TILE_ID.DIRT] = "Dirt",
	[TILE_ID.STONE] = "Stone",
	[TILE_ID.SNOW] = "Snow",
	[TILE_ID.ICE] = "Ice",
	[TILE_ID.MUD] = "Mud",
	[TILE_ID.COPPER_ORE] = "CopperOre",
	[TILE_ID.CORRUPT_STONE] = "EbonStone",
	[TILE_ID.WOOD] = "Wood",
}

local TILE_RULE_BY_ID: { [number]: TileRule } = {
	[TILE_ID.AIR] = DEFAULT_TILE_RULE,
	[TILE_ID.GRASS] = {
		id = TILE_ID.GRASS,
		name = "Grass",
		assetName = "Grass",
		isSolid = true,
		replaceable = false,
		requiresSupport = true,
		supportMode = "Below",
		fallWhenUnsupported = true,
		hardness = 0.9,
		breakTime = 0.32,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.DIRT] = {
		id = TILE_ID.DIRT,
		name = "Dirt",
		assetName = "Dirt",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1,
		breakTime = 0.45,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.STONE] = {
		id = TILE_ID.STONE,
		name = "Stone",
		assetName = "Stone",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.4,
		breakTime = 0.9,
		requiredToolPower = 35,
		unbreakableWithoutTool = true,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.SAND] = {
		id = TILE_ID.SAND,
		name = "Sand",
		assetName = "Sand",
		isSolid = true,
		replaceable = false,
		requiresSupport = true,
		supportMode = "Below",
		fallWhenUnsupported = true,
		hardness = 0.8,
		breakTime = 0.32,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.SANDSTONE] = {
		id = TILE_ID.SANDSTONE,
		name = "Sandstone",
		assetName = "Sandstone",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.2,
		breakTime = 0.72,
		requiredToolPower = 20,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.SNOW] = {
		id = TILE_ID.SNOW,
		name = "Snow",
		assetName = "Snow",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 0.9,
		breakTime = 0.38,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.ICE] = {
		id = TILE_ID.ICE,
		name = "Ice",
		assetName = "Ice",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.1,
		breakTime = 0.52,
		requiredToolPower = 15,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.MUD] = {
		id = TILE_ID.MUD,
		name = "Mud",
		assetName = "Mud",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1,
		breakTime = 0.52,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.CLAY] = {
		id = TILE_ID.CLAY,
		name = "Clay",
		assetName = "Clay",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.05,
		breakTime = 0.56,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.COPPER_ORE] = {
		id = TILE_ID.COPPER_ORE,
		name = "CopperOre",
		assetName = "CopperOre",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.3,
		breakTime = 0.85,
		requiredToolPower = 30,
		unbreakableWithoutTool = true,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.IRON_ORE] = {
		id = TILE_ID.IRON_ORE,
		name = "IronOre",
		assetName = "IronOre",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.35,
		breakTime = 0.95,
		requiredToolPower = 40,
		unbreakableWithoutTool = true,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.SILVER_ORE] = {
		id = TILE_ID.SILVER_ORE,
		name = "SilverOre",
		assetName = "SilverOre",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.45,
		breakTime = 1.05,
		requiredToolPower = 45,
		unbreakableWithoutTool = true,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.GOLD_ORE] = {
		id = TILE_ID.GOLD_ORE,
		name = "GoldOre",
		assetName = "GoldOre",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.6,
		breakTime = 1.2,
		requiredToolPower = 55,
		unbreakableWithoutTool = true,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.CORRUPT_GRASS] = {
		id = TILE_ID.CORRUPT_GRASS,
		name = "CorruptGrass",
		assetName = "CorruptGrass",
		isSolid = true,
		replaceable = false,
		requiresSupport = true,
		supportMode = "Below",
		fallWhenUnsupported = true,
		hardness = 1,
		breakTime = 0.36,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.CORRUPT_SOIL] = {
		id = TILE_ID.CORRUPT_SOIL,
		name = "CorruptSoil",
		assetName = "CorruptSoil",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.1,
		breakTime = 0.56,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.CORRUPT_STONE] = {
		id = TILE_ID.CORRUPT_STONE,
		name = "CorruptStone",
		assetName = "CorruptStone",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 1.55,
		breakTime = 1.1,
		requiredToolPower = 45,
		unbreakableWithoutTool = true,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.JUNGLE_GRASS] = {
		id = TILE_ID.JUNGLE_GRASS,
		name = "JungleGrass",
		assetName = "JungleGrass",
		isSolid = true,
		replaceable = false,
		requiresSupport = true,
		supportMode = "Below",
		fallWhenUnsupported = true,
		hardness = 1,
		breakTime = 0.36,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
	[TILE_ID.WOOD] = {
		id = TILE_ID.WOOD,
		name = "Wood",
		assetName = "Wood",
		isSolid = true,
		replaceable = false,
		requiresSupport = false,
		supportMode = "None",
		fallWhenUnsupported = false,
		hardness = 0.95,
		breakTime = 0.4,
		requiredToolPower = 0,
		unbreakableWithoutTool = false,
		multiTileSizeX = 1,
		multiTileSizeY = 1,
		anchorOffsetX = 0,
		anchorOffsetY = 0,
	},
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function coerceString(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end
	if valueRaw == "" then
		return fallback
	end
	return valueRaw
end

local function normalizeToken(valueRaw: any): string
	local value = string.lower(coerceString(valueRaw, ""))
	if value == "" then
		return ""
	end
	return string.gsub(value, "[%s_%-%.]+", "")
end

local function getSeededUnit(seedRaw: any, sampleX: number, sampleY: number, sampleZ: number): number
	local seed = if isFiniteNumber(seedRaw) then seedRaw :: number else 0
	return Noise.ToUnit(
		math.noise(
			(seed + 53.17) * 0.017 + sampleX * 0.239,
			(seed - 21.91) * 0.013 + sampleY * 0.211,
			(seed + 9.73) * 0.009 + sampleZ * 0.197
		)
	)
end

local function coerceInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function coerceNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function cloneTileRule(rule: TileRule): TileRule
	return {
		id = rule.id,
		name = rule.name,
		assetName = rule.assetName,
		isSolid = rule.isSolid,
		replaceable = rule.replaceable,
		requiresSupport = rule.requiresSupport,
		supportMode = rule.supportMode,
		fallWhenUnsupported = rule.fallWhenUnsupported,
		hardness = rule.hardness,
		breakTime = rule.breakTime,
		requiredToolPower = rule.requiredToolPower,
		unbreakableWithoutTool = rule.unbreakableWithoutTool,
		multiTileSizeX = rule.multiTileSizeX,
		multiTileSizeY = rule.multiTileSizeY,
		anchorOffsetX = rule.anchorOffsetX,
		anchorOffsetY = rule.anchorOffsetY,
	}
end

local function getRuleOrDefault(tileIdRaw: any): TileRule
	local tileId = coerceInteger(tileIdRaw, BuildServiceUtils.MIN_TILE_ID, BuildServiceUtils.MAX_TILE_ID, TILE_ID.AIR)
	local rule = TILE_RULE_BY_ID[tileId]
	if rule == nil then
		return DEFAULT_TILE_RULE
	end
	return rule
end

function BuildServiceUtils.CreateDefaultConfig(): BuildServiceConfig
	return {
		maxInteractionDistanceTiles = DEFAULT_MAX_INTERACTION_DISTANCE_TILES,
		breakInputTimeout = DEFAULT_BREAK_INPUT_TIMEOUT,
		breakProgressPushInterval = DEFAULT_BREAK_PROGRESS_PUSH_INTERVAL,
		breakSupportFloodLimit = DEFAULT_BREAK_SUPPORT_FLOOD_LIMIT,
		deltaBatchMax = DEFAULT_DELTA_BATCH_MAX,
		defaultToolPower = DEFAULT_TOOL_POWER,
		clientBreakInputRate = DEFAULT_CLIENT_BREAK_INPUT_RATE,
		clientPlaceInputRate = DEFAULT_CLIENT_PLACE_INPUT_RATE,
		enableDefaultInputBinding = false,
	}
end

function BuildServiceUtils.CoerceConfig(configRaw: any, fallbackRaw: BuildServiceConfig?): BuildServiceConfig
	local fallback = if fallbackRaw ~= nil then fallbackRaw else BuildServiceUtils.CreateDefaultConfig()
	local source = if typeof(configRaw) == "table" then configRaw :: { [string]: any } else {} :: any
	return {
		maxInteractionDistanceTiles = coerceNumber(
			source.maxInteractionDistanceTiles,
			1,
			64,
			fallback.maxInteractionDistanceTiles
		),
		breakInputTimeout = coerceNumber(source.breakInputTimeout, 0.08, 2, fallback.breakInputTimeout),
		breakProgressPushInterval = coerceNumber(
			source.breakProgressPushInterval,
			0.03,
			0.5,
			fallback.breakProgressPushInterval
		),
		breakSupportFloodLimit = coerceInteger(
			source.breakSupportFloodLimit,
			16,
			4096,
			fallback.breakSupportFloodLimit
		),
		deltaBatchMax = coerceInteger(source.deltaBatchMax, 8, 2048, fallback.deltaBatchMax),
		defaultToolPower = coerceNumber(source.defaultToolPower, 0, 1000, fallback.defaultToolPower),
		clientBreakInputRate = coerceNumber(source.clientBreakInputRate, 1 / 120, 1, fallback.clientBreakInputRate),
		clientPlaceInputRate = coerceNumber(source.clientPlaceInputRate, 1 / 120, 1, fallback.clientPlaceInputRate),
		enableDefaultInputBinding = if typeof(source.enableDefaultInputBinding) == "boolean"
			then source.enableDefaultInputBinding
			else fallback.enableDefaultInputBinding,
	}
end

function BuildServiceUtils.CloneTileRules(): { [number]: TileRule }
	local cloned: { [number]: TileRule } = {}
	for tileId, rule in TILE_RULE_BY_ID do
		cloned[tileId] = cloneTileRule(rule)
	end
	return cloned
end

function BuildServiceUtils.CreateDefaultState(): BuildServiceState
	return {
		ready = false,
		tileSize = 2,
		chunkSize = 32,
		worldOrigin = Vector3.zero,
		basePlaneX = 0,
		maxInteractionDistanceTiles = DEFAULT_MAX_INTERACTION_DISTANCE_TILES,
		clientBreakInputRate = DEFAULT_CLIENT_BREAK_INPUT_RATE,
		clientPlaceInputRate = DEFAULT_CLIENT_PLACE_INPUT_RATE,
		tileRules = BuildServiceUtils.CloneTileRules(),
		updatedAt = os.clock(),
	}
end

function BuildServiceUtils.CreateState(stateRaw: any, fallbackRaw: BuildServiceState?): BuildServiceState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else BuildServiceUtils.CreateDefaultState()
	local source = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else {} :: any
	return {
		ready = if typeof(source.ready) == "boolean" then source.ready else fallback.ready,
		tileSize = coerceNumber(source.tileSize, 0.5, 64, fallback.tileSize),
		chunkSize = coerceInteger(source.chunkSize, 4, 256, fallback.chunkSize),
		worldOrigin = if typeof(source.worldOrigin) == "Vector3" then source.worldOrigin else fallback.worldOrigin,
		basePlaneX = coerceNumber(source.basePlaneX, -32768, 32768, fallback.basePlaneX),
		maxInteractionDistanceTiles = coerceNumber(
			source.maxInteractionDistanceTiles,
			1,
			64,
			fallback.maxInteractionDistanceTiles
		),
		clientBreakInputRate = coerceNumber(source.clientBreakInputRate, 1 / 120, 1, fallback.clientBreakInputRate),
		clientPlaceInputRate = coerceNumber(source.clientPlaceInputRate, 1 / 120, 1, fallback.clientPlaceInputRate),
		tileRules = BuildServiceUtils.CloneTileRules(),
		updatedAt = os.clock(),
	}
end

function BuildServiceUtils.CloneState(state: BuildServiceState): BuildServiceState
	return {
		ready = state.ready,
		tileSize = state.tileSize,
		chunkSize = state.chunkSize,
		worldOrigin = state.worldOrigin,
		basePlaneX = state.basePlaneX,
		maxInteractionDistanceTiles = state.maxInteractionDistanceTiles,
		clientBreakInputRate = state.clientBreakInputRate,
		clientPlaceInputRate = state.clientPlaceInputRate,
		tileRules = BuildServiceUtils.CloneTileRules(),
		updatedAt = state.updatedAt,
	}
end

function BuildServiceUtils.CoerceRequestId(valueRaw: any): number
	return coerceInteger(valueRaw, 0, 2147483647, 0)
end

function BuildServiceUtils.CoerceTileCoordinate(valueRaw: any): number?
	if not isFiniteNumber(valueRaw) then
		return nil
	end
	return math.floor(valueRaw)
end

function BuildServiceUtils.CoerceTileId(valueRaw: any): number?
	if not isFiniteNumber(valueRaw) then
		return nil
	end
	local tileId = math.floor(valueRaw)
	if tileId < BuildServiceUtils.MIN_TILE_ID or tileId > BuildServiceUtils.MAX_TILE_ID then
		return nil
	end
	return tileId
end

function BuildServiceUtils.CoerceBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

function BuildServiceUtils.PackTileKey(tileX: number, tileY: number): string
	return `{tileX}:{tileY}`
end

function BuildServiceUtils.UnpackTileKey(tileKeyRaw: any): (number?, number?)
	if typeof(tileKeyRaw) ~= "string" then
		return nil, nil
	end
	local xRaw, yRaw = string.match(tileKeyRaw, "^(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil then
		return nil, nil
	end
	local tileX = tonumber(xRaw)
	local tileY = tonumber(yRaw)
	if tileX == nil or tileY == nil then
		return nil, nil
	end
	return tileX, tileY
end

function BuildServiceUtils.PackChunkKey(chunkX: number, chunkY: number): string
	return `{chunkX}:{chunkY}`
end

function BuildServiceUtils.UnpackChunkKey(chunkKeyRaw: any): (number?, number?)
	if typeof(chunkKeyRaw) ~= "string" then
		return nil, nil
	end
	local xRaw, yRaw = string.match(chunkKeyRaw, "^(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil then
		return nil, nil
	end
	local chunkX = tonumber(xRaw)
	local chunkY = tonumber(yRaw)
	if chunkX == nil or chunkY == nil then
		return nil, nil
	end
	return chunkX, chunkY
end

function BuildServiceUtils.ToTileCoordinate(worldAxis: number, tileSize: number): number
	return math.floor(worldAxis / tileSize)
end

function BuildServiceUtils.ToChunkCoordinate(tileAxis: number, chunkSize: number): number
	return math.floor(tileAxis / chunkSize)
end

function BuildServiceUtils.ComputeTileIndex(localX: number, localY: number, width: number): number
	return localY * width + localX + 1
end

function BuildServiceUtils.ComputeTreeId(rootTileXRaw: any, rootTileYRaw: any, seedRaw: any): string
	local rootTileX = BuildServiceUtils.CoerceTileCoordinate(rootTileXRaw) or 0
	local rootTileY = BuildServiceUtils.CoerceTileCoordinate(rootTileYRaw) or 0
	local seed = coerceInteger(seedRaw, -2147483648, 2147483647, 0)
	return `tree:{rootTileX}:{rootTileY}:{seed}`
end

function BuildServiceUtils.GetTreeHealthPoolKey(treeIdRaw: any): string
	return coerceString(treeIdRaw, "")
end

function BuildServiceUtils.CreateTreeSnapshot(chunkXRaw: any, chunkYRaw: any, treeRaw: any): TreeSnapshot?
	if typeof(treeRaw) ~= "table" then
		return nil
	end
	local chunkX = BuildServiceUtils.CoerceTileCoordinate(chunkXRaw)
	local chunkY = BuildServiceUtils.CoerceTileCoordinate(chunkYRaw)
	if chunkX == nil or chunkY == nil then
		return nil
	end

	local source = treeRaw :: { [string]: any }
	local rootTileX = BuildServiceUtils.CoerceTileCoordinate(source.tileX)
	local rootTileY = BuildServiceUtils.CoerceTileCoordinate(source.tileY)
	if rootTileX == nil or rootTileY == nil then
		return nil
	end

	local variantIndex = coerceInteger(source.variantIndex, 1, 128, coerceInteger(source.templateIndex, 1, 128, 1))
	local seed = coerceInteger(
		source.seed,
		-2147483648,
		2147483647,
		rootTileX * 92821 + rootTileY * 68917 + variantIndex * 193 + 1337
	)
	local state = if source.state == "Felled" then "Felled" else "Alive"
	local treeId = BuildServiceUtils.ComputeTreeId(rootTileX, rootTileY, seed)
	return {
		treeId = treeId,
		chunkX = chunkX,
		chunkY = chunkY,
		chunkKey = BuildServiceUtils.PackChunkKey(chunkX, chunkY),
		rootTileX = rootTileX,
		rootTileY = rootTileY,
		variantIndex = variantIndex,
		seed = seed,
		biomeType = if isFiniteNumber(source.biomeType) then math.floor(source.biomeType) else nil,
		biomeId = if isFiniteNumber(source.biomeId) then math.floor(source.biomeId) else nil,
		state = state,
	}
end

function BuildServiceUtils.GetTreeRootAtTile(
	tileXRaw: any,
	tileYRaw: any,
	chunkSizeRaw: any,
	getTreesForChunk: (chunkX: number, chunkY: number) -> { any }?
): TreeSnapshot?
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil or typeof(getTreesForChunk) ~= "function" then
		return nil
	end

	local chunkSize = coerceInteger(chunkSizeRaw, 4, 256, 32)
	local chunkX = BuildServiceUtils.ToChunkCoordinate(tileX, chunkSize)
	local chunkY = BuildServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	local trees = getTreesForChunk(chunkX, chunkY)
	if typeof(trees) ~= "table" then
		return nil
	end

	return Table.reduce(trees :: any, function(found: TreeSnapshot?, treeRaw: any): TreeSnapshot?
		if found ~= nil then
			return found
		end
		local tree = BuildServiceUtils.CreateTreeSnapshot(chunkX, chunkY, treeRaw)
		if tree ~= nil and tree.rootTileX == tileX and tree.rootTileY == tileY then
			return tree
		end
		return nil
	end, nil :: TreeSnapshot?)
end

function BuildServiceUtils.GetTreeTrunkHeight(treeRaw: any): number
	local source = if typeof(treeRaw) == "table" then treeRaw :: { [string]: any } else {} :: any
	local seed = coerceInteger(source.seed, -2147483648, 2147483647, 0)
	return Height.GetHeightTiles(seed, DEFAULT_TREE_TRUNK_HEIGHT_MIN, DEFAULT_TREE_TRUNK_HEIGHT_MAX)
end

function BuildServiceUtils.GetTreeCanopyRadius(treeRaw: any): number
	local source = if typeof(treeRaw) == "table" then treeRaw :: { [string]: any } else {} :: any
	local seed = coerceInteger(source.seed, -2147483648, 2147483647, 0)
	local variantIndex = coerceInteger(source.variantIndex, 1, 128, 1)
	local biomeType = coerceInteger(source.biomeType, TREE_BIOME_TYPE_NORMAL, 32, TREE_BIOME_TYPE_NORMAL)
	local alpha = getSeededUnit(seed, variantIndex, biomeType, 2)
	local rawRadius = DEFAULT_TREE_CANOPY_RADIUS_MIN
		+ math.floor(alpha * (DEFAULT_TREE_CANOPY_RADIUS_MAX - DEFAULT_TREE_CANOPY_RADIUS_MIN) + 0.5)
	return math.clamp(rawRadius, DEFAULT_TREE_CANOPY_RADIUS_MIN, DEFAULT_TREE_CANOPY_RADIUS_MAX)
end

function BuildServiceUtils.FloodTreeFootprint(treeRaw: any): TreeFootprint
	local source = if typeof(treeRaw) == "table" then treeRaw :: { [string]: any } else {} :: any
	local rootTileX = BuildServiceUtils.CoerceTileCoordinate(source.rootTileX or source.tileX) or 0
	local rootTileY = BuildServiceUtils.CoerceTileCoordinate(source.rootTileY or source.tileY) or 0
	local trunkHeight = BuildServiceUtils.GetTreeTrunkHeight(source)
	local canopyRadius = BuildServiceUtils.GetTreeCanopyRadius(source)

	local trunkTiles: { TileCoordinate } = {}
	local leafTiles: { TileCoordinate } = {}
	local allTiles: { TileCoordinate } = {}
	local trunkLookup: { [string]: boolean } = {}
	local leafLookup: { [string]: boolean } = {}
	local allLookup: { [string]: boolean } = {}
	local maxTileY = rootTileY

	local function pushTile(lookup: { [string]: boolean }, list: { TileCoordinate }, tileX: number, tileY: number)
		local tileKey = BuildServiceUtils.PackTileKey(tileX, tileY)
		if lookup[tileKey] then
			return
		end
		lookup[tileKey] = true
		list[#list + 1] = {
			tileX = tileX,
			tileY = tileY,
		}
		if not allLookup[tileKey] then
			allLookup[tileKey] = true
			allTiles[#allTiles + 1] = {
				tileX = tileX,
				tileY = tileY,
			}
			maxTileY = math.max(maxTileY, tileY)
		end
	end

	for offsetY = 1, trunkHeight do
		pushTile(trunkLookup, trunkTiles, rootTileX, rootTileY + offsetY)
	end

	local canopyCenterY = rootTileY + trunkHeight + 1
	local queue: { { tileX: number, tileY: number, depth: number } } = {
		{
			tileX = rootTileX,
			tileY = canopyCenterY,
			depth = 0,
		},
	}
	local queueHead = 1
	local visited: { [string]: boolean } = {}
	while queueHead <= #queue do
		local node = queue[queueHead]
		queueHead += 1

		local visitedKey = BuildServiceUtils.PackTileKey(node.tileX, node.tileY)
		if visited[visitedKey] then
			continue
		end
		visited[visitedKey] = true

		local deltaX = math.abs(node.tileX - rootTileX)
		local deltaY = math.abs(node.tileY - canopyCenterY)
		if deltaX + deltaY > canopyRadius + 1 then
			continue
		end

		pushTile(leafLookup, leafTiles, node.tileX, node.tileY)
		if node.depth >= canopyRadius then
			continue
		end

		queue[#queue + 1] = { tileX = node.tileX + 1, tileY = node.tileY, depth = node.depth + 1 }
		queue[#queue + 1] = { tileX = node.tileX - 1, tileY = node.tileY, depth = node.depth + 1 }
		queue[#queue + 1] = { tileX = node.tileX, tileY = node.tileY + 1, depth = node.depth + 1 }
		queue[#queue + 1] = { tileX = node.tileX, tileY = node.tileY - 1, depth = node.depth + 1 }
	end

	for offsetX = -canopyRadius, canopyRadius do
		local span = math.max(0, canopyRadius - math.abs(offsetX))
		pushTile(leafLookup, leafTiles, rootTileX + offsetX, canopyCenterY + span)
		if span > 0 then
			pushTile(leafLookup, leafTiles, rootTileX + offsetX, canopyCenterY - span)
		end
	end

	return {
		rootTileX = rootTileX,
		rootTileY = rootTileY,
		heightTiles = math.max(1, maxTileY - rootTileY),
		trunkTiles = trunkTiles,
		leafTiles = leafTiles,
		allTiles = allTiles,
		trunkLookup = trunkLookup,
		leafLookup = leafLookup,
		maxTileY = maxTileY,
	}
end

function BuildServiceUtils.ClassifyTreeFootprintTile(footprintRaw: any, tileXRaw: any, tileYRaw: any): TreeTileType?
	if typeof(footprintRaw) ~= "table" then
		return nil
	end
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return nil
	end

	local footprint = footprintRaw :: TreeFootprint
	local tileKey = BuildServiceUtils.PackTileKey(tileX, tileY)
	if footprint.trunkLookup[tileKey] then
		return "trunk"
	end
	if footprint.leafLookup[tileKey] then
		return "leaf"
	end
	return nil
end

function BuildServiceUtils.GetTreeAtTile(
	tileXRaw: any,
	tileYRaw: any,
	chunkSizeRaw: any,
	getTreesForChunk: (chunkX: number, chunkY: number) -> { any }?
): TreeHitResult?
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return nil
	end
	if typeof(getTreesForChunk) ~= "function" then
		return nil
	end

	local chunkSize = coerceInteger(chunkSizeRaw, 4, 256, 32)
	local centerChunkX = BuildServiceUtils.ToChunkCoordinate(tileX, chunkSize)
	local centerChunkY = BuildServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	local bestScore = math.huge
	local bestHit: TreeHitResult? = nil

	for chunkOffsetY = -DEFAULT_TREE_SCAN_CHUNK_RADIUS, DEFAULT_TREE_SCAN_CHUNK_RADIUS do
		for chunkOffsetX = -DEFAULT_TREE_SCAN_CHUNK_RADIUS, DEFAULT_TREE_SCAN_CHUNK_RADIUS do
			local scanChunkX = centerChunkX + chunkOffsetX
			local scanChunkY = centerChunkY + chunkOffsetY
			local trees = getTreesForChunk(scanChunkX, scanChunkY)
			if typeof(trees) ~= "table" then
				continue
			end

			for _, treeRaw in trees do
				local tree = BuildServiceUtils.CreateTreeSnapshot(scanChunkX, scanChunkY, treeRaw)
				if tree == nil then
					continue
				end
				local footprint = BuildServiceUtils.FloodTreeFootprint(tree)
				local tileType = BuildServiceUtils.ClassifyTreeFootprintTile(footprint, tileX, tileY)
				if tileType == nil then
					continue
				end

				local score = BuildServiceUtils.TileDistance(tileX, tileY, tree.rootTileX, tree.rootTileY)
					+ (if tileType == "trunk" then 0 else 0.25)
				if score >= bestScore then
					continue
				end

				bestScore = score
				bestHit = {
					tree = tree,
					footprint = footprint,
					tileType = tileType :: any,
				}
			end
		end
	end

	return bestHit
end

function BuildServiceUtils.GetTreeDropTableId(treeRaw: any): string
	local source = if typeof(treeRaw) == "table" then treeRaw :: { [string]: any } else {} :: any
	local biomeType = if isFiniteNumber(source.biomeType) then math.floor(source.biomeType) else TREE_BIOME_TYPE_NORMAL
	local biomeId = if isFiniteNumber(source.biomeId) then math.floor(source.biomeId) else TREE_BIOME_ID_FOREST
	if biomeType == TREE_BIOME_TYPE_CORRUPTION then
		return "CorruptTree"
	end
	if biomeId == TREE_BIOME_ID_JUNGLE then
		return "JungleTree"
	end
	if biomeId == TREE_BIOME_ID_FOREST then
		return "ForestTree"
	end
	return "DefaultTree"
end

function BuildServiceUtils.GetTreeFallDuration(heightTilesRaw: any): number
	local heightTiles = coerceInteger(heightTilesRaw, DEFAULT_TREE_TRUNK_HEIGHT_MIN, 128, DEFAULT_TREE_TRUNK_HEIGHT_MIN)
	local alpha = math.clamp(
		(heightTiles - DEFAULT_TREE_TRUNK_HEIGHT_MIN) / (DEFAULT_TREE_TRUNK_HEIGHT_MAX - DEFAULT_TREE_TRUNK_HEIGHT_MIN),
		0,
		1
	)
	return DEFAULT_TREE_FALL_DURATION_MIN + (DEFAULT_TREE_FALL_DURATION_MAX - DEFAULT_TREE_FALL_DURATION_MIN) * alpha
end

function BuildServiceUtils.GetTreeBreakProfile(treeRaw: any, toolPowerRaw: any): TreeBreakProfile
	local source = if typeof(treeRaw) == "table" then treeRaw :: { [string]: any } else {} :: any
	local heightTiles = if isFiniteNumber(source.heightTiles)
		then coerceInteger(source.heightTiles, 1, 128, DEFAULT_TREE_TRUNK_HEIGHT_MIN)
		else BuildServiceUtils.GetTreeTrunkHeight(source) + 1
	local dropTableId = BuildServiceUtils.GetTreeDropTableId(source)
	local treeRequirement = MiningPower.GetTreeRequirement(dropTableId)
	local maxHealth = DEFAULT_TREE_BASE_HEALTH + heightTiles * DEFAULT_TREE_HEALTH_PER_HEIGHT
	local toolPower = coerceNumber(toolPowerRaw, 0, 100000, 0)
	local effectivePower = math.max(DEFAULT_TREE_BREAK_POWER_FLOOR, toolPower)
	local breakDuration = math.max(0.35, maxHealth / (effectivePower * 6))
	local breakHits = math.max(1, math.ceil(breakDuration * DEFAULT_TREE_BREAK_HIT_RATE))
	return {
		maxHealth = maxHealth,
		requiredToolType = treeRequirement.requiredToolType or string.lower(DEFAULT_TREE_REQUIRED_TOOL_TYPE),
		requiredToolPower = treeRequirement.requiredToolPower or DEFAULT_TREE_REQUIRED_TOOL_POWER,
		breakHits = breakHits,
		breakDuration = breakDuration,
		fallDuration = BuildServiceUtils.GetTreeFallDuration(heightTiles),
		dropTableId = dropTableId,
	}
end

function BuildServiceUtils.CanBreakTree(
	treeRaw: any,
	toolTypeRaw: any,
	toolPowerRaw: any
): (boolean, string, number, TreeBreakProfile)
	local profile = BuildServiceUtils.GetTreeBreakProfile(treeRaw, toolPowerRaw)
	local toolType = string.lower(coerceString(toolTypeRaw, ""))
	local toolPower = coerceNumber(toolPowerRaw, 0, 100000, 0)
	local requiredToolType = string.lower(coerceString(profile.requiredToolType, DEFAULT_TREE_REQUIRED_TOOL_TYPE))
	if TREE_REQUIRE_AXE_FOR_BREAKING and requiredToolType == "axe" and string.find(toolType, "axe", 1, true) == nil then
		return false, "tree_requires_axe", math.huge, profile
	end
	if toolPower < profile.requiredToolPower then
		return false, "insufficient_axe_power", math.huge, profile
	end
	return true, "ok", profile.breakHits, profile
end

function BuildServiceUtils.NormalizeFallDirection(directionRaw: any): number
	if isFiniteNumber(directionRaw) then
		local signed = math.sign(directionRaw :: number)
		if signed ~= 0 then
			return signed
		end
	elseif typeof(directionRaw) == "string" then
		local token = string.lower(directionRaw)
		if token == "left" or token == "-1" then
			return -1
		end
		if token == "right" or token == "1" then
			return 1
		end
	end
	return 1
end

function BuildServiceUtils.ComputeTreeFallDirection(
	rootTileXRaw: any,
	playerTileXRaw: any,
	preferredDirectionRaw: any?
): number
	local preferredDirection = BuildServiceUtils.NormalizeFallDirection(preferredDirectionRaw)
	if isFiniteNumber(preferredDirectionRaw) and math.sign(preferredDirectionRaw :: number) ~= 0 then
		return preferredDirection
	end
	if typeof(preferredDirectionRaw) == "string" and preferredDirectionRaw ~= "" then
		return preferredDirection
	end

	local rootTileX = BuildServiceUtils.CoerceTileCoordinate(rootTileXRaw) or 0
	local playerTileX = BuildServiceUtils.CoerceTileCoordinate(playerTileXRaw) or rootTileX
	if playerTileX > rootTileX then
		return -1
	end
	if playerTileX < rootTileX then
		return 1
	end
	return 1
end

function BuildServiceUtils.ComputeTreeFallVector2D(fallDirectionRaw: any): Vector3
	local direction = BuildServiceUtils.NormalizeFallDirection(fallDirectionRaw)
	return Vector3.new(0, 0, direction)
end

function BuildServiceUtils.ComputeTreePivotOffset(heightTilesRaw: any, tileSizeRaw: any): Vector3
	local heightTiles = coerceInteger(heightTilesRaw, 1, 128, DEFAULT_TREE_TRUNK_HEIGHT_MIN)
	local tileSize = coerceNumber(tileSizeRaw, 0.05, 64, 2)
	return Vector3.new(0, math.max(tileSize * 0.5, heightTiles * tileSize * 0.45), 0)
end

function BuildServiceUtils.ComputeTreePivotCFrame(
	rootTileXRaw: any,
	rootTileYRaw: any,
	worldOriginRaw: any,
	tileSizeRaw: any,
	basePlaneXRaw: any
): CFrame
	local rootTileX = BuildServiceUtils.CoerceTileCoordinate(rootTileXRaw) or 0
	local rootTileY = BuildServiceUtils.CoerceTileCoordinate(rootTileYRaw) or 0
	local worldOrigin = if typeof(worldOriginRaw) == "Vector3" then worldOriginRaw else Vector3.zero
	local tileSize = coerceNumber(tileSizeRaw, 0.05, 64, 2)
	local basePlaneX = coerceNumber(basePlaneXRaw, -32768, 32768, 0)
	local pivotPosition =
		BuildServiceUtils.TileToWorldCenter(rootTileX, rootTileY + 1, worldOrigin, tileSize, basePlaneX)
	return CFrame.new(pivotPosition)
end

function BuildServiceUtils.ComputeTreeImpactPosition(
	pivotCFrameRaw: any,
	fallDirectionRaw: any,
	heightTilesRaw: any,
	tileSizeRaw: any
): Vector3
	local pivotCFrame = if typeof(pivotCFrameRaw) == "CFrame" then pivotCFrameRaw else CFrame.new()
	local direction = BuildServiceUtils.NormalizeFallDirection(fallDirectionRaw)
	local heightTiles = coerceInteger(heightTilesRaw, 1, 128, DEFAULT_TREE_TRUNK_HEIGHT_MIN)
	local tileSize = coerceNumber(tileSizeRaw, 0.05, 64, 2)
	local horizontalDistance = math.max(tileSize * 1.1, heightTiles * tileSize * 0.65)
	local impactOffset = BuildServiceUtils.ComputeTreeFallVector2D(direction) * horizontalDistance
	return pivotCFrame.Position + impactOffset + Vector3.new(0, -tileSize * 0.12, 0)
end

function BuildServiceUtils.RollTreeDrops(treeRaw: any): { TreeDropEntry }
	local source = if typeof(treeRaw) == "table" then treeRaw :: { [string]: any } else {} :: any
	local dropTableId = BuildServiceUtils.GetTreeDropTableId(source)
	local dropTable = TREE_DROP_TABLES[dropTableId]
	if dropTable == nil then
		dropTable = TREE_DROP_TABLES.DefaultTree
	end

	local heightTiles = if isFiniteNumber(source.heightTiles)
		then coerceInteger(source.heightTiles, 1, 128, DEFAULT_TREE_TRUNK_HEIGHT_MIN)
		else BuildServiceUtils.GetTreeTrunkHeight(source) + 1
	local seed = coerceInteger(source.seed, -2147483648, 2147483647, 0)
	local random = Random.new(seed + heightTiles * 157 + #dropTable * 41)
	local drops: { TreeDropEntry } = {}

	for _, entry in dropTable do
		local chance = math.clamp(entry.chance + heightTiles * entry.bonusPerHeight * 0.01, 0, 1)
		if random:NextNumber() > chance then
			continue
		end
		local minAmount = math.max(1, math.floor(entry.minAmount + heightTiles * entry.bonusPerHeight * 0.35))
		local maxAmount = math.max(minAmount, math.floor(entry.maxAmount + heightTiles * entry.bonusPerHeight * 0.45))
		local amount = random:NextInteger(minAmount, maxAmount)
		if amount <= 0 then
			continue
		end
		drops[#drops + 1] = {
			itemId = entry.itemId,
			amount = amount,
		}
	end

	if #drops <= 0 and #dropTable > 0 then
		local fallback = dropTable[1]
		drops[1] = {
			itemId = fallback.itemId,
			amount = math.max(1, fallback.minAmount),
		}
	end

	return drops
end

function BuildServiceUtils.CoerceTreeFelledPayload(payloadRaw: any): TreeFelledPayload?
	if typeof(payloadRaw) ~= "table" then
		return nil
	end
	local source = payloadRaw :: { [string]: any }
	if typeof(source.pivotCFrame) ~= "CFrame" then
		return nil
	end
	local treeId = coerceString(source.treeId, "")
	if treeId == "" then
		return nil
	end

	local height = coerceInteger(source.height, 1, 128, DEFAULT_TREE_TRUNK_HEIGHT_MIN)
	local fallDuration = coerceNumber(
		source.fallDuration,
		DEFAULT_TREE_FALL_DURATION_MIN,
		DEFAULT_TREE_FALL_DURATION_MAX,
		BuildServiceUtils.GetTreeFallDuration(height)
	)
	return {
		treeId = treeId,
		pivotCFrame = source.pivotCFrame,
		fallDirection = BuildServiceUtils.NormalizeFallDirection(source.fallDirection),
		height = height,
		seed = coerceInteger(source.seed, -2147483648, 2147483647, 0),
		fallDuration = fallDuration,
	}
end

function BuildServiceUtils.GetTileIdFromAlias(tileIdRaw: any): number?
	local numericTileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if numericTileId ~= nil then
		return numericTileId
	end

	local normalized = normalizeToken(tileIdRaw)
	if normalized == "" then
		return nil
	end

	return TILE_NAME_TO_ID[normalized]
end

function BuildServiceUtils.GetTileBreakDropItemId(tileIdRaw: any): string?
	local tileId = BuildServiceUtils.GetTileIdFromAlias(tileIdRaw)
	if tileId == nil then
		return nil
	end
	return TILE_BREAK_DROP_ITEM_BY_TILE_ID[tileId]
end

function BuildServiceUtils.GetPlaceableItemConfig(itemIdRaw: any): PlaceableItemConfig?
	local canonicalItemId = ItemRegistry.GetCanonicalItemId(itemIdRaw)
	if canonicalItemId == nil then
		return nil
	end

	local definition = ItemRegistry.GetDefinition(canonicalItemId)
	if typeof(definition) ~= "table" then
		return nil
	end

	local definitionTable = definition :: { [string]: any }
	local placement = if typeof(definitionTable.build) == "table"
		then definitionTable.build :: { [string]: any }
		else if typeof(definitionTable.placement) == "table"
			then definitionTable.placement :: { [string]: any }
			else {} :: any
	local tileId = BuildServiceUtils.GetTileIdFromAlias(
		placement.tileId
			or placement.buildTileId
			or placement.placedTileId
			or definitionTable.buildTileId
			or definitionTable.placedTileId
	)

	if tileId == nil then
		local itemType = normalizeToken(definitionTable.itemType or definitionTable.type)
		local functionality = string.lower(coerceString(definitionTable.functionality, ""))
		local useCase = string.lower(coerceString(definitionTable.useCase, ""))
		local looksPlaceable = itemType == "tile"
			or string.find(functionality, "placed", 1, true) ~= nil
			or string.find(useCase, "place", 1, true) ~= nil
		if looksPlaceable then
			tileId = BuildServiceUtils.GetTileIdFromAlias(canonicalItemId)
				or BuildServiceUtils.GetTileIdFromAlias(definitionTable.name)
		end
	end

	if tileId == nil or tileId == BuildServiceUtils.AIR_TILE_ID then
		return nil
	end

	local animationProfile =
		coerceString(placement.animationProfile or placement.animationName or definitionTable.animationProfile, "")
	return {
		itemId = canonicalItemId,
		tileId = tileId,
		consumesOnPlace = if typeof(placement.consumesOnPlace) == "boolean" then placement.consumesOnPlace else true,
		animationProfile = if animationProfile ~= "" then animationProfile else nil,
	}
end

function BuildServiceUtils.WorldPositionToTile(
	worldPosition: Vector3,
	worldOrigin: Vector3,
	tileSize: number
): (number, number)
	local tileX = BuildServiceUtils.ToTileCoordinate(worldPosition.Z - worldOrigin.Z, tileSize)
	local tileY = BuildServiceUtils.ToTileCoordinate(worldPosition.Y - worldOrigin.Y, tileSize)
	return tileX, tileY
end

function BuildServiceUtils.TileToWorldCenter(
	tileX: number,
	tileY: number,
	worldOrigin: Vector3,
	tileSize: number,
	basePlaneX: number
): Vector3
	return Vector3.new(basePlaneX, worldOrigin.Y + (tileY + 0.5) * tileSize, worldOrigin.Z + (tileX + 0.5) * tileSize)
end

function BuildServiceUtils.WorldDistance2D(a: Vector3, b: Vector3): number
	local dz = a.Z - b.Z
	local dy = a.Y - b.Y
	return math.sqrt(dz * dz + dy * dy)
end

function BuildServiceUtils.TileDistance(tileAX: number, tileAY: number, tileBX: number, tileBY: number): number
	local dx = tileAX - tileBX
	local dy = tileAY - tileBY
	return math.sqrt(dx * dx + dy * dy)
end

function BuildServiceUtils.GetCardinalNeighbors(tileX: number, tileY: number): { TileCoordinate }
	return {
		{ tileX = tileX + 1, tileY = tileY },
		{ tileX = tileX - 1, tileY = tileY },
		{ tileX = tileX, tileY = tileY + 1 },
		{ tileX = tileX, tileY = tileY - 1 },
	}
end

function BuildServiceUtils.TraceGridLine2D(
	startTileXRaw: any,
	startTileYRaw: any,
	endTileXRaw: any,
	endTileYRaw: any,
	maxStepsRaw: any?
): { TileCoordinate }
	local startTileX = BuildServiceUtils.CoerceTileCoordinate(startTileXRaw)
	local startTileY = BuildServiceUtils.CoerceTileCoordinate(startTileYRaw)
	local endTileX = BuildServiceUtils.CoerceTileCoordinate(endTileXRaw)
	local endTileY = BuildServiceUtils.CoerceTileCoordinate(endTileYRaw)
	if startTileX == nil or startTileY == nil or endTileX == nil or endTileY == nil then
		return {}
	end

	local maxSteps = coerceInteger(maxStepsRaw, 1, 8192, 1024)
	local output: { TileCoordinate } = {}

	local x = startTileX
	local y = startTileY
	local dx = math.abs(endTileX - startTileX)
	local dy = math.abs(endTileY - startTileY)
	local stepX = if startTileX < endTileX then 1 else -1
	local stepY = if startTileY < endTileY then 1 else -1
	local errorTerm = dx - dy
	local steps = 0

	while steps < maxSteps do
		output[#output + 1] = {
			tileX = x,
			tileY = y,
		}
		steps += 1
		if x == endTileX and y == endTileY then
			break
		end
		local doubledError = errorTerm * 2
		if doubledError > -dy then
			errorTerm -= dy
			x += stepX
		end
		if doubledError < dx then
			errorTerm += dx
			y += stepY
		end
	end

	return output
end

function BuildServiceUtils.RaycastToBuildPlane(origin: Vector3, direction: Vector3, basePlaneX: number): Vector3?
	if Vec.IsNearlyZero(direction) then
		return nil
	end

	local plane = Plane.FromPointNormal(Vector3.new(basePlaneX, 0, 0), Vector3.xAxis)
	local hit = Plane.Raycast(plane, origin, direction)
	if hit == nil then
		return nil
	end
	return hit.point
end

function BuildServiceUtils.TraceTilesFromWorldRay2D(
	origin: Vector3,
	direction: Vector3,
	maxDistanceRaw: any,
	worldOrigin: Vector3,
	tileSize: number,
	basePlaneX: number
): { TileCoordinate }
	local maxDistance = coerceNumber(maxDistanceRaw, 0.5, 10000, 256)
	local unitDirection = Vec.Unit(direction, Vector3.xAxis)
	local startPoint = BuildServiceUtils.RaycastToBuildPlane(origin, unitDirection, basePlaneX)
	if startPoint == nil then
		return {}
	end
	local endPoint3D = startPoint + unitDirection * maxDistance
	local startTileX, startTileY = BuildServiceUtils.WorldPositionToTile(startPoint, worldOrigin, tileSize)
	local endTileX, endTileY = BuildServiceUtils.WorldPositionToTile(endPoint3D, worldOrigin, tileSize)
	return BuildServiceUtils.TraceGridLine2D(startTileX, startTileY, endTileX, endTileY, 1024)
end

function BuildServiceUtils.GetTileRule(tileIdRaw: any): TileRule
	return cloneTileRule(getRuleOrDefault(tileIdRaw))
end

function BuildServiceUtils.GetTileAssetName(tileIdRaw: any): string
	return getRuleOrDefault(tileIdRaw).assetName
end

function BuildServiceUtils.IsSolidTile(tileIdRaw: any): boolean
	return getRuleOrDefault(tileIdRaw).isSolid
end

function BuildServiceUtils.IsReplaceableTile(tileIdRaw: any): boolean
	return getRuleOrDefault(tileIdRaw).replaceable
end

function BuildServiceUtils.ComputePlacementFootprint(tileX: number, tileY: number, tileRuleRaw: any): { TileCoordinate }
	local tileRule = if typeof(tileRuleRaw) == "table" then tileRuleRaw :: TileRule else getRuleOrDefault(TILE_ID.AIR)
	local originX = tileX - tileRule.anchorOffsetX
	local originY = tileY - tileRule.anchorOffsetY
	local footprint: { TileCoordinate } = {}

	for offsetY = 0, tileRule.multiTileSizeY - 1 do
		for offsetX = 0, tileRule.multiTileSizeX - 1 do
			footprint[#footprint + 1] = {
				tileX = originX + offsetX,
				tileY = originY + offsetY,
			}
		end
	end

	return footprint
end

function BuildServiceUtils.HasSupportAt(
	tileX: number,
	tileY: number,
	supportModeRaw: any,
	getTileAt: (tileX: number, tileY: number) -> number
): boolean
	local supportMode = if supportModeRaw == "Below"
			or supportModeRaw == "Cardinal"
			or supportModeRaw == "Any"
			or supportModeRaw == "None"
		then supportModeRaw
		else "None"
	if supportMode == "None" then
		return true
	end

	local belowTileId = getTileAt(tileX, tileY - 1)
	local hasBelowSupport = BuildServiceUtils.IsSolidTile(belowTileId)
	if supportMode == "Below" then
		return hasBelowSupport
	end

	local leftTileId = getTileAt(tileX - 1, tileY)
	local rightTileId = getTileAt(tileX + 1, tileY)
	local topTileId = getTileAt(tileX, tileY + 1)
	local hasCardinalSupport = BuildServiceUtils.IsSolidTile(leftTileId)
		or BuildServiceUtils.IsSolidTile(rightTileId)
		or BuildServiceUtils.IsSolidTile(topTileId)
		or hasBelowSupport

	if supportMode == "Cardinal" then
		return hasCardinalSupport
	end

	return hasBelowSupport or hasCardinalSupport
end

function BuildServiceUtils.CanPlaceAt(
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any,
	getTileAt: (tileX: number, tileY: number) -> number,
	minTileYRaw: any?,
	maxTileYRaw: any?
): TilePlacementResult
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileX == nil or tileY == nil or tileId == nil then
		return {
			canPlace = false,
			reason = "invalid_tile_coordinate_or_id",
			footprint = {},
		}
	end

	if tileId == TILE_ID.AIR then
		return {
			canPlace = false,
			reason = "cannot_place_air",
			footprint = {},
		}
	end

	local minTileY = if isFiniteNumber(minTileYRaw) then math.floor(minTileYRaw :: number) else -65536
	local maxTileY = if isFiniteNumber(maxTileYRaw) then math.floor(maxTileYRaw :: number) else 65536
	if tileY < minTileY or tileY > maxTileY then
		return {
			canPlace = false,
			reason = "tile_out_of_bounds",
			footprint = {},
		}
	end

	local rule = getRuleOrDefault(tileId)
	local footprint = BuildServiceUtils.ComputePlacementFootprint(tileX, tileY, rule)
	if #footprint <= 0 then
		return {
			canPlace = false,
			reason = "empty_footprint",
			footprint = {},
		}
	end

	for _, entry in footprint do
		local existingTileId = getTileAt(entry.tileX, entry.tileY)
		if not BuildServiceUtils.IsReplaceableTile(existingTileId) then
			return {
				canPlace = false,
				reason = "occupied",
				footprint = footprint,
			}
		end
	end

	if rule.requiresSupport then
		if not BuildServiceUtils.HasSupportAt(tileX, tileY, rule.supportMode, getTileAt) then
			return {
				canPlace = false,
				reason = "missing_support",
				footprint = footprint,
			}
		end
	end

	return {
		canPlace = true,
		reason = "ok",
		footprint = footprint,
	}
end

function BuildServiceUtils.GetBreakDuration(tileIdRaw: any, toolPowerRaw: any): number
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileId == nil then
		return math.huge
	end
	local rule = getRuleOrDefault(tileId)
	if tileId == TILE_ID.AIR then
		return 0
	end

	local toolPower = coerceNumber(toolPowerRaw, 0, 100000, 0)
	if rule.requiredToolPower > 0 and toolPower < rule.requiredToolPower then
		if rule.unbreakableWithoutTool then
			return math.huge
		end
		local deficit = (rule.requiredToolPower - toolPower) / rule.requiredToolPower
		return rule.breakTime * rule.hardness * (2 + deficit * 3)
	end

	local efficiencyDenominator = math.max(1, rule.requiredToolPower)
	local efficiency = math.max(0.3, toolPower / efficiencyDenominator)
	return rule.breakTime * rule.hardness / efficiency
end

function BuildServiceUtils.GetTileBreakHits(tileIdRaw: any, toolPowerRaw: any): number
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileId == nil then
		return math.huge
	end

	local breakDuration = BuildServiceUtils.GetBreakDuration(tileIdRaw, toolPowerRaw)
	if breakDuration == math.huge then
		return math.huge
	end
	if breakDuration <= 0 then
		return 0
	end

	local fixedBreakHits = FIXED_TILE_BREAK_HITS_BY_TILE_ID[tileId]
	if fixedBreakHits ~= nil then
		return fixedBreakHits
	end

	return math.max(1, math.ceil(breakDuration * DEFAULT_TILE_BREAK_HIT_RATE))
end

function BuildServiceUtils.GetTileBreakProfile(tileIdRaw: any, toolPowerRaw: any): TileBreakProfile
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileId == nil then
		return {
			requiredToolType = string.lower(DEFAULT_TILE_REQUIRED_TOOL_TYPE),
			requiredToolPower = 0,
			breakHits = math.huge,
			tileTier = "invalid",
		}
	end

	local rule = getRuleOrDefault(tileId)
	local tileRequirement = MiningPower.GetTileRequirement(tileId, rule.name)
	return {
		requiredToolType = tileRequirement.requiredToolType or string.lower(DEFAULT_TILE_REQUIRED_TOOL_TYPE),
		requiredToolPower = math.max(rule.requiredToolPower, tileRequirement.requiredToolPower or 0),
		breakHits = BuildServiceUtils.GetTileBreakHits(tileId, toolPowerRaw),
		tileTier = tileRequirement.tileTier or "default",
	}
end

function BuildServiceUtils.CanBreakTile(
	tileIdRaw: any,
	toolTypeRaw: any,
	toolPowerRaw: any
): (boolean, string, number, TileBreakProfile)
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileId == nil then
		return false, "invalid_tile_id", math.huge, BuildServiceUtils.GetTileBreakProfile(tileIdRaw, toolPowerRaw)
	end
	if tileId == TILE_ID.AIR then
		return false, "air", 0, BuildServiceUtils.GetTileBreakProfile(tileId, toolPowerRaw)
	end

	local profile = BuildServiceUtils.GetTileBreakProfile(tileId, toolPowerRaw)
	local toolType = string.lower(coerceString(toolTypeRaw, ""))
	local requiredToolType = string.lower(coerceString(profile.requiredToolType, DEFAULT_TILE_REQUIRED_TOOL_TYPE))
	if
		TILE_REQUIRE_PICKAXE_FOR_BREAKING
		and requiredToolType == "pickaxe"
		and string.find(toolType, "pickaxe", 1, true) == nil
	then
		return false, "tile_requires_pickaxe", math.huge, profile
	end
	if profile.breakHits == math.huge then
		return false, "insufficient_pickaxe_power", profile.breakHits, profile
	end
	return true, "ok", profile.breakHits, profile
end

function BuildServiceUtils.FloodFillSupportComponent(
	startTileXRaw: any,
	startTileYRaw: any,
	getTileAt: (tileX: number, tileY: number) -> number,
	maxNodesRaw: any?
): ({ TileCoordinate }, boolean, boolean)
	local startTileX = BuildServiceUtils.CoerceTileCoordinate(startTileXRaw)
	local startTileY = BuildServiceUtils.CoerceTileCoordinate(startTileYRaw)
	if startTileX == nil or startTileY == nil then
		return {}, true, false
	end

	local startTileId = getTileAt(startTileX, startTileY)
	local startRule = getRuleOrDefault(startTileId)
	if not startRule.requiresSupport and not startRule.fallWhenUnsupported then
		return {}, true, false
	end

	local maxNodes = coerceInteger(maxNodesRaw, 8, 20000, DEFAULT_BREAK_SUPPORT_FLOOD_LIMIT)
	local queue: { TileCoordinate } = {
		{
			tileX = startTileX,
			tileY = startTileY,
		},
	}
	local queueHead = 1
	local visited: { [string]: boolean } = {}
	local component: { TileCoordinate } = {}
	local componentSupported = false

	while queueHead <= #queue and #component < maxNodes do
		local current = queue[queueHead]
		queue[queueHead] = nil :: any
		queueHead += 1

		local key = BuildServiceUtils.PackTileKey(current.tileX, current.tileY)
		if visited[key] then
			continue
		end
		visited[key] = true

		local tileId = getTileAt(current.tileX, current.tileY)
		local tileRule = getRuleOrDefault(tileId)
		if tileRule.replaceable then
			continue
		end
		if not tileRule.requiresSupport and not tileRule.fallWhenUnsupported then
			continue
		end

		component[#component + 1] = current
		if BuildServiceUtils.HasSupportAt(current.tileX, current.tileY, tileRule.supportMode, getTileAt) then
			componentSupported = true
		end

		local neighbors = BuildServiceUtils.GetCardinalNeighbors(current.tileX, current.tileY)
		for _, neighbor in neighbors do
			local neighborKey = BuildServiceUtils.PackTileKey(neighbor.tileX, neighbor.tileY)
			if not visited[neighborKey] then
				queue[#queue + 1] = neighbor
			end
		end
	end

	local truncated = queueHead <= #queue
	return component, componentSupported, truncated
end

function BuildServiceUtils.CloneTileDelta(deltaRaw: any): TileDelta?
	if typeof(deltaRaw) ~= "table" then
		return nil
	end
	local source = deltaRaw :: { [string]: any }
	local tileX = BuildServiceUtils.CoerceTileCoordinate(source.tileX)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(source.tileY)
	local tileId = BuildServiceUtils.CoerceTileId(source.tileId)
	if tileX == nil or tileY == nil or tileId == nil then
		return nil
	end
	return {
		tileX = tileX,
		tileY = tileY,
		tileId = tileId,
		reason = if typeof(source.reason) == "string" then source.reason else nil,
	}
end
return BuildServiceUtils
