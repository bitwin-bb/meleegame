local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "JungleGrass",
	TileId = AtlasDefinition.TileIds.JUNGLE_GRASS,
	Image = "rbxassetid://100342653817095",
	SourceAsset = "assets/blocks/JungleGrass.png",
	ConnectGroup = "Mud",
	RuleStrictness = BlendRule.Strictness.Grass,
	MergeTileIds = {
		AtlasDefinition.TileIds.MUD,
	},
}))
