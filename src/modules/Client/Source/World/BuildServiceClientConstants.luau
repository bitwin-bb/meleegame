local require = require(script.Parent.loader).load(script)

local AudioRegistry = require("Audio")
local BuildServiceUtils = require("BuildServiceUtils")

local BREAK_DEBRIS_VISUALS = {
	[BuildServiceUtils.TILE_ID.GRASS] = {
		color = Color3.fromRGB(95, 159, 53),
		material = Enum.Material.Grass,
	},
	[BuildServiceUtils.TILE_ID.JUNGLE_GRASS] = {
		color = Color3.fromRGB(113, 186, 72),
		material = Enum.Material.Grass,
	},
	[BuildServiceUtils.TILE_ID.DIRT] = {
		color = Color3.fromRGB(108, 78, 52),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.STONE] = {
		color = Color3.fromRGB(108, 113, 122),
		material = Enum.Material.Slate,
	},
	[BuildServiceUtils.TILE_ID.SAND] = {
		color = Color3.fromRGB(225, 206, 136),
		material = Enum.Material.Sand,
	},
	[BuildServiceUtils.TILE_ID.SANDSTONE] = {
		color = Color3.fromRGB(183, 154, 109),
		material = Enum.Material.Sandstone,
	},
	[BuildServiceUtils.TILE_ID.SNOW] = {
		color = Color3.fromRGB(232, 240, 255),
		material = Enum.Material.Snow,
	},
	[BuildServiceUtils.TILE_ID.ICE] = {
		color = Color3.fromRGB(178, 214, 255),
		material = Enum.Material.Glacier,
	},
	[BuildServiceUtils.TILE_ID.MUD] = {
		color = Color3.fromRGB(112, 90, 61),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.CLAY] = {
		color = Color3.fromRGB(135, 98, 73),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.COPPER_ORE] = {
		color = Color3.fromRGB(189, 118, 63),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.IRON_ORE] = {
		color = Color3.fromRGB(141, 134, 116),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.SILVER_ORE] = {
		color = Color3.fromRGB(177, 177, 185),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.GOLD_ORE] = {
		color = Color3.fromRGB(214, 186, 62),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.CORRUPT_GRASS] = {
		color = Color3.fromRGB(131, 84, 193),
		material = Enum.Material.Grass,
	},
	[BuildServiceUtils.TILE_ID.CORRUPT_SOIL] = {
		color = Color3.fromRGB(116, 84, 88),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.CORRUPT_STONE] = {
		color = Color3.fromRGB(126, 104, 160),
		material = Enum.Material.Rock,
	},
	[BuildServiceUtils.TILE_ID.WOOD] = {
		color = Color3.fromRGB(121, 91, 56),
		material = Enum.Material.Wood,
	},
}

local TREE_AUDIO = (((AudioRegistry :: any).Misc or ({} :: any)).Tree or ({} :: any))
local TILE_AUDIO = (((AudioRegistry :: any).Misc or ({} :: any)).Tile or ({} :: any))

return table.freeze({
	BUILD_PREVIEW_RUNTIME_ATTRIBUTE = "BuildPreviewRuntime",
	WIND_FOLIAGE_ENABLED_ATTRIBUTE = "WindFoliageEnabled",
	TREE_NODE_TYPE_ATTRIBUTE = "WindTreeNodeType",
	TILE_QUERY_FETCH_COOLDOWN = 0.25,
	PREDICTION_TTL_SECONDS = 2,
	TERRAIN_HOVER_SCAN_DEPTH_TILES = 8,
	HOVER_BREAK_TEST_MODE = false,
	MAX_BREAK_DEBRIS_TILES_PER_BATCH = 16,
	BREAK_DEBRIS_REASONS = {
		["break"] = true,
		cascade = true,
	},
	BREAK_DEBRIS_VISUALS = BREAK_DEBRIS_VISUALS,
	DEFAULT_BREAK_DEBRIS_VISUAL = BREAK_DEBRIS_VISUALS[BuildServiceUtils.TILE_ID.STONE],
	BREAK_CHUNK_ANIMATION_SKIP_SECONDS = 1.5,
	PRIMARY_INPUT_USER_TYPES = {
		[Enum.UserInputType.MouseButton1] = true,
		[Enum.UserInputType.Touch] = true,
	},
	TREE_MODEL_MATCH_MAX_DISTANCE_TILES = 6,
	TREE_FALL_DURATION_MIN = 4,
	TREE_FALL_DURATION_MAX = 5,
	TREE_FALL_ACCELERATION_EXPONENT = 2.2,
	TREE_FALL_BASE_ANGLE = math.rad(88),
	TREE_FALL_OVERSHOOT_ANGLE = math.rad(8),
	TREE_FALL_BOUNCE_ANGLE = math.rad(6),
	TREE_BOUNCE_DURATION = 0.16,
	TREE_SETTLE_DURATION = 0.24,
	TREE_FADE_DURATION = 0.85,
	TREE_GROUND_HIT_MIN_ANGLE = math.rad(28),
	TREE_GROUND_HIT_MIN_PROGRESS = 0.2,
	TREE_GROUND_HIT_SAMPLE_COUNT = 5,
	TREE_GROUND_HIT_SCAN_DEPTH_TILES = 3,
	TREE_GROUND_HIT_SURFACE_PADDING_TILES = 0.2,
	TREE_GROUND_HIT_FAILSAFE_SECONDS = 1.2,
	TREE_FALL_SOUND_FADE_OUT_SECONDS = 0.7,
	TREE_FALL_SPRING = {
		frequency = 2.7,
		damping = 0.72,
	},
	TREE_BOUNCE_SPRING = {
		frequency = 4.8,
		damping = 0.58,
	},
	TREE_SETTLE_SPRING = {
		frequency = 6.5,
		damping = 0.92,
	},
	TREE_FADE_SPRING = {
		frequency = 7,
		damping = 1,
	},
	INPUT_ACTION_PRIMARY = "BuildService.Primary",
	CURSOR_VISUAL_RAYCAST_DISTANCE_STUDS = 4096,
	BUILD_TREE_ROOT_TILE_X_ATTRIBUTE = "BuildTreeRootTileX",
	BUILD_TREE_ROOT_TILE_Y_ATTRIBUTE = "BuildTreeRootTileY",
	TREE_CHOP_AUDIO = TREE_AUDIO.Chop or ({} :: any),
	TREE_FALL_AUDIO = TREE_AUDIO.Fall or ({} :: any),
	TILE_HIT_AUDIO = TILE_AUDIO.Hit or ({} :: any),
	TILE_BREAK_AUDIO = TILE_AUDIO.Break or ({} :: any),
})
