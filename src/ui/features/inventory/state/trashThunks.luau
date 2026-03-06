--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local trashSlice = require(ReplicatedStorage.UI.features.inventory.state.trashSlice)
local inventorySlice = require(ReplicatedStorage.UI.features.inventory.state.inventorySlice)
local InventoryServiceClient = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceClient)

local trashThunks = {}

local runtime = {
	started = false,
	unsubscribeInventoryState = nil :: (() -> ())?,
}

local function applyInventoryState(nextInventoryStateRaw: any)
	return trashSlice.setFromInventoryState(nextInventoryStateRaw)
end

local function syncFromInventory()
	return applyInventoryState(inventorySlice.getInventoryState())
end

function trashThunks.start(): () -> ()
	if runtime.started then
		return trashThunks.stop
	end

	runtime.started = true
	syncFromInventory()

	runtime.unsubscribeInventoryState = Charm.subscribe(inventorySlice.inventoryStateAtom, function(nextInventoryState)
		applyInventoryState(nextInventoryState)
	end, {
		inclusive = true,
	})

	return trashThunks.stop
end

function trashThunks.stop()
	if runtime.unsubscribeInventoryState ~= nil then
		runtime.unsubscribeInventoryState()
		runtime.unsubscribeInventoryState = nil
	end
	runtime.started = false
end

function trashThunks.setHovered(isHoveredRaw: any)
	return trashSlice.setHovered(isHoveredRaw)
end

function trashThunks.open()
	return trashSlice.setHovered(true)
end

function trashThunks.close()
	return trashSlice.setHovered(false)
end

function trashThunks.trashSelected(amountRaw: any): boolean
	local state = trashSlice.getTrashState()
	if not state.canTrash then
		return false
	end

	local success = pcall(function()
		InventoryServiceClient:trashSelectedSlot(amountRaw)
	end)
	return success
end

function trashThunks.trashSlot(slotIndexRaw: any, amountRaw: any): boolean
	local success = pcall(function()
		InventoryServiceClient:trashSlot(slotIndexRaw, amountRaw)
	end)
	return success
end

return trashThunks
