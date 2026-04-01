--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local LootServiceClient = require(ReplicatedStorage.Shared.Services.LootService.LootServiceClient)
local PlayerDataServiceClient = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceClient)
local PlayerDataServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceUtils)

type InventoryState = InventoryServiceUtils.InventoryState
type InventorySlot = InventoryServiceUtils.InventorySlot
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: InventoryState) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: InventoryState) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local InventoryServiceClient = {}

local DISABLE_BACKPACK_UI_MAX_ATTEMPTS = 8
local DISABLE_BACKPACK_UI_RETRY_DELAY = 0.2

local function disableDefaultBackpackUi()
	local attempts = 0
	local function apply()
		attempts += 1
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if attempts >= DISABLE_BACKPACK_UI_MAX_ATTEMPTS then
			return
		end
		local ok, enabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
		end)
		if not ok or enabled then
			task.delay(DISABLE_BACKPACK_UI_RETRY_DELAY, apply)
		end
	end
	apply()
end

local function resolveThrowDirectionFromMouse(): Vector3?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local direction = ray.Direction
	if direction.Magnitude <= 1e-4 then
		direction = camera.CFrame.LookVector
	end
	if direction.Magnitude <= 1e-4 then
		return nil
	end
	return direction.Unit
end

local function resolveDropAmountPreference(amountRaw: any): any
	local ok, resolved = pcall(function()
		return LootServiceClient:resolveDropAmount(amountRaw)
	end)
	if ok then
		return resolved
	end
	return amountRaw
end

function InventoryServiceClient.init(self: InventoryServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("InventoryService", self)
	self.janitor = Janitor.new()
	self.state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADING)
	self.hasReceivedServerState = false
	self.stateChanged = Signal.new()

	disableDefaultBackpackUi()
	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function()
		disableDefaultBackpackUi()
	end))
	if PlayerDataServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(PlayerDataServiceClient.stateChanged:Connect(function(nextState: PlayerDataServiceState)
			if PlayerDataServiceUtils.isLoadedState(nextState.loadState) and not InventoryServiceUtils.isLoadedState(self.state.loadState) then
				self:requestSync()
			end
		end))
	end
	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:requestSync()
end

function InventoryServiceClient.applyState(self: InventoryServiceClient, stateRaw: any)
	self.state = InventoryServiceUtils.sanitizeState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.stateChanged:Fire(InventoryServiceUtils.cloneState(self.state))
end

function InventoryServiceClient.requestSync(self: InventoryServiceClient)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function InventoryServiceClient.getState(self: InventoryServiceClient): InventoryState
	return InventoryServiceUtils.cloneState(self.state)
end

function InventoryServiceClient.getSlots(self: InventoryServiceClient): { InventorySlot }
	return self:getState().slots
end

function InventoryServiceClient.getSlot(self: InventoryServiceClient, slotIndexRaw: any): InventorySlot?
	return InventoryServiceUtils.getSlot(self:getState(), slotIndexRaw)
end

function InventoryServiceClient.getSelectedSlot(self: InventoryServiceClient): number?
	return self.state.selectedSlot
end

function InventoryServiceClient.getSelectedStack(self: InventoryServiceClient): InventoryItemStack?
	if self.state.selectedSlot == nil then
		return nil
	end
	return InventoryServiceUtils.getStack(self.state, self.state.selectedSlot)
end

function InventoryServiceClient.isLoaded(self: InventoryServiceClient): boolean
	return InventoryServiceUtils.isLoadedState(self.state.loadState)
end

function InventoryServiceClient.setSelectedSlot(self: InventoryServiceClient, slotIndexRaw: any, replicateToServerRaw: any): boolean
	local nextState = InventoryServiceUtils.cloneState(self.state)
	local changed = InventoryServiceUtils.setSelectedSlot(nextState, slotIndexRaw)
	if changed then
		self.state = nextState
		self.stateChanged:Fire(InventoryServiceUtils.cloneState(self.state))
	end
	if replicateToServerRaw ~= false then
		self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SET_SELECTED_SLOT, slotIndexRaw)
	end
	return changed
end

function InventoryServiceClient.clearSelectedSlot(self: InventoryServiceClient, replicateToServerRaw: any): boolean
	return self:setSelectedSlot(nil, replicateToServerRaw)
end

function InventoryServiceClient.moveSlot(self: InventoryServiceClient, fromSlotRaw: any, toSlotRaw: any, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_MOVE_SLOT, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceClient.splitSlot(self: InventoryServiceClient, fromSlotRaw: any, toSlotRaw: any, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SPLIT_SLOT, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceClient.dropFromSlot(_self: InventoryServiceClient, slotIndexRaw: any, amountRaw: any)
	local amount = resolveDropAmountPreference(amountRaw)
	local throwDirection = resolveThrowDirectionFromMouse()
	local ok = pcall(function()
		LootServiceClient:requestDropFromSlot(slotIndexRaw, amount, throwDirection)
	end)
	if not ok then
		warn("[InventoryServiceClient] LootService drop request failed; drop ignored to preserve server loot authority.")
	end
end

function InventoryServiceClient.trashSlot(self: InventoryServiceClient, slotIndexRaw: any, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SLOT, slotIndexRaw, amountRaw)
end

function InventoryServiceClient.trashSelectedSlot(self: InventoryServiceClient, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SELECTED_SLOT, amountRaw)
end

function InventoryServiceClient.useSelectedSlot(self: InventoryServiceClient, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_USE_SELECTED_SLOT, amountRaw)
end

function InventoryServiceClient.destroy(self: InventoryServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

type InventoryServiceClient = typeof(InventoryServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	state: InventoryState,
	hasReceivedServerState: boolean,
	stateChanged: SignalObject,
}

return InventoryServiceClient :: InventoryServiceClient
