--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Tile = require(gameRoot.Shared.Features.worldGeneration.components.Tile)

local Water = {}

export type WaterPartConfig = Tile.PartConfig

function Water.CreatePart(configRaw: WaterPartConfig?): Part
	local config = table.clone(if typeof(configRaw) == "table" then configRaw :: WaterPartConfig else {} :: any)
	config.name = config.name or "Water"
	config.material = config.material or Enum.Material.Water
	config.color = config.color or Color3.fromRGB(69, 154, 221)
	config.transparency = config.transparency or 0.28
	config.canCollide = if config.canCollide == nil then false else config.canCollide
	config.canTouch = if config.canTouch == nil then false else config.canTouch
	config.canQuery = if config.canQuery == nil then false else config.canQuery
	config.castShadow = if config.castShadow == nil then false else config.castShadow
	return Tile.CreatePart(config)
end

Water.createPart = Water.CreatePart

return Water
