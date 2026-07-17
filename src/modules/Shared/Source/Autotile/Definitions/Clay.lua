local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Clay",
	TileId = AtlasDefinition.TileIds.CLAY,
	Image = "rbxassetid://0",
	ConnectGroup = "Clay",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
	},
}))
