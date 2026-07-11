local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local DirectionBits = require("DirectionBits")

local MaskAliases = {}

local function createCardinalAliases(): { [number]: number }
	local aliases = {}
	for mask = 0, DirectionBits.AllMask do
		local cardinalMask = bit32.band(mask, DirectionBits.CardinalMask)
		if cardinalMask ~= mask then
			aliases[mask] = cardinalMask
		end
	end
	return aliases
end

MaskAliases.CardinalAliases = Table.readonly(createCardinalAliases())

function MaskAliases.CreateCardinalAliases(): { [number]: number }
	return table.clone(MaskAliases.CardinalAliases)
end

function MaskAliases.Resolve(aliasesRaw: any, maskRaw: any): number?
	if typeof(maskRaw) ~= "number" then
		return nil
	end
	if typeof(aliasesRaw) ~= "table" then
		return nil
	end

	local mask = bit32.band(math.floor(maskRaw), DirectionBits.AllMask)
	local alias = (aliasesRaw :: any)[mask]
	if typeof(alias) ~= "number" then
		return nil
	end
	return bit32.band(math.floor(alias), DirectionBits.AllMask)
end

return Table.readonly(MaskAliases)
