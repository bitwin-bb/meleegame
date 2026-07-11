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

function RectUtil.FromCell(
	cellRaw: any,
	tileSizeRaw: any,
	paddingRaw: any?,
	spacingRaw: any?
): {
	ImageRectOffset: Vector2,
	ImageRectSize: Vector2,
}
	local cell = if typeof(cellRaw) == "Vector2" then cellRaw else Vector2.zero
	local tileSize = coerceSize(tileSizeRaw)
	local padding = coerceNumber(paddingRaw, 0)
	local spacing = coerceNumber(spacingRaw, 0)

	return {
		ImageRectOffset = Vector2.new(
			padding + math.floor(cell.X) * (tileSize.X + spacing),
			padding + math.floor(cell.Y) * (tileSize.Y + spacing)
		),
		ImageRectSize = tileSize,
	}
end

RectUtil.GetRect = RectUtil.FromCell

return Table.readonly(RectUtil)
