local require = require(script.Parent.loader).load(script)

local Math = require("Math")

local SpaceShared = {}

SpaceShared.SPACE_BIOME_KEY = "space"
SpaceShared.SPACE_BIOME_NAME = "Space"
SpaceShared.SPACE_SKY_KEY = "Space"
SpaceShared.SPACE_SOUNDTRACK_BIOME = "Space"
SpaceShared.SPACE_HEIGHT_TILES = 200
SpaceShared.SPACE_SAMPLE_INTERVAL_SECONDS = 0.2

local DEFAULT_TILE_SIZE = 2
local DEFAULT_WORLD_ORIGIN = Vector3.zero

local function coerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and not Math.isNaN(valueRaw) and Math.isFinite(valueRaw) then
		value = valueRaw
	end
	if minimum ~= nil then
		value = math.max(value, minimum)
	end
	if maximum ~= nil then
		value = math.min(value, maximum)
	end
	return value
end

function SpaceShared.GetTileSize(worldStateRaw: any): number
	local worldState = if typeof(worldStateRaw) == "table" then worldStateRaw :: { [string]: any } else {} :: any
	return coerceNumber(worldState.tileSize, DEFAULT_TILE_SIZE, 0.25, 1024)
end

function SpaceShared.GetWorldOrigin(worldOriginRaw: any): Vector3
	if typeof(worldOriginRaw) == "Vector3" then
		return worldOriginRaw
	end
	return DEFAULT_WORLD_ORIGIN
end

function SpaceShared.GetSpaceThresholdY(worldStateRaw: any, worldOriginRaw: any): number
	local tileSize = SpaceShared.GetTileSize(worldStateRaw)
	local worldOrigin = SpaceShared.GetWorldOrigin(worldOriginRaw)
	return worldOrigin.Y + tileSize * SpaceShared.SPACE_HEIGHT_TILES
end

function SpaceShared.IsInSpaceAtWorldPosition(worldPositionRaw: any, worldStateRaw: any, worldOriginRaw: any): boolean
	if typeof(worldPositionRaw) ~= "Vector3" then
		return false
	end
	return (worldPositionRaw :: Vector3).Y >= SpaceShared.GetSpaceThresholdY(worldStateRaw, worldOriginRaw)
end


return SpaceShared
