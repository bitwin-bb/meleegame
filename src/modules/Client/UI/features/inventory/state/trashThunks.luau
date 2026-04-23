--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local trashSlice = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.trashSlice)
local inventorySlice = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.inventorySlice)
local InventoryServiceClient = require(script:FindFirstAncestor("game").Client.Services.InventoryServiceClient)

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

function trashThunks.Start(): () -> ()
	if runtime.started then
		return trashThunks.Stop
	end

	runtime.started = true
	syncFromInventory()

	runtime.unsubscribeInventoryState = Charm.subscribe(inventorySlice.inventoryStateAtom, function(nextInventoryState)
		applyInventoryState(nextInventoryState)
	end, {
		inclusive = true,
	})

	return trashThunks.Stop
end

function trashThunks.Stop()
	if runtime.unsubscribeInventoryState ~= nil then
		runtime.unsubscribeInventoryState()
		runtime.unsubscribeInventoryState = nil
	end
	runtime.started = false
end

function trashThunks.SetHovered(isHoveredRaw: any)
	return trashSlice.setHovered(isHoveredRaw)
end

function trashThunks.Open()
	return trashSlice.setHovered(true)
end

function trashThunks.Close()
	return trashSlice.setHovered(false)
end

function trashThunks.TrashSelected(amountRaw: any): boolean
	local state = trashSlice.getTrashState()
	if not state.canTrash then
		return false
	end

	local success = pcall(function()
		InventoryServiceClient:trashSelectedSlot(amountRaw)
	end)
	return success
end

function trashThunks.TrashSlot(slotIndexRaw: any, amountRaw: any): boolean
	local success = pcall(function()
		InventoryServiceClient:trashSlot(slotIndexRaw, amountRaw)
	end)
	return success
end

trashThunks.start = trashThunks.Start
trashThunks.stop = trashThunks.Stop
trashThunks.setHovered = trashThunks.SetHovered
trashThunks.open = trashThunks.Open
trashThunks.close = trashThunks.Close
trashThunks.trashSelected = trashThunks.TrashSelected
trashThunks.trashSlot = trashThunks.TrashSlot

return trashThunks
