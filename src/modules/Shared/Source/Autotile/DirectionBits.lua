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

function DirectionBits.MirrorHorizontal(maskRaw: any): number
	local mask = if typeof(maskRaw) == "number" then bit32.band(math.floor(maskRaw), DirectionBits.AllMask) else 0
	local mirrored = bit32.band(mask, DirectionBits.N + DirectionBits.S)

	if bit32.band(mask, DirectionBits.E) ~= 0 then
		mirrored = bit32.bor(mirrored, DirectionBits.W)
	end
	if bit32.band(mask, DirectionBits.W) ~= 0 then
		mirrored = bit32.bor(mirrored, DirectionBits.E)
	end
	if bit32.band(mask, DirectionBits.NE) ~= 0 then
		mirrored = bit32.bor(mirrored, DirectionBits.NW)
	end
	if bit32.band(mask, DirectionBits.NW) ~= 0 then
		mirrored = bit32.bor(mirrored, DirectionBits.NE)
	end
	if bit32.band(mask, DirectionBits.SE) ~= 0 then
		mirrored = bit32.bor(mirrored, DirectionBits.SW)
	end
	if bit32.band(mask, DirectionBits.SW) ~= 0 then
		mirrored = bit32.bor(mirrored, DirectionBits.SE)
	end

	return mirrored
end

return Table.readonly(DirectionBits)
