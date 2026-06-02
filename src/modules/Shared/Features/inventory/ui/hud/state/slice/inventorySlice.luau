--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local InventoryServiceUtils = require(gameRoot.Shared.Features.inventory.InventoryServiceUtils)

type InventoryState = InventoryServiceUtils.InventoryState
type InventorySlot = InventoryServiceUtils.InventorySlot

export type InventoryHudState = {
	isInventoryPanelOpen: boolean,
	isHotbarExpanded: boolean,
	isLeftSideBarVisible: boolean,
	updatedAt: number,
}

local DEFAULT_STATE: InventoryHudState = {
	isInventoryPanelOpen = false,
	isHotbarExpanded = false,
	isLeftSideBarVisible = true,
	updatedAt = os.clock(),
}

local inventoryStateAtom =
	Charm.atom(InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED))
local inventoryHudStateAtom = Charm.atom(DEFAULT_STATE)

local slotsAtom = Charm.computed(function(): { InventorySlot }
	return inventoryStateAtom().slots
end)

local selectedSlotAtom = Charm.computed(function(): number?
	return inventoryStateAtom().selectedSlot
end)

local totalItemCountAtom = Charm.computed(function(): number
	return inventoryStateAtom().totalItemCount
end)

local occupiedSlotCountAtom = Charm.computed(function(): number
	return inventoryStateAtom().occupiedSlotCount
end)

local loadStateAtom = Charm.computed(function(): InventoryServiceUtils.InventoryLoadState
	return inventoryStateAtom().loadState
end)

local isInventoryPanelOpenAtom = Charm.computed(function(): boolean
	return inventoryHudStateAtom().isInventoryPanelOpen
end)

local isHotbarExpandedAtom = Charm.computed(function(): boolean
	return inventoryHudStateAtom().isHotbarExpanded
end)

local isLeftSideBarVisibleAtom = Charm.computed(function(): boolean
	return inventoryHudStateAtom().isLeftSideBarVisible
end)

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

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

local function getInventoryHudState(): InventoryHudState
	return inventoryHudStateAtom()
end

local function setInventoryHudState(stateRaw: any): InventoryHudState
	local current = inventoryHudStateAtom()
	local source: { [string]: any } = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else {} :: any

	local nextIsHotbarExpanded = sanitizeBoolean(source.isHotbarExpanded, current.isHotbarExpanded)
	local nextIsInventoryPanelOpen = sanitizeBoolean(source.isInventoryPanelOpen, nextIsHotbarExpanded)

	local nextState: InventoryHudState = {
		isInventoryPanelOpen = nextIsInventoryPanelOpen,
		isHotbarExpanded = nextIsHotbarExpanded,
		isLeftSideBarVisible = sanitizeBoolean(source.isLeftSideBarVisible, current.isLeftSideBarVisible),
		updatedAt = os.clock(),
	}

	inventoryHudStateAtom(nextState)
	return nextState
end

local function resetInventoryHudState(): InventoryHudState
	local nextState: InventoryHudState = {
		isInventoryPanelOpen = DEFAULT_STATE.isInventoryPanelOpen,
		isHotbarExpanded = DEFAULT_STATE.isHotbarExpanded,
		isLeftSideBarVisible = DEFAULT_STATE.isLeftSideBarVisible,
		updatedAt = os.clock(),
	}
	inventoryHudStateAtom(nextState)
	return nextState
end

local function setInventoryPanelOpen(isOpenRaw: any): InventoryHudState
	local isOpen = isOpenRaw == true
	return setInventoryHudState({
		isInventoryPanelOpen = isOpen,
		isHotbarExpanded = isOpen,
	})
end

local function setHotbarExpanded(isExpandedRaw: any): InventoryHudState
	local isExpanded = isExpandedRaw == true
	return setInventoryHudState({
		isInventoryPanelOpen = isExpanded,
		isHotbarExpanded = isExpanded,
	})
end

local function toggleHotbarExpanded(): InventoryHudState
	return setHotbarExpanded(not inventoryHudStateAtom().isHotbarExpanded)
end

local function setLeftSideBarVisible(isVisibleRaw: any): InventoryHudState
	return setInventoryHudState({
		isLeftSideBarVisible = isVisibleRaw == true,
	})
end

return {
	inventoryStateAtom = inventoryStateAtom,
	slotsAtom = slotsAtom,
	selectedSlotAtom = selectedSlotAtom,
	totalItemCountAtom = totalItemCountAtom,
	occupiedSlotCountAtom = occupiedSlotCountAtom,
	loadStateAtom = loadStateAtom,
	inventoryHudStateAtom = inventoryHudStateAtom,
	isInventoryPanelOpenAtom = isInventoryPanelOpenAtom,
	isHotbarExpandedAtom = isHotbarExpandedAtom,
	isLeftSideBarVisibleAtom = isLeftSideBarVisibleAtom,
	getInventoryState = getInventoryState,
	setInventoryState = setInventoryState,
	resetInventoryState = resetInventoryState,
	getInventoryHudState = getInventoryHudState,
	setInventoryHudState = setInventoryHudState,
	resetInventoryHudState = resetInventoryHudState,
	setInventoryPanelOpen = setInventoryPanelOpen,
	setHotbarExpanded = setHotbarExpanded,
	toggleHotbarExpanded = toggleHotbarExpanded,
	setLeftSideBarVisible = setLeftSideBarVisible,
}
