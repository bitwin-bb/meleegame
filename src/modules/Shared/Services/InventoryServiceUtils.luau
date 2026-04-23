--!strict
local InventoryServiceUtils = {}

export type InventoryLoadState = "Unloaded" | "Loading" | "Loaded" | "Failed"
export type InventoryItemMetadata = { [string]: any }
export type InventoryItemStack = { stackId: string, itemId: string, amount: number, maxStack: number, metadata: InventoryItemMetadata? }
export type InventorySlot = { index: number, stack: InventoryItemStack? }
export type InventoryState = {
	capacity: number,
	slots: { InventorySlot },
	selectedSlot: number?,
	occupiedSlotCount: number,
	totalItemCount: number,
	loadState: InventoryLoadState,
	updatedAt: number,
}
export type AddItemResult = { requested: number, added: number, leftover: number, changed: boolean, touchedSlots: { number } }
export type RemoveItemResult = { requested: number, removed: number, leftover: number, changed: boolean, touchedSlots: { number } }
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
InventoryServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_SET_SELECTED_SLOT = "requestSetSelectedSlot"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_MOVE_SLOT = "requestMoveSlot"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_SPLIT_SLOT = "requestSplitSlot"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_DROP_SLOT = "requestDropFromSlot"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SLOT = "requestTrashSlot"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SELECTED_SLOT = "requestTrashSelectedSlot"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_USE_SELECTED_SLOT = "requestUseSelectedSlot"
InventoryServiceUtils.NETWORK_METHOD_REQUEST_PLACE_SELECTED_DEPLOYABLE = "requestPlaceSelectedDeployable"
InventoryServiceUtils.DEFAULT_CAPACITY = DEFAULT_CAPACITY
InventoryServiceUtils.MIN_CAPACITY = MIN_CAPACITY
InventoryServiceUtils.MAX_CAPACITY = MAX_CAPACITY
InventoryServiceUtils.DEFAULT_MAX_STACK = DEFAULT_MAX_STACK
InventoryServiceUtils.DEFAULT_DATA_PATH = DEFAULT_DATA_PATH

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
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
	local cached = seen[value]
	if cached ~= nil then
		return cached
	end
	local clone = {}
	seen[value] = clone
	for key, nested in value do
		clone[cloneDeepInternal(key, seen)] = cloneDeepInternal(nested, seen)
	end
	return clone
end

local function deepEqualInternal(a: any, b: any, seen: { [any]: any }): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end
	local cached = seen[a]
	if cached ~= nil then
		return cached == b
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

local function sanitizeMetadata(metadataRaw: any): InventoryItemMetadata?
	if typeof(metadataRaw) ~= "table" then
		return nil
	end
	return cloneDeepInternal(metadataRaw, {})
end

local function normalizeLoadState(loadStateRaw: any, fallback: InventoryLoadState?): InventoryLoadState
	if loadStateRaw == LOAD_STATE_UNLOADED or loadStateRaw == LOAD_STATE_LOADING or loadStateRaw == LOAD_STATE_LOADED or loadStateRaw == LOAD_STATE_FAILED then
		return loadStateRaw
	end
	return fallback or LOAD_STATE_UNLOADED
end

local function normalizeCapacity(capacityRaw: any, fallback: number?): number
	local base = if typeof(fallback) == "number" and fallback == fallback then fallback else DEFAULT_CAPACITY
	return math.max(DEFAULT_CAPACITY, sanitizeInteger(capacityRaw, base, MIN_CAPACITY, MAX_CAPACITY))
end

local function resolveCapacity(stateOrCapacityRaw: any): number
	if typeof(stateOrCapacityRaw) == "number" then
		return normalizeCapacity(stateOrCapacityRaw, DEFAULT_CAPACITY)
	end
	if typeof(stateOrCapacityRaw) == "table" then
		return normalizeCapacity((stateOrCapacityRaw :: any).capacity, DEFAULT_CAPACITY)
	end
	return DEFAULT_CAPACITY
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

local function normalizeUpdatedAt(updatedAtRaw: any, fallback: number?): number
	local value = if typeof(updatedAtRaw) == "number" and updatedAtRaw == updatedAtRaw then updatedAtRaw else fallback or 0
	return math.max(0, math.floor(value))
end

local function cloneStack(stack: InventoryItemStack): InventoryItemStack
	return {
		stackId = stack.stackId,
		itemId = stack.itemId,
		amount = stack.amount,
		maxStack = stack.maxStack,
		metadata = sanitizeMetadata(stack.metadata),
	}
end

local function createEmptySlots(capacity: number): { InventorySlot }
	local slots = table.create(capacity)
	for index = 1, capacity do
		slots[index] = { index = index, stack = nil }
	end
	return slots
end

local function normalizeStack(stackRaw: any, fallbackStackIdRaw: any): InventoryItemStack?
	if typeof(stackRaw) ~= "table" then
		return nil
	end
	local stackTable = stackRaw :: { [string]: any }
	local itemId = normalizeItemId(stackTable.itemId, nil)
	if itemId == nil then
		return nil
	end
	local amount = sanitizeInteger(stackTable.amount, 1, MIN_STACK, MAX_STACK)
	local maxStack = sanitizeInteger(stackTable.maxStack, math.max(DEFAULT_MAX_STACK, amount), MIN_STACK, MAX_STACK)
	local fallbackStackId = sanitizeString(fallbackStackIdRaw, ("stack_%s"):format(itemId)) or ("stack_%s"):format(itemId)
	return {
		stackId = sanitizeString(stackTable.stackId, fallbackStackId) or fallbackStackId,
		itemId = itemId,
		amount = math.clamp(amount, MIN_STACK, maxStack),
		maxStack = maxStack,
		metadata = sanitizeMetadata(stackTable.metadata),
	}
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
		local slotIndex = normalizeSlotIndex(entry.index, capacity, normalizeSlotIndex(key, capacity, nil))
		if slotIndex == nil then
			continue
		end
		local stackRaw = entry.stack
		if stackRaw == nil and (entry.itemId ~= nil or entry.stackId ~= nil) then
			stackRaw = entry
		end
		slots[slotIndex] = {
			index = slotIndex,
			stack = normalizeStack(stackRaw, ("slot_%d"):format(slotIndex)),
		}
	end
	return slots
end

local function appendTouchedSlot(touchedSlots: { number }, slotIndex: number)
	for _, touched in touchedSlots do
		if touched == slotIndex then
			return
		end
	end
	touchedSlots[#touchedSlots + 1] = slotIndex
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
	state.selectedSlot = normalizeSlotIndex(state.selectedSlot, state.capacity, nil)
	if updateTimestamp then
		state.updatedAt = math.max(0, math.floor(state.updatedAt)) + 1
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

local function serializeScalar(value: any): string
	local valueType = typeof(value)
	if valueType == "table" then
		return "table"
	end
	return ("%s:%s"):format(valueType, tostring(value))
end

local function stableSerialize(value: any, seen: { [any]: boolean }): string
	if typeof(value) ~= "table" then
		return serializeScalar(value)
	end
	if seen[value] == true then
		return "cycle"
	end
	seen[value] = true
	local keys = {}
	for key in value do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return serializeScalar(a) < serializeScalar(b)
	end)
	local parts = table.create(#keys)
	for index, key in keys do
		parts[index] = ("%s=%s"):format(serializeScalar(key), stableSerialize(value[key], seen))
	end
	seen[value] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

local function nextStackId(state: InventoryState, prefixRaw: any, itemIdRaw: any): string
	local prefix = sanitizeString(prefixRaw, "stack") or "stack"
	local itemId = sanitizeString(itemIdRaw, "item") or "item"
	local used = {}
	for _, slot in state.slots do
		if slot.stack ~= nil then
			used[slot.stack.stackId] = true
		end
	end
	local serial = 1
	while true do
		local candidate = ("%s_%s_%d"):format(prefix, itemId, serial)
		if used[candidate] ~= true then
			return candidate
		end
		serial += 1
	end
end

local function emptyAddResult(requested: number): AddItemResult
	return { requested = requested, added = 0, leftover = requested, changed = false, touchedSlots = {} }
end

local function emptyRemoveResult(requested: number): RemoveItemResult
	return { requested = requested, removed = 0, leftover = requested, changed = false, touchedSlots = {} }
end

local function emptySlotMutation(fromSlot: number?, toSlot: number?): SlotMutationResult
	return {
		changed = false,
		touchedSlots = {},
		fromSlot = fromSlot,
		toSlot = toSlot,
		movedAmount = 0,
		removedAmount = 0,
		swapped = false,
	}
end

function InventoryServiceUtils.CloneDeep(value: any): any
	return cloneDeepInternal(value, {})
end

function InventoryServiceUtils.DeepEqual(a: any, b: any): boolean
	return deepEqual(a, b)
end

function InventoryServiceUtils.ClonePath(pathRaw: any): { string }
	local source = if typeof(pathRaw) == "table" then pathRaw else DEFAULT_DATA_PATH
	local path = {}
	for _, segmentRaw in source do
		local segment = sanitizeString(segmentRaw, nil)
		if segment ~= nil then
			path[#path + 1] = segment
		end
	end
	if #path <= 0 then
		return { "inventory" }
	end
	return path
end

function InventoryServiceUtils.GetDefaultDataPath(): { string }
	return InventoryServiceUtils.ClonePath(DEFAULT_DATA_PATH)
end

function InventoryServiceUtils.SanitizeLoadState(loadStateRaw: any, fallback: InventoryLoadState?): InventoryLoadState
	return normalizeLoadState(loadStateRaw, fallback)
end

function InventoryServiceUtils.SanitizeCapacity(capacityRaw: any, fallbackRaw: any?): number
	return normalizeCapacity(capacityRaw, if typeof(fallbackRaw) == "number" then fallbackRaw else DEFAULT_CAPACITY)
end

function InventoryServiceUtils.SanitizeSlotIndex(slotIndexRaw: any, stateOrCapacityRaw: any, fallbackRaw: any?): number?
	return normalizeSlotIndex(slotIndexRaw, resolveCapacity(stateOrCapacityRaw), if typeof(fallbackRaw) == "number" then math.floor(fallbackRaw) else nil)
end

function InventoryServiceUtils.SanitizeAmount(amountRaw: any, fallbackRaw: any, minimumRaw: any?, maximumRaw: any?): number
	return sanitizeInteger(amountRaw, if typeof(fallbackRaw) == "number" then math.floor(fallbackRaw) else 0, if typeof(minimumRaw) == "number" then math.floor(minimumRaw) else 0, if typeof(maximumRaw) == "number" then math.floor(maximumRaw) else nil)
end

function InventoryServiceUtils.SanitizeStack(stackRaw: any, fallbackStackIdRaw: any): InventoryItemStack?
	return normalizeStack(stackRaw, fallbackStackIdRaw)
end

function InventoryServiceUtils.CloneStack(stackRaw: any): InventoryItemStack?
	local stack = normalizeStack(stackRaw, "stack_item")
	if stack == nil then
		return nil
	end
	return cloneStack(stack)
end

function InventoryServiceUtils.IsLoadedState(loadStateRaw: any): boolean
	return normalizeLoadState(loadStateRaw, LOAD_STATE_UNLOADED) == LOAD_STATE_LOADED
end

function InventoryServiceUtils.CreateDefaultState(loadStateRaw: any): InventoryState
	return {
		capacity = DEFAULT_CAPACITY,
		slots = createEmptySlots(DEFAULT_CAPACITY),
		selectedSlot = nil,
		occupiedSlotCount = 0,
		totalItemCount = 0,
		loadState = normalizeLoadState(loadStateRaw, LOAD_STATE_UNLOADED),
		updatedAt = 0,
	}
end

function InventoryServiceUtils.CreateState(stateRaw: any, fallbackStateRaw: any): InventoryState
	local fallback = if typeof(fallbackStateRaw) == "table" then (fallbackStateRaw :: InventoryState) else InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)
	local source = if typeof(stateRaw) == "table" then (stateRaw :: { [string]: any }) else {}
	local state: InventoryState = {
		capacity = normalizeCapacity(source.capacity, fallback.capacity),
		slots = normalizeSlots(source.slots, normalizeCapacity(source.capacity, fallback.capacity)),
		selectedSlot = nil,
		occupiedSlotCount = 0,
		totalItemCount = 0,
		loadState = normalizeLoadState(source.loadState, fallback.loadState),
		updatedAt = normalizeUpdatedAt(source.updatedAt, fallback.updatedAt),
	}
	state.selectedSlot = normalizeSlotIndex(source.selectedSlot, state.capacity, fallback.selectedSlot)
	refreshStateDerived(state, false)
	return state
end

function InventoryServiceUtils.CreateStateFromData(dataRaw: any, fallbackStateRaw: any, loadStateRaw: any): InventoryState
	local fallback = if typeof(fallbackStateRaw) == "table" then (fallbackStateRaw :: InventoryState) else InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)
	local dataTable = if typeof(dataRaw) == "table" then (dataRaw :: { [string]: any }) else {}
	local slotsRaw = if typeof(dataTable.slots) == "table" then dataTable.slots else dataTable.items
	local state = InventoryServiceUtils.CreateState({
		capacity = dataTable.capacity,
		slots = slotsRaw,
		selectedSlot = dataTable.selectedSlot,
		loadState = normalizeLoadState(loadStateRaw, LOAD_STATE_LOADED),
		updatedAt = normalizeUpdatedAt(dataTable.updatedAt, fallback.updatedAt + 1),
	}, fallback)
	state.loadState = normalizeLoadState(loadStateRaw, LOAD_STATE_LOADED)
	return state
end

function InventoryServiceUtils.SanitizeState(stateRaw: any, fallbackStateRaw: any): InventoryState
	return InventoryServiceUtils.CreateState(stateRaw, fallbackStateRaw)
end

function InventoryServiceUtils.CloneState(stateRaw: any): InventoryState
	local state = if typeof(stateRaw) == "table" then InventoryServiceUtils.SanitizeState(stateRaw, InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)) else InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)
	local slots = table.create(#state.slots)
	for index, slot in state.slots do
		slots[index] = { index = slot.index, stack = if slot.stack ~= nil then cloneStack(slot.stack) else nil }
	end
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

function InventoryServiceUtils.SerializeStateForData(stateRaw: any): { [string]: any }
	local state = if typeof(stateRaw) == "table" then InventoryServiceUtils.SanitizeState(stateRaw, InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)) else InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)
	local slots = {}
	for _, slot in state.slots do
		if slot.stack ~= nil then
			slots[#slots + 1] = {
				index = slot.index,
				stackId = slot.stack.stackId,
				itemId = slot.stack.itemId,
				amount = slot.stack.amount,
				maxStack = slot.stack.maxStack,
				metadata = sanitizeMetadata(slot.stack.metadata),
			}
		end
	end
	return {
		capacity = state.capacity,
		selectedSlot = state.selectedSlot,
		slots = slots,
	}
end

function InventoryServiceUtils.HashState(stateRaw: any): string
	local state = if typeof(stateRaw) == "table" then InventoryServiceUtils.SanitizeState(stateRaw, InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)) else InventoryServiceUtils.CreateDefaultState(LOAD_STATE_UNLOADED)
	return stableSerialize({
		loadState = state.loadState,
		updatedAt = state.updatedAt,
		state = InventoryServiceUtils.SerializeStateForData(state),
	}, {})
end

function InventoryServiceUtils.SetLoadState(state: InventoryState, loadStateRaw: any): boolean
	local nextLoadState = normalizeLoadState(loadStateRaw, state.loadState)
	if state.loadState == nextLoadState then
		return false
	end
	state.loadState = nextLoadState
	refreshStateDerived(state, true)
	return true
end

function InventoryServiceUtils.SetSelectedSlot(state: InventoryState, slotIndexRaw: any): boolean
	local nextSelectedSlot = normalizeSlotIndex(slotIndexRaw, state.capacity, nil)
	if state.selectedSlot == nextSelectedSlot then
		return false
	end
	state.selectedSlot = nextSelectedSlot
	refreshStateDerived(state, true)
	return true
end

function InventoryServiceUtils.GetSlot(state: InventoryState, slotIndexRaw: any): InventorySlot?
	local slotIndex = normalizeSlotIndex(slotIndexRaw, state.capacity, nil)
	if slotIndex == nil then
		return nil
	end
	return state.slots[slotIndex]
end

function InventoryServiceUtils.GetStack(state: InventoryState, slotIndexRaw: any): InventoryItemStack?
	local slot = InventoryServiceUtils.GetSlot(state, slotIndexRaw)
	if slot == nil then
		return nil
	end
	return slot.stack
end

function InventoryServiceUtils.Clear(state: InventoryState): boolean
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

function InventoryServiceUtils.AddItem(state: InventoryState, itemIdRaw: any, amountRaw: any, maxStackRaw: any, metadataRaw: any, stackIdPrefixRaw: any): AddItemResult
	local itemId = normalizeItemId(itemIdRaw, nil)
	local requested = sanitizeInteger(amountRaw, 0, 0, MAX_STACK * state.capacity)
	local maxStack = sanitizeInteger(maxStackRaw, DEFAULT_MAX_STACK, MIN_STACK, MAX_STACK)
	local metadata = sanitizeMetadata(metadataRaw)
	local result = emptyAddResult(requested)
	if itemId == nil or requested <= 0 then
		return result
	end
	local remaining = requested
	for _, slot in state.slots do
		if remaining <= 0 then
			break
		end
		local stack = slot.stack
		if stack == nil or stack.itemId ~= itemId or not metadataMatches(stack.metadata, metadata, true) then
			continue
		end
		local room = math.max(0, stack.maxStack - stack.amount)
		if room <= 0 then
			continue
		end
		local added = math.min(remaining, room)
		stack.amount += added
		remaining -= added
		appendTouchedSlot(result.touchedSlots, slot.index)
	end
	local prefix = sanitizeString(stackIdPrefixRaw, "stack") or "stack"
	for _, slot in state.slots do
		if remaining <= 0 then
			break
		end
		if slot.stack ~= nil then
			continue
		end
		local added = math.min(remaining, maxStack)
		slot.stack = {
			stackId = nextStackId(state, prefix, itemId),
			itemId = itemId,
			amount = added,
			maxStack = maxStack,
			metadata = sanitizeMetadata(metadata),
		}
		remaining -= added
		appendTouchedSlot(result.touchedSlots, slot.index)
	end
	result.added = requested - remaining
	result.leftover = remaining
	result.changed = result.added > 0
	if result.changed then
		refreshStateDerived(state, true)
	end
	return result
end

function InventoryServiceUtils.RemoveItem(state: InventoryState, itemIdRaw: any, amountRaw: any, metadataRaw: any, requireExactMetadataRaw: any): RemoveItemResult
	local itemId = normalizeItemId(itemIdRaw, nil)
	local requested = sanitizeInteger(amountRaw, 0, 0, MAX_STACK * state.capacity)
	local result = emptyRemoveResult(requested)
	local requireExactMetadata = requireExactMetadataRaw == true
	if itemId == nil or requested <= 0 then
		return result
	end
	local remaining = requested
	for index = #state.slots, 1, -1 do
		if remaining <= 0 then
			break
		end
		local slot = state.slots[index]
		local stack = slot.stack
		if stack == nil or stack.itemId ~= itemId or not metadataMatches(stack.metadata, metadataRaw, requireExactMetadata) then
			continue
		end
		local removed = math.min(remaining, stack.amount)
		stack.amount -= removed
		remaining -= removed
		appendTouchedSlot(result.touchedSlots, slot.index)
		if stack.amount <= 0 then
			slot.stack = nil
		end
	end
	result.removed = requested - remaining
	result.leftover = remaining
	result.changed = result.removed > 0
	if result.changed then
		refreshStateDerived(state, true)
	end
	return result
end

function InventoryServiceUtils.RemoveFromSlot(state: InventoryState, slotIndexRaw: any, amountRaw: any): SlotMutationResult
	local slot = InventoryServiceUtils.GetSlot(state, slotIndexRaw)
	if slot == nil or slot.stack == nil then
		return emptySlotMutation(nil, nil)
	end
	local amount = if amountRaw == nil then slot.stack.amount else sanitizeInteger(amountRaw, 0, 0, slot.stack.amount)
	if amount <= 0 then
		return emptySlotMutation(slot.index, nil)
	end
	slot.stack.amount -= amount
	if slot.stack.amount <= 0 then
		slot.stack = nil
	end
	refreshStateDerived(state, true)
	return { changed = true, touchedSlots = { slot.index }, fromSlot = slot.index, toSlot = nil, movedAmount = 0, removedAmount = amount, swapped = false }
end

function InventoryServiceUtils.TrashSlot(state: InventoryState, slotIndexRaw: any, amountRaw: any): SlotMutationResult
	return InventoryServiceUtils.RemoveFromSlot(state, slotIndexRaw, amountRaw)
end

function InventoryServiceUtils.MoveSlot(state: InventoryState, fromSlotRaw: any, toSlotRaw: any, amountRaw: any): SlotMutationResult
	local fromSlot = InventoryServiceUtils.GetSlot(state, fromSlotRaw)
	local toSlot = InventoryServiceUtils.GetSlot(state, toSlotRaw)
	if fromSlot == nil or toSlot == nil then
		return emptySlotMutation(nil, nil)
	end
	if fromSlot.index == toSlot.index or fromSlot.stack == nil then
		return emptySlotMutation(fromSlot.index, toSlot.index)
	end
	local sourceStack = fromSlot.stack
	local requestedAmount = if amountRaw == nil then sourceStack.amount else sanitizeInteger(amountRaw, 0, 0, sourceStack.amount)
	if requestedAmount <= 0 then
		return emptySlotMutation(fromSlot.index, toSlot.index)
	end
	local targetStack = toSlot.stack
	if targetStack == nil then
		if requestedAmount >= sourceStack.amount then
			toSlot.stack = sourceStack
			fromSlot.stack = nil
			refreshStateDerived(state, true)
			return { changed = true, touchedSlots = { fromSlot.index, toSlot.index }, fromSlot = fromSlot.index, toSlot = toSlot.index, movedAmount = sourceStack.amount, removedAmount = 0, swapped = false }
		end
		sourceStack.amount -= requestedAmount
		local movedStack = cloneStack(sourceStack)
		movedStack.amount = requestedAmount
		movedStack.stackId = nextStackId(state, sourceStack.stackId .. "_move_" .. tostring(toSlot.index), sourceStack.itemId)
		toSlot.stack = movedStack
		refreshStateDerived(state, true)
		return { changed = true, touchedSlots = { fromSlot.index, toSlot.index }, fromSlot = fromSlot.index, toSlot = toSlot.index, movedAmount = requestedAmount, removedAmount = 0, swapped = false }
	end
	if sourceStack.itemId == targetStack.itemId and deepEqual(sourceStack.metadata, targetStack.metadata) then
		local room = math.max(0, targetStack.maxStack - targetStack.amount)
		local movedAmount = math.min(requestedAmount, room, sourceStack.amount)
		if movedAmount <= 0 then
			return emptySlotMutation(fromSlot.index, toSlot.index)
		end
		targetStack.amount += movedAmount
		sourceStack.amount -= movedAmount
		if sourceStack.amount <= 0 then
			fromSlot.stack = nil
		end
		refreshStateDerived(state, true)
		return { changed = true, touchedSlots = { fromSlot.index, toSlot.index }, fromSlot = fromSlot.index, toSlot = toSlot.index, movedAmount = movedAmount, removedAmount = 0, swapped = false }
	end
	if requestedAmount < sourceStack.amount then
		return emptySlotMutation(fromSlot.index, toSlot.index)
	end
	fromSlot.stack = targetStack
	toSlot.stack = sourceStack
	refreshStateDerived(state, true)
	return { changed = true, touchedSlots = { fromSlot.index, toSlot.index }, fromSlot = fromSlot.index, toSlot = toSlot.index, movedAmount = sourceStack.amount, removedAmount = 0, swapped = true }
end

function InventoryServiceUtils.SplitSlot(state: InventoryState, fromSlotRaw: any, toSlotRaw: any, amountRaw: any): SlotMutationResult
	local fromSlot = InventoryServiceUtils.GetSlot(state, fromSlotRaw)
	local toSlot = InventoryServiceUtils.GetSlot(state, toSlotRaw)
	if fromSlot == nil or toSlot == nil then
		return emptySlotMutation(nil, nil)
	end
	if fromSlot.index == toSlot.index or toSlot.stack ~= nil or fromSlot.stack == nil then
		return emptySlotMutation(fromSlot.index, toSlot.index)
	end
	local sourceStack = fromSlot.stack
	local maxSplit = math.max(0, sourceStack.amount - 1)
	local splitAmount = sanitizeInteger(amountRaw, math.floor(sourceStack.amount * 0.5), 1, maxSplit)
	if splitAmount <= 0 or splitAmount >= sourceStack.amount then
		return emptySlotMutation(fromSlot.index, toSlot.index)
	end
	sourceStack.amount -= splitAmount
	local splitStack = cloneStack(sourceStack)
	splitStack.amount = splitAmount
	splitStack.stackId = nextStackId(state, sourceStack.stackId .. "_split_" .. tostring(toSlot.index), sourceStack.itemId)
	toSlot.stack = splitStack
	refreshStateDerived(state, true)
	return { changed = true, touchedSlots = { fromSlot.index, toSlot.index }, fromSlot = fromSlot.index, toSlot = toSlot.index, movedAmount = splitAmount, removedAmount = 0, swapped = false }
end

function InventoryServiceUtils.ConsumeSelected(state: InventoryState, amountRaw: any): SlotMutationResult
	if state.selectedSlot == nil then
		return emptySlotMutation(nil, nil)
	end
	return InventoryServiceUtils.RemoveFromSlot(state, state.selectedSlot, amountRaw)
end

function InventoryServiceUtils.TrashSelected(state: InventoryState, amountRaw: any): SlotMutationResult
	return InventoryServiceUtils.ConsumeSelected(state, amountRaw)
end

function InventoryServiceUtils.CountItem(state: InventoryState, itemIdRaw: any, metadataRaw: any, requireExactMetadataRaw: any): number
	local itemId = normalizeItemId(itemIdRaw, nil)
	if itemId == nil then
		return 0
	end
	local requireExactMetadata = requireExactMetadataRaw == true
	local total = 0
	for _, slot in state.slots do
		local stack = slot.stack
		if stack ~= nil and stack.itemId == itemId and metadataMatches(stack.metadata, metadataRaw, requireExactMetadata) then
			total += stack.amount
		end
	end
	return total
end

InventoryServiceUtils.cloneDeep = InventoryServiceUtils.CloneDeep
InventoryServiceUtils.deepEqual = InventoryServiceUtils.DeepEqual
InventoryServiceUtils.clonePath = InventoryServiceUtils.ClonePath
InventoryServiceUtils.getDefaultDataPath = InventoryServiceUtils.GetDefaultDataPath
InventoryServiceUtils.sanitizeLoadState = InventoryServiceUtils.SanitizeLoadState
InventoryServiceUtils.sanitizeCapacity = InventoryServiceUtils.SanitizeCapacity
InventoryServiceUtils.sanitizeSlotIndex = InventoryServiceUtils.SanitizeSlotIndex
InventoryServiceUtils.sanitizeAmount = InventoryServiceUtils.SanitizeAmount
InventoryServiceUtils.sanitizeStack = InventoryServiceUtils.SanitizeStack
InventoryServiceUtils.cloneStack = InventoryServiceUtils.CloneStack
InventoryServiceUtils.isLoadedState = InventoryServiceUtils.IsLoadedState
InventoryServiceUtils.createDefaultState = InventoryServiceUtils.CreateDefaultState
InventoryServiceUtils.createState = InventoryServiceUtils.CreateState
InventoryServiceUtils.createStateFromData = InventoryServiceUtils.CreateStateFromData
InventoryServiceUtils.sanitizeState = InventoryServiceUtils.SanitizeState
InventoryServiceUtils.cloneState = InventoryServiceUtils.CloneState
InventoryServiceUtils.serializeStateForData = InventoryServiceUtils.SerializeStateForData
InventoryServiceUtils.hashState = InventoryServiceUtils.HashState
InventoryServiceUtils.setLoadState = InventoryServiceUtils.SetLoadState
InventoryServiceUtils.setSelectedSlot = InventoryServiceUtils.SetSelectedSlot
InventoryServiceUtils.getSlot = InventoryServiceUtils.GetSlot
InventoryServiceUtils.getStack = InventoryServiceUtils.GetStack
InventoryServiceUtils.clear = InventoryServiceUtils.Clear
InventoryServiceUtils.addItem = InventoryServiceUtils.AddItem
InventoryServiceUtils.removeItem = InventoryServiceUtils.RemoveItem
InventoryServiceUtils.removeFromSlot = InventoryServiceUtils.RemoveFromSlot
InventoryServiceUtils.trashSlot = InventoryServiceUtils.TrashSlot
InventoryServiceUtils.moveSlot = InventoryServiceUtils.MoveSlot
InventoryServiceUtils.splitSlot = InventoryServiceUtils.SplitSlot
InventoryServiceUtils.consumeSelected = InventoryServiceUtils.ConsumeSelected
InventoryServiceUtils.trashSelected = InventoryServiceUtils.TrashSelected
InventoryServiceUtils.countItem = InventoryServiceUtils.CountItem

return InventoryServiceUtils
