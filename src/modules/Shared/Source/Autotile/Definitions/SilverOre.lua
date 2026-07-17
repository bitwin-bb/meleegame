local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "SilverOre",
	TileId = AtlasDefinition.TileIds.SILVER_ORE,
	Image = "rbxassetid://0",
	ConnectGroup = "SilverOre",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
	},
}))
