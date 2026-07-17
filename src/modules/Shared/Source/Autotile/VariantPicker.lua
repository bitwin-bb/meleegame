local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local Rand = require("Rand")

local VariantPicker = {}

local UINT32_MOD = 4294967296

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

local function getWeight(entryRaw: any): number
	if typeof(entryRaw) ~= "table" then
		return 0
	end
	local weight = (entryRaw :: any).Weight or (entryRaw :: any).weight
	if typeof(weight) ~= "number" then
		return 1
	end
	return math.max(0, weight)
end

function VariantPicker.GetSeed(coordRaw: any, maskRaw: any, seedRaw: any?): number
	local x, y = getCoordinate(coordRaw)
	local mask = if typeof(maskRaw) == "number" then math.floor(maskRaw) else 0
	local seed = Rand.Seed(seedRaw)
	return Rand.HashCoordinates(seed, x, y, mask)
end

function VariantPicker.GetTerrariaVariantIndex(coordRaw: any, seedRaw: any?): number
	local x, y = getCoordinate(coordRaw)
	local seed = Rand.Seed(seedRaw)
	return (Rand.HashCoordinates(seed, x + 104729, y + 130363, 486187739) % 3) + 1
end

function VariantPicker.Pick<T>(variantsRaw: { T }, coordRaw: any, maskRaw: any, seedRaw: any?): T?
	if typeof(variantsRaw) ~= "table" or #variantsRaw <= 0 then
		return nil
	end
	if #variantsRaw == 1 then
		return variantsRaw[1]
	end

	local totalWeight = 0
	for _, variant in variantsRaw do
		totalWeight += getWeight(variant)
	end
	if totalWeight <= 0 then
		return variantsRaw[1]
	end

	local stableSeed = VariantPicker.GetSeed(coordRaw, maskRaw, seedRaw)
	local roll = (stableSeed % UINT32_MOD) / UINT32_MOD * totalWeight
	local runningWeight = 0
	for _, variant in variantsRaw do
		runningWeight += getWeight(variant)
		if roll <= runningWeight then
			return variant
		end
	end

	return variantsRaw[#variantsRaw]
end

return Table.readonly(VariantPicker)
