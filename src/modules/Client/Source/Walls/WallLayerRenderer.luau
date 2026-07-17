local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local TileLayerRenderer = require("TileLayerRenderer")

local WallLayerRenderer = {}

local WALL_LAYER_OPTIONS = Table.readonly({
	containerName = "WallAutotileLayer",
	rootName = "WallAutotileRoot",
	surfaceName = "WallAutotileSurface",
	imageName = "WallAutotileImage",
	imageZIndex = 1,
	frameScale = 2,
})

function WallLayerRenderer.new(parent: Instance, widthRaw: any?, heightRaw: any?): any
	return TileLayerRenderer.new(parent, widthRaw, heightRaw, WALL_LAYER_OPTIONS)
end

return Table.readonly(WallLayerRenderer)
