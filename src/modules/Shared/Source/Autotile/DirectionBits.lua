local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local DirectionBits = {
	N = 1,
	E = 2,
	S = 4,
	W = 8,
	NE = 16,
	SE = 32,
	SW = 64,
	NW = 128,
}

DirectionBits.CardinalMask = DirectionBits.N + DirectionBits.E + DirectionBits.S + DirectionBits.W
DirectionBits.DiagonalMask = DirectionBits.NE + DirectionBits.SE + DirectionBits.SW + DirectionBits.NW
DirectionBits.AllMask = DirectionBits.CardinalMask + DirectionBits.DiagonalMask

DirectionBits.Offsets = Table.readonly({
	{ bit = DirectionBits.N, x = 0, y = 1 },
	{ bit = DirectionBits.E, x = 1, y = 0 },
	{ bit = DirectionBits.S, x = 0, y = -1 },
	{ bit = DirectionBits.W, x = -1, y = 0 },
	{ bit = DirectionBits.NE, x = 1, y = 1, required = { DirectionBits.N, DirectionBits.E } },
	{ bit = DirectionBits.SE, x = 1, y = -1, required = { DirectionBits.S, DirectionBits.E } },
	{ bit = DirectionBits.SW, x = -1, y = -1, required = { DirectionBits.S, DirectionBits.W } },
	{ bit = DirectionBits.NW, x = -1, y = 1, required = { DirectionBits.N, DirectionBits.W } },
})

return Table.readonly(DirectionBits)
