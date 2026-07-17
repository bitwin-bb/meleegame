local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "CorruptGrass",
	TileId = AtlasDefinition.TileIds.CORRUPT_GRASS,
	Image = "rbxassetid://72981908250936",
	SourceAsset = "assets/blocks/CorruptGrass.png",
	ConnectGroup = "CorruptSoil",
	RuleStrictness = BlendRule.Strictness.Grass,
	MergeTileIds = {
		AtlasDefinition.TileIds.CORRUPT_SOIL,
		AtlasDefinition.TileIds.DIRT,
	},
}))
