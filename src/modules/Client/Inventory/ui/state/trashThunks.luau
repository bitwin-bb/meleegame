local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local InventoryServiceClient = require("InventoryServiceClient")
local inventorySlice = require("inventorySlice")
local trashSlice = require("trashSlice")

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
		InventoryServiceClient:TrashSelectedSlot(amountRaw)
	end)
	return success
end

function trashThunks.TrashSlot(slotIndexRaw: any, amountRaw: any): boolean
	local success = pcall(function()
		InventoryServiceClient:TrashSlot(slotIndexRaw, amountRaw)
	end)
	return success
end
return trashThunks
