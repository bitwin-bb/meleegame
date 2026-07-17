local require = require(script.Parent.loader).load(script)

local PlaneUtils = require("PlaneUtils")
local Table = require("Table")

local CullUtil = {}

export type TileBounds = {
	minX: number,
	minY: number,
	maxX: number,
	maxY: number,
}

local MIN_RAY_PLANE_DOT = 0.0001
local DEFAULT_MAX_TILE_SPAN = 1024
local MAX_VIEWPORT_MARGIN_PIXELS = 2048

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function coerceInteger(valueRaw: any, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.floor(valueRaw :: number)
end

local function getPlaneIntersection(camera: Camera, viewportX: number, viewportY: number, planeX: number): Vector3?
	local ray = camera:ViewportPointToRay(viewportX, viewportY)
	if math.abs(ray.Direction.X) < MIN_RAY_PLANE_DOT then
		return nil
	end

	local intersection, distance =
		PlaneUtils.rayIntersection(Vector3.new(planeX, 0, 0), Vector3.xAxis, ray.Origin, ray.Direction)
	if intersection == nil or not isFiniteNumber(distance) or (distance :: number) <= 0 then
		return nil
	end
	if
		not isFiniteNumber(intersection.X)
		or not isFiniteNumber(intersection.Y)
		or not isFiniteNumber(intersection.Z)
	then
		return nil
	end

	return intersection
end

function CullUtil.CreateBounds(minXRaw: any, minYRaw: any, maxXRaw: any, maxYRaw: any): TileBounds?
	local minX = coerceInteger(minXRaw, 0)
	local minY = coerceInteger(minYRaw, 0)
	local maxX = coerceInteger(maxXRaw, minX)
	local maxY = coerceInteger(maxYRaw, minY)
	if maxX <= minX or maxY <= minY then
		return nil
	end

	return {
		minX = minX,
		minY = minY,
		maxX = maxX,
		maxY = maxY,
	}
end

function CullUtil.CloneBounds(bounds: TileBounds?): TileBounds?
	if bounds == nil then
		return nil
	end
	return CullUtil.CreateBounds(bounds.minX, bounds.minY, bounds.maxX, bounds.maxY)
end

function CullUtil.GetChunkBounds(tileMinXRaw: any, tileMinYRaw: any, widthRaw: any, heightRaw: any): TileBounds?
	local tileMinX = coerceInteger(tileMinXRaw, 0)
	local tileMinY = coerceInteger(tileMinYRaw, 0)
	local width = math.max(0, coerceInteger(widthRaw, 0))
	local height = math.max(0, coerceInteger(heightRaw, 0))
	return CullUtil.CreateBounds(tileMinX, tileMinY, tileMinX + width, tileMinY + height)
end

function CullUtil.IntersectBounds(first: TileBounds?, second: TileBounds?): TileBounds?
	if first == nil or second == nil then
		return nil
	end

	return CullUtil.CreateBounds(
		math.max(first.minX, second.minX),
		math.max(first.minY, second.minY),
		math.min(first.maxX, second.maxX),
		math.min(first.maxY, second.maxY)
	)
end

function CullUtil.BoundsEqual(first: TileBounds?, second: TileBounds?): boolean
	if first == second then
		return true
	end
	if first == nil or second == nil then
		return false
	end

	return first.minX == second.minX
		and first.minY == second.minY
		and first.maxX == second.maxX
		and first.maxY == second.maxY
end

function CullUtil.ContainsTile(bounds: TileBounds?, tileX: number, tileY: number): boolean
	return bounds ~= nil
		and tileX >= bounds.minX
		and tileX < bounds.maxX
		and tileY >= bounds.minY
		and tileY < bounds.maxY
end

function CullUtil.GetCameraTileBounds(
	camera: Camera?,
	worldOriginRaw: any,
	basePlaneXRaw: any,
	tileSizeRaw: any,
	viewportMarginPixelsRaw: any?,
	maxTileSpanRaw: any?
): TileBounds?
	if camera == nil then
		return nil
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return nil
	end

	local worldOrigin = if typeof(worldOriginRaw) == "Vector3" then worldOriginRaw :: Vector3 else Vector3.zero
	local basePlaneX = if isFiniteNumber(basePlaneXRaw) then basePlaneXRaw :: number else 0
	local tileSize = if isFiniteNumber(tileSizeRaw) then math.max(0.05, tileSizeRaw :: number) else 1
	local viewportMarginPixels = math.clamp(coerceInteger(viewportMarginPixelsRaw, 0), 0, MAX_VIEWPORT_MARGIN_PIXELS)
	local maxTileSpan = math.max(1, coerceInteger(maxTileSpanRaw, DEFAULT_MAX_TILE_SPAN))
	local planeX = worldOrigin.X + basePlaneX

	local minWorldY = math.huge
	local minWorldZ = math.huge
	local maxWorldY = -math.huge
	local maxWorldZ = -math.huge
	local function includeViewportCorner(viewportX: number, viewportY: number): boolean
		local intersection = getPlaneIntersection(camera, viewportX, viewportY, planeX)
		if intersection == nil then
			return false
		end

		minWorldY = math.min(minWorldY, intersection.Y)
		minWorldZ = math.min(minWorldZ, intersection.Z)
		maxWorldY = math.max(maxWorldY, intersection.Y)
		maxWorldZ = math.max(maxWorldZ, intersection.Z)
		return true
	end

	local viewportMin = -viewportMarginPixels
	local viewportMaxX = viewportSize.X + viewportMarginPixels
	local viewportMaxY = viewportSize.Y + viewportMarginPixels
	if
		not includeViewportCorner(viewportMin, viewportMin)
		or not includeViewportCorner(viewportMaxX, viewportMin)
		or not includeViewportCorner(viewportMin, viewportMaxY)
		or not includeViewportCorner(viewportMaxX, viewportMaxY)
	then
		return nil
	end

	local minTileX = math.floor((minWorldZ - worldOrigin.Z) / tileSize)
	local minTileY = math.floor((minWorldY - worldOrigin.Y) / tileSize)
	local maxTileX = math.ceil((maxWorldZ - worldOrigin.Z) / tileSize)
	local maxTileY = math.ceil((maxWorldY - worldOrigin.Y) / tileSize)
	if maxTileX - minTileX > maxTileSpan or maxTileY - minTileY > maxTileSpan then
		return nil
	end

	return CullUtil.CreateBounds(minTileX, minTileY, maxTileX, maxTileY)
end

return Table.readonly(CullUtil)
