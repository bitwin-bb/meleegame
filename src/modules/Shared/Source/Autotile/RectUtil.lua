local require = require(script.Parent.loader).load(script)

local Math = require("Math")
local Table = require("Table")

local RectUtil = {}

local function coerceNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or not Math.isFinite(valueRaw) then
		return fallback
	end
	return valueRaw
end

local function coerceSize(tileSizeRaw: any): Vector2
	if typeof(tileSizeRaw) == "Vector2" then
		return Vector2.new(math.max(0, tileSizeRaw.X), math.max(0, tileSizeRaw.Y))
	end

	local tileSize = math.max(0, coerceNumber(tileSizeRaw, 16))
	return Vector2.new(tileSize, tileSize)
end

local function coerceScale(scaleRaw: any): Vector2
	if typeof(scaleRaw) == "Vector2" then
		if Math.isFinite(scaleRaw.X) and Math.isFinite(scaleRaw.Y) and scaleRaw.X > 0 and scaleRaw.Y > 0 then
			return scaleRaw
		end
	elseif typeof(scaleRaw) == "number" and Math.isFinite(scaleRaw) and scaleRaw > 0 then
		return Vector2.new(scaleRaw, scaleRaw)
	end

	return Vector2.new(1, 1)
end

function RectUtil.FromCell(
	cellRaw: any,
	tileSizeRaw: any,
	paddingRaw: any?,
	spacingRaw: any?,
	imageRectScaleRaw: any?
): {
	ImageRectOffset: Vector2,
	ImageRectSize: Vector2,
}
	local cell = if typeof(cellRaw) == "Vector2" then cellRaw else Vector2.zero
	local tileSize = coerceSize(tileSizeRaw)
	local padding = coerceNumber(paddingRaw, 0)
	local spacing = coerceNumber(spacingRaw, 0)
	local imageRectScale = coerceScale(imageRectScaleRaw)
	local logicalOffset = Vector2.new(
		padding + math.floor(cell.X) * (tileSize.X + spacing),
		padding + math.floor(cell.Y) * (tileSize.Y + spacing)
	)

	return {
		ImageRectOffset = Vector2.new(logicalOffset.X * imageRectScale.X, logicalOffset.Y * imageRectScale.Y),
		ImageRectSize = Vector2.new(tileSize.X * imageRectScale.X, tileSize.Y * imageRectScale.Y),
	}
end

RectUtil.GetRect = RectUtil.FromCell

return Table.readonly(RectUtil)
