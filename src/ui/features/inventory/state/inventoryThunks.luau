--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local inventorySlice = require(ReplicatedStorage.UI.features.inventory.state.inventorySlice)
local InventoryServiceClient = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceClient)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)

type InventoryState = InventoryServiceUtils.InventoryState

local inventoryThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local function applyState(nextStateRaw: any): InventoryState
	return inventorySlice.setInventoryState(nextStateRaw)
end

local function syncFromService(): InventoryState
	return ServiceSync.syncFromService(InventoryServiceClient, inventorySlice.getInventoryState, applyState)
end

function inventoryThunks.start(): () -> ()
	if runtime.started then
		return inventoryThunks.stop
	end

	runtime.started = true
	syncFromService()

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(InventoryServiceClient, function(nextState: InventoryState)
		applyState(nextState)
	end)
	ServiceSync.requestSync(InventoryServiceClient)

	return inventoryThunks.stop
end

function inventoryThunks.stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil
	runtime.started = false
end

function inventoryThunks.syncFromService(): InventoryState
	return syncFromService()
end

function inventoryThunks.applyState(nextStateRaw: any): InventoryState
	return applyState(nextStateRaw)
end

function inventoryThunks.selectSlot(slotIndexRaw: any): boolean
	local success, didSet = pcall(function()
		return InventoryServiceClient:setSelectedSlot(slotIndexRaw, true)
	end)
	if success then
		return didSet == true
	end
	return false
end

function inventoryThunks.clearSelectedSlot(): boolean
	local success, didSet = pcall(function()
		return InventoryServiceClient:clearSelectedSlot(true)
	end)
	if success then
		return didSet == true
	end
	return false
end

function inventoryThunks.moveSlot(fromSlotRaw: any, toSlotRaw: any, amountRaw: any): boolean
	local currentState = inventorySlice.getInventoryState()
	local optimisticState = InventoryServiceUtils.cloneState(currentState)
	local optimisticResult = InventoryServiceUtils.moveSlot(optimisticState, fromSlotRaw, toSlotRaw, amountRaw)
	if optimisticResult.changed then
		inventorySlice.setInventoryState(optimisticState)
	end

	pcall(function()
		InventoryServiceClient:moveSlot(fromSlotRaw, toSlotRaw, amountRaw)
	end)
	return optimisticResult.changed
end

function inventoryThunks.splitSlot(fromSlotRaw: any, toSlotRaw: any, amountRaw: any): boolean
	pcall(function()
		InventoryServiceClient:splitSlot(fromSlotRaw, toSlotRaw, amountRaw)
	end)
	return true
end

function inventoryThunks.dropFromSlot(slotIndexRaw: any, amountRaw: any): boolean
	local currentState = inventorySlice.getInventoryState()
	local safeState = InventoryServiceUtils.sanitizeState(currentState, currentState)
	if not InventoryServiceUtils.isLoadedState(safeState.loadState) then
		return false
	end

	local slot = InventoryServiceUtils.getSlot(safeState, slotIndexRaw)
	if slot == nil or slot.stack == nil then
		return false
	end

	task.defer(function()
		pcall(function()
			InventoryServiceClient:dropFromSlot(slotIndexRaw, amountRaw)
		end)
	end)
	return true
end

function inventoryThunks.trashSlot(slotIndexRaw: any, amountRaw: any): boolean
	local currentState = inventorySlice.getInventoryState()
	local optimisticState = InventoryServiceUtils.cloneState(currentState)
	local optimisticResult = InventoryServiceUtils.trashSlot(optimisticState, slotIndexRaw, amountRaw)
	if optimisticResult.changed then
		inventorySlice.setInventoryState(optimisticState)
	end

	local success = pcall(function()
		InventoryServiceClient:trashSlot(slotIndexRaw, amountRaw)
	end)
	return success
end

function inventoryThunks.useSelectedSlot(amountRaw: any)
	pcall(function()
		InventoryServiceClient:useSelectedSlot(amountRaw)
	end)
end

return inventoryThunks
