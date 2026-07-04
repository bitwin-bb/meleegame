local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Sift: any = require(ReplicatedStorage.Packages.Sift)

local ImageIds = require("ImageIds")
local InventoryServiceUtils = require("InventoryServiceUtils")
local ItemIcons = require("ItemIcons")
local ItemRegistry = require("ItemRegistry")
local inventoryThunks = require("InventoryThunks")
local itemSlice = require("ItemSlice")

type InventoryItemStack = InventoryServiceUtils.InventoryItemStack
type ItemDragState = itemSlice.ItemDragState
type ItemDefinition = {
	itemId: string,
	name: string,
	description: string,
	useCase: string?,
	itemType: string?,
	stats: { [string]: any }?,
}

local itemThunks = {}
local cachedItemDefinitions: { [string]: ItemDefinition } = {}

local function joinStrings(values: { string }, delimiter: string): string
	local output = ""
	for index, value in values do
		if index > 1 then
			output ..= delimiter
		end
		output ..= value
	end
	return output
end

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeTypeKey(valueRaw: any): string?
	local value = string.lower(trim(valueRaw))
	if value == "" then
		return nil
	end
	value = string.gsub(value, "[%s_%-]+", "")
	if value == "" then
		return nil
	end
	return value
end

local function CoerceText(valueRaw: any, fallback: string?): string?
	local value = trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

local function toTitleCase(textRaw: any): string
	local value = CoerceText(textRaw, "Item") or "Item"
	value = string.gsub(value, "_", " ")
	value = string.gsub(value, "-", " ")
	value = string.gsub(value, "%s+", " ")
	local title = (string.gsub :: any)(value, "(%a)([%w']*)", function(first: string, rest: string)
		return string.upper(first) .. string.lower(rest)
	end) :: string
	return title
end

local function GetItemTypeFromItemId(itemIdRaw: any): string?
	local itemId = normalizeTypeKey(itemIdRaw)
	if itemId == nil then
		return nil
	end

	if string.find(itemId, "sword", 1, true) ~= nil then
		return "sword"
	end
	if string.find(itemId, "pickaxe", 1, true) ~= nil then
		return "pickaxe"
	end
	if string.find(itemId, "axe", 1, true) ~= nil then
		return "axe"
	end
	if string.find(itemId, "hammer", 1, true) ~= nil then
		return "hammer"
	end
	if string.find(itemId, "coin", 1, true) ~= nil then
		return "coin"
	end
	if string.find(itemId, "crystal", 1, true) ~= nil then
		return "consumable"
	end

	return nil
end

local function normalizeItemDefinition(itemId: string, definitionRaw: any): ItemDefinition?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end

	local definition = definitionRaw :: { [string]: any }
	local itemType = normalizeTypeKey(definition.itemType or definition.type)
	if itemType == nil then
		itemType = GetItemTypeFromItemId(itemId)
	end

	local description = CoerceText(definition.description, nil)
	if description == nil and definition.value ~= nil then
		description = CoerceText(tostring(definition.value), nil)
	end

	return {
		itemId = itemId,
		name = toTitleCase(definition.name or itemId),
		description = description or "No description.",
		useCase = CoerceText(definition.useCase, nil),
		itemType = itemType,
		stats = if typeof(definition.stats) == "table" then definition.stats else nil,
	}
end

local function GetItemDefinition(itemIdRaw: any): ItemDefinition?
	local itemId = CoerceText(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local cached = cachedItemDefinitions[itemId]
	if cached ~= nil then
		return cached
	end

	local canonicalItemId = ItemRegistry.GetCanonicalItemId(itemId)
	local definitionTable = ItemRegistry.GetDefinition(itemId)
	if canonicalItemId == nil or definitionTable == nil then
		return nil
	end

	local normalized = normalizeItemDefinition(canonicalItemId, definitionTable)
	if normalized == nil then
		return nil
	end

	cachedItemDefinitions[itemId] = normalized
	cachedItemDefinitions[canonicalItemId] = normalized
	local altId = CoerceText((definitionTable :: any).id, nil)
	if altId ~= nil then
		cachedItemDefinitions[altId] = normalized
	end
	return normalized
end

local function GetItemTypeFromStack(stackRaw: any): string?
	if typeof(stackRaw) ~= "table" then
		return nil
	end

	local stack = stackRaw :: { [string]: any }
	local metadata = if typeof(stack.metadata) == "table" then stack.metadata :: { [string]: any } else nil
	if metadata ~= nil then
		local typedFromMetadata = normalizeTypeKey(metadata.itemType or metadata.itemtype or metadata.type)
		if typedFromMetadata ~= nil then
			return typedFromMetadata
		end
	end

	local definition = GetItemDefinition(stack.itemId)
	if definition ~= nil and definition.itemType ~= nil then
		return definition.itemType
	end

	return GetItemTypeFromItemId(stack.itemId)
end

local function formatStats(statsRaw: any): string
	if typeof(statsRaw) ~= "table" then
		return ""
	end

	local stats = statsRaw :: { [string]: any }
	local lines = {}
	for key, value in stats do
		local label = toTitleCase(key)
		local textValue = CoerceText(tostring(value), "")
		if textValue ~= nil and textValue ~= "" then
			lines = Sift.Array.append(lines, ("%s: %s"):format(label, textValue))
		end
	end
	lines = Sift.Array.sort(lines)
	return joinStrings(lines, "\n")
end

local function GetStackAmount(stackRaw: any): number
	if typeof(stackRaw) ~= "table" then
		return 0
	end
	local amountRaw = (stackRaw :: any).amount
	if typeof(amountRaw) ~= "number" or amountRaw ~= amountRaw then
		return 0
	end
	return math.max(0, math.floor(amountRaw))
end

local function GetEquestedDragAmount(state: ItemDragState, amountRaw: any): any
	if amountRaw ~= nil then
		return amountRaw
	end
	if state.stack == nil then
		return nil
	end
	return state.stack.amount
end

function itemThunks.GetItemIconByType(itemTypeRaw: any, itemIdRaw: any?): string?
	local normalizedType = normalizeTypeKey(itemTypeRaw)
	local normalizedItemId = normalizeTypeKey(itemIdRaw)
	local itemIcons = if typeof(ItemIcons) == "table" then ItemIcons :: { [string]: any } else nil
	if normalizedType == nil and normalizedItemId ~= nil then
		normalizedType = GetItemTypeFromItemId(itemIdRaw)
	end

	if itemIcons ~= nil and normalizedItemId ~= nil then
		local byItemId = itemIcons[normalizedItemId]
		if typeof(byItemId) == "string" and byItemId ~= "" then
			return byItemId
		end

		for key, value in itemIcons do
			if normalizeTypeKey(key) == normalizedItemId and typeof(value) == "string" and value ~= "" then
				return value
			end
		end
	end

	if itemIcons ~= nil and normalizedType ~= nil then
		local icon = itemIcons[normalizedType]
		if typeof(icon) == "string" and icon ~= "" then
			return icon
		end
	end

	if itemIcons ~= nil then
		local fallbackIcon = itemIcons.default
		if typeof(fallbackIcon) == "string" and fallbackIcon ~= "" then
			return fallbackIcon
		end
	end

	local questionMarkIcon = ImageIds.questionMark
	if typeof(questionMarkIcon) == "string" and questionMarkIcon ~= "" then
		return questionMarkIcon
	end

	return nil
end

function itemThunks.GetIconForStack(stackRaw: any): string?
	local itemId = if typeof(stackRaw) == "table" then (stackRaw :: { [string]: any }).itemId else nil
	local itemType = GetItemTypeFromStack(stackRaw)
	return itemThunks.GetItemIconByType(itemType, itemId)
end

function itemThunks.GetDisplayNameForStack(stackRaw: any): string
	if typeof(stackRaw) ~= "table" then
		return "Item"
	end

	local stack = stackRaw :: { [string]: any }
	local definition = GetItemDefinition(stack.itemId)
	if definition ~= nil then
		return definition.name
	end
	return toTitleCase(stack.itemId)
end

function itemThunks.GetHoverTextForStack(stackRaw: any, slotIndexRaw: any): string
	if typeof(stackRaw) ~= "table" then
		local slotIndex = if typeof(slotIndexRaw) == "number" and slotIndexRaw == slotIndexRaw
			then math.floor(slotIndexRaw)
			else 0
		return ("Slot %d\nEmpty"):format(slotIndex)
	end

	local stack = stackRaw :: { [string]: any }
	local definition = GetItemDefinition(stack.itemId)
	local name = if definition ~= nil then definition.name else toTitleCase(stack.itemId)
	local amount = if typeof(stack.amount) == "number" and stack.amount == stack.amount
		then math.max(0, stack.amount)
		else 0
	local useCase = if definition ~= nil then definition.useCase else nil
	local description = if definition ~= nil then definition.description else nil
	local statsText = if definition ~= nil then formatStats(definition.stats) else ""

	local lines = { name, ("Amount: %d"):format(amount) }
	if useCase ~= nil and useCase ~= "" then
		lines = Sift.Array.append(lines, ("Use: %s"):format(useCase))
	end
	if description ~= nil and description ~= "" then
		lines = Sift.Array.append(lines, description)
	end
	if statsText ~= "" then
		lines = Sift.Array.append(lines, statsText)
	end
	return joinStrings(lines, "\n")
end

function itemThunks.BeginDrag(slotIndexRaw: any, stackRaw: any, pointerPositionRaw: any): ItemDragState
	local itemId = if typeof(stackRaw) == "table" then (stackRaw :: { [string]: any }).itemId else nil
	local itemType = GetItemTypeFromStack(stackRaw)
	local icon = itemThunks.GetItemIconByType(itemType, itemId)
	return itemSlice.beginDrag(slotIndexRaw, stackRaw, pointerPositionRaw, itemType, icon)
end

function itemThunks.BeginSplitDrag(
	slotIndexRaw: any,
	stackRaw: any,
	pointerPositionRaw: any,
	amountRaw: any
): ItemDragState
	local itemId = if typeof(stackRaw) == "table" then (stackRaw :: { [string]: any }).itemId else nil
	local itemType = GetItemTypeFromStack(stackRaw)
	local icon = itemThunks.GetItemIconByType(itemType, itemId)
	local sourceStackAmount = GetStackAmount(stackRaw)
	return itemSlice.beginDrag(slotIndexRaw, stackRaw, pointerPositionRaw, itemType, icon, {
		mode = "SplitHold",
		dragAmount = amountRaw,
		sourceStackAmount = sourceStackAmount,
	})
end

function itemThunks.UpdatePointer(pointerPositionRaw: any): ItemDragState
	return itemSlice.setPointerPosition(pointerPositionRaw)
end

function itemThunks.SetDragStackAmount(amountRaw: any): ItemDragState
	return itemSlice.setStackAmount(amountRaw)
end

function itemThunks.SetHoveredSlot(slotIndexRaw: any): ItemDragState
	return itemSlice.setHoveredSlot(slotIndexRaw)
end

function itemThunks.CancelDrag(): ItemDragState
	return itemSlice.clearDragState()
end

function itemThunks.TrashDrag(amountRaw: any): boolean
	local state = itemSlice.getDragState()
	if not state.active then
		return false
	end

	local sourceSlot = state.sourceSlot
	if sourceSlot == nil then
		itemSlice.clearDragState()
		return false
	end

	local requestedAmount = GetEquestedDragAmount(state, amountRaw)
	local didRequest = inventoryThunks.TrashSlot(sourceSlot, requestedAmount)
	itemSlice.clearDragState()
	return didRequest
end

function itemThunks.DropDrag(amountRaw: any): boolean
	local state = itemSlice.getDragState()
	if not state.active then
		return false
	end

	local sourceSlot = state.sourceSlot
	if sourceSlot == nil then
		itemSlice.clearDragState()
		return false
	end

	local requestedAmount = GetEquestedDragAmount(state, amountRaw)
	local didRequest = inventoryThunks.DropFromSlot(sourceSlot, requestedAmount)
	if didRequest then
		itemSlice.clearDragState()
	end
	return didRequest
end

function itemThunks.EndDrag(targetSlotRaw: any): boolean
	local state = itemSlice.getDragState()
	if not state.active then
		return false
	end

	local sourceSlot = state.sourceSlot
	local targetSlot = if typeof(targetSlotRaw) == "number" and targetSlotRaw == targetSlotRaw
		then math.floor(targetSlotRaw)
		else nil
	local dragAmount = if state.stack ~= nil then state.stack.amount else nil
	local didMove = false
	if sourceSlot ~= nil and targetSlot ~= nil and sourceSlot ~= targetSlot then
		local requestedAmount = if state.mode == "SplitHold" then dragAmount else nil
		didMove = inventoryThunks.MoveSlot(sourceSlot, targetSlot, requestedAmount)
	end

	itemSlice.clearDragState()
	return didMove
end

return itemThunks
