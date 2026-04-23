--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local ServiceSync = require(script:FindFirstAncestor("game").Client.UI.core.utils.ServiceSync)
local inventorySlice = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.inventorySlice)
local InventoryServiceClient = require(script:FindFirstAncestor("game").Client.Services.InventoryServiceClient)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryServiceUtils)

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

function inventoryThunks.Start(): () -> ()
	if runtime.started then
		return inventoryThunks.Stop
	end

	runtime.started = true
	syncFromService()

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(InventoryServiceClient, function(nextState: InventoryState)
		applyState(nextState)
	end)
	ServiceSync.requestSync(InventoryServiceClient)

	return inventoryThunks.Stop
end

function inventoryThunks.Stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil
	runtime.started = false
end

function inventoryThunks.SyncFromService(): InventoryState
	return syncFromService()
end

function inventoryThunks.ApplyState(nextStateRaw: any): InventoryState
	return applyState(nextStateRaw)
end

function inventoryThunks.SelectSlot(slotIndexRaw: any): boolean
	local success, didSet = pcall(function()
		return InventoryServiceClient:setSelectedSlot(slotIndexRaw, true)
	end)
	if success then
		return didSet == true
	end
	return false
end

function inventoryThunks.ClearSelectedSlot(): boolean
	local success, didSet = pcall(function()
		return InventoryServiceClient:clearSelectedSlot(true)
	end)
	if success then
		return didSet == true
	end
	return false
end

function inventoryThunks.MoveSlot(fromSlotRaw: any, toSlotRaw: any, amountRaw: any): boolean
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

function inventoryThunks.SplitSlot(fromSlotRaw: any, toSlotRaw: any, amountRaw: any): boolean
	pcall(function()
		InventoryServiceClient:splitSlot(fromSlotRaw, toSlotRaw, amountRaw)
	end)
	return true
end

function inventoryThunks.DropFromSlot(slotIndexRaw: any, amountRaw: any): boolean
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

function inventoryThunks.TrashSlot(slotIndexRaw: any, amountRaw: any): boolean
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

function inventoryThunks.UseSelectedSlot(amountRaw: any)
	pcall(function()
		InventoryServiceClient:useSelectedSlot(amountRaw)
	end)
end

inventoryThunks.start = inventoryThunks.Start
inventoryThunks.stop = inventoryThunks.Stop
inventoryThunks.syncFromService = inventoryThunks.SyncFromService
inventoryThunks.applyState = inventoryThunks.ApplyState
inventoryThunks.selectSlot = inventoryThunks.SelectSlot
inventoryThunks.clearSelectedSlot = inventoryThunks.ClearSelectedSlot
inventoryThunks.moveSlot = inventoryThunks.MoveSlot
inventoryThunks.splitSlot = inventoryThunks.SplitSlot
inventoryThunks.dropFromSlot = inventoryThunks.DropFromSlot
inventoryThunks.trashSlot = inventoryThunks.TrashSlot
inventoryThunks.useSelectedSlot = inventoryThunks.UseSelectedSlot

return inventoryThunks
