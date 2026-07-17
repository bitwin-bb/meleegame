local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Ice",
	TileId = AtlasDefinition.TileIds.ICE,
	Image = "rbxassetid://96540381608163",
	SourceAsset = "assets/blocks/Ice.png",
	ConnectGroup = "Ice",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.SNOW,
	},
}))
