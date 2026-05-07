--!strict

export type TileLookup = (worldX: number, worldY: number, layer: any?) -> any?

export type ChunkLike = {
	chunkX: number?,
	chunkY: number?,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tiles: { any },
}

export type ResolverOptions = {
	airTileId: number?,
	tileMinX: number?,
	tileMinY: number?,
	layer: any?,
	includeDiagonals: boolean?,
	missingIsVisible: boolean?,
	transparentTileIds: { [number]: boolean }?,
	getTileAtWorldCell: TileLookup?,
}

export type DirtyWorldCell = {
	tileX: number,
	tileY: number,
}

export type DirtyBounds = {
	minTileX: number,
	minTileY: number,
	maxTileX: number,
	maxTileY: number,
}

local TileVisibilityResolver = {}

local DEFAULT_AIR_TILE_ID = 0
local CARDINAL_OFFSETS = {
	{ x = -1, y = 0 },
	{ x = 1, y = 0 },
	{ x = 0, y = -1 },
	{ x = 0, y = 1 },
}
local DIAGONAL_OFFSETS = {
	{ x = -1, y = -1 },
	{ x = 1, y = -1 },
	{ x = -1, y = 1 },
	{ x = 1, y = 1 },
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function resolveAirTileId(options: ResolverOptions?): number
	if options ~= nil and isFiniteNumber(options.airTileId) then
		return math.floor(options.airTileId :: number)
	end
	return DEFAULT_AIR_TILE_ID
end

local function resolveTileId(tileRaw: any): number?
	if isFiniteNumber(tileRaw) then
		return math.floor(tileRaw :: number)
	end
	if typeof(tileRaw) ~= "table" then
		return nil
	end

	local tile = tileRaw :: { [any]: any }
	local idRaw = tile.id or tile.tileId or tile.TileId or tile.value
	if isFiniteNumber(idRaw) then
		return math.floor(idRaw :: number)
	end
	if tile.solid == false or tile.isSolid == false then
		return DEFAULT_AIR_TILE_ID
	end
	return nil
end

function TileVisibilityResolver.ComputeTileIndex(localX: number, localY: number, width: number): number
	return localY * width + localX + 1
end

function TileVisibilityResolver.PackChunkKey(chunkX: number, chunkY: number): string
	return `{chunkX}:{chunkY}`
end

function TileVisibilityResolver.ToChunkCoordinate(tile: number, chunkSize: number): number
	return math.floor(tile / math.max(1, math.floor(chunkSize)))
end

function TileVisibilityResolver.IsTileOpaque(tileRaw: any, options: ResolverOptions?): boolean
	if tileRaw == nil then
		return options ~= nil and options.missingIsVisible == false
	end

	if typeof(tileRaw) == "table" then
		local tile = tileRaw :: { [any]: any }
		if tile.opaque ~= nil then
			return tile.opaque == true
		end
		if tile.isOpaque ~= nil then
			return tile.isOpaque == true
		end
		if tile.solid ~= nil then
			return tile.solid == true
		end
		if tile.isSolid ~= nil then
			return tile.isSolid == true
		end
	end

	local tileId = resolveTileId(tileRaw)
	if tileId == nil then
		return false
	end

	local transparentTileIds = if options ~= nil then options.transparentTileIds else nil
	if transparentTileIds ~= nil and transparentTileIds[tileId] == true then
		return false
	end

	return tileId ~= resolveAirTileId(options)
end

function TileVisibilityResolver.GetTileAtChunkCell(
	chunksByKey: { [string]: ChunkLike },
	chunkX: number,
	chunkY: number,
	localX: number,
	localY: number
): any?
	local chunk = chunksByKey[TileVisibilityResolver.PackChunkKey(chunkX, chunkY)]
	if chunk == nil then
		return nil
	end
	if localX < 0 or localX >= chunk.width or localY < 0 or localY >= chunk.height then
		return nil
	end
	return chunk.tiles[TileVisibilityResolver.ComputeTileIndex(localX, localY, chunk.width)]
end

function TileVisibilityResolver.GetTileAtWorldCell(
	chunksByKey: { [string]: ChunkLike },
	worldX: number,
	worldY: number,
	chunkSize: number
): any?
	local chunkX = TileVisibilityResolver.ToChunkCoordinate(worldX, chunkSize)
	local chunkY = TileVisibilityResolver.ToChunkCoordinate(worldY, chunkSize)
	local chunk = chunksByKey[TileVisibilityResolver.PackChunkKey(chunkX, chunkY)]
	if chunk == nil then
		return nil
	end

	local localX = worldX - chunk.tileMinX
	local localY = worldY - chunk.tileMinY
	if localX < 0 or localX >= chunk.width or localY < 0 or localY >= chunk.height then
		return nil
	end

	return chunk.tiles[TileVisibilityResolver.ComputeTileIndex(localX, localY, chunk.width)]
end

function TileVisibilityResolver.ResolveNeighborTile(
	chunksByKey: { [string]: ChunkLike },
	chunk: ChunkLike,
	localX: number,
	localY: number,
	deltaX: number,
	deltaY: number,
	chunkSize: number
): any?
	local worldX = chunk.tileMinX + localX + deltaX
	local worldY = chunk.tileMinY + localY + deltaY
	return TileVisibilityResolver.GetTileAtWorldCell(chunksByKey, worldX, worldY, chunkSize)
end

function TileVisibilityResolver.ShouldRenderTile(tileRaw: any, worldX: number, worldY: number, options: ResolverOptions?): boolean
	if not TileVisibilityResolver.IsTileOpaque(tileRaw, options) then
		return false
	end

	local lookup = if options ~= nil then options.getTileAtWorldCell else nil
	if lookup == nil then
		return true
	end

	local layer = if options ~= nil then options.layer else nil
	for _, offset in CARDINAL_OFFSETS do
		local neighbor = lookup(worldX + offset.x, worldY + offset.y, layer)
		if not TileVisibilityResolver.IsTileOpaque(neighbor, options) then
			return true
		end
	end

	if options ~= nil and options.includeDiagonals == true then
		for _, offset in DIAGONAL_OFFSETS do
			local neighbor = lookup(worldX + offset.x, worldY + offset.y, layer)
			if not TileVisibilityResolver.IsTileOpaque(neighbor, options) then
				return true
			end
		end
	end

	return false
end

function TileVisibilityResolver.BuildVisibleTileMask(
	tiles: { any },
	width: number,
	height: number,
	options: ResolverOptions?
): ({ boolean }, number)
	local tileMinX = if options ~= nil and isFiniteNumber(options.tileMinX) then options.tileMinX :: number else 0
	local tileMinY = if options ~= nil and isFiniteNumber(options.tileMinY) then options.tileMinY :: number else 0
	local tileCount = math.max(0, width * height)
	local visible = table.create(tileCount, false) :: { boolean }
	local visibleCount = 0

	for localY = 0, height - 1 do
		for localX = 0, width - 1 do
			local index = TileVisibilityResolver.ComputeTileIndex(localX, localY, width)
			if TileVisibilityResolver.ShouldRenderTile(tiles[index], tileMinX + localX, tileMinY + localY, options) then
				visible[index] = true
				visibleCount += 1
			end
		end
	end

	return visible, visibleCount
end

function TileVisibilityResolver.BuildVisibleTileValues(
	tiles: { number },
	width: number,
	height: number,
	options: ResolverOptions?
): ({ number }, { boolean }, number)
	local visibleMask, visibleCount = TileVisibilityResolver.BuildVisibleTileMask(tiles, width, height, options)
	local airTileId = resolveAirTileId(options)
	local visibleTiles = table.create(math.max(0, width * height), airTileId) :: { number }

	for index, isVisible in visibleMask do
		if isVisible then
			visibleTiles[index] = tiles[index] or airTileId
		end
	end

	return visibleTiles, visibleMask, visibleCount
end

function TileVisibilityResolver.CollectVisibilityDirtyWorldCells(
	tileX: number,
	tileY: number,
	includeDiagonals: boolean?
): { DirtyWorldCell }
	local cells = {
		{ tileX = tileX, tileY = tileY },
	} :: { DirtyWorldCell }

	for _, offset in CARDINAL_OFFSETS do
		table.insert(cells, {
			tileX = tileX + offset.x,
			tileY = tileY + offset.y,
		})
	end

	if includeDiagonals == true then
		for _, offset in DIAGONAL_OFFSETS do
			table.insert(cells, {
				tileX = tileX + offset.x,
				tileY = tileY + offset.y,
			})
		end
	end

	return cells
end

function TileVisibilityResolver.ComputeDirtyBounds(
	tileX: number,
	tileY: number,
	includeDiagonals: boolean?
): DirtyBounds
	local minTileX = tileX
	local minTileY = tileY
	local maxTileX = tileX
	local maxTileY = tileY

	for _, cell in TileVisibilityResolver.CollectVisibilityDirtyWorldCells(tileX, tileY, includeDiagonals) do
		minTileX = math.min(minTileX, cell.tileX)
		minTileY = math.min(minTileY, cell.tileY)
		maxTileX = math.max(maxTileX, cell.tileX)
		maxTileY = math.max(maxTileY, cell.tileY)
	end

	return {
		minTileX = minTileX,
		minTileY = minTileY,
		maxTileX = maxTileX,
		maxTileY = maxTileY,
	}
end

TileVisibilityResolver.computeTileIndex = TileVisibilityResolver.ComputeTileIndex
TileVisibilityResolver.packChunkKey = TileVisibilityResolver.PackChunkKey
TileVisibilityResolver.toChunkCoordinate = TileVisibilityResolver.ToChunkCoordinate
TileVisibilityResolver.isTileOpaque = TileVisibilityResolver.IsTileOpaque
TileVisibilityResolver.getTileAtChunkCell = TileVisibilityResolver.GetTileAtChunkCell
TileVisibilityResolver.getTileAtWorldCell = TileVisibilityResolver.GetTileAtWorldCell
TileVisibilityResolver.resolveNeighborTile = TileVisibilityResolver.ResolveNeighborTile
TileVisibilityResolver.shouldRenderTile = TileVisibilityResolver.ShouldRenderTile
TileVisibilityResolver.buildVisibleTileMask = TileVisibilityResolver.BuildVisibleTileMask
TileVisibilityResolver.buildVisibleTileValues = TileVisibilityResolver.BuildVisibleTileValues
TileVisibilityResolver.collectVisibilityDirtyWorldCells = TileVisibilityResolver.CollectVisibilityDirtyWorldCells
TileVisibilityResolver.computeDirtyBounds = TileVisibilityResolver.ComputeDirtyBounds

return TileVisibilityResolver
