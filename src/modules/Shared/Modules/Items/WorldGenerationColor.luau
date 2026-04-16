--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


export type TileVisual = {
	name: string,
	color: Color3,
	material: Enum.Material,
	transparency: number,
}

export type TreePalette = {
	BranchColor: Color3,
	LeafColor: Color3,
}

export type LiquidColorDefinition = {
	baseColor: Color3,
	surfaceColor: Color3,
}

export type LiquidBiomeTints = {
	byBiomeId: { [number]: Color3 },
	byBiomeType: { [number]: Color3 },
	lavaAmbientByBiomeId: { [number]: Color3 },
	lavaAmbientByBiomeType: { [number]: Color3 },
}

local WorldGenerationColor = {}
local TILE_MATERIAL = Enum.Material.Plastic

-- Ore tiles are rendered from dedicated assets, so they intentionally do not
-- get unique flat color entries in the shared tile visual palette.
local TILE_VISUALS: { [number]: TileVisual } = {
	[1] = {
		name = "Grass",
		color = Color3.fromRGB(113, 155, 76),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[17] = {
		name = "JungleGrass",
		color = Color3.fromRGB(112, 147, 41),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[18] = {
		name = "Wood",
		color = Color3.fromRGB(90, 64, 44),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[2] = {
		name = "Dirt",
		color = Color3.fromRGB(79, 47, 20),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[3] = {
		name = "Stone",
		color = Color3.fromRGB(95, 102, 111),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[4] = {
		name = "Sand",
		color = Color3.fromRGB(211, 196, 139),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[5] = {
		name = "Sandstone",
		color = Color3.fromRGB(199, 161, 103),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[6] = {
		name = "Snow",
		color = Color3.fromRGB(232, 240, 255),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[7] = {
		name = "Ice",
		color = Color3.fromRGB(178, 214, 255),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[8] = {
		name = "Mud",
		color = Color3.fromRGB(48, 40, 31),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[9] = {
		name = "Clay",
		color = Color3.fromRGB(174, 78, 54),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[14] = {
		name = "CorruptGrass",
		color = Color3.fromRGB(70, 40, 109),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[15] = {
		name = "CorruptSoil",
		color = Color3.fromRGB(104, 73, 74),
		material = TILE_MATERIAL,
		transparency = 0,
	},
	[16] = {
		name = "CorruptStone",
		color = Color3.fromRGB(69, 35, 119),
		material = TILE_MATERIAL,
		transparency = 0,
	},
}

local TREE_PALETTES: { [string]: TreePalette } = {
	Default = {
		BranchColor = Color3.fromRGB(109, 80, 60),
		LeafColor = Color3.fromRGB(100, 141, 84),
	},
	Corruption1 = {
		BranchColor = Color3.fromRGB(31, 19, 56),
		LeafColor = Color3.fromRGB(153, 92, 210),
	},
	Corruption2 = {
		BranchColor = Color3.fromRGB(31, 15, 63),
		LeafColor = Color3.fromRGB(171, 101, 231),
	},
	Jungle1 = {
		BranchColor = Color3.fromRGB(123, 71, 87),
		LeafColor = Color3.fromRGB(52, 132, 58),
	},
	Jungle2 = {
		BranchColor = Color3.fromRGB(154, 74, 105),
		LeafColor = Color3.fromRGB(51, 138, 66),
	},
	Snow1 = {
		BranchColor = Color3.fromRGB(89, 75, 70),
		LeafColor = Color3.fromRGB(220, 238, 244),
	},
	Snow2 = {
		BranchColor = Color3.fromRGB(74, 68, 81),
		LeafColor = Color3.fromRGB(197, 226, 239),
	},
}

local LIQUID_DEFINITIONS: { [number]: LiquidColorDefinition } = {
	[1] = {
		baseColor = Color3.fromRGB(51, 90, 163),
		surfaceColor = Color3.fromRGB(38, 69, 128),
	},
	[2] = {
		baseColor = Color3.fromRGB(246, 104, 31),
		surfaceColor = Color3.fromRGB(255, 187, 76),
	},
}

local LIQUID_BIOME_TINTS: LiquidBiomeTints = {
	byBiomeId = {
		[1] = Color3.fromRGB(52, 60, 133),
		[2] = Color3.fromRGB(141, 116, 68),
		[3] = Color3.fromRGB(39, 90, 114),
		[4] = Color3.fromRGB(70, 143, 102),
	},
	byBiomeType = {
		[1] = Color3.fromRGB(41, 66, 104),
		[2] = Color3.fromRGB(97, 61, 151),
	},
	lavaAmbientByBiomeId = {
		[3] = Color3.fromRGB(238, 179, 116),
		[4] = Color3.fromRGB(182, 85, 43),
	},
	lavaAmbientByBiomeType = {
		[2] = Color3.fromRGB(255, 108, 153),
	},
}

local function cloneColor3Map(source: { [number]: Color3 }): { [number]: Color3 }
	return Sift.Dictionary.copy(source)
end

local function cloneTreePalette(palette: TreePalette): TreePalette
	return {
		BranchColor = palette.BranchColor,
		LeafColor = palette.LeafColor,
	}
end

WorldGenerationColor.TILE_VISUALS = TILE_VISUALS
WorldGenerationColor.TREE_PALETTES = TREE_PALETTES
WorldGenerationColor.LIQUID_DEFINITIONS = LIQUID_DEFINITIONS
WorldGenerationColor.LIQUID_BIOME_TINTS = LIQUID_BIOME_TINTS

function WorldGenerationColor.GetTileVisual(tileId: number): TileVisual?
	local visual = TILE_VISUALS[tileId]
	if visual == nil then
		return nil
	end
	return Sift.Dictionary.copy(visual)
end

function WorldGenerationColor.GetTileVisuals(): { [number]: TileVisual }
	local visuals = {}
	for tileId, visual in TILE_VISUALS do
		visuals[tileId] = Sift.Dictionary.copy(visual)
	end
	return visuals
end

function WorldGenerationColor.GetTreePalette(name: string): TreePalette?
	local palette = TREE_PALETTES[name]
	if palette == nil then
		return nil
	end
	return cloneTreePalette(palette)
end

function WorldGenerationColor.GetTreePalettes(): { [string]: TreePalette }
	local palettes = {}
	for name, palette in TREE_PALETTES do
		palettes[name] = cloneTreePalette(palette)
	end
	return palettes
end

function WorldGenerationColor.GetLiquidDefinitions(): { [number]: LiquidColorDefinition }
	local definitions = {}
	for liquidType, definition in LIQUID_DEFINITIONS do
		definitions[liquidType] = {
			baseColor = definition.baseColor,
			surfaceColor = definition.surfaceColor,
		}
	end
	return definitions
end

function WorldGenerationColor.GetLiquidBiomeTints(): LiquidBiomeTints
	return {
		byBiomeId = cloneColor3Map(LIQUID_BIOME_TINTS.byBiomeId),
		byBiomeType = cloneColor3Map(LIQUID_BIOME_TINTS.byBiomeType),
		lavaAmbientByBiomeId = cloneColor3Map(LIQUID_BIOME_TINTS.lavaAmbientByBiomeId),
		lavaAmbientByBiomeType = cloneColor3Map(LIQUID_BIOME_TINTS.lavaAmbientByBiomeType),
	}
end

WorldGenerationColor.getTileVisual = WorldGenerationColor.GetTileVisual
WorldGenerationColor.getTileVisuals = WorldGenerationColor.GetTileVisuals
WorldGenerationColor.getTreePalette = WorldGenerationColor.GetTreePalette
WorldGenerationColor.getTreePalettes = WorldGenerationColor.GetTreePalettes
WorldGenerationColor.getLiquidDefinitions = WorldGenerationColor.GetLiquidDefinitions
WorldGenerationColor.getLiquidBiomeTints = WorldGenerationColor.GetLiquidBiomeTints

return WorldGenerationColor
