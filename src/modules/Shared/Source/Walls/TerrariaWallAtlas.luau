local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local DirectionBits = require("DirectionBits")
local RectUtil = require("RectUtil")
local VariantPicker = require("VariantPicker")

local TerrariaWallAtlas = {}

TerrariaWallAtlas.Name = "TerrariaWall"
TerrariaWallAtlas.FrameSize = Vector2.new(32, 32)
TerrariaWallAtlas.FrameSpacing = 4
TerrariaWallAtlas.LogicalTilePixels = 16
TerrariaWallAtlas.FrameWorldScale = 2

TerrariaWallAtlas.StyleBits = Table.readonly({
	Up = 1,
	Left = 2,
	Right = 4,
	Down = 8,
})

local STYLE_CELLS = Table.deepReadonly({
	[0] = { Vector2.new(9, 3), Vector2.new(10, 3), Vector2.new(11, 3) },
	[1] = { Vector2.new(6, 3), Vector2.new(7, 3), Vector2.new(8, 3) },
	[2] = { Vector2.new(12, 0), Vector2.new(12, 1), Vector2.new(12, 2) },
	[3] = { Vector2.new(1, 4), Vector2.new(3, 4), Vector2.new(5, 4) },
	[4] = { Vector2.new(9, 0), Vector2.new(9, 1), Vector2.new(9, 2) },
	[5] = { Vector2.new(0, 4), Vector2.new(2, 4), Vector2.new(4, 4) },
	[6] = { Vector2.new(6, 4), Vector2.new(7, 4), Vector2.new(8, 4) },
	[7] = { Vector2.new(1, 2), Vector2.new(2, 2), Vector2.new(3, 2) },
	[8] = { Vector2.new(6, 0), Vector2.new(7, 0), Vector2.new(8, 0) },
	[9] = { Vector2.new(5, 0), Vector2.new(5, 1), Vector2.new(5, 2) },
	[10] = { Vector2.new(1, 3), Vector2.new(3, 3), Vector2.new(5, 3) },
	[11] = { Vector2.new(4, 0), Vector2.new(4, 1), Vector2.new(4, 2) },
	[12] = { Vector2.new(0, 3), Vector2.new(2, 3), Vector2.new(4, 3) },
	[13] = { Vector2.new(0, 0), Vector2.new(0, 1), Vector2.new(0, 2) },
	[14] = { Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(3, 0) },
	[15] = { Vector2.new(1, 1), Vector2.new(2, 1), Vector2.new(3, 1) },
	[16] = { Vector2.new(6, 1), Vector2.new(7, 1), Vector2.new(8, 1) },
	[17] = { Vector2.new(6, 2), Vector2.new(7, 2), Vector2.new(8, 2) },
	[18] = { Vector2.new(10, 0), Vector2.new(10, 1), Vector2.new(10, 2) },
	[19] = { Vector2.new(11, 0), Vector2.new(11, 1), Vector2.new(11, 2) },
})

local CENTER_STYLE_OFFSETS = Table.deepReadonly({
	[0] = { [0] = 2, [1] = 0, [2] = 0 },
	[1] = { [0] = 0, [1] = 1, [2] = 3 },
	[2] = { [0] = 0, [1] = 4, [2] = 0 },
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

function TerrariaWallAtlas.ToStyleMask(maskRaw: any): number
	local mask = if typeof(maskRaw) == "number" then bit32.band(math.floor(maskRaw), DirectionBits.CardinalMask) else 0
	local styleMask = 0
	if bit32.band(mask, DirectionBits.N) ~= 0 then
		styleMask = bit32.bor(styleMask, TerrariaWallAtlas.StyleBits.Up)
	end
	if bit32.band(mask, DirectionBits.W) ~= 0 then
		styleMask = bit32.bor(styleMask, TerrariaWallAtlas.StyleBits.Left)
	end
	if bit32.band(mask, DirectionBits.E) ~= 0 then
		styleMask = bit32.bor(styleMask, TerrariaWallAtlas.StyleBits.Right)
	end
	if bit32.band(mask, DirectionBits.S) ~= 0 then
		styleMask = bit32.bor(styleMask, TerrariaWallAtlas.StyleBits.Down)
	end
	return styleMask
end

function TerrariaWallAtlas.GetStyle(maskRaw: any, coordRaw: any?): number
	local styleMask = TerrariaWallAtlas.ToStyleMask(maskRaw)
	if styleMask ~= 15 then
		return styleMask
	end

	local x, y = getCoordinate(coordRaw)
	return 15 + CENTER_STYLE_OFFSETS[y % 3][x % 3]
end

function TerrariaWallAtlas.GetCell(styleRaw: any, frameNumberRaw: any): Vector2?
	if typeof(styleRaw) ~= "number" then
		return nil
	end
	local cells = STYLE_CELLS[math.floor(styleRaw)]
	if cells == nil then
		return nil
	end

	local frameNumber = if typeof(frameNumberRaw) == "number" then math.floor(frameNumberRaw) else 0
	return cells[math.clamp(frameNumber, 0, 2) + 1]
end

function TerrariaWallAtlas.Resolve(definitionRaw: any, maskRaw: any, coordRaw: any?, seedRaw: any?): any?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end

	local definition = definitionRaw :: any
	local styleMask = TerrariaWallAtlas.ToStyleMask(maskRaw)
	local style = TerrariaWallAtlas.GetStyle(maskRaw, coordRaw)
	local frameNumber = VariantPicker.GetTerrariaVariantIndex(coordRaw, seedRaw) - 1
	local cell = TerrariaWallAtlas.GetCell(style, frameNumber)
	if cell == nil then
		return nil
	end

	local rect = RectUtil.FromCell(
		cell,
		definition.FrameSize or TerrariaWallAtlas.FrameSize,
		definition.Padding,
		definition.Spacing or TerrariaWallAtlas.FrameSpacing,
		definition.ImageRectScale
	)
	return {
		Image = if typeof(definition.Image) == "string" then definition.Image else "",
		ImageRectOffset = rect.ImageRectOffset,
		ImageRectSize = rect.ImageRectSize,
		Mask = if typeof(maskRaw) == "number" then bit32.band(math.floor(maskRaw), DirectionBits.CardinalMask) else 0,
		WallStyleMask = styleMask,
		Style = style,
		FrameNumber = frameNumber,
		Cell = cell,
		Definition = definition,
	}
end

return Table.readonly(TerrariaWallAtlas)
