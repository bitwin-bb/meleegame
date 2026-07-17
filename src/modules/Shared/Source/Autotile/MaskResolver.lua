local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local DirectionBits = require("DirectionBits")
local EightWayBlobRule = require("EightWayBlobRule")

local MaskResolver = {}

local CARDINAL_DIRECTIONS = Table.readonly({
	{ bit = DirectionBits.N, x = 0, y = 1 },
	{ bit = DirectionBits.E, x = 1, y = 0 },
	{ bit = DirectionBits.S, x = 0, y = -1 },
	{ bit = DirectionBits.W, x = -1, y = 0 },
})

local DIAGONAL_DIRECTIONS = Table.readonly({
	{ bit = DirectionBits.NE, x = 1, y = 1, requiredA = DirectionBits.N, requiredB = DirectionBits.E },
	{ bit = DirectionBits.SE, x = 1, y = -1, requiredA = DirectionBits.S, requiredB = DirectionBits.E },
	{ bit = DirectionBits.SW, x = -1, y = -1, requiredA = DirectionBits.S, requiredB = DirectionBits.W },
	{ bit = DirectionBits.NW, x = -1, y = 1, requiredA = DirectionBits.N, requiredB = DirectionBits.W },
})

local function getCoordinate(coordRaw: any): (number, number)
	if typeof(coordRaw) == "Vector2" then
		return math.floor(coordRaw.X), math.floor(coordRaw.Y)
	end
	if typeof(coordRaw) == "table" then
		local x = (coordRaw :: any).x or (coordRaw :: any).X or (coordRaw :: any).tileX
		local y = (coordRaw :: any).y or (coordRaw :: any).Y or (coordRaw :: any).tileY
		if typeof(x) == "number" and typeof(y) == "number" then
			return math.floor(x), math.floor(y)
		end
	end
	return 0, 0
end

local function getTile(accessorRaw: any, x: number, y: number): any?
	if typeof(accessorRaw) == "function" then
		return accessorRaw(x, y)
	end
	if typeof(accessorRaw) ~= "table" then
		return nil
	end

	local getTileMethod = (accessorRaw :: any).GetTile or (accessorRaw :: any).getTile
	if typeof(getTileMethod) == "function" then
		return getTileMethod(accessorRaw, x, y)
	end

	local getTileAtCoordMethod = (accessorRaw :: any).GetTileAtCoord or (accessorRaw :: any).getTileAtCoord
	if typeof(getTileAtCoordMethod) == "function" then
		return getTileAtCoordMethod(accessorRaw, Vector2.new(x, y))
	end

	return nil
end

local function getTileId(tileRaw: any): number?
	if typeof(tileRaw) ~= "table" then
		return nil
	end

	local tileId = (tileRaw :: any).TileId or (tileRaw :: any).tileId or (tileRaw :: any).id
	if typeof(tileId) ~= "number" then
		return nil
	end
	return math.floor(tileId)
end

local function connects(ruleRaw: any, tile: any, neighbor: any): boolean
	local rule = if typeof(ruleRaw) == "table" then ruleRaw else EightWayBlobRule
	local connectsMethod = (rule :: any).Connects or (rule :: any).connects or (rule :: any).CanConnect
	if typeof(connectsMethod) == "function" then
		return connectsMethod(tile, neighbor) == true
	end
	return EightWayBlobRule.Connects(tile, neighbor)
end

function MaskResolver.Resolve(accessorRaw: any, coordRaw: any, ruleRaw: any?): number
	local x, y = getCoordinate(coordRaw)
	local centerTile = getTile(accessorRaw, x, y)
	if centerTile == nil then
		return 0
	end

	local rule = if typeof(ruleRaw) == "table" then ruleRaw else EightWayBlobRule
	local mask = 0
	for _, direction in CARDINAL_DIRECTIONS do
		local neighbor = getTile(accessorRaw, x + direction.x, y + direction.y)
		if connects(rule, centerTile, neighbor) then
			mask = bit32.bor(mask, direction.bit)
		end
	end

	if (rule :: any).IncludeDiagonals == false then
		return bit32.band(mask, DirectionBits.CardinalMask)
	end

	for _, direction in DIAGONAL_DIRECTIONS do
		if bit32.band(mask, direction.requiredA) == 0 or bit32.band(mask, direction.requiredB) == 0 then
			continue
		end

		local neighbor = getTile(accessorRaw, x + direction.x, y + direction.y)
		if connects(rule, centerTile, neighbor) then
			mask = bit32.bor(mask, direction.bit)
		end
	end

	return bit32.band(mask, DirectionBits.AllMask)
end

function MaskResolver.ResolveTileMasks(
	accessorRaw: any,
	coordRaw: any,
	tileIdRaw: any,
	mergeTileIdsRaw: any?,
	connectTileIdsRaw: any?
): (number, number)
	local x, y = getCoordinate(coordRaw)
	local tileId = if typeof(tileIdRaw) == "number"
		then math.floor(tileIdRaw)
		else getTileId(getTile(accessorRaw, x, y))
	if tileId == nil then
		return 0, 0
	end

	local mergeTileIds = if typeof(mergeTileIdsRaw) == "table" then mergeTileIdsRaw else {}
	local connectTileIds = if typeof(connectTileIdsRaw) == "table" then connectTileIdsRaw else {}
	local sameMask = 0
	local mergeMask = 0
	for _, direction in DirectionBits.Offsets do
		local neighborTileId = getTileId(getTile(accessorRaw, x + direction.x, y + direction.y))
		if neighborTileId == nil then
			continue
		end

		if neighborTileId ~= tileId and rawget(mergeTileIds, neighborTileId) == true then
			mergeMask = bit32.bor(mergeMask, direction.bit)
		elseif neighborTileId == tileId or rawget(connectTileIds, neighborTileId) == true then
			sameMask = bit32.bor(sameMask, direction.bit)
		end
	end

	return bit32.band(sameMask, DirectionBits.AllMask), bit32.band(mergeMask, DirectionBits.AllMask)
end

MaskResolver.GetMask = MaskResolver.Resolve
MaskResolver.GetTileMasks = MaskResolver.ResolveTileMasks

return Table.readonly(MaskResolver)
