local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AtlasDefinition = require("AtlasDefinition")
local BlendRule = require("BlendRule")

local SOURCE_IMAGE_SIZE = Vector2.new(288, 1980)
local ROBLOX_IMAGE_SIZE = Vector2.new(148, 1017)
local IMAGE_RECT_SCALE =
	Vector2.new(ROBLOX_IMAGE_SIZE.X / SOURCE_IMAGE_SIZE.X, ROBLOX_IMAGE_SIZE.Y / SOURCE_IMAGE_SIZE.Y)

return Table.readonly(AtlasDefinition.Create({
	Id = "Grass",
	TileId = AtlasDefinition.TileIds.GRASS,
	Image = "rbxassetid://104962191554416",
	SourceAsset = "assets/blocks/Grass.png",
	ImageRectScale = IMAGE_RECT_SCALE,
	ConnectGroup = "Soil",
	RuleStrictness = BlendRule.Strictness.Grass,
	MergeTileIds = {
		AtlasDefinition.TileIds.DIRT,
	},
}))
