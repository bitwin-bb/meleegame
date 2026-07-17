local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local DirectionBits = require("DirectionBits")
local MaskAliases = require("MaskAliases")
local RectUtil = require("RectUtil")
local VariantPicker = require("VariantPicker")

local AtlasResolver = {}

local function getEntry(definition: any, mask: number): (any?, number)
	local entries = if typeof(definition.Entries) == "table" then definition.Entries else {}
	local entry = entries[mask]
	if entry ~= nil then
		return entry, mask
	end

	local alias = MaskAliases.Resolve(rawget(definition, "Aliases"), mask)
	if alias ~= nil then
		entry = entries[alias]
		if entry ~= nil then
			return entry, alias
		end
	end

	local fallback = definition.Fallback
	if typeof(fallback) == "table" then
		return fallback, mask
	end

	return nil, mask
end

local function resolveEntryVariant(entry: any, coordRaw: any, mask: number, seedRaw: any?): any?
	if typeof(entry) ~= "table" then
		return nil
	end

	local variants = (entry :: any).Variants
	if typeof(variants) == "table" then
		local variant = VariantPicker.Pick(variants, coordRaw, mask, seedRaw)
		if variant ~= nil then
			return variant
		end
	end

	return entry
end

function AtlasResolver.Resolve(definitionRaw: any, maskRaw: any, coordRaw: any?, seedRaw: any?): any?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end
	local definition = definitionRaw :: any
	local requestedMask = if typeof(maskRaw) == "number"
		then bit32.band(math.floor(maskRaw), DirectionBits.AllMask)
		else 0
	local entry, resolvedMask = getEntry(definition, requestedMask)
	local selectedEntry = resolveEntryVariant(entry, coordRaw, resolvedMask, seedRaw or rawget(definition, "VariantSeed"))
	if typeof(selectedEntry) ~= "table" then
		return nil
	end

	local cell = (selectedEntry :: any).Cell
	if typeof(cell) ~= "Vector2" then
		return nil
	end

	local rect = RectUtil.FromCell(
		cell,
		definition.TileSize,
		rawget(definition, "Padding"),
		rawget(definition, "Spacing"),
		rawget(definition, "ImageRectScale")
	)
	return {
		Image = if typeof((selectedEntry :: any).Image) == "string"
			then (selectedEntry :: any).Image
			else definition.Image,
		ImageRectOffset = rect.ImageRectOffset,
		ImageRectSize = rect.ImageRectSize,
		Mask = resolvedMask,
		RequestedMask = requestedMask,
		Cell = cell,
		Entry = selectedEntry,
	}
end

AtlasResolver.Get = AtlasResolver.Resolve

return Table.readonly(AtlasResolver)
