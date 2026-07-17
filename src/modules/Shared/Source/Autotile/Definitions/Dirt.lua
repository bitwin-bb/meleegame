local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Dirt",
	TileId = AtlasDefinition.TileIds.DIRT,
	Image = "rbxassetid://115586684643692",
	SourceAsset = "assets/blocks/Dirt.png",
	ConnectGroup = "Soil",
	RuleStrictness = BlendRule.Strictness.Blend,
	ConnectTileIds = {
		AtlasDefinition.TileIds.GRASS,
		AtlasDefinition.TileIds.STONE,
		AtlasDefinition.TileIds.SAND,
		AtlasDefinition.TileIds.CLAY,
		AtlasDefinition.TileIds.COPPER_ORE,
		AtlasDefinition.TileIds.IRON_ORE,
		AtlasDefinition.TileIds.SILVER_ORE,
		AtlasDefinition.TileIds.GOLD_ORE,
		AtlasDefinition.TileIds.CORRUPT_GRASS,
		AtlasDefinition.TileIds.CORRUPT_STONE,
		AtlasDefinition.TileIds.MUD,
		AtlasDefinition.TileIds.WOOD,
	},
}))
