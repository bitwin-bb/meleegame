local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "CorruptStone",
	TileId = AtlasDefinition.TileIds.CORRUPT_STONE,
	Image = "rbxassetid://131340975613948",
	SourceAsset = "assets/blocks/EbonStone.png",
	ConnectGroup = "CorruptStone",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
		AtlasDefinition.TileIds.CORRUPT_SOIL,
	},
}))
