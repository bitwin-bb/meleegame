local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Sand",
	TileId = AtlasDefinition.TileIds.SAND,
	Image = "rbxassetid://94903859425655",
	SourceAsset = "assets/blocks/Sand.png",
	ConnectGroup = "Sand",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
	},
	ConnectTileIds = {
		AtlasDefinition.TileIds.SANDSTONE,
	},
}))
