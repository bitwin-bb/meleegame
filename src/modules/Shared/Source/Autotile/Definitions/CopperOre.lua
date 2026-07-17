local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "CopperOre",
	TileId = AtlasDefinition.TileIds.COPPER_ORE,
	Image = "rbxassetid://76226866459218",
	SourceAsset = "assets/blocks/Copper.png",
	ConnectGroup = "CopperOre",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
	},
}))
