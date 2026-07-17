local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Snow",
	TileId = AtlasDefinition.TileIds.SNOW,
	Image = "rbxassetid://136615899750509",
	SourceAsset = "assets/blocks/Snow.png",
	ConnectGroup = "Snow",
	RuleStrictness = BlendRule.Strictness.Blend,
	ConnectTileIds = {
		AtlasDefinition.TileIds.ICE,
	},
}))
