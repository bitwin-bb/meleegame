local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Wood",
	TileId = AtlasDefinition.TileIds.WOOD,
	Image = "rbxassetid://138301279978552",
	SourceAsset = "assets/blocks/Wood.png",
	ConnectGroup = "Wood",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
	},
}))
