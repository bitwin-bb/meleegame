local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

return Table.readonly(AtlasDefinition.Create({
	Id = "CorruptSoil",
	TileId = AtlasDefinition.TileIds.CORRUPT_SOIL,
	Image = "rbxassetid://115586684643692",
	ConnectGroup = "CorruptSoil",
	RuleStrictness = BlendRule.Strictness.Blend,
	ConnectTileIds = {
		AtlasDefinition.TileIds.CORRUPT_GRASS,
		AtlasDefinition.TileIds.CORRUPT_STONE,
	},
}))
