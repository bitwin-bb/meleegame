--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildService.BuildServiceUtils)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryService.InventoryServiceUtils)
local LootServiceClient = require(script:FindFirstAncestor("game").Client.Services.LootService.LootServiceClient)
local PlayerDataServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerDataService.PlayerDataServiceClient)
local PlayerDataServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerDataService.PlayerDataServiceUtils)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationService.WorldGenerationServiceClient)

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
local WORLD_FOLDER_NAME = "WorldGeneration"

local function resolveWorldGridConfig(): (Vector3?, number?, number?)
	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if worldFolder ~= nil then
		local originX = worldFolder:GetAttribute("WorldOriginX")
		local originY = worldFolder:GetAttribute("WorldOriginY")
		local originZ = worldFolder:GetAttribute("WorldOriginZ")
		local tileSize = worldFolder:GetAttribute("TileSize")
		local basePlaneX = worldFolder:GetAttribute("BasePlaneX")
		if typeof(tileSize) == "number" and tileSize == tileSize and tileSize > 0 then
			if typeof(basePlaneX) == "number" and basePlaneX == basePlaneX then
				return Vector3.new(
					if typeof(originX) == "number" and originX == originX then originX else 0,
					if typeof(originY) == "number" and originY == originY then originY else 0,
					if typeof(originZ) == "number" and originZ == originZ then originZ else 0
				), tileSize, basePlaneX
			end
		end
	end

	local worldClient = WorldGenerationServiceClient :: any
	local refreshWorldAttributesMethod = worldClient.refreshWorldAttributes
	if typeof(refreshWorldAttributesMethod) == "function" then
		pcall(function()
			worldClient:refreshWorldAttributes()
		end)
	end

	local worldOrigin = if typeof(worldClient.worldOrigin) == "Vector3" then worldClient.worldOrigin else nil
	local basePlaneX = if typeof(worldClient.basePlaneX) == "number" and worldClient.basePlaneX == worldClient.basePlaneX
		then worldClient.basePlaneX
		else nil
	local state = if typeof(worldClient.state) == "table" then worldClient.state else nil
	local tileSize = if state ~= nil and typeof((state :: any).tileSize) == "number" and (state :: any).tileSize == (state :: any).tileSize
		then (state :: any).tileSize
		else nil
	if worldOrigin == nil or tileSize == nil or tileSize <= 0 or basePlaneX == nil then
		return nil, nil, nil
	end

	return worldOrigin, tileSize, basePlaneX
end

local function resolveCursorScreenPosition(): Vector2?
	local runtimeContext = nil
	local ok, runtimeOrError = pcall(function()
		return CoreRuntime.getClientRuntime()
	end)
	if ok then
		runtimeContext = runtimeOrError
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).init) == "function" then
		pcall(function()
			(runtimeContext :: any):init()
		end)
	end

	local cursorModule = if runtimeContext ~= nil then (runtimeContext :: any).cursor else nil
	if cursorModule ~= nil and typeof((cursorModule :: any).getScreenPosition) == "function" then
		local didResolveCursor, cursorPosition = pcall(function()
			return (cursorModule :: any):getScreenPosition()
		end)
		if didResolveCursor and typeof(cursorPosition) == "Vector2" then
			return cursorPosition
		end
	end

	local didResolveMouse, mousePosition = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if didResolveMouse and typeof(mousePosition) == "Vector2" then
		return mousePosition
	end

	return nil
end

local function resolveCursorTileFromMouse(): (number?, number?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, nil
	end

	local worldOrigin, tileSize, basePlaneX = resolveWorldGridConfig()
	if worldOrigin == nil or tileSize == nil or basePlaneX == nil then
		return nil, nil
	end

	local mouseLocation = resolveCursorScreenPosition()
	if mouseLocation == nil then
		return nil, nil
	end
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local hitOnPlane = BuildServiceUtils.RaycastToBuildPlane(ray.Origin, ray.Direction, basePlaneX)
	if hitOnPlane == nil then
		return nil, nil
	end

	return BuildServiceUtils.WorldPositionToTile(hitOnPlane, worldOrigin, tileSize)
end

local function isTorchSelected(self: InventoryServiceClient): boolean
	local selectedStack = self:getSelectedStack()
	return selectedStack ~= nil and selectedStack.itemId == "Torch"
end

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

function InventoryServiceClient.Init(self: InventoryServiceClient)
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
	self.janitor:GiveChore(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not isTorchSelected(self) then
			return
		end
		self:requestPlaceSelectedDeployable()
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

function InventoryServiceClient.ApplyState(self: InventoryServiceClient, stateRaw: any)
	self.state = InventoryServiceUtils.sanitizeState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.stateChanged:Fire(InventoryServiceUtils.cloneState(self.state))
end

function InventoryServiceClient.RequestSync(self: InventoryServiceClient)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function InventoryServiceClient.GetState(self: InventoryServiceClient): InventoryState
	return InventoryServiceUtils.cloneState(self.state)
end

function InventoryServiceClient.GetSlots(self: InventoryServiceClient): { InventorySlot }
	return self:getState().slots
end

function InventoryServiceClient.GetSlot(self: InventoryServiceClient, slotIndexRaw: any): InventorySlot?
	return InventoryServiceUtils.getSlot(self:getState(), slotIndexRaw)
end

function InventoryServiceClient.GetSelectedSlot(self: InventoryServiceClient): number?
	return self.state.selectedSlot
end

function InventoryServiceClient.GetSelectedStack(self: InventoryServiceClient): InventoryItemStack?
	if self.state.selectedSlot == nil then
		return nil
	end
	return InventoryServiceUtils.getStack(self.state, self.state.selectedSlot)
end

function InventoryServiceClient.IsLoaded(self: InventoryServiceClient): boolean
	return InventoryServiceUtils.isLoadedState(self.state.loadState)
end

function InventoryServiceClient.SetSelectedSlot(self: InventoryServiceClient, slotIndexRaw: any, replicateToServerRaw: any): boolean
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

function InventoryServiceClient.ClearSelectedSlot(self: InventoryServiceClient, replicateToServerRaw: any): boolean
	return self:setSelectedSlot(nil, replicateToServerRaw)
end

function InventoryServiceClient.MoveSlot(self: InventoryServiceClient, fromSlotRaw: any, toSlotRaw: any, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_MOVE_SLOT, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceClient.SplitSlot(self: InventoryServiceClient, fromSlotRaw: any, toSlotRaw: any, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SPLIT_SLOT, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceClient.DropFromSlot(_self: InventoryServiceClient, slotIndexRaw: any, amountRaw: any)
	local amount = resolveDropAmountPreference(amountRaw)
	local throwDirection = resolveThrowDirectionFromMouse()
	pcall(function()
		LootServiceClient:requestDropFromSlot(slotIndexRaw, amount, throwDirection)
	end)
end

function InventoryServiceClient.TrashSlot(self: InventoryServiceClient, slotIndexRaw: any, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SLOT, slotIndexRaw, amountRaw)
end

function InventoryServiceClient.TrashSelectedSlot(self: InventoryServiceClient, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SELECTED_SLOT, amountRaw)
end

function InventoryServiceClient.UseSelectedSlot(self: InventoryServiceClient, amountRaw: any)
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_USE_SELECTED_SLOT, amountRaw)
end

function InventoryServiceClient.RequestPlaceSelectedDeployable(self: InventoryServiceClient)
	local tileX, tileY = resolveCursorTileFromMouse()
	if tileX == nil or tileY == nil then
		return
	end
	self.networker:fire(InventoryServiceUtils.NETWORK_METHOD_REQUEST_PLACE_SELECTED_DEPLOYABLE, tileX, tileY)
end

function InventoryServiceClient.Destroy(self: InventoryServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

InventoryServiceClient.init = InventoryServiceClient.Init
InventoryServiceClient.applyState = InventoryServiceClient.ApplyState
InventoryServiceClient.requestSync = InventoryServiceClient.RequestSync
InventoryServiceClient.getState = InventoryServiceClient.GetState
InventoryServiceClient.getSlots = InventoryServiceClient.GetSlots
InventoryServiceClient.getSlot = InventoryServiceClient.GetSlot
InventoryServiceClient.getSelectedSlot = InventoryServiceClient.GetSelectedSlot
InventoryServiceClient.getSelectedStack = InventoryServiceClient.GetSelectedStack
InventoryServiceClient.isLoaded = InventoryServiceClient.IsLoaded
InventoryServiceClient.setSelectedSlot = InventoryServiceClient.SetSelectedSlot
InventoryServiceClient.clearSelectedSlot = InventoryServiceClient.ClearSelectedSlot
InventoryServiceClient.moveSlot = InventoryServiceClient.MoveSlot
InventoryServiceClient.splitSlot = InventoryServiceClient.SplitSlot
InventoryServiceClient.dropFromSlot = InventoryServiceClient.DropFromSlot
InventoryServiceClient.trashSlot = InventoryServiceClient.TrashSlot
InventoryServiceClient.trashSelectedSlot = InventoryServiceClient.TrashSelectedSlot
InventoryServiceClient.useSelectedSlot = InventoryServiceClient.UseSelectedSlot
InventoryServiceClient.requestPlaceSelectedDeployable = InventoryServiceClient.RequestPlaceSelectedDeployable
InventoryServiceClient.destroy = InventoryServiceClient.Destroy

type InventoryServiceClient = typeof(InventoryServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	state: InventoryState,
	hasReceivedServerState: boolean,
	stateChanged: SignalObject,
}

return InventoryServiceClient :: InventoryServiceClient
