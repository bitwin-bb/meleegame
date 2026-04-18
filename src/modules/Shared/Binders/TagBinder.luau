--!strict

local CollectionService = game:GetService("CollectionService")

local TagBinder = {}

local function trimTag(valueRaw: any): string?
	if typeof(valueRaw) ~= "string" then
		return nil
	end

	local value = string.match(valueRaw, "^%s*(.-)%s*$")
	if value == nil or value == "" then
		return nil
	end

	return value
end

local function copyStringList(source: { string }): { string }
	local list = table.create(#source)
	for index, value in source do
		list[index] = value
	end
	return list
end

local function freezeDictionary<T>(source: T): T
	return table.freeze(source)
end

local Tags = freezeDictionary({
	Npc = "Npc",
	Npc_Slime = "Npc_Slime",
	Npc_Flying = "Npc_Flying",
	Npc_Ground = "Npc_Ground",
	Boss = "Boss",
	Boss_EyeOfCthulhu = "Boss_EyeOfCthulhu",
	Unit = "Unit",
	Hitbox = "Hitbox",
	Loot = "Loot",
	Drop = "Drop",
	Pickup = "Pickup",
	Station = "Station",
	Station_Workbench = "Station_Workbench",
	Station_Furnace = "Station_Furnace",
	Station_Anvil = "Station_Anvil",
	Station_AlchemyTable = "Station_AlchemyTable",
	Placeable = "Placeable",
	Placeable_Torch = "Placeable_Torch",
	Placeable_Workbench = "Placeable_Workbench",
	Light_Torch = "Light_Torch",
	Foliage = "Foliage",
	Disturber = "Disturber",
	Ragdoll = "Ragdoll",
	Gore = "Gore",
	Gore_Slime = "Gore_Slime",
	Gore_Humanoid = "Gore_Humanoid",
	Gore_Boss = "Gore_Boss",
	Melee = "Melee",
	Melee_Shortsword = "Melee_Shortsword",
	Melee_Broadsword = "Melee_Broadsword",
	Melee_Katana = "Melee_Katana",
	Magic = "Magic",
	Use = "Use",
	Chunk = "Chunk",
	Character = "Character",
	Hazard = "Hazard",
	Hazard_Lava = "Hazard_Lava",
	Hazard_Spikes = "Hazard_Spikes",
	Hazard_Poison = "Hazard_Poison",
	Liquid = "Liquid",
	Breath = "Breath",
	Breath_Water = "Breath_Water",
	Breath_Air = "Breath_Air",
	Audio = "Audio",
	Layer = "Layer",
	Preview = "Preview",
	Breakable = "Breakable",
})

local LegacyAliases = freezeDictionary({
	[Tags.Station_Workbench] = table.freeze({ "CraftingStation_Workbench" }),
	[Tags.Station_Furnace] = table.freeze({ "CraftingStation_Furnace" }),
	[Tags.Station_Anvil] = table.freeze({ "CraftingStation_Anvil" }),
	[Tags.Station_AlchemyTable] = table.freeze({ "CraftingStation_AlchemyTable" }),
	[Tags.Light_Torch] = table.freeze({ "LightSource_Torch" }),
	[Tags.Foliage] = table.freeze({ "WindFoliage" }),
	[Tags.Disturber] = table.freeze({ "WindFoliageDisturber" }),
})

local ImpliedTags = freezeDictionary({
	[Tags.Npc] = table.freeze({ Tags.Unit }),
	[Tags.Npc_Slime] = table.freeze({ Tags.Npc }),
	[Tags.Npc_Flying] = table.freeze({ Tags.Npc }),
	[Tags.Npc_Ground] = table.freeze({ Tags.Npc }),
	[Tags.Boss] = table.freeze({ Tags.Unit }),
	[Tags.Boss_EyeOfCthulhu] = table.freeze({ Tags.Boss }),
	[Tags.Character] = table.freeze({ Tags.Unit }),
	[Tags.Station_Workbench] = table.freeze({ Tags.Station, Tags.Use }),
	[Tags.Station_Furnace] = table.freeze({ Tags.Station, Tags.Use }),
	[Tags.Station_Anvil] = table.freeze({ Tags.Station, Tags.Use }),
	[Tags.Station_AlchemyTable] = table.freeze({ Tags.Station, Tags.Use }),
	[Tags.Placeable_Torch] = table.freeze({ Tags.Placeable, Tags.Light_Torch }),
	[Tags.Placeable_Workbench] = table.freeze({ Tags.Placeable, Tags.Station_Workbench }),
	[Tags.Gore_Slime] = table.freeze({ Tags.Gore }),
	[Tags.Gore_Humanoid] = table.freeze({ Tags.Gore }),
	[Tags.Gore_Boss] = table.freeze({ Tags.Gore }),
	[Tags.Melee_Shortsword] = table.freeze({ Tags.Melee }),
	[Tags.Melee_Broadsword] = table.freeze({ Tags.Melee }),
	[Tags.Melee_Katana] = table.freeze({ Tags.Melee }),
	[Tags.Hazard_Lava] = table.freeze({ Tags.Hazard }),
	[Tags.Hazard_Spikes] = table.freeze({ Tags.Hazard }),
	[Tags.Hazard_Poison] = table.freeze({ Tags.Hazard }),
	[Tags.Breath_Water] = table.freeze({ Tags.Breath }),
	[Tags.Breath_Air] = table.freeze({ Tags.Breath }),
})

local CanonicalTags = {}
local CanonicalTagLookup = {} :: { [string]: boolean }
local CanonicalByAlias = {} :: { [string]: string }
local DirectImplyingTags = {} :: { [string]: { string } }

for _, canonicalTag in Tags do
	CanonicalTags[#CanonicalTags + 1] = canonicalTag
	CanonicalTagLookup[canonicalTag] = true
	CanonicalByAlias[canonicalTag] = canonicalTag
end

for canonicalTag, aliases in LegacyAliases do
	for _, alias in aliases do
		CanonicalByAlias[alias] = canonicalTag
	end
end

for sourceTag, impliedList in ImpliedTags do
	for _, impliedTag in impliedList do
		local implyingList = DirectImplyingTags[impliedTag]
		if implyingList == nil then
			implyingList = {}
			DirectImplyingTags[impliedTag] = implyingList
		end
		implyingList[#implyingList + 1] = sourceTag
	end
end

local function normalizeTagList(tagsRaw: any): { string }
	local normalized = {}
	local seen = {} :: { [string]: boolean }

	local function appendTag(tagRaw: any)
		local tag = TagBinder.getCanonicalTag(tagRaw)
		if tag == nil or seen[tag] == true then
			return
		end

		seen[tag] = true
		normalized[#normalized + 1] = tag
	end

	if typeof(tagsRaw) == "table" then
		for _, tagRaw in tagsRaw do
			appendTag(tagRaw)
		end
	else
		appendTag(tagsRaw)
	end

	return normalized
end

local function collectImpliedTags(canonicalTag: string, output: { string }, seen: { [string]: boolean })
	local implied = ImpliedTags[canonicalTag]
	if implied == nil then
		return
	end

	for _, impliedTag in implied do
		if seen[impliedTag] == true then
			continue
		end

		seen[impliedTag] = true
		output[#output + 1] = impliedTag
		collectImpliedTags(impliedTag, output, seen)
	end
end

local function collectObservedTags(canonicalTag: string, output: { string }, seen: { [string]: boolean })
	if seen[canonicalTag] ~= true then
		seen[canonicalTag] = true
		output[#output + 1] = canonicalTag
	end

	local aliases = LegacyAliases[canonicalTag]
	if aliases ~= nil then
		for _, alias in aliases do
			if seen[alias] == true then
				continue
			end

			seen[alias] = true
			output[#output + 1] = alias
		end
	end

	local implyingTags = DirectImplyingTags[canonicalTag]
	if implyingTags == nil then
		return
	end

	for _, implyingTag in implyingTags do
		collectObservedTags(implyingTag, output, seen)
	end
end

local function getTagService(collectionServiceRaw: any?): any
	if collectionServiceRaw ~= nil then
		return collectionServiceRaw
	end

	return CollectionService
end

local function addCanonicalTag(
	instance: Instance,
	canonicalTag: string,
	tagService: any,
	seen: { [string]: boolean }
)
	if seen[canonicalTag] == true then
		return
	end

	seen[canonicalTag] = true
	if not tagService:HasTag(instance, canonicalTag) then
		tagService:AddTag(instance, canonicalTag)
	end

	local implied = ImpliedTags[canonicalTag]
	if implied == nil then
		return
	end

	for _, impliedTag in implied do
		addCanonicalTag(instance, impliedTag, tagService, seen)
	end
end

function TagBinder.getCanonicalTag(tagRaw: any): string?
	local tag = trimTag(tagRaw)
	if tag == nil then
		return nil
	end

	return CanonicalByAlias[tag]
end

function TagBinder.getCanonicalTags(): { string }
	return copyStringList(CanonicalTags)
end

function TagBinder.normalizeTags(tagsRaw: any): { string }
	return normalizeTagList(tagsRaw)
end

function TagBinder.getLegacyAliases(tagRaw: any): { string }
	local canonicalTag = TagBinder.getCanonicalTag(tagRaw)
	if canonicalTag == nil then
		return {}
	end

	local aliases = LegacyAliases[canonicalTag]
	if aliases == nil then
		return {}
	end

	return copyStringList(aliases)
end

function TagBinder.getImpliedTags(tagRaw: any): { string }
	local canonicalTag = TagBinder.getCanonicalTag(tagRaw)
	if canonicalTag == nil then
		return {}
	end

	local output = {}
	local seen = {} :: { [string]: boolean }
	collectImpliedTags(canonicalTag, output, seen)
	return output
end

function TagBinder.getObservedTags(tagRaw: any): { string }
	local canonicalTag = TagBinder.getCanonicalTag(tagRaw)
	if canonicalTag == nil then
		return {}
	end

	local output = {}
	local seen = {} :: { [string]: boolean }
	collectObservedTags(canonicalTag, output, seen)
	return output
end

function TagBinder.hasTag(instanceRaw: any, tagRaw: any, collectionServiceRaw: any?): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end

	local observedTags = TagBinder.getObservedTags(tagRaw)
	if #observedTags <= 0 then
		return false
	end

	local tagService = getTagService(collectionServiceRaw)
	for _, observedTag in observedTags do
		if tagService:HasTag(instanceRaw, observedTag) then
			return true
		end
	end

	return false
end

function TagBinder.hasAnyTag(instanceRaw: any, tagsRaw: any, collectionServiceRaw: any?): boolean
	for _, tag in normalizeTagList(tagsRaw) do
		if TagBinder.hasTag(instanceRaw, tag, collectionServiceRaw) then
			return true
		end
	end

	return false
end

function TagBinder.getMatchedTags(instanceRaw: any, tagsRaw: any, collectionServiceRaw: any?): { string }
	local matched = {}
	for _, tag in normalizeTagList(tagsRaw) do
		if TagBinder.hasTag(instanceRaw, tag, collectionServiceRaw) then
			matched[#matched + 1] = tag
		end
	end
	return matched
end

function TagBinder.applyTag(instanceRaw: any, tagRaw: any, collectionServiceRaw: any?): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end

	local canonicalTag = TagBinder.getCanonicalTag(tagRaw)
	if canonicalTag == nil then
		return false
	end

	local instance = instanceRaw :: Instance
	local tagService = getTagService(collectionServiceRaw)
	local rawTag = trimTag(tagRaw)
	if rawTag ~= nil and rawTag ~= canonicalTag and not tagService:HasTag(instance, rawTag) then
		tagService:AddTag(instance, rawTag)
	end

	addCanonicalTag(instance, canonicalTag, tagService, {})
	return true
end

function TagBinder.applyTags(instanceRaw: any, tagsRaw: any, collectionServiceRaw: any?): number
	if typeof(instanceRaw) ~= "Instance" then
		return 0
	end

	local appliedCount = 0
	for _, tag in normalizeTagList(tagsRaw) do
		if TagBinder.applyTag(instanceRaw, tag, collectionServiceRaw) then
			appliedCount += 1
		end
	end

	return appliedCount
end

function TagBinder.getTagged(tagRaw: any, collectionServiceRaw: any?): { Instance }
	local observedTags = TagBinder.getObservedTags(tagRaw)
	if #observedTags <= 0 then
		return {}
	end

	local tagService = getTagService(collectionServiceRaw)
	local seen = {} :: { [Instance]: boolean }
	local results = {}

	for _, observedTag in observedTags do
		for _, instance in tagService:GetTagged(observedTag) do
			if seen[instance] == true then
				continue
			end

			seen[instance] = true
			results[#results + 1] = instance
		end
	end

	return results
end

TagBinder.Tags = Tags
TagBinder.LegacyAliases = LegacyAliases
TagBinder.ImpliedTags = ImpliedTags
TagBinder.CanonicalTagLookup = CanonicalTagLookup

TagBinder.getCanonicalTag = TagBinder.getCanonicalTag
TagBinder.getCanonicalTags = TagBinder.getCanonicalTags
TagBinder.normalizeTags = TagBinder.normalizeTags
TagBinder.getLegacyAliases = TagBinder.getLegacyAliases
TagBinder.getImpliedTags = TagBinder.getImpliedTags
TagBinder.getObservedTags = TagBinder.getObservedTags
TagBinder.hasTag = TagBinder.hasTag
TagBinder.hasAnyTag = TagBinder.hasAnyTag
TagBinder.getMatchedTags = TagBinder.getMatchedTags
TagBinder.applyTag = TagBinder.applyTag
TagBinder.applyTags = TagBinder.applyTags
TagBinder.getTagged = TagBinder.getTagged

return TagBinder
