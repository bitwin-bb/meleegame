local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BuildServiceUtils = require("BuildServiceUtils")
local CoreRuntime = require("CoreRuntime")
local GamepadPointer = require("GamepadPointer")
local InventoryServiceUtils = require("InventoryServiceUtils")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local LootServiceClient = require("LootServiceClient")
local PacketPayload = require("PacketPayload")
local InventoryServicePackets = require("NetPacketsShared").InventoryService

local function sendPacket(methodName: string, ...: any)
	local packet = InventoryServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for InventoryService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = InventoryServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for InventoryService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyState")
	bindPacket(self, "requestPlaceSelectedDeployable")
	bindPacket(self, "requestSync")
end

local PlatformServiceClient = require("PlatformServiceClient")
local PlayerDataServiceClient = require("PlayerDataServiceClient")
local PlayerDataServiceUtils = require("PlayerDataServiceUtils")
local Signal = require("Signal")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

type InventoryState = InventoryServiceUtils.InventoryState
type InventorySlot = InventoryServiceUtils.InventorySlot
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

type SignalObject = Signal.Signal<...any>

type JanitorClass = any

local InventoryServiceClient = {}

local DISABLE_BACKPACK_UI_MAX_ATTEMPTS = 8
local DISABLE_BACKPACK_UI_RETRY_DELAY = 0.2
local WORLD_FOLDER_NAME = "WorldGeneration"

local function GetCharacterRootPart(playerRaw: any): BasePart?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local player = playerRaw :: Player
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

local function shouldUseGamepadWorldSelection(): boolean
	return PlatformServiceClient:IsGamepad() and PlatformServiceClient:GetMachineFamily() ~= "desktop"
end

local function GetWorldGridConfig(): (Vector3?, number?, number?)
	local worldFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
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
				),
					tileSize,
					basePlaneX
			end
		end
	end

	local worldClient = WorldGenerationServiceClient :: any
	local refreshWorldAttributesMethod = worldClient.RefreshWorldAttributes
	if typeof(refreshWorldAttributesMethod) == "function" then
		pcall(function()
			worldClient:RefreshWorldAttributes()
		end)
	end

	local worldOrigin = if typeof(worldClient.worldOrigin) == "Vector3" then worldClient.worldOrigin else nil
	local basePlaneX = if typeof(worldClient.basePlaneX) == "number"
			and worldClient.basePlaneX == worldClient.basePlaneX
		then worldClient.basePlaneX
		else nil
	local state = if typeof(worldClient.state) == "table" then worldClient.state else nil
	local tileSize = if state ~= nil
			and typeof((state :: any).tileSize) == "number"
			and (state :: any).tileSize == (state :: any).tileSize
		then (state :: any).tileSize
		else nil
	if worldOrigin == nil or tileSize == nil or tileSize <= 0 or basePlaneX == nil then
		return nil, nil, nil
	end

	return worldOrigin, tileSize, basePlaneX
end

local function GetCursorScreenPosition(): Vector2?
	local runtimeContext = nil
	local ok, runtimeOrError = pcall(function()
		return CoreRuntime.GetClientRuntime()
	end)
	if ok then
		runtimeContext = runtimeOrError
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).Init) == "function" then
		pcall(function()
			(runtimeContext :: any):Init()
		end)
	end

	local cursorModule = if runtimeContext ~= nil then (runtimeContext :: any).cursor else nil
	if cursorModule ~= nil and typeof((cursorModule :: any).GetScreenPosition) == "function" then
		local didGetCursor, cursorPosition = pcall(function()
			return (cursorModule :: any):GetScreenPosition()
		end)
		if didGetCursor and typeof(cursorPosition) == "Vector2" then
			return cursorPosition
		end
	end

	local didGetMouse, mousePosition = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if didGetMouse and typeof(mousePosition) == "Vector2" then
		return mousePosition
	end

	return nil
end

local function GetGamepadNav(): any?
	local runtimeContext = nil
	local ok, runtimeOrError = pcall(function()
		return CoreRuntime.GetClientRuntime()
	end)
	if ok then
		runtimeContext = runtimeOrError
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).Init) == "function" then
		pcall(function()
			(runtimeContext :: any):Init()
		end)
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).GetGamepadNav) == "function" then
		local didGet, gamepadNavOrError = pcall(function()
			return (runtimeContext :: any):GetGamepadNav()
		end)
		if didGet then
			return gamepadNavOrError
		end
	end

	if runtimeContext ~= nil then
		return (runtimeContext :: any).gamepadNav
	end

	return nil
end

local function GetGamepadScreenVector(): Vector2?
	local gamepadNav = GetGamepadNav()
	if gamepadNav == nil or typeof((gamepadNav :: any).GetThumbstickState) ~= "function" then
		return nil
	end

	local ok, snapshotOrError = pcall(function()
		return (gamepadNav :: any):GetThumbstickState()
	end)
	if not ok or typeof(snapshotOrError) ~= "table" then
		return nil
	end

	local screenVector = GamepadPointer.GetOwnedVector(snapshotOrError)
	return if typeof(screenVector) == "Vector2" then screenVector else nil
end

local function GetGamepadWorldPosition(tileSize: number, rootPart: BasePart?): Vector3?
	local screenVector = GetGamepadScreenVector()
	if screenVector == nil or rootPart == nil then
		return nil
	end

	local worldOffset = GamepadPointer.GetWorldOffsetForScreenVector(screenVector, tileSize, rootPart)
	if worldOffset == nil then
		return nil
	end

	return rootPart.Position + worldOffset
end

local function GetCursorTileFromMouse(): (number?, number?)
	local worldOrigin, tileSize, basePlaneX = GetWorldGridConfig()
	if worldOrigin == nil or tileSize == nil or basePlaneX == nil then
		return nil, nil
	end

	if shouldUseGamepadWorldSelection() then
		local rootPart = GetCharacterRootPart(Players.LocalPlayer)
		local worldPosition = GetGamepadWorldPosition(tileSize, rootPart)
		if worldPosition ~= nil then
			return BuildServiceUtils.WorldPositionToTile(worldPosition, worldOrigin, tileSize)
		end

		return nil, nil
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, nil
	end

	local mouseLocation = GetCursorScreenPosition()
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
	local selectedStack = self:GetSelectedStack()
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

local function GetThrowDirectionFromMouse(): Vector3?
	if shouldUseGamepadWorldSelection() then
		local _, tileSize = GetWorldGridConfig()
		if tileSize ~= nil then
			local rootPart = GetCharacterRootPart(Players.LocalPlayer)
			local worldPosition = GetGamepadWorldPosition(tileSize, rootPart)
			if rootPart ~= nil and worldPosition ~= nil then
				local direction = worldPosition - rootPart.Position
				if direction.Magnitude > 1e-4 then
					return direction.Unit
				end
			end
		end

		return nil
	end

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

local function GotRopAmountPreference(amountRaw: any): any
	local ok, Got = pcall(function()
		return LootServiceClient:GotRopAmount(amountRaw)
	end)
	if ok then
		return Got
	end
	return amountRaw
end

function InventoryServiceClient.Init(self: InventoryServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_LOADING)
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
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		if not isTorchSelected(self) then
			return
		end
		self:RequestPlaceSelectedDeployable()
	end))
	if PlayerDataServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(PlayerDataServiceClient.stateChanged:Connect(function(nextState: PlayerDataServiceState)
			if
				PlayerDataServiceUtils.IsLoadedState(nextState.loadState)
				and not InventoryServiceUtils.IsLoadedState(self.state.loadState)
			then
				self:RequestSync()
			end
		end))
	end
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:RequestSync()
end

function InventoryServiceClient.ApplyState(self: InventoryServiceClient, stateRaw: any)
	self.state = InventoryServiceUtils.CoerceState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.stateChanged:Fire(InventoryServiceUtils.CloneState(self.state))
end

function InventoryServiceClient.RequestSync(_self: InventoryServiceClient)
	sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function InventoryServiceClient.GetState(self: InventoryServiceClient): InventoryState
	return InventoryServiceUtils.CloneState(self.state)
end

function InventoryServiceClient.GetSlots(self: InventoryServiceClient): { InventorySlot }
	return self:GetState().slots
end

function InventoryServiceClient.GetSlot(self: InventoryServiceClient, slotIndexRaw: any): InventorySlot?
	return InventoryServiceUtils.GetSlot(self:GetState(), slotIndexRaw)
end

function InventoryServiceClient.GetSelectedSlot(self: InventoryServiceClient): number?
	return self.state.selectedSlot
end

function InventoryServiceClient.GetSelectedStack(self: InventoryServiceClient): InventoryItemStack?
	if self.state.selectedSlot == nil then
		return nil
	end
	return InventoryServiceUtils.GetStack(self.state, self.state.selectedSlot)
end

function InventoryServiceClient.IsLoaded(self: InventoryServiceClient): boolean
	return InventoryServiceUtils.IsLoadedState(self.state.loadState)
end

function InventoryServiceClient.SetSelectedSlot(
	self: InventoryServiceClient,
	slotIndexRaw: any,
	replicateToServerRaw: any
): boolean
	local nextState = InventoryServiceUtils.CloneState(self.state)
	local changed = InventoryServiceUtils.SetSelectedSlot(nextState, slotIndexRaw)
	if changed then
		self.state = nextState
		self.stateChanged:Fire(InventoryServiceUtils.CloneState(self.state))
	end
	if replicateToServerRaw ~= false then
		sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SET_SELECTED_SLOT, slotIndexRaw)
	end
	return changed
end

function InventoryServiceClient.ClearSelectedSlot(self: InventoryServiceClient, replicateToServerRaw: any): boolean
	return self:SetSelectedSlot(nil, replicateToServerRaw)
end

function InventoryServiceClient.MoveSlot(_self: InventoryServiceClient, fromSlotRaw: any, toSlotRaw: any, amountRaw: any)
	sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_MOVE_SLOT, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceClient.SplitSlot(
	_self: InventoryServiceClient,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
)
	sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_SPLIT_SLOT, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceClient.DropFromSlot(_self: InventoryServiceClient, slotIndexRaw: any, amountRaw: any)
	local amount = GotRopAmountPreference(amountRaw)
	local throwDirection = GetThrowDirectionFromMouse()
	pcall(function()
		LootServiceClient:RequestDropFromSlot(slotIndexRaw, amount, throwDirection)
	end)
end

function InventoryServiceClient.TrashSlot(_self: InventoryServiceClient, slotIndexRaw: any, amountRaw: any)
	sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SLOT, slotIndexRaw, amountRaw)
end

function InventoryServiceClient.TrashSelectedSlot(_self: InventoryServiceClient, amountRaw: any)
	sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_TRASH_SELECTED_SLOT, amountRaw)
end

function InventoryServiceClient.UseSelectedSlot(_self: InventoryServiceClient, amountRaw: any)
	sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_USE_SELECTED_SLOT, amountRaw)
end

function InventoryServiceClient.RequestPlaceSelectedDeployable(_self: InventoryServiceClient)
	local tileX, tileY = GetCursorTileFromMouse()
	if tileX == nil or tileY == nil then
		return
	end
	sendPacket(InventoryServiceUtils.NETWORK_METHOD_REQUEST_PLACE_SELECTED_DEPLOYABLE, tileX, tileY)
end

function InventoryServiceClient.Destroy(self: InventoryServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end
type InventoryServiceClient = typeof(InventoryServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass,
	state: InventoryState,
	hasReceivedServerState: boolean,
	stateChanged: SignalObject,
}

return InventoryServiceClient :: InventoryServiceClient
