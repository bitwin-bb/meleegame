local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local DirectionBits = require("DirectionBits")
local MaskResolver = require("MaskResolver")
local WallAtlas = require("WallAtlas")
local WallServiceUtils = require("WallServiceUtils")

local WallAutotileResolver = {}

local function getWallId(wallRaw: any): number
	if typeof(wallRaw) ~= "table" then
		return WallServiceUtils.WALL_ID.NONE
	end
	local wallId = (wallRaw :: any).WallId
		or (wallRaw :: any).wallId
		or (wallRaw :: any).TileId
		or (wallRaw :: any).tileId
	return WallServiceUtils.CoerceWallId(wallId) or WallServiceUtils.WALL_ID.NONE
end

local CONNECTION_RULE = Table.readonly({
	IncludeDiagonals = false,
	Connects = function(_centerWall: any, neighborWall: any): boolean
		return getWallId(neighborWall) ~= WallServiceUtils.WALL_ID.NONE
	end,
})

function WallAutotileResolver.ResolveMask(accessorRaw: any, coordRaw: any): number
	return MaskResolver.Resolve(accessorRaw, coordRaw, CONNECTION_RULE)
end

function WallAutotileResolver.Resolve(definitionRaw: any, accessorRaw: any, coordRaw: any, seedRaw: any?): any?
	local worldMask = WallAutotileResolver.ResolveMask(accessorRaw, coordRaw)
	local atlasMask = DirectionBits.MirrorHorizontal(worldMask)
	local resolved = WallAtlas.Resolve(definitionRaw, atlasMask, coordRaw, seedRaw)
	if resolved ~= nil then
		(resolved :: any).WorldMask = worldMask
	end
	return resolved
end

return Table.readonly(WallAutotileResolver)
