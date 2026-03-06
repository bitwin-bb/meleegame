--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeleeServiceUtils = {}
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local SoundServiceUtils = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceUtils)

export type MeleeWeaponConfig = {
	itemId: string,
	displayName: string,
	damage: number,
	cooldown: number,
	slashCooldown: number,
	slashResetCooldown: number,
	swingDuration: number,
	hitboxDuration: number,
	range: number,
	width: number,
	height: number,
	pointCount: number,
	autoRepeatWhileHeld: boolean,
	canHitPlayers: boolean,
	canHitNpcs: boolean,
	animations: { [string]: any }?,
}

local DEFAULT_DAMAGE = 7
local DEFAULT_COOLDOWN = 0.45
local DEFAULT_SLASH_RESET_COOLDOWN = 0.9
local DEFAULT_SWING_DURATION = 1
local DEFAULT_HITBOX_DURATION = 0.2
local DEFAULT_RANGE = 4.6
local DEFAULT_WIDTH = 2.25
local DEFAULT_HEIGHT = 1.8
local DEFAULT_POINT_COUNT = 5
local DEFAULT_AUTO_REPEAT = true
local DEFAULT_CAN_HIT_PLAYERS = true
local DEFAULT_CAN_HIT_NPCS = true
local DEFAULT_FALLBACK_SWING_PADDING = 0.04

local MELEE_ITEM_NAME_HINTS = {
	"sword",
	"blade",
	"dagger",
	"knife",
	"axe",
	"hammer",
	"mace",
	"spear",
	"trident",
	"scythe",
	"club",
}
local MELEE_ITEM_TYPE_HINTS = {
	sword = true,
	blade = true,
	dagger = true,
	knife = true,
	axe = true,
	hammer = true,
	mace = true,
	spear = true,
	trident = true,
	scythe = true,
	club = true,
	melee = true,
}

local ATTACK_SPEED_TO_COOLDOWN = {
	["insanely fast"] = 0.14,
	["very fast"] = 0.2,
	["fast"] = 0.28,
	["normal speed"] = 0.38,
	["normal"] = 0.38,
	["slow"] = 0.52,
	["very slow"] = 0.66,
}
local DEFAULT_TOOL_ANIMATION_LOOKUP_ORDER = {
	"Equip",
	"Idle",
	"StanceTransition",
	"StanceIdle",
	"Swing1",
	"Swing2",
	"Swing3",
	"Unequip",
	"Walk",
}
local DEFAULT_TOOL_SWING_LOOKUP_ORDER = {
	"Swing1",
	"Swing2",
	"Swing3",
	"Swing",
}
local NAMED_ANIMATION_STATE_ALIASES: { [string]: { string } } = {
	Equip = { "equip", "draw", "equipanimation", "drawanimation" },
	Idle = { "idle", "weaponidle", "holdidle", "idleanimation" },
	Unequip = { "unequip", "holster", "sheath", "sheathe", "unequipanimation" },
	StanceTransition = {
		"stancetransition",
		"transitiontostance",
		"enterstance",
		"stancestart",
		"stancetransitionanimation",
	},
	StanceIdle = { "stanceidle", "stance", "combatidle", "readyidle", "stanceidleanimation" },
	Walk = { "walk", "walkcycle", "walkanimation" },
}
local NAMED_ANIMATION_TOKEN_TO_STATE: { [string]: string } = {}

for stateName, aliases in NAMED_ANIMATION_STATE_ALIASES do
	for _, alias in aliases do
		NAMED_ANIMATION_TOKEN_TO_STATE[alias] = stateName
	end
end

MeleeServiceUtils.NETWORK_METHOD_REFRESH_EQUIPPED = "requestRefreshEquipped"
MeleeServiceUtils.NETWORK_METHOD_SET_INPUT_HELD = "requestSetInputHeld"
MeleeServiceUtils.DEFAULT_FALLBACK_SWING_PADDING = DEFAULT_FALLBACK_SWING_PADDING

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
local modulesFolder = if sharedFolder and sharedFolder:IsA("Folder") then sharedFolder:FindFirstChild("Modules") else nil

local cachedDefinitions: { [string]: any } = {}
local cachedWeaponConfigs: { [string]: MeleeWeaponConfig | false } = {}
local cachedItemIdLookup: { [string]: string }? = nil

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeString(valueRaw: any, fallback: string): string
	local value = trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

local function sanitizeItemId(itemIdRaw: any): string?
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return nil
	end
	return itemId
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local numericText = string.match(string.lower(valueRaw), "%-?%d+%.?%d*")
		if numericText ~= nil then
			local parsed = tonumber(numericText)
			if parsed ~= nil and parsed == parsed then
				value = parsed
			end
		end
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function resolveItemIdLookup(): { [string]: string }
	if cachedItemIdLookup ~= nil then
		return cachedItemIdLookup
	end

	cachedItemIdLookup = ItemRegistry.getItemIdLookup()
	return cachedItemIdLookup :: { [string]: string }
end

local function resolveCanonicalItemId(itemIdRaw: any): string?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local itemIdLookup = resolveItemIdLookup()
	local canonicalItemId = itemIdLookup[itemId]
	if canonicalItemId == nil then
		canonicalItemId = itemIdLookup[string.lower(itemId)]
	end
	if canonicalItemId ~= nil then
		return canonicalItemId
	end

	return nil
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeAttackSpeedToCooldown(valueRaw: any, fallback: number): number
	local attackSpeed = string.lower(trim(valueRaw))
	if attackSpeed == "" then
		return fallback
	end
	local fromMap = ATTACK_SPEED_TO_COOLDOWN[attackSpeed]
	if fromMap ~= nil then
		return fromMap
	end
	return fallback
end

local function normalizeTypeToken(valueRaw: any): string
	local normalized = string.lower(trim(valueRaw))
	if normalized == "" then
		return ""
	end
	normalized = string.gsub(normalized, "[%s_%-]+", "")
	return normalized
end

local function normalizeAnimationLookupKey(nameRaw: any): string
	local normalized = string.lower(trim(nameRaw))
	if normalized == "" then
		return ""
	end
	normalized = string.gsub(normalized, "[%s_%-]+", "")
	return normalized
end

local function normalizeNamedAnimationStateKey(nameRaw: any): string?
	local token = normalizeAnimationLookupKey(nameRaw)
	if token == "" then
		return nil
	end
	return NAMED_ANIMATION_TOKEN_TO_STATE[token]
end

local function normalizeAnimationMode(modeRaw: any): string
	local mode = string.lower(trim(modeRaw))
	if mode == "sequence" or mode == "sequential" or mode == "ordered" then
		return "Sequence"
	end
	return "Sequence"
end

local function normalizeAnimationId(animationIdRaw: any): string?
	if typeof(animationIdRaw) == "number" then
		if animationIdRaw <= 0 or animationIdRaw ~= animationIdRaw then
			return nil
		end
		return "rbxassetid://" .. tostring(math.floor(animationIdRaw))
	end

	if typeof(animationIdRaw) ~= "string" then
		return nil
	end

	local text = trim(animationIdRaw)
	if text == "" then
		return nil
	end

	if string.find(text, "rbxassetid://", 1, true) == 1 then
		return text
	end

	local digits = string.match(text, "^%d+$")
	if digits ~= nil then
		return "rbxassetid://" .. digits
	end

	return text
end

local function mergeNamedAnimationsFromSource(
	target: { [string]: any },
	sourceRaw: any,
	parseClip: (clipRaw: any, fallbackNameRaw: any) -> { [string]: any }?
)
	if typeof(sourceRaw) ~= "table" then
		return
	end

	for key, value in sourceRaw do
		local stateKey = normalizeNamedAnimationStateKey(key)
		if stateKey == nil or target[stateKey] ~= nil then
			continue
		end

		local clip = parseClip(value, stateKey)
		if clip ~= nil then
			target[stateKey] = clip
		end
	end
end

local function shallowCopyTable(sourceRaw: any): { [string]: any }
	local copied = {}
	if typeof(sourceRaw) ~= "table" then
		return copied
	end

	for key, value in (sourceRaw :: { [string]: any }) do
		copied[key] = value
	end
	return copied
end

local function findNamedChild(container: Instance?, childName: string): Instance?
	if container == nil then
		return nil
	end
	for _, child in container:GetChildren() do
		if child.Name == childName then
			return child
		end
	end
	return nil
end

local function resolveOptionalNumber(valueRaw: any): number?
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		return valueRaw
	end
	if typeof(valueRaw) == "string" then
		local parsed = tonumber(valueRaw)
		if parsed ~= nil and parsed == parsed then
			return parsed
		end
	end
	return nil
end

local function resolveToolAttributeText(tool: Tool, ...: string): string?
	for _, attributeName in { ... } do
		local attributeValue = sanitizeItemId(tool:GetAttribute(attributeName))
		if attributeValue ~= nil then
			return attributeValue
		end
	end
	return nil
end

function MeleeServiceUtils.resolveToolItemId(toolRaw: any): string?
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		return nil
	end

	local tool = toolRaw :: Tool
	local directItemId = resolveToolAttributeText(tool, "itemId", "ItemId", "ittemId", "id")
	if directItemId ~= nil then
		local canonical = resolveCanonicalItemId(directItemId)
		if canonical ~= nil then
			return canonical
		end
	end

	local fromName = sanitizeItemId(tool.Name)
	if fromName ~= nil then
		return resolveCanonicalItemId(fromName)
	end

	return nil
end

function MeleeServiceUtils.resolveToolItemType(toolRaw: any): string?
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		return nil
	end

	local tool = toolRaw :: Tool
	local itemType = resolveToolAttributeText(tool, "itemType", "ItemType", "itemtype", "type", "Type")
	if itemType == nil then
		return nil
	end

	local normalized = normalizeTypeToken(itemType)
	if normalized == "" then
		return nil
	end
	return normalized
end

function MeleeServiceUtils.isSwordTool(toolRaw: any): boolean
	return MeleeServiceUtils.resolveToolItemType(toolRaw) == "sword"
end

function MeleeServiceUtils.isMeleeTool(toolRaw: any): boolean
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		return false
	end

	local toolItemId = MeleeServiceUtils.resolveToolItemId(toolRaw)
	if toolItemId ~= nil then
		local weaponConfig = MeleeServiceUtils.resolveWeaponConfig(toolItemId)
		if weaponConfig ~= nil then
			return true
		end
	end

	local itemType = MeleeServiceUtils.resolveToolItemType(toolRaw)
	if itemType ~= nil and MELEE_ITEM_TYPE_HINTS[itemType] then
		return true
	end

	return false
end

function MeleeServiceUtils.resolveToolByItemId(characterRaw: any, backpackRaw: any, itemIdRaw: any): Tool?
	local itemId = resolveCanonicalItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local function findInContainer(containerRaw: any): Tool?
		if typeof(containerRaw) ~= "Instance" then
			return nil
		end
		local container = containerRaw :: Instance
		for _, child in container:GetChildren() do
			if not child:IsA("Tool") then
				continue
			end
			local childItemId = MeleeServiceUtils.resolveToolItemId(child)
			if childItemId == itemId then
				return child
			end
		end
		return nil
	end

	local tool = findInContainer(characterRaw)
	if tool ~= nil then
		return tool
	end
	return findInContainer(backpackRaw)
end

function MeleeServiceUtils.resolveToolAnimationOverrides(toolRaw: any, fallbackAnimationsRaw: any): { [string]: any }?
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		if typeof(fallbackAnimationsRaw) == "table" then
			return shallowCopyTable(fallbackAnimationsRaw)
		end
		return nil
	end

	local tool = toolRaw :: Tool
	local animationsContainer = findNamedChild(tool, "Animations")
	if animationsContainer == nil then
		if typeof(fallbackAnimationsRaw) == "table" then
			return shallowCopyTable(fallbackAnimationsRaw)
		end
		return nil
	end

	local indexedAnimations: { { order: number, animation: Animation } } = {}
	for _, descendant in animationsContainer:GetDescendants() do
		if not descendant:IsA("Animation") then
			continue
		end

		local order = sanitizeNumber(descendant:GetAttribute("Order"), #indexedAnimations + 1, -100000, 100000)
		table.insert(indexedAnimations, {
			order = order,
			animation = descendant,
		})
	end

	table.sort(indexedAnimations, function(a, b)
		if a.order == b.order then
			return a.animation.Name < b.animation.Name
		end
		return a.order < b.order
	end)

	if #indexedAnimations <= 0 then
		if typeof(fallbackAnimationsRaw) == "table" then
			return shallowCopyTable(fallbackAnimationsRaw)
		end
		return nil
	end

	local animationConfig = if typeof(fallbackAnimationsRaw) == "table"
		then shallowCopyTable(fallbackAnimationsRaw)
		else {}
	local modeRaw = animationsContainer:GetAttribute("mode")
		or animationsContainer:GetAttribute("animationMode")
		or animationsContainer:GetAttribute("swingMode")
		or tool:GetAttribute("animationMode")
		or tool:GetAttribute("swingMode")
		or animationConfig.mode
	animationConfig.mode = normalizeAnimationMode(modeRaw)
	local stanceDelayRaw = animationsContainer:GetAttribute("stanceDelay")
		or animationsContainer:GetAttribute("weaponStanceDelay")
		or tool:GetAttribute("stanceDelay")
		or tool:GetAttribute("weaponStanceDelay")
		or animationConfig.stanceDelay
	if stanceDelayRaw ~= nil then
		animationConfig.stanceDelay = sanitizeNumber(stanceDelayRaw, 1.35, 0.05, 30)
	end

	local stanceEnabledRaw = animationsContainer:GetAttribute("stanceEnabled")
	if stanceEnabledRaw == nil then
		stanceEnabledRaw = tool:GetAttribute("stanceEnabled")
	end
	if typeof(stanceEnabledRaw) == "boolean" then
		animationConfig.stanceEnabled = stanceEnabledRaw
	end

	local clips = {}
	local animationsByLookupKey: { [string]: Animation } = {}
	for _, indexed in indexedAnimations do
		local lookupKey = normalizeAnimationLookupKey(indexed.animation.Name)
		if lookupKey ~= "" and animationsByLookupKey[lookupKey] == nil then
			animationsByLookupKey[lookupKey] = indexed.animation
		end
	end

	local namedAnimations: { [string]: any } = {}
	if typeof(animationConfig.namedAnimations) == "table" then
		for key, value in (animationConfig.namedAnimations :: { [any]: any }) do
			if typeof(key) == "string" and value ~= nil then
				namedAnimations[key] = value
			end
		end
	end

	for _, animationName in DEFAULT_TOOL_ANIMATION_LOOKUP_ORDER do
		local stateKey = normalizeNamedAnimationStateKey(animationName)
		local namedAnimation = animationsByLookupKey[normalizeAnimationLookupKey(animationName)]
		if stateKey ~= nil and namedAnimation ~= nil then
			namedAnimations[stateKey] = namedAnimation
		end
	end

	for lookupKey, animation in animationsByLookupKey do
		local stateKey = normalizeNamedAnimationStateKey(lookupKey)
		if stateKey ~= nil then
			namedAnimations[stateKey] = animation
		end
	end

	local chosenSwingAnimations: { Animation } = {}
	local chosenSwingSet: { [Animation]: boolean } = {}
	local function pushSwingAnimation(animation: Animation?)
		if animation == nil then
			return
		end
		if chosenSwingSet[animation] then
			return
		end
		chosenSwingSet[animation] = true
		table.insert(chosenSwingAnimations, animation)
	end

	for _, animationName in DEFAULT_TOOL_SWING_LOOKUP_ORDER do
		pushSwingAnimation(animationsByLookupKey[normalizeAnimationLookupKey(animationName)])
	end

	if #chosenSwingAnimations <= 0 then
		for _, indexed in indexedAnimations do
			local lookupKey = normalizeAnimationLookupKey(indexed.animation.Name)
			local isSwingLike = string.find(lookupKey, "swing", 1, true) ~= nil
				or string.find(lookupKey, "attack", 1, true) ~= nil
			if isSwingLike then
				pushSwingAnimation(indexed.animation)
			end
		end
	end

	if #chosenSwingAnimations <= 0 then
		for _, indexed in indexedAnimations do
			pushSwingAnimation(indexed.animation)
		end
	end

	for index, animation in chosenSwingAnimations do
		local speed = resolveOptionalNumber(animation:GetAttribute("speed"))
		local weight = resolveOptionalNumber(animation:GetAttribute("weight"))
		local fadeTime = resolveOptionalNumber(animation:GetAttribute("fadeTime"))
		local duration = resolveOptionalNumber(animation:GetAttribute("duration"))
		table.insert(clips, {
			name = animation.Name ~= "" and animation.Name or ("Swing_%d"):format(index),
			animation = animation,
			speed = if speed ~= nil then sanitizeNumber(speed, 1, 0.01, 4) else nil,
			weight = if weight ~= nil then sanitizeNumber(weight, 1, 0.01, 10) else nil,
			fadeTime = if fadeTime ~= nil then sanitizeNumber(fadeTime, 0.06, 0, 2) else nil,
			cooldown = nil,
			duration = if duration ~= nil then sanitizeNumber(duration, duration, 0.01, 10) else nil,
		})
	end

	animationConfig.clips = clips
	if next(namedAnimations) ~= nil then
		animationConfig.namedAnimations = namedAnimations
	end
	return animationConfig
end

function MeleeServiceUtils.resolveToolSounds(toolRaw: any): { [string]: string }
	local sounds: { [string]: string } = {}
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		return sounds
	end

	local tool = toolRaw :: Tool
	local soundsContainer = findNamedChild(tool, "Sounds")
	if soundsContainer == nil then
		return sounds
	end

	for _, descendant in soundsContainer:GetDescendants() do
		if not descendant:IsA("Sound") then
			continue
		end

		local soundName = trim(descendant.Name)
		if soundName ~= "" then
			local soundAssetId = SoundServiceUtils.resolveSoundAssetId(descendant)
			if soundAssetId ~= nil then
				sounds[soundName] = soundAssetId
				sounds[string.lower(soundName)] = soundAssetId
			end
		end
	end

	return sounds
end

local function normalizeSoundLookupKey(nameRaw: any): string
	local normalized = string.lower(trim(nameRaw))
	if normalized == "" then
		return ""
	end
	return string.gsub(normalized, "[%s_%-]+", "")
end

local function resolveSwingSoundGroupFromName(nameRaw: any): string?
	local normalized = normalizeSoundLookupKey(nameRaw)
	if normalized == "" then
		return nil
	end
	local swingIndexText = string.match(normalized, "^swing([123])")
	if swingIndexText == nil then
		return nil
	end
	return "swing" .. swingIndexText
end

function MeleeServiceUtils.resolveToolSwingSounds(toolRaw: any): { [string]: { string } }
	local swingSounds: { [string]: { string } } = {}
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		return swingSounds
	end

	local tool = toolRaw :: Tool
	local soundsContainer = findNamedChild(tool, "Sounds")
	if soundsContainer == nil then
		return swingSounds
	end

	local function pushSwingSound(groupName: string, soundAssetId: string)
		local bucket = swingSounds[groupName]
		if bucket == nil then
			bucket = {}
			swingSounds[groupName] = bucket
		end
		table.insert(bucket, soundAssetId)
	end

	for _, descendant in soundsContainer:GetDescendants() do
		if not descendant:IsA("Sound") then
			continue
		end

		local groupName = nil :: string?
		local cursor = descendant.Parent
		while cursor ~= nil and cursor ~= soundsContainer do
			groupName = resolveSwingSoundGroupFromName(cursor.Name)
			if groupName ~= nil then
				break
			end
			cursor = cursor.Parent
		end

		if groupName == nil then
			groupName = resolveSwingSoundGroupFromName(descendant.Name)
		end

		if groupName ~= nil then
			local soundAssetId = SoundServiceUtils.resolveSoundAssetId(descendant)
			if soundAssetId ~= nil then
				pushSwingSound(groupName, soundAssetId)
			end
		end
	end

	return swingSounds
end

local function collectStringArray(valueRaw: any): { string }
	local values = {}
	local seen = {}

	local function push(textRaw: any)
		local text = trim(textRaw)
		if text == "" or seen[text] then
			return
		end
		seen[text] = true
		table.insert(values, text)
	end

	if typeof(valueRaw) == "string" then
		push(valueRaw)
		return values
	end

	if typeof(valueRaw) == "table" then
		for _, entry in valueRaw do
			push(entry)
		end
	end

	return values
end

local function normalizeAnimationClip(clipRaw: any, fallbackNameRaw: any): { [string]: any }?
	local fallbackName = sanitizeString(fallbackNameRaw, "Swing")

	if typeof(clipRaw) == "table" then
		local clip = clipRaw :: { [string]: any }
		local animation = if typeof(clip.animation) == "Instance" and clip.animation:IsA("Animation")
			then clip.animation
			else nil
		local animationId = normalizeAnimationId(clip.id)
			or normalizeAnimationId(clip.animationId)
			or normalizeAnimationId(clip.AnimationId)
			or normalizeAnimationId(clip.assetId)
			or normalizeAnimationId(clip.animId)

		if animationId == nil then
			animationId = normalizeAnimationId(clip.animation)
		end

		if animation == nil and animationId == nil then
			return nil
		end

		return {
			name = sanitizeString(clip.name, fallbackName),
			animation = animation,
			id = animationId,
			looped = if typeof(clip.looped) == "boolean" then clip.looped else nil,
			priority = if typeof(clip.priority) == "EnumItem" then clip.priority else nil,
			speed = if typeof(clip.speed) == "number" then clip.speed else nil,
			weight = if typeof(clip.weight) == "number" then clip.weight else nil,
			fadeTime = if typeof(clip.fadeTime) == "number" then clip.fadeTime else nil,
			cooldown = nil,
			duration = if typeof(clip.duration) == "number" then clip.duration else nil,
		}
	end

	if typeof(clipRaw) == "Instance" and clipRaw:IsA("Animation") then
		return {
			name = fallbackName,
			animation = clipRaw,
			id = normalizeAnimationId(clipRaw.AnimationId),
		}
	end

	local animationId = normalizeAnimationId(clipRaw)
	if animationId == nil then
		return nil
	end

	return {
		name = fallbackName,
		id = animationId,
	}
end

local function normalizeAnimationClips(clipsRaw: any): { [number]: { [string]: any } }
	local clips = {}
	if clipsRaw == nil then
		return clips
	end

	if typeof(clipsRaw) ~= "table" then
		local single = normalizeAnimationClip(clipsRaw, "Swing_1")
		if single ~= nil then
			table.insert(clips, single)
		end
		return clips
	end

	local source = clipsRaw :: { [any]: any }
	local numericKeys = {}
	for key in source do
		if typeof(key) == "number" and key == key then
			table.insert(numericKeys, key)
		end
	end
	table.sort(numericKeys)

	local consumedKeys = {}
	local nextFallbackIndex = 1
	for _, numericKey in numericKeys do
		consumedKeys[numericKey] = true
		local fallbackName = ("Swing_%d"):format(nextFallbackIndex)
		nextFallbackIndex += 1
		local clip = normalizeAnimationClip(source[numericKey], fallbackName)
		if clip ~= nil then
			table.insert(clips, clip)
		end
	end

	local remainingEntries = {}
	for key, value in source do
		if not consumedKeys[key] then
			table.insert(remainingEntries, {
				key = key,
				value = value,
			})
		end
	end

	local function resolveSortIndex(entry: { key: any, value: any }): number
		if typeof(entry.key) ~= "string" then
			return 1_000_000
		end
		local normalized = normalizeAnimationLookupKey(entry.key)
		local indexText = string.match(normalized, "^swing(%d+)$")
		if indexText ~= nil then
			local parsed = tonumber(indexText)
			if parsed ~= nil then
				return parsed
			end
		end
		return 1_000_000
	end

	table.sort(remainingEntries, function(a, b)
		local aSortIndex = resolveSortIndex(a)
		local bSortIndex = resolveSortIndex(b)
		if aSortIndex ~= bSortIndex then
			return aSortIndex < bSortIndex
		end
		local aKeyString = tostring(a.key)
		local bKeyString = tostring(b.key)
		return aKeyString < bKeyString
	end)

	for _, entry in remainingEntries do
		local key = entry.key
		local value = entry.value
		local fallbackName = if typeof(key) == "string"
			then key
			else ("Swing_%d"):format(nextFallbackIndex)
		nextFallbackIndex += 1

		local clip: { [string]: any }?
		if typeof(key) == "string"
			and (typeof(value) == "string"
				or typeof(value) == "number"
				or (typeof(value) == "Instance" and value:IsA("Animation"))) then
			clip = normalizeAnimationClip({
				name = key,
				id = value,
			}, fallbackName)
		else
			clip = normalizeAnimationClip(value, fallbackName)
		end

		if clip ~= nil then
			table.insert(clips, clip)
		end
	end

	return clips
end

local function normalizeNamedAnimationClips(
	animationTableRaw: any,
	meleeRaw: any,
	definitionRaw: any
): { [string]: { [string]: any } }?
	local animationTable = if typeof(animationTableRaw) == "table" then (animationTableRaw :: { [string]: any }) else nil
	local melee = if typeof(meleeRaw) == "table" then (meleeRaw :: { [string]: any }) else {}
	local definition = if typeof(definitionRaw) == "table" then (definitionRaw :: { [string]: any }) else {}

	local namedAnimations: { [string]: { [string]: any } } = {}
	local function parseNamedClip(clipRaw: any, fallbackNameRaw: any): { [string]: any }?
		local clip = normalizeAnimationClip(clipRaw, fallbackNameRaw)
		if clip == nil then
			return nil
		end

		local stateKey = if typeof(fallbackNameRaw) == "string" then fallbackNameRaw else nil
		if stateKey == "Idle" or stateKey == "StanceIdle" then
			if clip.looped == nil then
				clip.looped = true
			end
		elseif stateKey == "Equip" or stateKey == "Unequip" or stateKey == "StanceTransition" then
			if clip.looped == nil then
				clip.looped = false
			end
		end
		return clip
	end

	if animationTable ~= nil then
		mergeNamedAnimationsFromSource(namedAnimations, animationTable.namedAnimations, parseNamedClip)
		mergeNamedAnimationsFromSource(namedAnimations, animationTable.named, parseNamedClip)
		mergeNamedAnimationsFromSource(namedAnimations, animationTable, parseNamedClip)
	end

	mergeNamedAnimationsFromSource(namedAnimations, melee.namedAnimations, parseNamedClip)
	mergeNamedAnimationsFromSource(namedAnimations, melee.named, parseNamedClip)
	mergeNamedAnimationsFromSource(namedAnimations, definition.namedAnimations, parseNamedClip)
	mergeNamedAnimationsFromSource(namedAnimations, definition.named, parseNamedClip)

	if next(namedAnimations) == nil then
		return nil
	end
	return namedAnimations
end

local function normalizeItemDefinition(itemId: string, moduleResultRaw: any): any?
	if typeof(moduleResultRaw) ~= "table" then
		return nil
	end

	local moduleResult = moduleResultRaw :: { [string]: any }

	local direct = moduleResult[itemId]
	if typeof(direct) == "table" then
		return direct
	end

	local definition = moduleResult.definition
	if typeof(definition) == "table" then
		return definition
	end

	if moduleResult.name ~= nil or moduleResult.useCase ~= nil or moduleResult.melee ~= nil then
		return moduleResultRaw
	end

	for _, value in moduleResult do
		if typeof(value) ~= "table" then
			continue
		end
		local candidate = value :: { [string]: any }
		if candidate.name ~= nil or candidate.useCase ~= nil or candidate.melee ~= nil then
			return candidate
		end
	end

	return nil
end

local function getItemDefinition(itemIdRaw: any): any?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local canonicalItemId = resolveCanonicalItemId(itemId)
	if canonicalItemId == nil then
		return nil
	end

	local cached = cachedDefinitions[itemId]
	if cached ~= nil then
		return cached
	end
	local canonicalCached = cachedDefinitions[canonicalItemId]
	if canonicalCached ~= nil then
		cachedDefinitions[itemId] = canonicalCached
		return canonicalCached
	end

	local definitionRaw = ItemRegistry.resolveDefinition(canonicalItemId)
	if definitionRaw == nil then
		return nil
	end

	local definition = normalizeItemDefinition(canonicalItemId, definitionRaw)
	if definition == nil then
		return nil
	end

	cachedDefinitions[itemId] = definition
	cachedDefinitions[canonicalItemId] = definition
	local definitionId = sanitizeItemId((definition :: any).id)
	if definitionId ~= nil then
		cachedDefinitions[definitionId] = definition
		cachedDefinitions[string.lower(definitionId)] = definition
	end
	return definition
end

local function looksLikeMeleeWeaponName(itemId: string, displayName: string): boolean
	local haystack = string.lower(itemId .. " " .. displayName)
	for _, hint in MELEE_ITEM_NAME_HINTS do
		if string.find(haystack, hint, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function isMeleeDefinition(itemId: string, definitionRaw: any): boolean
	if typeof(definitionRaw) ~= "table" then
		return false
	end

	local definition = definitionRaw :: { [string]: any }
	if typeof(definition.melee) == "table" then
		return true
	end

	local weaponType = normalizeTypeToken(definition.weaponType)
	local weaponClass = normalizeTypeToken(definition.weaponClass)
	local className = normalizeTypeToken(definition.class)
	if weaponType == "melee" or weaponClass == "melee" or className == "melee" then
		return true
	end

	local itemType = normalizeTypeToken(definition.itemType or definition.type)
	if itemType ~= "" and MELEE_ITEM_TYPE_HINTS[itemType] then
		return true
	end

	local useCase = string.lower(trim(definition.useCase))
	if useCase ~= "weapon" then
		return false
	end

	local displayName = sanitizeString(definition.name, itemId)
	return looksLikeMeleeWeaponName(itemId, displayName)
end

local function sanitizeAnimations(animationsRaw: any, meleeRaw: any, definitionRaw: any): { [string]: any }?
	local animationTable = if typeof(animationsRaw) == "table" then (animationsRaw :: { [string]: any }) else nil
	local melee = if typeof(meleeRaw) == "table" then (meleeRaw :: { [string]: any }) else {}
	local definition = if typeof(definitionRaw) == "table" then (definitionRaw :: { [string]: any }) else {}

	local clipsRaw = nil
	if animationTable ~= nil then
		clipsRaw = animationTable.clips
		if clipsRaw == nil then
			clipsRaw = animationTable.swingAnimations
		end
		if clipsRaw == nil then
			clipsRaw = animationTable.swings
		end
		if clipsRaw == nil then
			clipsRaw = animationTable.animationIds
		end
		if clipsRaw == nil and #animationTable > 0 then
			clipsRaw = animationTable
		end
	end

	if clipsRaw == nil then
		clipsRaw = melee.swingAnimations
			or melee.swings
			or melee.animationIds
			or melee.clips
	end

	if clipsRaw == nil then
		local oneAnimation = melee.animationId
			or melee.animId
			or melee.animation
			or definition.animationId
			or definition.animId
			or definition.animation
		if oneAnimation ~= nil then
			clipsRaw = { oneAnimation }
		end
	end

	if clipsRaw == nil then
		clipsRaw = definition.swingAnimations
			or definition.swings
			or definition.animationIds
	end

	if clipsRaw == nil and animationsRaw ~= nil and typeof(animationsRaw) ~= "table" then
		clipsRaw = { animationsRaw }
	end

	local clips = normalizeAnimationClips(clipsRaw)
	if #clips <= 0 then
		return nil
	end

	local modeRaw = nil
	if animationTable ~= nil then
		modeRaw = animationTable.mode or animationTable.animationMode or animationTable.swingMode
	end
	if modeRaw == nil then
		modeRaw = melee.animationMode or melee.swingMode or definition.animationMode or definition.swingMode
	end

	local markerNamesRaw = if animationTable ~= nil then animationTable.markerNames else nil
	if markerNamesRaw == nil then
		markerNamesRaw = melee.markerNames or definition.markerNames
	end
	local markerNames = collectStringArray(markerNamesRaw)
	local namedAnimations = normalizeNamedAnimationClips(animationTable, melee, definition)

	local stanceDelayRaw = if animationTable ~= nil
		then animationTable.stanceDelay or animationTable.weaponStanceDelay
		else nil
	if stanceDelayRaw == nil then
		stanceDelayRaw = melee.stanceDelay or melee.weaponStanceDelay or definition.stanceDelay or definition.weaponStanceDelay
	end
	local stanceEnabledRaw = if animationTable ~= nil then animationTable.stanceEnabled else nil
	if stanceEnabledRaw == nil then
		stanceEnabledRaw = melee.stanceEnabled or definition.stanceEnabled
	end

	local normalizedAnimations: { [string]: any } = {
		mode = normalizeAnimationMode(modeRaw),
		clips = clips,
	}
	if #markerNames > 0 then
		normalizedAnimations.markerNames = markerNames
	end
	if namedAnimations ~= nil then
		normalizedAnimations.namedAnimations = namedAnimations
	end
	if stanceDelayRaw ~= nil then
		normalizedAnimations.stanceDelay = sanitizeNumber(stanceDelayRaw, 1.35, 0.05, 30)
	end
	if typeof(stanceEnabledRaw) == "boolean" then
		normalizedAnimations.stanceEnabled = stanceEnabledRaw
	end

	return normalizedAnimations
end

local function cloneWeaponConfig(config: MeleeWeaponConfig): MeleeWeaponConfig
	return {
		itemId = config.itemId,
		displayName = config.displayName,
		damage = config.damage,
		cooldown = config.cooldown,
		slashCooldown = config.slashCooldown,
		slashResetCooldown = config.slashResetCooldown,
		swingDuration = config.swingDuration,
		hitboxDuration = config.hitboxDuration,
		range = config.range,
		width = config.width,
		height = config.height,
		pointCount = config.pointCount,
		autoRepeatWhileHeld = config.autoRepeatWhileHeld,
		canHitPlayers = config.canHitPlayers,
		canHitNpcs = config.canHitNpcs,
		animations = config.animations,
	}
end

function MeleeServiceUtils.resolveWeaponConfig(itemIdRaw: any): MeleeWeaponConfig?
	local rawItemId = sanitizeItemId(itemIdRaw)
	if rawItemId == nil then
		return nil
	end

	local itemId = resolveCanonicalItemId(rawItemId)
	if itemId == nil then
		cachedWeaponConfigs[rawItemId] = false
		return nil
	end

	local cached = cachedWeaponConfigs[itemId]
	if cached == nil then
		cached = cachedWeaponConfigs[rawItemId]
	end
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cloneWeaponConfig(cached)
	end

	local definitionRaw = getItemDefinition(itemId)
	if definitionRaw == nil then
		cachedWeaponConfigs[itemId] = false
		cachedWeaponConfigs[rawItemId] = false
		return nil
	end

	if not isMeleeDefinition(itemId, definitionRaw) then
		cachedWeaponConfigs[itemId] = false
		cachedWeaponConfigs[rawItemId] = false
		return nil
	end

	local definition = definitionRaw :: { [string]: any }
	local stats = if typeof(definition.stats) == "table" then definition.stats else {}
	local melee = if typeof(definition.melee) == "table" then definition.melee else {}

	local damage = sanitizeNumber(
		(melee :: any).damage or (stats :: any).dmg or definition.damage,
		DEFAULT_DAMAGE,
		1,
		50000
	)
	local cooldownFromSpeed = sanitizeAttackSpeedToCooldown((stats :: any).attackSpeed, DEFAULT_COOLDOWN)
	local slashCooldown = sanitizeNumber(
		(melee :: any).slashCooldown or (melee :: any).cooldown,
		cooldownFromSpeed,
		0.05,
		10
	)
	local slashResetCooldown = sanitizeNumber(
		(melee :: any).slashResetCooldown or (melee :: any).comboResetCooldown or (melee :: any).resetCooldown,
		math.max(DEFAULT_SLASH_RESET_COOLDOWN, slashCooldown * 2),
		slashCooldown,
		30
	)
	local swingDuration = sanitizeNumber((melee :: any).swingDuration, DEFAULT_SWING_DURATION, 0.05, 5)
	local hitboxDuration = sanitizeNumber((melee :: any).hitboxDuration, math.min(slashCooldown, DEFAULT_HITBOX_DURATION), 0.02, 5)
	local range = sanitizeNumber((melee :: any).range, DEFAULT_RANGE, 1, 30)
	local width = sanitizeNumber((melee :: any).width, DEFAULT_WIDTH, 0.1, 20)
	local height = sanitizeNumber((melee :: any).height, DEFAULT_HEIGHT, 0.1, 20)
	local pointCount = math.max(
		2,
		math.floor(sanitizeNumber((melee :: any).pointCount, DEFAULT_POINT_COUNT, 2, 30))
	)
	local displayName = sanitizeString(definition.name, itemId)

	local weaponConfig: MeleeWeaponConfig = {
		itemId = itemId,
		displayName = displayName,
		damage = damage,
		cooldown = slashCooldown,
		slashCooldown = slashCooldown,
		slashResetCooldown = slashResetCooldown,
		swingDuration = swingDuration,
		hitboxDuration = hitboxDuration,
		range = range,
		width = width,
		height = height,
		pointCount = pointCount,
		autoRepeatWhileHeld = sanitizeBoolean((melee :: any).autoRepeatWhileHeld, DEFAULT_AUTO_REPEAT),
		canHitPlayers = sanitizeBoolean((melee :: any).canHitPlayers, DEFAULT_CAN_HIT_PLAYERS),
		canHitNpcs = sanitizeBoolean((melee :: any).canHitNpcs, DEFAULT_CAN_HIT_NPCS),
		animations = sanitizeAnimations((melee :: any).animations, melee, definition),
	}

	cachedWeaponConfigs[itemId] = weaponConfig
	cachedWeaponConfigs[rawItemId] = weaponConfig
	return cloneWeaponConfig(weaponConfig)
end

function MeleeServiceUtils.buildHitboxPoints(weaponConfigRaw: any): { Vector3 }
	if typeof(weaponConfigRaw) ~= "table" then
		return {}
	end

	local weaponConfig = weaponConfigRaw :: MeleeWeaponConfig
	local range = sanitizeNumber(weaponConfig.range, DEFAULT_RANGE, 1, 30)
	local width = sanitizeNumber(weaponConfig.width, DEFAULT_WIDTH, 0.1, 20)
	local height = sanitizeNumber(weaponConfig.height, DEFAULT_HEIGHT, 0.1, 20)
	local pointCount = math.max(2, math.floor(sanitizeNumber(weaponConfig.pointCount, DEFAULT_POINT_COUNT, 2, 40)))

	local points: { Vector3 } = {}
	local halfWidth = width * 0.5
	local startY = 1
	local yScale = math.max(0.1, height)

	for pointIndex = 0, pointCount do
		local alpha = pointIndex / pointCount
		local z = -(range * alpha)
		local y = startY + yScale * alpha
		table.insert(points, Vector3.new(0, y, z))
		table.insert(points, Vector3.new(halfWidth, y, z))
		table.insert(points, Vector3.new(-halfWidth, y, z))
	end

	return points
end

function MeleeServiceUtils.createMeleeClassConfig(weaponConfigRaw: any, overridesRaw: any): { [string]: any }?
	if typeof(weaponConfigRaw) ~= "table" then
		return nil
	end

	local weaponConfig = weaponConfigRaw :: MeleeWeaponConfig
	local overrides = if typeof(overridesRaw) == "table" then overridesRaw else {}
	local overrideAnimations = (overrides :: any).animations
	local weaponAnimations = weaponConfig.animations
	local animations = if overrideAnimations ~= nil then overrideAnimations else weaponAnimations
	local callbacks = if typeof((overrides :: any).callbacks) == "table" then (overrides :: any).callbacks else {}

	return {
		enabled = true,
		autoRepeatWhileHeld = if typeof((overrides :: any).autoRepeatWhileHeld) == "boolean"
			then (overrides :: any).autoRepeatWhileHeld
			else weaponConfig.autoRepeatWhileHeld,
		namedAnimationPlaybackEnabled = sanitizeBoolean((overrides :: any).namedAnimationPlaybackEnabled, true),
		stanceEnabled = if typeof((overrides :: any).stanceEnabled) == "boolean"
			then (overrides :: any).stanceEnabled
			else nil,
		stanceDelay = if (overrides :: any).stanceDelay ~= nil
			then sanitizeNumber((overrides :: any).stanceDelay, 1.35, 0.05, 30)
			else nil,
		cooldown = weaponConfig.slashCooldown,
		slashResetCooldown = weaponConfig.slashResetCooldown,
		fallbackSwingDuration = weaponConfig.swingDuration,
		fallbackSwingPadding = sanitizeNumber(
			(overrides :: any).fallbackSwingPadding,
			DEFAULT_FALLBACK_SWING_PADDING,
			0,
			2
		),
		syntheticSwingEventsWhenMissing = true,
		syntheticAttackWhenNoTrack = true,
		trackAllKeyframes = false,
		animations = animations,
		callbacks = callbacks,
		character = (overrides :: any).character,
		humanoid = (overrides :: any).humanoid,
		animator = (overrides :: any).animator,
	}
end

local function resolveClipComparableToken(clipRaw: any): string
	if typeof(clipRaw) == "Instance" and clipRaw:IsA("Animation") then
		local animationId = normalizeAnimationId(clipRaw.AnimationId)
		if animationId ~= nil then
			return animationId
		end
		return clipRaw:GetFullName()
	end

	if typeof(clipRaw) ~= "table" then
		local normalizedDirectId = normalizeAnimationId(clipRaw)
		if normalizedDirectId ~= nil then
			return normalizedDirectId
		end
		return ""
	end

	local clip = clipRaw :: { [string]: any }
	local normalizedId = normalizeAnimationId(clip.id)
		or normalizeAnimationId(clip.animationId)
		or normalizeAnimationId(clip.AnimationId)
		or normalizeAnimationId(clip.assetId)
		or normalizeAnimationId(clip.animId)

	if normalizedId ~= nil then
		return normalizedId
	end

	local animation = clip.animation
	if typeof(animation) == "Instance" and animation:IsA("Animation") then
		local animationId = normalizeAnimationId(animation.AnimationId)
		if animationId ~= nil then
			return animationId
		end
		return animation:GetFullName()
	end

	return ""
end

local function resolveNamedAnimationComparableTokens(namedRaw: any): { [string]: string }
	local comparable: { [string]: string } = {}
	if typeof(namedRaw) ~= "table" then
		return comparable
	end

	for key, value in (namedRaw :: { [any]: any }) do
		local normalizedKey = normalizeNamedAnimationStateKey(key)
		if normalizedKey == nil then
			if typeof(key) == "string" and trim(key) ~= "" then
				normalizedKey = key
			else
				continue
			end
		end

		local token = resolveClipComparableToken(value)
		if token ~= "" then
			comparable[normalizedKey] = token
		end
	end

	return comparable
end

function MeleeServiceUtils.areAnimationConfigsEquivalent(lhsRaw: any, rhsRaw: any): boolean
	if lhsRaw == rhsRaw then
		return true
	end
	if lhsRaw == nil or rhsRaw == nil then
		return false
	end
	if typeof(lhsRaw) ~= "table" or typeof(rhsRaw) ~= "table" then
		return false
	end

	local lhs = lhsRaw :: { [string]: any }
	local rhs = rhsRaw :: { [string]: any }
	local lhsMode = normalizeAnimationMode(lhs.mode)
	local rhsMode = normalizeAnimationMode(rhs.mode)
	if lhsMode ~= rhsMode then
		return false
	end

	local lhsClips = normalizeAnimationClips(lhs.clips)
	local rhsClips = normalizeAnimationClips(rhs.clips)
	if #lhsClips ~= #rhsClips then
		return false
	end

	for clipIndex = 1, #lhsClips do
		local lhsToken = resolveClipComparableToken(lhsClips[clipIndex])
		local rhsToken = resolveClipComparableToken(rhsClips[clipIndex])
		if lhsToken ~= rhsToken then
			return false
		end
	end

	local lhsNamedComparable = resolveNamedAnimationComparableTokens(lhs.namedAnimations)
	local rhsNamedComparable = resolveNamedAnimationComparableTokens(rhs.namedAnimations)
	local lhsNamedCount = 0
	local rhsNamedCount = 0
	for _ in lhsNamedComparable do
		lhsNamedCount += 1
	end
	for _ in rhsNamedComparable do
		rhsNamedCount += 1
	end
	if lhsNamedCount ~= rhsNamedCount then
		return false
	end
	for key, lhsToken in lhsNamedComparable do
		if rhsNamedComparable[key] ~= lhsToken then
			return false
		end
	end

	local lhsStanceDelay = sanitizeNumber(lhs.stanceDelay, -1, -1, 30)
	local rhsStanceDelay = sanitizeNumber(rhs.stanceDelay, -1, -1, 30)
	if lhsStanceDelay ~= rhsStanceDelay then
		return false
	end

	local lhsStanceEnabled = if typeof(lhs.stanceEnabled) == "boolean" then lhs.stanceEnabled else nil
	local rhsStanceEnabled = if typeof(rhs.stanceEnabled) == "boolean" then rhs.stanceEnabled else nil
	if lhsStanceEnabled ~= rhsStanceEnabled then
		return false
	end

	return true
end

function MeleeServiceUtils.resolveSelectedItemIdFromInventoryState(stateRaw: any): (string?, number?)
	if typeof(stateRaw) ~= "table" then
		return nil, nil
	end

	local state = stateRaw :: { [string]: any }
	local selectedSlotRaw = state.selectedSlot
	if typeof(selectedSlotRaw) ~= "number" or selectedSlotRaw ~= selectedSlotRaw then
		return nil, nil
	end

	local selectedSlot = math.floor(selectedSlotRaw)
	local slots = state.slots
	if typeof(slots) ~= "table" then
		return nil, selectedSlot
	end

	local slot = slots[selectedSlot]
	if typeof(slot) ~= "table" then
		return nil, selectedSlot
	end

	local stack = (slot :: any).stack
	if typeof(stack) ~= "table" then
		return nil, selectedSlot
	end

	local itemId = sanitizeItemId((stack :: any).itemId)
	return itemId, selectedSlot
end

return MeleeServiceUtils
