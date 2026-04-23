--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryServiceUtils)

type InventoryState = InventoryServiceUtils.InventoryState
type InventorySlot = InventoryServiceUtils.InventorySlot

local inventoryStateAtom: Charm.Atom<InventoryState> =
	Charm.atom(InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED))

local slotsAtom: Charm.Selector<{ InventorySlot }> = Charm.computed(function(): { InventorySlot }
	return inventoryStateAtom().slots
end)

local selectedSlotAtom: Charm.Selector<number?> = Charm.computed(function(): number?
	return inventoryStateAtom().selectedSlot
end)

local totalItemCountAtom: Charm.Selector<number> = Charm.computed(function(): number
	return inventoryStateAtom().totalItemCount
end)

local occupiedSlotCountAtom: Charm.Selector<number> = Charm.computed(function(): number
	return inventoryStateAtom().occupiedSlotCount
end)

local loadStateAtom: Charm.Selector<InventoryServiceUtils.InventoryLoadState> = Charm.computed(function()
	return inventoryStateAtom().loadState
end)

local function getInventoryState(): InventoryState
	return inventoryStateAtom()
end

local function setInventoryState(stateRaw: any): InventoryState
	local nextState = InventoryServiceUtils.sanitizeState(stateRaw, inventoryStateAtom())
	inventoryStateAtom(nextState)
	return nextState
end

local function resetInventoryState(): InventoryState
	local nextState = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	inventoryStateAtom(nextState)
	return nextState
end

return {
	inventoryStateAtom = inventoryStateAtom,
	slotsAtom = slotsAtom,
	selectedSlotAtom = selectedSlotAtom,
	totalItemCountAtom = totalItemCountAtom,
	occupiedSlotCountAtom = occupiedSlotCountAtom,
	loadStateAtom = loadStateAtom,
	getInventoryState = getInventoryState,
	setInventoryState = setInventoryState,
	resetInventoryState = resetInventoryState,
}
