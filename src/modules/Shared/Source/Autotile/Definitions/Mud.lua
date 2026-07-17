local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "Mud",
	TileId = AtlasDefinition.TileIds.MUD,
	Image = "rbxassetid://74303271698207",
	SourceAsset = "assets/blocks/Mud.png",
	ConnectGroup = "Mud",
	RuleStrictness = BlendRule.Strictness.Blend,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
		AtlasDefinition.TileIds.STONE,
	},
	ConnectTileIds = {
		AtlasDefinition.TileIds.JUNGLE_GRASS,
	},
}))
