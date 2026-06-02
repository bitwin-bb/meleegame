--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Tile = require(gameRoot.Shared.Features.worldGeneration.components.Tile)

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

Copper.createOreTexture = Copper.CreateOreTexture

return Copper
