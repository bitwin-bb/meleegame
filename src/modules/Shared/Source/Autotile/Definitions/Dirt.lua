local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuildServiceUtils = require("BuildServiceUtils")
local DirectionBits = require("DirectionBits")

local function createVariants(cellA: Vector2, cellB: Vector2, cellC: Vector2): any
	return {
		Variants = {
			{ Cell = cellA },
			{ Cell = cellB },
			{ Cell = cellC },
		},
	}
end

local SelfFrameEntries = {
	[0] = createVariants(Vector2.new(9, 3), Vector2.new(10, 3), Vector2.new(11, 3)),
	[1] = createVariants(Vector2.new(6, 3), Vector2.new(7, 3), Vector2.new(8, 3)),
	[2] = createVariants(Vector2.new(12, 0), Vector2.new(12, 1), Vector2.new(12, 2)),
	[3] = createVariants(Vector2.new(15, 2), Vector2.new(15, 2), Vector2.new(15, 2)),
	[4] = createVariants(Vector2.new(9, 0), Vector2.new(9, 1), Vector2.new(9, 2)),
	[5] = createVariants(Vector2.new(13, 2), Vector2.new(13, 2), Vector2.new(13, 2)),
	[6] = createVariants(Vector2.new(6, 4), Vector2.new(7, 4), Vector2.new(8, 4)),
	[7] = createVariants(Vector2.new(14, 2), Vector2.new(14, 2), Vector2.new(14, 2)),
	[8] = createVariants(Vector2.new(6, 0), Vector2.new(7, 0), Vector2.new(8, 0)),
	[9] = createVariants(Vector2.new(5, 0), Vector2.new(5, 1), Vector2.new(5, 2)),
	[10] = createVariants(Vector2.new(15, 0), Vector2.new(15, 0), Vector2.new(15, 0)),
	[11] = createVariants(Vector2.new(15, 1), Vector2.new(15, 1), Vector2.new(15, 1)),
	[12] = createVariants(Vector2.new(13, 0), Vector2.new(13, 0), Vector2.new(13, 0)),
	[13] = createVariants(Vector2.new(13, 1), Vector2.new(13, 1), Vector2.new(13, 1)),
	[14] = createVariants(Vector2.new(14, 0), Vector2.new(14, 0), Vector2.new(14, 0)),
	[15] = createVariants(Vector2.new(14, 1), Vector2.new(14, 1), Vector2.new(14, 1)),
	[19] = createVariants(Vector2.new(1, 4), Vector2.new(3, 4), Vector2.new(5, 4)),
	[31] = createVariants(Vector2.new(13, 4), Vector2.new(13, 4), Vector2.new(13, 4)),
	[37] = createVariants(Vector2.new(0, 4), Vector2.new(2, 4), Vector2.new(4, 4)),
	[47] = createVariants(Vector2.new(12, 4), Vector2.new(12, 4), Vector2.new(12, 4)),
	[55] = createVariants(Vector2.new(1, 2), Vector2.new(2, 2), Vector2.new(3, 2)),
	[63] = createVariants(Vector2.new(6, 2), Vector2.new(7, 2), Vector2.new(8, 2)),
	[74] = createVariants(Vector2.new(1, 3), Vector2.new(3, 3), Vector2.new(5, 3)),
	[79] = createVariants(Vector2.new(13, 3), Vector2.new(13, 3), Vector2.new(13, 3)),
	[91] = createVariants(Vector2.new(4, 0), Vector2.new(4, 1), Vector2.new(4, 2)),
	[95] = createVariants(Vector2.new(11, 0), Vector2.new(11, 1), Vector2.new(11, 2)),
	[127] = createVariants(Vector2.new(14, 3), Vector2.new(14, 3), Vector2.new(14, 3)),
	[140] = createVariants(Vector2.new(0, 3), Vector2.new(2, 3), Vector2.new(4, 3)),
	[143] = createVariants(Vector2.new(12, 3), Vector2.new(12, 3), Vector2.new(12, 3)),
	[173] = createVariants(Vector2.new(0, 0), Vector2.new(0, 1), Vector2.new(0, 2)),
	[175] = createVariants(Vector2.new(10, 0), Vector2.new(10, 1), Vector2.new(10, 2)),
	[191] = createVariants(Vector2.new(15, 3), Vector2.new(15, 3), Vector2.new(15, 3)),
	[206] = createVariants(Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(3, 0)),
	[207] = createVariants(Vector2.new(6, 1), Vector2.new(7, 1), Vector2.new(8, 1)),
	[223] = createVariants(Vector2.new(14, 4), Vector2.new(14, 4), Vector2.new(14, 4)),
	[239] = createVariants(Vector2.new(15, 4), Vector2.new(15, 4), Vector2.new(15, 4)),
	[255] = createVariants(Vector2.new(1, 1), Vector2.new(2, 1), Vector2.new(3, 1)),
}

local function hasBit(mask: number, bit: number): boolean
	return bit32.band(mask, bit) ~= 0
end

local function translateMaskToSelfFrame(mask: number): number
	local selfFrameMask = 0
	if hasBit(mask, DirectionBits.N) then
		selfFrameMask += 1
	end
	if hasBit(mask, DirectionBits.W) then
		selfFrameMask += 2
	end
	if hasBit(mask, DirectionBits.E) then
		selfFrameMask += 4
	end
	if hasBit(mask, DirectionBits.S) then
		selfFrameMask += 8
	end
	if hasBit(mask, DirectionBits.NW) then
		selfFrameMask += 16
	end
	if hasBit(mask, DirectionBits.NE) then
		selfFrameMask += 32
	end
	if hasBit(mask, DirectionBits.SW) then
		selfFrameMask += 64
	end
	if hasBit(mask, DirectionBits.SE) then
		selfFrameMask += 128
	end
	return selfFrameMask
end

local function getSelfFrameEntry(mask: number): any
	local selfFrameMask = translateMaskToSelfFrame(mask)
	local entry = SelfFrameEntries[selfFrameMask]
	if entry ~= nil then
		return entry
	end

	local cardinalMask = bit32.band(mask, DirectionBits.CardinalMask)
	return SelfFrameEntries[translateMaskToSelfFrame(cardinalMask)] or SelfFrameEntries[0]
end

local function createEntries(): any
	local entries = {}
	for mask = 0, DirectionBits.AllMask do
		entries[mask] = getSelfFrameEntry(mask)
	end
	return entries
end

local Entries = createEntries()

return Table.readonly({
	Id = "Dirt",
	TileId = BuildServiceUtils.TILE_ID.DIRT,
	Image = "rbxassetid://115586684643692",
	TileSize = 16,
	Padding = 0,
	Spacing = 2,
	UseSurfaceGui = true,
	Mode = "EightWayBlob",
	ConnectGroup = "Soil",
	Entries = Entries,
	Fallback = Entries[0],
})
