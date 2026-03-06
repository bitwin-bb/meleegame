--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)

type InventoryItemStack = InventoryServiceUtils.InventoryItemStack

export type ItemDragState = {
	active: boolean,
	sourceSlot: number?,
	hoveredSlot: number?,
	stack: InventoryItemStack?,
	itemType: string?,
	icon: string?,
	pointerPosition: Vector2,
	updatedAt: number,
}

export type ItemDragDebugState = {
	enabled: boolean,
	lines: { string },
	updatedAt: number,
}

local MAX_DEBUG_LINES = 12

local function sanitizeSlot(slotRaw: any): number?
	if typeof(slotRaw) ~= "number" or slotRaw ~= slotRaw then
		return nil
	end

	local slot = math.floor(slotRaw)
	if slot <= 0 then
		return nil
	end
	return slot
end

local function sanitizeVector2(valueRaw: any): Vector2
	if typeof(valueRaw) == "Vector3" then
		local value3 = valueRaw :: Vector3
		if value3.X ~= value3.X or value3.Y ~= value3.Y then
			return Vector2.zero
		end
		return Vector2.new(value3.X, value3.Y)
	end
	if typeof(valueRaw) ~= "Vector2" then
		return Vector2.zero
	end
	if valueRaw.X ~= valueRaw.X or valueRaw.Y ~= valueRaw.Y then
		return Vector2.zero
	end
	return valueRaw
end

local function sanitizeText(valueRaw: any): string?
	if typeof(valueRaw) ~= "string" then
		return nil
	end
	local value = string.match(valueRaw, "^%s*(.-)%s*$")
	if value == nil or value == "" then
		return nil
	end
	return value
end

local function cloneStack(stackRaw: any): InventoryItemStack?
	if typeof(stackRaw) ~= "table" then
		return nil
	end

	local stack = stackRaw :: { [string]: any }
	if typeof(stack.stackId) ~= "string" or typeof(stack.itemId) ~= "string" then
		return nil
	end

	local amount = if typeof(stack.amount) == "number" and stack.amount == stack.amount then math.max(0, stack.amount) else 0
	local maxStack = if typeof(stack.maxStack) == "number" and stack.maxStack == stack.maxStack
		then math.max(1, stack.maxStack)
		else 1

	return {
		stackId = stack.stackId,
		itemId = stack.itemId,
		amount = amount,
		maxStack = maxStack,
		metadata = InventoryServiceUtils.cloneDeep(stack.metadata),
	}
end

local function createDefaultDragState(): ItemDragState
	return {
		active = false,
		sourceSlot = nil,
		hoveredSlot = nil,
		stack = nil,
		itemType = nil,
		icon = nil,
		pointerPosition = Vector2.zero,
		updatedAt = os.clock(),
	}
end

local dragStateAtom: Charm.Atom<ItemDragState> = Charm.atom(createDefaultDragState())
local dragDebugStateAtom: Charm.Atom<ItemDragDebugState> = Charm.atom({
	enabled = true,
	lines = {},
	updatedAt = os.clock(),
})

local function getDragState(): ItemDragState
	return dragStateAtom()
end

local function beginDrag(
	sourceSlotRaw: any,
	stackRaw: any,
	pointerPositionRaw: any,
	itemTypeRaw: any,
	iconRaw: any
): ItemDragState
	local sourceSlot = sanitizeSlot(sourceSlotRaw)
	local stack = cloneStack(stackRaw)
	if sourceSlot == nil or stack == nil then
		return dragStateAtom()
	end

	local nextState: ItemDragState = {
		active = true,
		sourceSlot = sourceSlot,
		hoveredSlot = sourceSlot,
		stack = stack,
		itemType = sanitizeText(itemTypeRaw),
		icon = sanitizeText(iconRaw),
		pointerPosition = sanitizeVector2(pointerPositionRaw),
		updatedAt = os.clock(),
	}
	dragStateAtom(nextState)
	return nextState
end

local function setPointerPosition(pointerPositionRaw: any): ItemDragState
	local state = dragStateAtom()
	if not state.active then
		return state
	end

	local pointerPosition = sanitizeVector2(pointerPositionRaw)
	if pointerPosition == state.pointerPosition then
		return state
	end

	local nextState: ItemDragState = {
		active = state.active,
		sourceSlot = state.sourceSlot,
		hoveredSlot = state.hoveredSlot,
		stack = state.stack,
		itemType = state.itemType,
		icon = state.icon,
		pointerPosition = pointerPosition,
		updatedAt = os.clock(),
	}
	dragStateAtom(nextState)
	return nextState
end

local function setHoveredSlot(slotRaw: any): ItemDragState
	local state = dragStateAtom()
	if not state.active then
		return state
	end

	local hoveredSlot = sanitizeSlot(slotRaw)
	if hoveredSlot == state.hoveredSlot then
		return state
	end

	local nextState: ItemDragState = {
		active = state.active,
		sourceSlot = state.sourceSlot,
		hoveredSlot = hoveredSlot,
		stack = state.stack,
		itemType = state.itemType,
		icon = state.icon,
		pointerPosition = state.pointerPosition,
		updatedAt = os.clock(),
	}
	dragStateAtom(nextState)
	return nextState
end

local function clearDragState(): ItemDragState
	local nextState = createDefaultDragState()
	dragStateAtom(nextState)
	return nextState
end

local function getDragDebugState(): ItemDragDebugState
	return dragDebugStateAtom()
end

local function setDragDebugEnabled(enabledRaw: any): ItemDragDebugState
	local current = dragDebugStateAtom()
	local enabled = enabledRaw == true
	if current.enabled == enabled then
		return current
	end

	local nextState: ItemDragDebugState = {
		enabled = enabled,
		lines = current.lines,
		updatedAt = os.clock(),
	}
	dragDebugStateAtom(nextState)
	return nextState
end

local function clearDragDebug(): ItemDragDebugState
	local current = dragDebugStateAtom()
	local nextState: ItemDragDebugState = {
		enabled = current.enabled,
		lines = {},
		updatedAt = os.clock(),
	}
	dragDebugStateAtom(nextState)
	return nextState
end

local function pushDragDebug(messageRaw: any): ItemDragDebugState
	local current = dragDebugStateAtom()
	if not current.enabled then
		return current
	end

	local message = if typeof(messageRaw) == "string"
		then string.match(messageRaw, "^%s*(.-)%s*$") or ""
		else tostring(messageRaw)
	if message == "" then
		return current
	end

	local timestamp = os.clock()
	local prefix = ("[%0.3f] "):format(timestamp)
	local lines = table.clone(current.lines)
	table.insert(lines, prefix .. message)
	if #lines > MAX_DEBUG_LINES then
		table.remove(lines, 1)
	end

	local nextState: ItemDragDebugState = {
		enabled = current.enabled,
		lines = lines,
		updatedAt = timestamp,
	}
	dragDebugStateAtom(nextState)
	return nextState
end

return {
	dragStateAtom = dragStateAtom,
	dragDebugStateAtom = dragDebugStateAtom,
	createDefaultDragState = createDefaultDragState,
	getDragState = getDragState,
	getDragDebugState = getDragDebugState,
	beginDrag = beginDrag,
	setPointerPosition = setPointerPosition,
	setHoveredSlot = setHoveredSlot,
	setDragDebugEnabled = setDragDebugEnabled,
	clearDragDebug = clearDragDebug,
	pushDragDebug = pushDragDebug,
	clearDragState = clearDragState,
}
