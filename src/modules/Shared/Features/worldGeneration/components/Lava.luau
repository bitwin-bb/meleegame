--!strict

local Tile = require(script.Parent.Tile)

local Lava = {}

export type LavaPartConfig = Tile.PartConfig

function Lava.CreatePart(configRaw: LavaPartConfig?): Part
	local config = table.clone(if typeof(configRaw) == "table" then configRaw :: LavaPartConfig else {})
	config.name = config.name or "Lava"
	config.material = config.material or Enum.Material.Neon
	config.color = config.color or Color3.fromRGB(235, 92, 35)
	config.transparency = config.transparency or 0.12
	config.canCollide = if config.canCollide == nil then false else config.canCollide
	config.canTouch = if config.canTouch == nil then true else config.canTouch
	config.canQuery = if config.canQuery == nil then false else config.canQuery
	config.castShadow = if config.castShadow == nil then false else config.castShadow
	return Tile.CreatePart(config)
end

Lava.createPart = Lava.CreatePart

return Lava
