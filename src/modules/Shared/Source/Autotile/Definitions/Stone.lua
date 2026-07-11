local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuildServiceUtils = require("BuildServiceUtils")
local MaskAliases = require("MaskAliases")

local Entries = {
	[0] = { Cell = Vector2.new(0, 0) },
	[1] = { Cell = Vector2.new(1, 0) },
	[2] = { Cell = Vector2.new(2, 0) },
	[3] = { Cell = Vector2.new(3, 0) },
	[4] = { Cell = Vector2.new(0, 1) },
	[5] = { Cell = Vector2.new(1, 1) },
	[6] = { Cell = Vector2.new(2, 1) },
	[7] = { Cell = Vector2.new(3, 1) },
	[8] = { Cell = Vector2.new(0, 2) },
	[9] = { Cell = Vector2.new(1, 2) },
	[10] = { Cell = Vector2.new(2, 2) },
	[11] = { Cell = Vector2.new(3, 2) },
	[12] = { Cell = Vector2.new(0, 3) },
	[13] = { Cell = Vector2.new(1, 3) },
	[14] = { Cell = Vector2.new(2, 3) },
	[15] = { Cell = Vector2.new(3, 3) },
	[255] = {
		Variants = {
			{ Cell = Vector2.new(0, 4), Weight = 70 },
			{ Cell = Vector2.new(1, 4), Weight = 30 },
		},
	},
}

return Table.readonly({
	Id = "Stone",
	TileId = BuildServiceUtils.TILE_ID.STONE,
	Image = "rbxassetid://1000000005",
	TileSize = 16,
	Padding = 0,
	Spacing = 0,
	Mode = "EightWayBlob",
	ConnectGroup = "Stone",
	Entries = Entries,
	Aliases = MaskAliases.CardinalAliases,
	Fallback = Entries[0],
})
