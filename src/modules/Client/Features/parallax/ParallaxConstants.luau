--!strict

return table.freeze({
	DEPTH_LAYER_SKY = 0,
	DEPTH_LAYER_UNDERGROUND = 2,

	BIOME_RESERVED_KEYS = {
		settings = true,
		aliases = true,
		layers = true,
		variants = true,
		defaultVariant = true,
		selectedVariant = true,
	},

	BUILT_IN_BIOME_ALIASES = {
		overworld = { "Forest", "Default", "Overworld", "Surface" },
		forest = { "Forest", "Default", "Overworld", "Surface" },
		desert = { "Desert", "Sand", "Dunes" },
		snow = { "Snow", "Tundra", "Ice" },
		jungle = { "Jungle", "Rainforest" },
		corruption = { "Corruption", "Corrupt", "Evil" },
		underground = { "Underground", "Cavern", "Caves" },
	},

	IMPLICIT_BIOME_TINTS = {
		overworld = Color3.fromRGB(175, 214, 188),
		forest = Color3.fromRGB(175, 214, 188),
		desert = Color3.fromRGB(229, 205, 160),
		snow = Color3.fromRGB(208, 227, 255),
		jungle = Color3.fromRGB(141, 190, 132),
		corruption = Color3.fromRGB(166, 140, 208),
		underground = Color3.fromRGB(132, 144, 170),
	},

	IMPLICIT_LAYER_FALLBACK_IMAGE_ASPECT_RATIO = 3.3,
	IMPLICIT_LAYER_BASE_TEXTURE_TILE_STUDS = 96,
	IMPLICIT_LAYER_DEPTH_BASE = 0.32,
	IMPLICIT_LAYER_DEPTH_STEP = 0.08,
	IMPLICIT_LAYER_PLANE_DEPTH_BASE = 40,
	IMPLICIT_LAYER_PLANE_DEPTH_STEP = 16,
	IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_BASE = 0.54,
	IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_STEP = 0.09,
	IMPLICIT_LAYER_TRANSPARENCY_BASE = 0,
	IMPLICIT_LAYER_TRANSPARENCY_STEP = 0,
	IMPLICIT_LAYER_VERTICAL_OFFSET_BASE = -18,
	IMPLICIT_LAYER_VERTICAL_OFFSET_STEP = 10,
	IMPLICIT_LAYER_VERTICAL_DEPTH_BASE = 0.008,
	IMPLICIT_LAYER_VERTICAL_DEPTH_STEP = 0.004,
	IMPLICIT_LAYER_BASE_Y_OFFSET = 1,
	IMPLICIT_LAYER_BOTTOM_OVERSCAN = 0.08,
	IMPLICIT_LAYER_MIN_Y = -0.06,
	IMPLICIT_LAYER_MAX_Y = 0.1,
	DEFAULT_HORIZONTAL_VISION_STUDS = 576,
	MINIMUM_TEXTURE_REPEAT_WIDTH_STUDS = 12,
	MINIMUM_HORIZONTAL_PLANE_BLEED_STUDS = 8,
	HORIZONTAL_PLANE_BLEED_FACTOR = 0.08,

	IMPLICIT_PARALLAX_SOURCE_DIMENSIONS = {
		overworld = {
			[1] = { width = 1024, height = 533 },
			[2] = { width = 1024, height = 600 },
			[3] = { width = 1024, height = 660 },
			[4] = { width = 1024, height = 699 },
		},
		corruption = {
			[1] = { width = 1024, height = 533 },
			[2] = { width = 1024, height = 533 },
			[3] = { width = 1024, height = 533 },
			[4] = { width = 1024, height = 371 },
		},
		jungle = {
			[1] = { width = 1024, height = 768 },
			[2] = { width = 1024, height = 533 },
			[3] = { width = 1024, height = 540 },
			[4] = { width = 1024, height = 533 },
		},
		desert = {
			[1] = { width = 1024, height = 400 },
			[2] = { width = 1024, height = 500 },
			[3] = { width = 1024, height = 434 },
			[4] = { width = 1024, height = 434 },
		},
		snow = {
			[1] = { width = 1024, height = 529 },
			[2] = { width = 1024, height = 529 },
			[3] = { width = 1024, height = 600 },
			[4] = { width = 1024, height = 600 },
		},
	},
})
