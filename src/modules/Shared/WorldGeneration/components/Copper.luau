
local require = require(script.Parent.loader).load(script)

local Tile = require("Tile")

local Copper = {}

export type OreTextureConfig = {
	name: string?,
	parent: Instance?,
	face: Enum.NormalId,
	texture: string,
	studsPerTileU: number,
	studsPerTileV: number,
}

function Copper.CreateOreTexture(config: OreTextureConfig): Texture
	return Tile.CreateTexture({
		name = config.name or "OreTexture",
		parent = config.parent,
		face = config.face,
		texture = config.texture,
		studsPerTileU = config.studsPerTileU,
		studsPerTileV = config.studsPerTileV,
	})
end
return Copper
