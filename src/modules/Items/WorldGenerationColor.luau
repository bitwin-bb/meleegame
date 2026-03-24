--!strict

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

local TILE_VISUALS: { [number]: TileVisual } = {
	[1] = {
		name = "Grass",
		color = Color3.fromRGB(113, 155, 76),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[17] = {
		name = "JungleGrass",
		color = Color3.fromRGB(112, 147, 41),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[18] = {
		name = "Wood",
		color = Color3.fromRGB(90, 64, 44),
		material = Enum.Material.Wood,
		transparency = 0,
	},
	[2] = {
		name = "Dirt",
		color = Color3.fromRGB(79, 47, 20),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[3] = {
		name = "Stone",
		color = Color3.fromRGB(95, 102, 111),
		material = Enum.Material.Slate,
		transparency = 0,
	},
	[4] = {
		name = "Sand",
		color = Color3.fromRGB(211, 196, 139),
		material = Enum.Material.Sand,
		transparency = 0,
	},
	[5] = {
		name = "Sandstone",
		color = Color3.fromRGB(199, 161, 103),
		material = Enum.Material.Sandstone,
		transparency = 0,
	},
	[6] = {
		name = "Snow",
		color = Color3.fromRGB(232, 240, 255),
		material = Enum.Material.Snow,
		transparency = 0,
	},
	[7] = {
		name = "Ice",
		color = Color3.fromRGB(178, 214, 255),
		material = Enum.Material.Glacier,
		transparency = 0,
	},
	[8] = {
		name = "Mud",
		color = Color3.fromRGB(48, 40, 31),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[9] = {
		name = "Clay",
		color = Color3.fromRGB(174, 78, 54),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[10] = {
		name = "CopperOre",
		color = Color3.fromRGB(189, 118, 63),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[11] = {
		name = "IronOre",
		color = Color3.fromRGB(141, 134, 116),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[12] = {
		name = "SilverOre",
		color = Color3.fromRGB(177, 177, 185),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[13] = {
		name = "GoldOre",
		color = Color3.fromRGB(214, 186, 62),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[14] = {
		name = "CorruptGrass",
		color = Color3.fromRGB(70, 40, 109),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[15] = {
		name = "CorruptSoil",
		color = Color3.fromRGB(104, 73, 74),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[16] = {
		name = "CorruptStone",
		color = Color3.fromRGB(69, 35, 119),
		material = Enum.Material.Rock,
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
		[2] = Color3.fromRGB(47, 87, 67),
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
	return table.clone(source)
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

function WorldGenerationColor.getTileVisual(tileId: number): TileVisual?
	local visual = TILE_VISUALS[tileId]
	if visual == nil then
		return nil
	end
	return table.clone(visual)
end

function WorldGenerationColor.getTileVisuals(): { [number]: TileVisual }
	local visuals = {}
	for tileId, visual in TILE_VISUALS do
		visuals[tileId] = table.clone(visual)
	end
	return visuals
end

function WorldGenerationColor.getTreePalette(name: string): TreePalette?
	local palette = TREE_PALETTES[name]
	if palette == nil then
		return nil
	end
	return cloneTreePalette(palette)
end

function WorldGenerationColor.getTreePalettes(): { [string]: TreePalette }
	local palettes = {}
	for name, palette in TREE_PALETTES do
		palettes[name] = cloneTreePalette(palette)
	end
	return palettes
end

function WorldGenerationColor.getLiquidDefinitions(): { [number]: LiquidColorDefinition }
	local definitions = {}
	for liquidType, definition in LIQUID_DEFINITIONS do
		definitions[liquidType] = {
			baseColor = definition.baseColor,
			surfaceColor = definition.surfaceColor,
		}
	end
	return definitions
end

function WorldGenerationColor.getLiquidBiomeTints(): LiquidBiomeTints
	return {
		byBiomeId = cloneColor3Map(LIQUID_BIOME_TINTS.byBiomeId),
		byBiomeType = cloneColor3Map(LIQUID_BIOME_TINTS.byBiomeType),
		lavaAmbientByBiomeId = cloneColor3Map(LIQUID_BIOME_TINTS.lavaAmbientByBiomeId),
		lavaAmbientByBiomeType = cloneColor3Map(LIQUID_BIOME_TINTS.lavaAmbientByBiomeType),
	}
end

return WorldGenerationColor
