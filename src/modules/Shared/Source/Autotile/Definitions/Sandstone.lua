local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Sandstone",
	TileId = AtlasDefinition.TileIds.SANDSTONE,
	Image = "rbxassetid://136513027008291",
	SourceAsset = "assets/blocks/Sandstone.png",
	ConnectGroup = "Sandstone",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.SAND,
	},
}))
