local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AutotileTypes = require("AutotileTypes")
local BuildServiceUtils = require("BuildServiceUtils")
local DirectionBits = require("DirectionBits")

local function createEntry(cell: Vector2): any
	return {
		Variants = {
			{ Cell = cell },
		},
	}
end

local TerrainEntries = {
	[0] = createEntry(Vector2.new(9, 3)),
	[1] = createEntry(Vector2.new(6, 3)),
	[2] = createEntry(Vector2.new(12, 0)),
	[3] = createEntry(Vector2.new(1, 4)),
	[4] = createEntry(Vector2.new(9, 0)),
	[5] = createEntry(Vector2.new(0, 4)),
	[6] = createEntry(Vector2.new(6, 4)),
	[7] = createEntry(Vector2.new(13, 1)),
	[8] = createEntry(Vector2.new(6, 0)),
	[9] = createEntry(Vector2.new(5, 0)),
	[10] = createEntry(Vector2.new(1, 3)),
	[11] = createEntry(Vector2.new(4, 0)),
	[12] = createEntry(Vector2.new(0, 3)),
	[13] = createEntry(Vector2.new(0, 0)),
	[14] = createEntry(Vector2.new(1, 0)),
	[15] = createEntry(Vector2.new(1, 1)),
}

local function hasBit(mask: number, bit: number): boolean
	return bit32.band(mask, bit) ~= 0
end

local function translateCardinalMask(mask: number): number
	local terrainMask = 0
	if hasBit(mask, DirectionBits.N) then
		terrainMask += 1
	end
	if hasBit(mask, DirectionBits.W) then
		terrainMask += 2
	end
	if hasBit(mask, DirectionBits.E) then
		terrainMask += 4
	end
	if hasBit(mask, DirectionBits.S) then
		terrainMask += 8
	end
	return terrainMask
end

local function createEntries(): any
	local entries = {}
	for mask = 0, DirectionBits.AllMask do
		local cardinalMask = bit32.band(mask, DirectionBits.CardinalMask)
		entries[mask] = TerrainEntries[translateCardinalMask(cardinalMask)] or TerrainEntries[0]
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
	Mode = AutotileTypes.Modes.EightWayBlob,
	ConnectGroup = "Soil",
	Entries = Entries,
	Fallback = Entries[0],
})
