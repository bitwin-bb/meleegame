--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryService.InventoryServiceUtils)

type InventoryState = InventoryServiceUtils.InventoryState
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack

export type TrashState = {
	isHovered: boolean,
	isOpen: boolean,
	canTrash: boolean,
	selectedSlot: number?,
	selectedStack: InventoryItemStack?,
	updatedAt: number,
}

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

local function createDefaultState(): TrashState
	return {
		isHovered = false,
		isOpen = false,
		canTrash = false,
		selectedSlot = nil,
		selectedStack = nil,
		updatedAt = os.clock(),
	}
end

local function createStateFromInventory(inventoryStateRaw: any, fallbackStateRaw: any): TrashState
	local fallback = if typeof(fallbackStateRaw) == "table" then (fallbackStateRaw :: TrashState) else createDefaultState()
	local inventoryState = if typeof(inventoryStateRaw) == "table" then (inventoryStateRaw :: InventoryState) else nil
	if inventoryState == nil then
		return fallback
	end

	local selectedSlot = inventoryState.selectedSlot
	local selectedStack: InventoryItemStack? = nil
	if selectedSlot ~= nil then
		local slot = InventoryServiceUtils.getSlot(inventoryState, selectedSlot)
		if slot ~= nil then
			selectedStack = cloneStack(slot.stack)
		end
	end

	local canTrash = selectedStack ~= nil and selectedStack.amount > 0
	return {
		isHovered = fallback.isHovered,
		isOpen = fallback.isHovered,
		canTrash = canTrash,
		selectedSlot = selectedSlot,
		selectedStack = selectedStack,
		updatedAt = os.clock(),
	}
end

local trashStateAtom: Charm.Atom<TrashState> = Charm.atom(createDefaultState())

local function getTrashState(): TrashState
	return trashStateAtom()
end

local function setHovered(isHoveredRaw: any): TrashState
	local state = trashStateAtom()
	local isHovered = isHoveredRaw == true
	if state.isHovered == isHovered and state.isOpen == isHovered then
		return state
	end

	local nextState: TrashState = {
		isHovered = isHovered,
		isOpen = isHovered,
		canTrash = state.canTrash,
		selectedSlot = state.selectedSlot,
		selectedStack = state.selectedStack,
		updatedAt = os.clock(),
	}
	trashStateAtom(nextState)
	return nextState
end

local function setFromInventoryState(inventoryStateRaw: any): TrashState
	local nextState = createStateFromInventory(inventoryStateRaw, trashStateAtom())
	trashStateAtom(nextState)
	return nextState
end

local function resetTrashState(): TrashState
	local nextState = createDefaultState()
	trashStateAtom(nextState)
	return nextState
end

return {
	trashStateAtom = trashStateAtom,
	createDefaultState = createDefaultState,
	getTrashState = getTrashState,
	setHovered = setHovered,
	setFromInventoryState = setFromInventoryState,
	resetTrashState = resetTrashState,
}
