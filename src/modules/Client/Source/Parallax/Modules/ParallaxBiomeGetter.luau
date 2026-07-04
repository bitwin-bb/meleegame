local require = require(script.Parent.loader).load(script)

local Table: any = require("Table")

local Profile = require("ParallaxProfiles")
local WorldSimulationShared = require("Shared")

local Biome = {}

local Styles = Profile.Styles

local BIOME_TYPE_CORRUPTION = 2

local TOKEN_STYLES = Table.deepReadonly({
	corruption = Styles.Corruption,
	corrupt = Styles.Corruption,
	evil = Styles.Corruption,
	desert = Styles.Desert,
	sand = Styles.Desert,
	dunes = Styles.Desert,
	jungle = Styles.Jungle,
	rainforest = Styles.Jungle,
	snow = Styles.Snow,
	tundra = Styles.Snow,
	ice = Styles.Snow,
	overworld = Styles.Overworld,
	forest = Styles.Overworld,
	default = Styles.Overworld,
	surface = Styles.Overworld,
})

local function GetStyleFromToken(token: string): number?
	return TOKEN_STYLES[token]
end

local function normalizeToken(valueRaw: any): string
	if typeof(valueRaw) == "number" then
		local biomeId = valueRaw
		if biomeId == WorldSimulationShared.BIOME_ID.DESERT then
			return "desert"
		end
		if biomeId == WorldSimulationShared.BIOME_ID.SNOW then
			return "snow"
		end
		if biomeId == WorldSimulationShared.BIOME_ID.JUNGLE then
			return "jungle"
		end
		if biomeId == WorldSimulationShared.BIOME_ID.CORRUPTION then
			return "corruption"
		end
		return "overworld"
	end
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	local value = string.lower(valueRaw)
	value = string.gsub(value, "%s+", "")
	value = string.gsub(value, "_", "")
	value = string.gsub(value, "%-", "")
	return value
end

local function GetStyleFromValue(valueRaw: any, catalog: any?): number?
	local token = normalizeToken(valueRaw)
	if token == "" then
		return nil
	end

	local style = GetStyleFromToken(token)
	if style ~= nil then
		return style
	end

	if typeof(catalog) == "table" and typeof(catalog.aliases) == "table" then
		local aliasTarget = catalog.aliases[token]
		if typeof(aliasTarget) == "string" then
			return GetStyleFromToken(normalizeToken(aliasTarget))
		end
	end

	return nil
end

local function GetCorruptionTypeStyle(sample: { [string]: any }, catalog: any?): number?
	if sample.biomeType == BIOME_TYPE_CORRUPTION then
		return Styles.Corruption
	end

	local biomeTypeNameStyle = GetStyleFromValue(sample.biomeTypeName, catalog)
	if biomeTypeNameStyle == Styles.Corruption then
		return Styles.Corruption
	end

	if typeof(sample.biomeType) == "string" then
		local biomeTypeStyle = GetStyleFromValue(sample.biomeType, catalog)
		if biomeTypeStyle == Styles.Corruption then
			return Styles.Corruption
		end
	end

	return nil
end

local function GetExplicitStyle(sample: { [string]: any }, catalog: any?): number?
	local corruptionTypeStyle = GetCorruptionTypeStyle(sample, catalog)
	if corruptionTypeStyle ~= nil then
		return corruptionTypeStyle
	end

	local biomeNameStyle = GetStyleFromValue(sample.biomeName, catalog)
	if biomeNameStyle ~= nil then
		return biomeNameStyle
	end

	local biomeIdStyle = GetStyleFromValue(sample.biomeId, catalog)
	if biomeIdStyle ~= nil then
		return biomeIdStyle
	end

	local surfaceBiomeIdStyle = GetStyleFromValue(sample.surfaceBiomeId, catalog)
	if surfaceBiomeIdStyle ~= nil then
		return surfaceBiomeIdStyle
	end

	return nil
end

local function collectTokens(sample: { [string]: any }, catalog: any?): { string }
	local tokens: { string } = {}
	local function append(valueRaw: any)
		local token = normalizeToken(valueRaw)
		if token ~= "" then
			table.insert(tokens, token)
			if typeof(catalog) == "table" and typeof(catalog.aliases) == "table" then
				local aliasTarget = catalog.aliases[token]
				if typeof(aliasTarget) == "string" then
					table.insert(tokens, normalizeToken(aliasTarget))
				end
			end
		end
	end

	append(sample.biomeName)
	append(sample.biomeId)
	append(sample.biomeTypeName)
	if typeof(sample.biomeType) == "string" then
		append(sample.biomeType)
	end
	append(sample.surfaceBiomeId)

	if sample.isHallow == true then
		append("hallow")
	end
	if sample.isCorruption == true or sample.isEvil == true then
		append("corruption")
	end
	if sample.isCrimson == true or sample.isBlood == true then
		append("crimson")
	end
	if sample.isMushroom == true or sample.isShroom == true then
		append("mushroom")
	end
	if sample.isDesert == true or sample.isSand == true then
		append("desert")
	end

	return tokens
end

local function hasToken(tokens: { string }, options: { string }): boolean
	for _, token in tokens do
		if Table.contains(options, token) then
			return true
		end
	end
	return false
end

local function isPositiveNumber(valueRaw: any): boolean
	return typeof(valueRaw) == "number" and valueRaw > 0
end

function Biome.GetBgStyle(sampleRaw: any, catalog: any?): number
	local sample = if typeof(sampleRaw) == "table" then sampleRaw :: { [string]: any } else {} :: { [string]: any }
	local explicitStyle = GetExplicitStyle(sample, catalog)
	if explicitStyle ~= nil then
		return explicitStyle
	end

	local tokens = collectTokens(sample, catalog)

	local isCorruption = hasToken(tokens, { "corruption", "corrupt", "evil" })
		or sample.biomeType == BIOME_TYPE_CORRUPTION
	local isDesert = hasToken(tokens, { "desert", "sand", "dunes" }) or isPositiveNumber(sample.sandTileCount)

	if isCorruption then
		return Styles.Corruption
	end
	if hasToken(tokens, { "jungle", "rainforest" }) then
		return Styles.Jungle
	end
	if hasToken(tokens, { "snow", "tundra", "ice" }) then
		return Styles.Snow
	end
	if isDesert then
		return Styles.Desert
	end
	return Styles.Overworld
end


return Biome
