--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local itemSlice = require(ReplicatedStorage.UI.features.item.state.itemSlice)
local inventoryThunks = require(ReplicatedStorage.UI.features.inventory.state.inventoryThunks)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)

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

local function sanitizeText(valueRaw: any, fallback: string?): string?
	local value = trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

local function toTitleCase(textRaw: any): string
	local value = sanitizeText(textRaw, "Item") or "Item"
	value = string.gsub(value, "_", " ")
	value = string.gsub(value, "-", " ")
	value = string.gsub(value, "%s+", " ")
	return string.gsub(value, "(%a)([%w']*)", function(first: string, rest: string)
		return string.upper(first) .. string.lower(rest)
	end)
end

local function resolveItemTypeFromItemId(itemIdRaw: any): string?
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
		itemType = resolveItemTypeFromItemId(itemId)
	end

	local description = sanitizeText(definition.description, nil)
	if description == nil and definition.value ~= nil then
		description = sanitizeText(tostring(definition.value), nil)
	end

	return {
		itemId = itemId,
		name = toTitleCase(definition.name or itemId),
		description = description or "No description.",
		useCase = sanitizeText(definition.useCase, nil),
		itemType = itemType,
		stats = if typeof(definition.stats) == "table" then definition.stats else nil,
	}
end

local function resolveItemDefinition(itemIdRaw: any): ItemDefinition?
	local itemId = sanitizeText(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local cached = cachedItemDefinitions[itemId]
	if cached ~= nil then
		return cached
	end

	local canonicalItemId = ItemRegistry.resolveCanonicalItemId(itemId)
	local definitionTable = ItemRegistry.resolveDefinition(itemId)
	if canonicalItemId == nil or definitionTable == nil then
		return nil
	end

	local normalized = normalizeItemDefinition(canonicalItemId, definitionTable)
	if normalized == nil then
		return nil
	end

	cachedItemDefinitions[itemId] = normalized
	cachedItemDefinitions[canonicalItemId] = normalized
	local altId = sanitizeText((definitionTable :: any).id, nil)
	if altId ~= nil then
		cachedItemDefinitions[altId] = normalized
	end
	return normalized
end

local function resolveItemTypeFromStack(stackRaw: any): string?
	if typeof(stackRaw) ~= "table" then
		return nil
	end

	local stack = stackRaw :: { [string]: any }
	local metadata = if typeof(stack.metadata) == "table" then (stack.metadata :: { [string]: any }) else nil
	if metadata ~= nil then
		local typedFromMetadata = normalizeTypeKey(metadata.itemType or metadata.itemtype or metadata.type)
		if typedFromMetadata ~= nil then
			return typedFromMetadata
		end
	end

	local definition = resolveItemDefinition(stack.itemId)
	if definition ~= nil and definition.itemType ~= nil then
		return definition.itemType
	end

	return resolveItemTypeFromItemId(stack.itemId)
end

local function formatStats(statsRaw: any): string
	if typeof(statsRaw) ~= "table" then
		return ""
	end

	local stats = statsRaw :: { [string]: any }
	local lines = {}
	for key, value in stats do
		local label = toTitleCase(key)
		local textValue = sanitizeText(tostring(value), "")
		if textValue ~= nil and textValue ~= "" then
			lines = Sift.Array.append(lines, ("%s: %s"):format(label, textValue))
		end
	end
	lines = Sift.Array.sort(lines)
	return joinStrings(lines, "\n")
end

local function resolveStackAmount(stackRaw: any): number
	if typeof(stackRaw) ~= "table" then
		return 0
	end
	local amountRaw = (stackRaw :: any).amount
	if typeof(amountRaw) ~= "number" or amountRaw ~= amountRaw then
		return 0
	end
	return math.max(0, math.floor(amountRaw))
end

local function resolveRequestedDragAmount(state: ItemDragState, amountRaw: any): any
	if amountRaw ~= nil then
		return amountRaw
	end
	if state.stack == nil then
		return nil
	end
	return state.stack.amount
end

function itemThunks.resolveItemIconByType(itemTypeRaw: any, itemIdRaw: any?): string?
	local normalizedType = normalizeTypeKey(itemTypeRaw)
	local normalizedItemId = normalizeTypeKey(itemIdRaw)
	local itemIcons = if typeof(ImageIds.itemIcons) == "table" then (ImageIds.itemIcons :: { [string]: any }) else nil

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
		local fallback = itemIcons.default
		if typeof(fallback) == "string" and fallback ~= "" then
			return fallback
		end
	end

	local questionMark = ImageIds.questionMark
	if typeof(questionMark) == "string" and questionMark ~= "" then
		return questionMark
	end

	return nil
end

function itemThunks.resolveIconForStack(stackRaw: any): string?
	local itemId = if typeof(stackRaw) == "table" then (stackRaw :: { [string]: any }).itemId else nil
	local itemType = resolveItemTypeFromStack(stackRaw)
	return itemThunks.resolveItemIconByType(itemType, itemId)
end

function itemThunks.resolveDisplayNameForStack(stackRaw: any): string
	if typeof(stackRaw) ~= "table" then
		return "Item"
	end

	local stack = stackRaw :: { [string]: any }
	local definition = resolveItemDefinition(stack.itemId)
	if definition ~= nil then
		return definition.name
	end
	return toTitleCase(stack.itemId)
end

function itemThunks.resolveHoverTextForStack(stackRaw: any, slotIndexRaw: any): string
	if typeof(stackRaw) ~= "table" then
		local slotIndex = if typeof(slotIndexRaw) == "number" and slotIndexRaw == slotIndexRaw
			then math.floor(slotIndexRaw)
			else 0
		return ("Slot %d\nEmpty"):format(slotIndex)
	end

	local stack = stackRaw :: { [string]: any }
	local definition = resolveItemDefinition(stack.itemId)
	local name = if definition ~= nil then definition.name else toTitleCase(stack.itemId)
	local amount = if typeof(stack.amount) == "number" and stack.amount == stack.amount then math.max(0, stack.amount) else 0
	local useCase = if definition ~= nil then definition.useCase else nil
	local description = if definition ~= nil then definition.description else nil
	local statsText = if definition ~= nil then formatStats(definition.stats) else ""

	local lines = { name, ("Amount: %d"):format(amount) }
	if useCase ~= nil and useCase ~= "" then
		lines = Sift.Array.append(lines, ("Use: %s"):format(useCase))
	end
	if description ~= nil and description ~= "" then
		lines = Sift.Array.append(lines, "")
		lines = Sift.Array.append(lines, description)
	end
	if statsText ~= "" then
		lines = Sift.Array.append(lines, "")
		lines = Sift.Array.append(lines, statsText)
	end
	return joinStrings(lines, "\n")
end

function itemThunks.beginDrag(slotIndexRaw: any, stackRaw: any, pointerPositionRaw: any): ItemDragState
	local itemId = if typeof(stackRaw) == "table" then (stackRaw :: { [string]: any }).itemId else nil
	local itemType = resolveItemTypeFromStack(stackRaw)
	local icon = itemThunks.resolveItemIconByType(itemType, itemId)
	return itemSlice.beginDrag(slotIndexRaw, stackRaw, pointerPositionRaw, itemType, icon)
end

function itemThunks.beginSplitDrag(slotIndexRaw: any, stackRaw: any, pointerPositionRaw: any, amountRaw: any): ItemDragState
	local itemId = if typeof(stackRaw) == "table" then (stackRaw :: { [string]: any }).itemId else nil
	local itemType = resolveItemTypeFromStack(stackRaw)
	local icon = itemThunks.resolveItemIconByType(itemType, itemId)
	local sourceStackAmount = resolveStackAmount(stackRaw)
	return itemSlice.beginDrag(slotIndexRaw, stackRaw, pointerPositionRaw, itemType, icon, {
		mode = "SplitHold",
		dragAmount = amountRaw,
		sourceStackAmount = sourceStackAmount,
	})
end

function itemThunks.updatePointer(pointerPositionRaw: any): ItemDragState
	return itemSlice.setPointerPosition(pointerPositionRaw)
end

function itemThunks.setDragStackAmount(amountRaw: any): ItemDragState
	return itemSlice.setStackAmount(amountRaw)
end

function itemThunks.setHoveredSlot(slotIndexRaw: any): ItemDragState
	return itemSlice.setHoveredSlot(slotIndexRaw)
end

function itemThunks.cancelDrag(): ItemDragState
	return itemSlice.clearDragState()
end

function itemThunks.trashDrag(amountRaw: any): boolean
	local state = itemSlice.getDragState()
	if not state.active then
		return false
	end

	local sourceSlot = state.sourceSlot
	if sourceSlot == nil then
		itemSlice.clearDragState()
		return false
	end

	local requestedAmount = resolveRequestedDragAmount(state, amountRaw)
	local didRequest = inventoryThunks.trashSlot(sourceSlot, requestedAmount)
	itemSlice.clearDragState()
	return didRequest
end

function itemThunks.dropDrag(amountRaw: any): boolean
	local state = itemSlice.getDragState()
	if not state.active then
		return false
	end

	local sourceSlot = state.sourceSlot
	if sourceSlot == nil then
		itemSlice.clearDragState()
		return false
	end

	local requestedAmount = resolveRequestedDragAmount(state, amountRaw)
	local didRequest = inventoryThunks.dropFromSlot(sourceSlot, requestedAmount)
	if didRequest then
		itemSlice.clearDragState()
	end
	return didRequest
end

function itemThunks.endDrag(targetSlotRaw: any): boolean
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
		didMove = inventoryThunks.moveSlot(sourceSlot, targetSlot, requestedAmount)
	end

	itemSlice.clearDragState()
	return didMove
end

return itemThunks
