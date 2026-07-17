local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Stone",
	TileId = AtlasDefinition.TileIds.STONE,
	Image = "rbxassetid://81371390916201",
	SourceAsset = "assets/blocks/Stone.png",
	ConnectGroup = "Stone",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
	},
	ConnectTileIds = {
		AtlasDefinition.TileIds.MUD,
	},
}))
