--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local InventoryServiceUtils = {}

export type InventoryLoadState = "Unloaded" | "Loading" | "Loaded" | "Failed"
export type InventoryItemMetadata = { [string]: any }
export type InventoryItemStack = {
	stackId: string,
	itemId: string,
	amount: number,
	maxStack: number,
	metadata: InventoryItemMetadata?,
}
export type InventorySlot = {
	index: number,
	stack: InventoryItemStack?,
}
export type InventoryState = {
	capacity: number,
	slots: { InventorySlot },
	selectedSlot: number?,
	occupiedSlotCount: number,
	totalItemCount: number,
	loadState: InventoryLoadState,
	updatedAt: number,
}
export type AddItemResult = {
	requested: number,
	added: number,
	leftover: number,
	changed: boolean,
	touchedSlots: { number },
}
export type RemoveItemResult = {
	requested: number,
	removed: number,
	leftover: number,
	changed: boolean,
	touchedSlots: { number },
}
export type SlotMutationResult = {
	changed: boolean,
	touchedSlots: { number },
	fromSlot: number?,
	toSlot: number?,
	movedAmount: number,
	removedAmount: number,
	swapped: boolean,
}

local LOAD_STATE_UNLOADED: InventoryLoadState = "Unloaded"
local LOAD_STATE_LOADING: InventoryLoadState = "Loading"
local LOAD_STATE_LOADED: InventoryLoadState = "Loaded"
local LOAD_STATE_FAILED: InventoryLoadState = "Failed"

local NETWORK_METHOD_REQUEST_SYNC = "requestSync"
local NETWORK_METHOD_REQUEST_SET_SELECTED_SLOT = "requestSetSelectedSlot"
local NETWORK_METHOD_REQUEST_MOVE_SLOT = "requestMoveSlot"
local NETWORK_METHOD_REQUEST_SPLIT_SLOT = "requestSplitSlot"
local NETWORK_METHOD_REQUEST_DROP_SLOT = "requestDropFromSlot"
local NETWORK_METHOD_REQUEST_TRASH_SLOT = "requestTrashSlot"
local NETWORK_METHOD_REQUEST_TRASH_SELECTED_SLOT = "requestTrashSelectedSlot"
local NETWORK_METHOD_REQUEST_USE_SELECTED_SLOT = "requestUseSelectedSlot"

local DEFAULT_CAPACITY = 72
local MIN_CAPACITY = 1
local MAX_CAPACITY = 240
local DEFAULT_MAX_STACK = 99
local MIN_STACK = 1
local MAX_STACK = 9999
local DEFAULT_DATA_PATH = { "inventory" }

InventoryServiceUtils.LOAD_STATE_UNLOADED = LOAD_STATE_UNLOADED
InventoryServiceUtils.LOAD_STATE_LOADING = LOAD_STATE_LOADING
InventoryServiceUtils.LOAD_STATE_LOADED = LOAD_STATE_LOADED
InventoryServiceUtils.LOAD_STATE_FAILED = LOAD_STATE_FAILED
InventoryServiceUtils.NETWORK_METHOD_REQUEST_SYNC = NETWORK_METHOD_REQUEST_SYNC
InventoryServiceUtils.NETWORK_METHOD_REQUEST_SET_SELECTED_SLOT = NETWORK_METHOD_REQUEST_SET_SELECTED_SLOT
InventoryServiceUtils.NETWORK_METHOD_REQUEST_MOVE_SLOT = NETWORK_METHOD_REQUEST_MOVE_SLOT
InventoryServiceUtils.NETWORK_METHOD_REQUEST_SPLIT_SLOT = NETWORK_METHOD_REQUEST_SPLIT_SLOT
InventoryServiceUtils.NETWORK_METHOD_REQUEST_DROP_SLOT = NETWORK_METHOD_REQUEST_DROP_SLOT
InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SLOT = NETWORK_METHOD_REQUEST_TRASH_SLOT
InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SELECTED_SLOT = NETWORK_METHOD_REQUEST_TRASH_SELECTED_SLOT
InventoryServiceUtils.NETWORK_METHOD_REQUEST_USE_SELECTED_SLOT = NETWORK_METHOD_REQUEST_USE_SELECTED_SLOT
InventoryServiceUtils.DEFAULT_CAPACITY = DEFAULT_CAPACITY
InventoryServiceUtils.MIN_CAPACITY = MIN_CAPACITY
InventoryServiceUtils.MAX_CAPACITY = MAX_CAPACITY
InventoryServiceUtils.DEFAULT_MAX_STACK = DEFAULT_MAX_STACK
InventoryServiceUtils.DEFAULT_DATA_PATH = DEFAULT_DATA_PATH

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeString(valueRaw: any, fallback: string?): string?
	local value = trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number, maximum: number?): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end

	local value = math.floor(valueRaw)
	if value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function cloneDeepInternal(value: any, seen: { [any]: any }): any
	if typeof(value) ~= "table" then
		return value
	end

	local existing = seen[value]
	if existing ~= nil then
		return existing
	end

	local cloned = {}
	seen[value] = cloned
	for key, nestedValue in value do
		local clonedKey = cloneDeepInternal(key, seen)
		cloned[clonedKey] = cloneDeepInternal(nestedValue, seen)
	end
	return cloned
end

local function deepEqualInternal(a: any, b: any, seen: { [any]: any }): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end

	local seenB = seen[a]
	if seenB ~= nil then
		return seenB == b
	end
	seen[a] = b

	for key, valueA in a do
		if not deepEqualInternal(valueA, b[key], seen) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function deepEqual(a: any, b: any): boolean
	return deepEqualInternal(a, b, {})
end

local function cloneMetadata(metadataRaw: any): InventoryItemMetadata?
	if typeof(metadataRaw) ~= "table" then
		return nil
	end
	return cloneDeepInternal(metadataRaw, {})
end

local function normalizeLoadState(loadStateRaw: any, fallback: InventoryLoadState?): InventoryLoadState
	if loadStateRaw == LOAD_STATE_UNLOADED then
		return LOAD_STATE_UNLOADED
	end
	if loadStateRaw == LOAD_STATE_LOADING then
		return LOAD_STATE_LOADING
	end
	if loadStateRaw == LOAD_STATE_LOADED then
		return LOAD_STATE_LOADED
	end
	if loadStateRaw == LOAD_STATE_FAILED then
		return LOAD_STATE_FAILED
	end
	return fallback or LOAD_STATE_UNLOADED
end

local function normalizeCapacity(capacityRaw: any, fallback: number?): number
	local normalized = sanitizeInteger(capacityRaw, fallback or DEFAULT_CAPACITY, MIN_CAPACITY, MAX_CAPACITY)
	return math.max(DEFAULT_CAPACITY, normalized)
end

local function normalizeSlotIndex(slotIndexRaw: any, capacity: number, fallback: number?): number?
	if slotIndexRaw == nil then
		return fallback
	end
	if typeof(slotIndexRaw) ~= "number" or slotIndexRaw ~= slotIndexRaw then
		return fallback
	end

	local slotIndex = math.floor(slotIndexRaw)
	if slotIndex < 1 or slotIndex > capacity then
		return fallback
	end
	return slotIndex
end

local function normalizeItemId(itemIdRaw: any, fallback: string?): string?
	return sanitizeString(itemIdRaw, fallback)
end

local function createStackIdFromFallback(itemId: string, fallbackStackId: string?): string
	local fallback = sanitizeString(fallbackStackId, nil)
	if fallback ~= nil then
		return fallback
	end
	return ("stack_%s_%d"):format(itemId, math.floor(os.clock() * 100000))
end

local function normalizeStack(stackRaw: any, fallbackStackId: string?): InventoryItemStack?
	if typeof(stackRaw) ~= "table" then
		return nil
	end
	local source = stackRaw :: { [string]: any }

	local itemId = normalizeItemId(source.itemId, nil)
	if itemId == nil then
		return nil
	end

	local amount = sanitizeInteger(source.amount, 1, MIN_STACK, MAX_STACK)
	local maxStack = sanitizeInteger(source.maxStack, math.max(DEFAULT_MAX_STACK, amount), MIN_STACK, MAX_STACK)
	amount = math.clamp(amount, MIN_STACK, maxStack)

	local stackId = sanitizeString(source.stackId, nil)
	if stackId == nil then
		stackId = createStackIdFromFallback(itemId, fallbackStackId)
	end

	return {
		stackId = stackId,
		itemId = itemId,
		amount = amount,
		maxStack = maxStack,
		metadata = cloneMetadata(source.metadata),
	}
end

local function cloneStack(stack: InventoryItemStack): InventoryItemStack
	return {
		stackId = stack.stackId,
		itemId = stack.itemId,
		amount = stack.amount,
		maxStack = stack.maxStack,
		metadata = cloneMetadata(stack.metadata),
	}
end

local function createEmptySlots(capacity: number): { InventorySlot }
	local slots: { InventorySlot } = Sift.Array.create(capacity)
	for slotIndex = 1, capacity do
		slots[slotIndex] = {
			index = slotIndex,
			stack = nil,
		}
	end
	return slots
end

local function normalizeSlots(slotsRaw: any, capacity: number): { InventorySlot }
	local slots = createEmptySlots(capacity)
	if typeof(slotsRaw) ~= "table" then
		return slots
	end

	for key, entryRaw in slotsRaw do
		if typeof(entryRaw) ~= "table" then
			continue
		end

		local entry = entryRaw :: { [string]: any }
		local slotIndex = normalizeSlotIndex(entry.index, capacity, nil)
		if slotIndex == nil then
			slotIndex = normalizeSlotIndex(key, capacity, nil)
		end
		if slotIndex == nil then
			continue
		end

		local stackRaw = entry.stack
		if stackRaw == nil and (entry.itemId ~= nil or entry.stackId ~= nil) then
			stackRaw = entry
		end

		local stack = normalizeStack(stackRaw, ("slot_%d"):format(slotIndex))
		if stack ~= nil then
			slots[slotIndex].stack = stack
		end
	end

	return slots
end

local function appendTouchedSlot(touchedSlots: { number }, slotIndex: number)
	for _, existingIndex in touchedSlots do
		if existingIndex == slotIndex then
			return
		end
	end
	table.insert(touchedSlots, slotIndex)
end

local function refreshStateDerived(state: InventoryState, updateTimestamp: boolean)
	local occupiedSlotCount = 0
	local totalItemCount = 0
	for _, slot in state.slots do
		local stack = slot.stack
		if stack ~= nil then
			occupiedSlotCount += 1
			totalItemCount += math.max(0, stack.amount)
		end
	end

	state.occupiedSlotCount = occupiedSlotCount
	state.totalItemCount = totalItemCount

	if state.selectedSlot ~= nil then
		state.selectedSlot = normalizeSlotIndex(state.selectedSlot, state.capacity, nil)
	end

	if updateTimestamp then
		state.updatedAt = os.clock()
	end
end

local function metadataMatches(stackMetadata: InventoryItemMetadata?, metadataRaw: any, requireExactMetadata: boolean): boolean
	if metadataRaw == nil then
		return (not requireExactMetadata) or stackMetadata == nil
	end
	if typeof(metadataRaw) ~= "table" then
		return false
	end
	return deepEqual(stackMetadata, metadataRaw)
end

function InventoryServiceUtils.cloneDeep(value: any): any
	return cloneDeepInternal(value, {})
end

function InventoryServiceUtils.deepEqual(a: any, b: any): boolean
	return deepEqual(a, b)
end

function InventoryServiceUtils.clonePath(pathRaw: any): { string }
	local source = if typeof(pathRaw) == "table" then pathRaw else DEFAULT_DATA_PATH
	local output = Sift.Array.map(source, function(segmentRaw: any): string?
		return sanitizeString(segmentRaw, nil)
	end)
	if #output == 0 then
		return { "inventory" }
	end
	return output
end

function InventoryServiceUtils.getDefaultDataPath(): { string }
	return InventoryServiceUtils.clonePath(DEFAULT_DATA_PATH)
end

function InventoryServiceUtils.sanitizeLoadState(
	loadStateRaw: any,
	fallback: InventoryLoadState?
): InventoryLoadState
	return normalizeLoadState(loadStateRaw, fallback)
end

function InventoryServiceUtils.isLoadedState(loadStateRaw: any): boolean
	return normalizeLoadState(loadStateRaw, LOAD_STATE_UNLOADED) == LOAD_STATE_LOADED
end

function InventoryServiceUtils.createDefaultState(loadStateRaw: any): InventoryState
	local state: InventoryState = {
		capacity = DEFAULT_CAPACITY,
		slots = createEmptySlots(DEFAULT_CAPACITY),
		selectedSlot = nil,
		occupiedSlotCount = 0,
		totalItemCount = 0,
		loadState = normalizeLoadState(loadStateRaw, LOAD_STATE_UNLOADED),
		updatedAt = os.clock(),
	}
	return state
end

function InventoryServiceUtils.createState(stateRaw: any, fallbackStateRaw: any): InventoryState
	local fallback = if typeof(fallbackStateRaw) == "table"
		then (fallbackStateRaw :: InventoryState)
		else InventoryServiceUtils.createDefaultState(LOAD_STATE_UNLOADED)
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	local sourceTable = source :: { [string]: any }

	local capacity = normalizeCapacity(sourceTable.capacity, fallback.capacity)
	local slots = normalizeSlots(sourceTable.slots, capacity)
	local selectedSlot = normalizeSlotIndex(sourceTable.selectedSlot, capacity, nil)
	local loadState = normalizeLoadState(sourceTable.loadState, fallback.loadState)
	local updatedAt = if typeof(sourceTable.updatedAt) == "number" and sourceTable.updatedAt == sourceTable.updatedAt
		then sourceTable.updatedAt
		else os.clock()

	local state: InventoryState = {
		capacity = capacity,
		slots = slots,
		selectedSlot = selectedSlot,
		occupiedSlotCount = 0,
		totalItemCount = 0,
		loadState = loadState,
		updatedAt = updatedAt,
	}
	refreshStateDerived(state, false)
	return state
end

function InventoryServiceUtils.createStateFromData(
	dataRaw: any,
	fallbackStateRaw: any,
	loadStateRaw: any
): InventoryState
	local source = if typeof(dataRaw) == "table" then dataRaw else {}
	local sourceTable = source :: { [string]: any }
	local slots = sourceTable.slots
	if typeof(slots) ~= "table" then
		slots = sourceTable.items
	end

	local state = InventoryServiceUtils.createState({
		capacity = sourceTable.capacity,
		slots = slots,
		selectedSlot = sourceTable.selectedSlot,
		loadState = normalizeLoadState(loadStateRaw, LOAD_STATE_LOADED),
		updatedAt = os.clock(),
	}, fallbackStateRaw)
	state.loadState = normalizeLoadState(loadStateRaw, LOAD_STATE_LOADED)
	return state
end

function InventoryServiceUtils.sanitizeState(stateRaw: any, fallbackStateRaw: any): InventoryState
	return InventoryServiceUtils.createState(stateRaw, fallbackStateRaw)
end

function InventoryServiceUtils.cloneState(state: InventoryState): InventoryState
	local slots = Sift.Array.map(state.slots, function(slot: InventorySlot): InventorySlot
		return {
			index = slot.index,
			stack = if slot.stack ~= nil then cloneStack(slot.stack) else nil,
		}
	end) :: { InventorySlot }

	return {
		capacity = state.capacity,
		slots = slots,
		selectedSlot = state.selectedSlot,
		occupiedSlotCount = state.occupiedSlotCount,
		totalItemCount = state.totalItemCount,
		loadState = state.loadState,
		updatedAt = state.updatedAt,
	}
end

function InventoryServiceUtils.serializeStateForData(stateRaw: any): { [string]: any }
	local state = if typeof(stateRaw) == "table"
		then InventoryServiceUtils.sanitizeState(stateRaw, InventoryServiceUtils.createDefaultState(LOAD_STATE_UNLOADED))
		else InventoryServiceUtils.createDefaultState(LOAD_STATE_UNLOADED)
	local serializedSlots = Sift.Array.map(state.slots, function(slot: InventorySlot)
		local stack = slot.stack
		if stack == nil then
			return nil
		end

		return {
			index = slot.index,
			stackId = stack.stackId,
			itemId = stack.itemId,
			amount = stack.amount,
			maxStack = stack.maxStack,
			metadata = cloneMetadata(stack.metadata),
		}
	end)

	return {
		capacity = state.capacity,
		selectedSlot = state.selectedSlot,
		slots = serializedSlots,
	}
end

function InventoryServiceUtils.setLoadState(state: InventoryState, loadStateRaw: any): boolean
	local nextLoadState = normalizeLoadState(loadStateRaw, state.loadState)
	if state.loadState == nextLoadState then
		return false
	end

	state.loadState = nextLoadState
	refreshStateDerived(state, true)
	return true
end

function InventoryServiceUtils.setSelectedSlot(state: InventoryState, slotIndexRaw: any): boolean
	local nextSelectedSlot = normalizeSlotIndex(slotIndexRaw, state.capacity, nil)
	if state.selectedSlot == nextSelectedSlot then
		return false
	end

	state.selectedSlot = nextSelectedSlot
	refreshStateDerived(state, true)
	return true
end

function InventoryServiceUtils.getSlot(state: InventoryState, slotIndexRaw: any): InventorySlot?
	local slotIndex = normalizeSlotIndex(slotIndexRaw, state.capacity, nil)
	if slotIndex == nil then
		return nil
	end
	return state.slots[slotIndex]
end

function InventoryServiceUtils.getStack(state: InventoryState, slotIndexRaw: any): InventoryItemStack?
	local slot = InventoryServiceUtils.getSlot(state, slotIndexRaw)
	if slot == nil then
		return nil
	end
	return slot.stack
end

function InventoryServiceUtils.clear(state: InventoryState): boolean
	local changed = false
	for _, slot in state.slots do
		if slot.stack ~= nil then
			slot.stack = nil
			changed = true
		end
	end
	if state.selectedSlot ~= nil then
		state.selectedSlot = nil
		changed = true
	end
	if changed then
		refreshStateDerived(state, true)
	end
	return changed
end

function InventoryServiceUtils.addItem(
	state: InventoryState,
	itemIdRaw: any,
	amountRaw: any,
	maxStackRaw: any,
	metadataRaw: any,
	stackIdPrefixRaw: any
): AddItemResult
	local itemId = normalizeItemId(itemIdRaw, nil)
	local requested = sanitizeInteger(amountRaw, 0, 0, MAX_STACK * state.capacity)
	local maxStack = sanitizeInteger(maxStackRaw, DEFAULT_MAX_STACK, MIN_STACK, MAX_STACK)
	local metadata = cloneMetadata(metadataRaw)
	local touchedSlots = {}

	if itemId == nil or requested <= 0 then
		return {
			requested = requested,
			added = 0,
			leftover = requested,
			changed = false,
			touchedSlots = touchedSlots,
		}
	end

	local remaining = requested
	for _, slot in state.slots do
		if remaining <= 0 then
			break
		end

		local stack = slot.stack
		if stack == nil then
			continue
		end
		if stack.itemId ~= itemId then
			continue
		end
		if not metadataMatches(stack.metadata, metadata, true) then
			continue
		end

		local room = math.max(0, stack.maxStack - stack.amount)
		if room <= 0 then
			continue
		end

		local added = math.min(remaining, room)
		stack.amount += added
		remaining -= added
		appendTouchedSlot(touchedSlots, slot.index)
	end

	local stackIdPrefix = sanitizeString(stackIdPrefixRaw, "stack") or "stack"
	local stackSerial = math.floor(os.clock() * 100000)
	for _, slot in state.slots do
		if remaining <= 0 then
			break
		end
		if slot.stack ~= nil then
			continue
		end

		local stackAmount = math.min(remaining, maxStack)
		stackSerial += 1
		slot.stack = {
			stackId = ("%s_%s_%d_%d"):format(stackIdPrefix, itemId, slot.index, stackSerial),
			itemId = itemId,
			amount = stackAmount,
			maxStack = maxStack,
			metadata = cloneMetadata(metadata),
		}
		remaining -= stackAmount
		appendTouchedSlot(touchedSlots, slot.index)
	end

	local addedTotal = requested - remaining
	local changed = addedTotal > 0
	if changed then
		refreshStateDerived(state, true)
	end

	return {
		requested = requested,
		added = addedTotal,
		leftover = remaining,
		changed = changed,
		touchedSlots = touchedSlots,
	}
end

function InventoryServiceUtils.removeItem(
	state: InventoryState,
	itemIdRaw: any,
	amountRaw: any,
	metadataRaw: any,
	requireExactMetadataRaw: any
): RemoveItemResult
	local itemId = normalizeItemId(itemIdRaw, nil)
	local requested = sanitizeInteger(amountRaw, 0, 0, MAX_STACK * state.capacity)
	local requireExactMetadata = requireExactMetadataRaw == true
	local touchedSlots = {}

	if itemId == nil or requested <= 0 then
		return {
			requested = requested,
			removed = 0,
			leftover = requested,
			changed = false,
			touchedSlots = touchedSlots,
		}
	end

	local remaining = requested
	for slotIndex = #state.slots, 1, -1 do
		if remaining <= 0 then
			break
		end

		local slot = state.slots[slotIndex]
		local stack = slot.stack
		if stack == nil then
			continue
		end
		if stack.itemId ~= itemId then
			continue
		end
		if not metadataMatches(stack.metadata, metadataRaw, requireExactMetadata) then
			continue
		end

		local removed = math.min(remaining, stack.amount)
		stack.amount -= removed
		remaining -= removed
		appendTouchedSlot(touchedSlots, slot.index)
		if stack.amount <= 0 then
			slot.stack = nil
		end
	end

	local removedTotal = requested - remaining
	local changed = removedTotal > 0
	if changed then
		refreshStateDerived(state, true)
	end

	return {
		requested = requested,
		removed = removedTotal,
		leftover = remaining,
		changed = changed,
		touchedSlots = touchedSlots,
	}
end

function InventoryServiceUtils.removeFromSlot(state: InventoryState, slotIndexRaw: any, amountRaw: any): SlotMutationResult
	local slot = InventoryServiceUtils.getSlot(state, slotIndexRaw)
	if slot == nil or slot.stack == nil then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = nil,
			toSlot = nil,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	local stack = slot.stack
	local amount = if amountRaw == nil
		then stack.amount
		else sanitizeInteger(amountRaw, 0, 0, stack.amount)
	if amount <= 0 then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = slot.index,
			toSlot = nil,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	stack.amount -= amount
	if stack.amount <= 0 then
		slot.stack = nil
	end
	refreshStateDerived(state, true)

	return {
		changed = true,
		touchedSlots = { slot.index },
		fromSlot = slot.index,
		toSlot = nil,
		movedAmount = 0,
		removedAmount = amount,
		swapped = false,
	}
end

function InventoryServiceUtils.trashSlot(state: InventoryState, slotIndexRaw: any, amountRaw: any): SlotMutationResult
	return InventoryServiceUtils.removeFromSlot(state, slotIndexRaw, amountRaw)
end

function InventoryServiceUtils.moveSlot(
	state: InventoryState,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
): SlotMutationResult
	local fromSlot = InventoryServiceUtils.getSlot(state, fromSlotRaw)
	local toSlot = InventoryServiceUtils.getSlot(state, toSlotRaw)
	if fromSlot == nil or toSlot == nil then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = nil,
			toSlot = nil,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end
	if fromSlot.index == toSlot.index then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	local sourceStack = fromSlot.stack
	if sourceStack == nil then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	local requestedAmount = if amountRaw == nil then sourceStack.amount else sanitizeInteger(amountRaw, 0, 0, sourceStack.amount)
	if requestedAmount <= 0 then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	local touchedSlots = {}
	local movedAmount = 0
	local swapped = false

	local targetStack = toSlot.stack
	if targetStack == nil then
		if requestedAmount >= sourceStack.amount then
			toSlot.stack = sourceStack
			fromSlot.stack = nil
			movedAmount = sourceStack.amount
		else
			sourceStack.amount -= requestedAmount
			local splitStack = cloneStack(sourceStack)
			splitStack.amount = requestedAmount
			splitStack.stackId = ("%s_move_%d_%d"):format(splitStack.stackId, toSlot.index, math.floor(os.clock() * 10000))
			toSlot.stack = splitStack
			movedAmount = requestedAmount
		end
		appendTouchedSlot(touchedSlots, fromSlot.index)
		appendTouchedSlot(touchedSlots, toSlot.index)
		refreshStateDerived(state, true)
		return {
			changed = true,
			touchedSlots = touchedSlots,
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = movedAmount,
			removedAmount = 0,
			swapped = false,
		}
	end

	if sourceStack.itemId == targetStack.itemId and deepEqual(sourceStack.metadata, targetStack.metadata) then
		local room = math.max(0, targetStack.maxStack - targetStack.amount)
		local amountToMove = math.min(requestedAmount, room, sourceStack.amount)
		if amountToMove <= 0 then
			return {
				changed = false,
				touchedSlots = {},
				fromSlot = fromSlot.index,
				toSlot = toSlot.index,
				movedAmount = 0,
				removedAmount = 0,
				swapped = false,
			}
		end

		targetStack.amount += amountToMove
		sourceStack.amount -= amountToMove
		if sourceStack.amount <= 0 then
			fromSlot.stack = nil
		end
		appendTouchedSlot(touchedSlots, fromSlot.index)
		appendTouchedSlot(touchedSlots, toSlot.index)
		refreshStateDerived(state, true)
		return {
			changed = true,
			touchedSlots = touchedSlots,
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = amountToMove,
			removedAmount = 0,
			swapped = false,
		}
	end

	if requestedAmount < sourceStack.amount then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	fromSlot.stack = targetStack
	toSlot.stack = sourceStack
	swapped = true
	appendTouchedSlot(touchedSlots, fromSlot.index)
	appendTouchedSlot(touchedSlots, toSlot.index)
	refreshStateDerived(state, true)
	return {
		changed = true,
		touchedSlots = touchedSlots,
		fromSlot = fromSlot.index,
		toSlot = toSlot.index,
		movedAmount = sourceStack.amount,
		removedAmount = 0,
		swapped = swapped,
	}
end

function InventoryServiceUtils.splitSlot(
	state: InventoryState,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
): SlotMutationResult
	local fromSlot = InventoryServiceUtils.getSlot(state, fromSlotRaw)
	local toSlot = InventoryServiceUtils.getSlot(state, toSlotRaw)
	if fromSlot == nil or toSlot == nil then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = nil,
			toSlot = nil,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end
	if fromSlot.index == toSlot.index then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	local sourceStack = fromSlot.stack
	if sourceStack == nil or toSlot.stack ~= nil then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	local maxSplit = math.max(0, sourceStack.amount - 1)
	local splitAmount = sanitizeInteger(amountRaw, math.floor(sourceStack.amount * 0.5), 1, maxSplit)
	if splitAmount <= 0 or splitAmount >= sourceStack.amount then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = fromSlot.index,
			toSlot = toSlot.index,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	sourceStack.amount -= splitAmount
	local splitStack = cloneStack(sourceStack)
	splitStack.amount = splitAmount
	splitStack.stackId = ("%s_split_%d_%d"):format(
		splitStack.stackId,
		toSlot.index,
		math.floor(os.clock() * 10000)
	)
	toSlot.stack = splitStack
	refreshStateDerived(state, true)

	return {
		changed = true,
		touchedSlots = { fromSlot.index, toSlot.index },
		fromSlot = fromSlot.index,
		toSlot = toSlot.index,
		movedAmount = splitAmount,
		removedAmount = 0,
		swapped = false,
	}
end

function InventoryServiceUtils.consumeSelected(state: InventoryState, amountRaw: any): SlotMutationResult
	local selectedSlot = state.selectedSlot
	if selectedSlot == nil then
		return {
			changed = false,
			touchedSlots = {},
			fromSlot = nil,
			toSlot = nil,
			movedAmount = 0,
			removedAmount = 0,
			swapped = false,
		}
	end

	return InventoryServiceUtils.removeFromSlot(state, selectedSlot, amountRaw)
end

function InventoryServiceUtils.trashSelected(state: InventoryState, amountRaw: any): SlotMutationResult
	return InventoryServiceUtils.consumeSelected(state, amountRaw)
end

function InventoryServiceUtils.countItem(
	state: InventoryState,
	itemIdRaw: any,
	metadataRaw: any,
	requireExactMetadataRaw: any
): number
	local itemId = normalizeItemId(itemIdRaw, nil)
	if itemId == nil then
		return 0
	end

	local requireExactMetadata = requireExactMetadataRaw == true
	local total = 0
	for _, slot in state.slots do
		local stack = slot.stack
		if stack == nil then
			continue
		end
		if stack.itemId ~= itemId then
			continue
		end
		if not metadataMatches(stack.metadata, metadataRaw, requireExactMetadata) then
			continue
		end
		total += stack.amount
	end
	return total
end

return InventoryServiceUtils
