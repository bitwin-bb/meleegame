local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CoreRuntime = require("CoreRuntime")
local GamepadPointer = require("GamepadPointer")
local InventoryServiceClient = require("InventoryServiceClient")
local InventoryServiceUtils = require("InventoryServiceUtils")
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local MagicServiceUtils = require("MagicServiceUtils")
local PacketPayload = require("PacketPayload")
local MagicServicePackets = require("NetPacketsShared").MagicService

local function sendPacket(methodName: string, ...: any)
	local packet = MagicServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for MagicService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = MagicServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for MagicService`)
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
	bindPacket(self, "onCastVisual")
	bindPacket(self, "onImpactVisual")
	bindPacket(self, "requestSync")
end

local PlatformServiceClient = require("PlatformServiceClient")
local Signal = require("Signal")
local WorkspaceFolders = require("WorkspaceFolders")

type InventoryState = InventoryServiceUtils.InventoryState
type ReplicatedState = MagicServiceUtils.ReplicatedState

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type VisualPoolEntry = {
	part: BasePart,
	active: boolean,
	weaponId: string,
}

type ActiveVisual = {
	castId: string,
	weaponId: string,
	entry: VisualPoolEntry,
	position: Vector3,
	direction: Vector3,
	velocity: Vector3,
	lifetimeRemaining: number,
}

local MagicServiceClient = {}

local CLIENT_VISUAL_FOLDER_NAME = "MagicClientVisuals"
local CLIENT_VISUAL_STEP = 1 / 120
local INPUT_ACTION_CAST = "MagicService.Cast"
local GAMEPAD_AIM_DEADZONE = 0.12

local function trim(raw: any): string
	if typeof(raw) ~= "string" then
		return ""
	end
	return string.match(raw, "^%s*(.-)%s*$") or ""
end

local function GetGamepadAimVector(gamepadNavRaw: any): Vector2?
	if gamepadNavRaw == nil or typeof((gamepadNavRaw :: any).GetThumbstickState) ~= "function" then
		return nil
	end
	local snapshot = (gamepadNavRaw :: any):GetThumbstickState()
	if typeof(snapshot) ~= "table" then
		return nil
	end

	local screenVector = GamepadPointer.GetOwnedVector(snapshot)
	if typeof(screenVector) ~= "Vector2" or screenVector.Magnitude <= GAMEPAD_AIM_DEADZONE then
		return nil
	end
	return screenVector
end

local function createDefaultReplicatedState(): ReplicatedState
	return {
		mana = MagicServiceUtils.DEFAULT_MAX_MANA,
		maxMana = MagicServiceUtils.DEFAULT_MAX_MANA,
		regenPerSecond = MagicServiceUtils.DEFAULT_MANA_REGEN,
		equippedWeaponId = nil,
		equippedSlot = nil,
		cooldowns = {},
		updatedAt = os.clock(),
	}
end

local function GetCharacterRootPart(characterRaw: any): BasePart?
	if typeof(characterRaw) ~= "Instance" or not characterRaw:IsA("Model") then
		return nil
	end
	local character = characterRaw :: Model
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end
	return nil
end

local function GetMouseHitPosition(localPlayer: Player): Vector3?
	local ok, hitOrError = pcall(function()
		local mouse = localPlayer:GetMouse()
		return mouse.Hit
	end)
	if not ok then
		return nil
	end
	if typeof(hitOrError) ~= "CFrame" then
		return nil
	end
	return (hitOrError :: CFrame).Position
end

function MagicServiceClient.CreateVisualPart(self: MagicServiceClient, _weaponIdRaw: any): BasePart
	local part = Instance.new("Part")
	part.Name = HttpService:GenerateGUID(false)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.45, 0.45, 0.45)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(100, 180, 255)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = self.visualFolder
	return part
end

function MagicServiceClient.AcquireVisualEntry(self: MagicServiceClient, weaponIdRaw: any): VisualPoolEntry
	local weaponId = trim(weaponIdRaw)
	local poolKey = if weaponId ~= "" then weaponId else "unknown"
	local pool = self.visualPools[poolKey]
	if pool == nil then
		pool = {}
		self.visualPools[poolKey] = pool
	end
	for _, entry in pool do
		if entry.active == false then
			entry.active = true
			return entry
		end
	end

	local entry: VisualPoolEntry = {
		part = self:CreateVisualPart(poolKey),
		active = true,
		weaponId = poolKey,
	}
	table.insert(pool, entry)
	return entry
end

function MagicServiceClient.ReleaseVisual(self: MagicServiceClient, castIdRaw: any)
	local castId = trim(castIdRaw)
	if castId == "" then
		return
	end
	local visual = self.activeVisuals[castId]
	if visual == nil then
		return
	end
	self.activeVisuals[castId] = nil
	visual.entry.active = false
	visual.entry.part.Transparency = 1
	visual.entry.part.CFrame = CFrame.new(0, -10000, 0)
end

function MagicServiceClient.GetInventoryState(_self: MagicServiceClient): InventoryState
	if InventoryServiceClient.GetState ~= nil then
		return InventoryServiceClient:GetState()
	end
	return InventoryServiceUtils.CoerceState(
		InventoryServiceClient.state,
		InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	)
end

function MagicServiceClient.GetEquippedMagicTool(self: MagicServiceClient): (string?, Tool?)
	local inventoryState = self:GetInventoryState()
	local itemId = MagicServiceUtils.GetSelectedItemIdFromInventoryState(inventoryState)
	if itemId == nil then
		return nil, nil
	end
	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	local tool = MagicServiceUtils.GetToolByItemId(self.character, backpack, itemId)
	if tool == nil or not MagicServiceUtils.IsMagicTool(tool) then
		return itemId, nil
	end
	return itemId, tool
end

function MagicServiceClient.RefreshEquipped(self: MagicServiceClient)
	local itemId, tool = self:GetEquippedMagicTool()
	self.equippedItemId = itemId
	self.equippedTool = tool
	if self.equippedTool == nil and self.inputHeld then
		self:SetInputHeld(false, "Unequipped")
	end
	sendPacket(MagicServiceUtils.NETWORK_METHOD_REQUEST_REFRESH_EQUIPPED)
end

function MagicServiceClient.BuildCastRequest(self: MagicServiceClient, triggerRaw: any): MagicServiceUtils.CastRequest
	local trigger = trim(triggerRaw)
	local rootPart = GetCharacterRootPart(self.character)
	local origin = if rootPart ~= nil then rootPart.Position + Vector3.new(0, 1.35, 0) else Vector3.zero
	local fallbackDirection = if rootPart ~= nil then rootPart.CFrame.LookVector else Vector3.new(0, 0, -1)
	local mousePosition = nil :: Vector3?
	local aimDirection = nil :: Vector3?

	if PlatformServiceClient:IsGamepad() then
		local gamepadAim = GetGamepadAimVector(self.gamepadNav)
		if gamepadAim ~= nil then
			local candidate = GamepadPointer.GetWorldOffsetForScreenVector(
				gamepadAim,
				GamepadPointer.DEFAULT_TILE_SIZE_STUDS,
				rootPart
			) or Vector3.new(0, -gamepadAim.Y, -gamepadAim.X)
			if candidate.Magnitude > 1e-4 then
				aimDirection = candidate.Unit
			end
		end
	end

	if aimDirection == nil then
		mousePosition = GetMouseHitPosition(self.localPlayer)
		if mousePosition ~= nil then
			local offset = mousePosition - origin
			if offset.Magnitude > 1e-4 then
				aimDirection = offset.Unit
			end
		end
	end
	if aimDirection == nil then
		aimDirection = fallbackDirection.Unit
	end
	return {
		trigger = if trigger ~= "" then trigger else "Cast",
		aimDirection = aimDirection,
		aimPosition = mousePosition,
	}
end

function MagicServiceClient.CanSendCast(self: MagicServiceClient): boolean
	if self.equippedTool == nil then
		return false
	end
	return os.clock() - self.lastCastRequestAt >= MagicServiceUtils.CLIENT_CAST_REQUEST_INTERVAL
end

function MagicServiceClient.SendCast(self: MagicServiceClient, triggerRaw: any)
	if not self:CanSendCast() then
		return
	end
	self.lastCastRequestAt = os.clock()
	local castRequest = self:BuildCastRequest(triggerRaw)
	self.lastCastRequest = castRequest
	sendPacket(MagicServiceUtils.NETWORK_METHOD_REQUEST_CAST, castRequest)
	if self.hapticsModule ~= nil and typeof((self.hapticsModule :: any).Confirm) == "function" then
		local hapticsAny = self.hapticsModule :: any
		hapticsAny:Confirm()
	end
end

function MagicServiceClient.SetInputHeld(self: MagicServiceClient, isHeld: boolean, triggerRaw: any)
	if self.inputHeld == isHeld then
		return
	end
	self.inputHeld = isHeld

	local castRequest = self:BuildCastRequest(triggerRaw)
	self.lastCastRequest = castRequest
	sendPacket(MagicServiceUtils.NETWORK_METHOD_REQUEST_SET_INPUT_HELD, isHeld, castRequest)
	if isHeld then
		self:SendCast(triggerRaw)
	end
end

function MagicServiceClient.StepHeldCast(self: MagicServiceClient)
	if not self.inputHeld then
		return
	end
	if self.equippedTool == nil then
		return
	end
	if self.lastCastRequest == nil then
		self.lastCastRequest = self:BuildCastRequest("Hold")
	else
		self.lastCastRequest = self:BuildCastRequest(self.lastCastRequest.trigger)
	end
	sendPacket(MagicServiceUtils.NETWORK_METHOD_REQUEST_SET_INPUT_HELD, true, self.lastCastRequest)
	self:SendCast("Hold")
end

function MagicServiceClient.ApplyState(self: MagicServiceClient, stateRaw: any)
	self.state = MagicServiceUtils.CoerceReplicatedState(stateRaw, self.state)
	self.stateChanged:Fire(self.state)
end

function MagicServiceClient.OnCastVisual(self: MagicServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local castId = trim(payload.castId)
	local weaponId = trim(payload.weaponId)
	local origin = payload.origin
	local direction = payload.direction
	local speed = payload.speed
	local lifetime = payload.lifetime
	if castId == "" then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if typeof(speed) ~= "number" or speed ~= speed then
		return
	end
	if typeof(lifetime) ~= "number" or lifetime ~= lifetime then
		return
	end
	if direction.Magnitude <= 1e-4 then
		return
	end

	self:ReleaseVisual(castId)
	local entry = self:AcquireVisualEntry(weaponId)
	local part = entry.part
	local visualSizeRaw = payload.visualSize
	local visualColorRaw = payload.visualColor
	if typeof(visualSizeRaw) == "Vector3" then
		part.Size = visualSizeRaw
	end
	if typeof(visualColorRaw) == "Color3" then
		part.Color = visualColorRaw
	end
	part.Transparency = 0.18
	part.CFrame = CFrame.lookAt(origin, origin + direction.Unit)

	self.activeVisuals[castId] = {
		castId = castId,
		weaponId = if weaponId ~= "" then weaponId else "unknown",
		entry = entry,
		position = origin,
		direction = direction.Unit,
		velocity = direction.Unit * math.max(1, speed),
		lifetimeRemaining = math.max(0.03, lifetime),
	}
end

function MagicServiceClient.SpawnImpactFlash(self: MagicServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end

	local flash = Instance.new("Part")
	flash.Name = HttpService:GenerateGUID(false)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.CastShadow = false
	flash.Color = if typeof(payload.visualColor) == "Color3" then payload.visualColor else Color3.fromRGB(170, 225, 255)
	flash.Size = if typeof(payload.visualSize) == "Vector3"
		then payload.visualSize * 0.8
		else Vector3.new(0.65, 0.65, 0.65)
	flash.Transparency = 0.15
	flash.CFrame = CFrame.new(position)
	flash.Parent = self.visualFolder

	task.delay(0.12, function()
		if flash.Parent ~= nil then
			flash:Destroy()
		end
	end)
end

function MagicServiceClient.OnImpactVisual(self: MagicServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	self:ReleaseVisual(payload.castId)
	self:SpawnImpactFlash(payload)
end

function MagicServiceClient.StepVisuals(self: MagicServiceClient, dt: number)
	for castId, visual in self.activeVisuals do
		visual.lifetimeRemaining -= dt
		if visual.lifetimeRemaining <= 0 then
			self:ReleaseVisual(castId)
			continue
		end
		visual.position += visual.velocity * dt
		visual.entry.part.CFrame = CFrame.lookAt(visual.position, visual.position + visual.direction)
	end
end

function MagicServiceClient.BindInputRouter(self: MagicServiceClient): boolean
	local runtimeContext = CoreRuntime.GetClientRuntime()
	if runtimeContext ~= nil and typeof((runtimeContext :: any).Init) == "function" then
		local runtimeAny = runtimeContext :: any
		runtimeAny:Init()
	end
	self.runtimeContext = runtimeContext
	self.hapticsModule = if runtimeContext ~= nil then (runtimeContext :: any).haptics else nil
	self.gamepadNav = if runtimeContext ~= nil and typeof((runtimeContext :: any).GetGamepadNav) == "function"
		then (runtimeContext :: any):GetGamepadNav()
		else if runtimeContext ~= nil then (runtimeContext :: any).gamepadNav else nil
	if not PlatformServiceClient:IsReady() then
		PlatformServiceClient:Init()
	end

	local disconnect = PlatformServiceClient:BindAction(INPUT_ACTION_CAST, function(phase: string)
		if phase == "Began" then
			if self.equippedTool ~= nil then
				self:SetInputHeld(true, "PrimaryInputBegan")
			end
		elseif phase == "Ended" then
			self:SetInputHeld(false, "PrimaryInputEnded")
		end
		return false
	end)

	if disconnect == nil then
		return false
	end

	self.janitor:GiveChore(disconnect)
	return true
end

function MagicServiceClient.OnInventoryStateChanged(self: MagicServiceClient, stateRaw: any)
	self.inventoryState = InventoryServiceUtils.CoerceState(
		stateRaw,
		InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	)
	self:RefreshEquipped()
end

function MagicServiceClient.OnCharacterAdded(self: MagicServiceClient, character: Model)
	self.character = character
	self.characterJanitor:Clean()
	local function bindBackpack(backpack: Backpack)
		self.characterJanitor:GiveChore(backpack.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:RefreshEquipped()
			end
		end))
		self.characterJanitor:GiveChore(backpack.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:RefreshEquipped()
			end
		end))
	end
	self.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:RefreshEquipped()
		end
	end))
	self.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:RefreshEquipped()
		end
	end))

	self.characterJanitor:GiveChore(self.localPlayer.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			bindBackpack(child)
			self:RefreshEquipped()
		end
	end))

	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		bindBackpack(backpack)
	end

	self:RefreshEquipped()
end

function MagicServiceClient.RequestSync(self: MagicServiceClient)
	sendPacket(MagicServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function MagicServiceClient.Init(self: MagicServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.janitor:GiveChore(self.characterJanitor)
	self.state = createDefaultReplicatedState()
	self.stateChanged = Signal.new()
	self.inputHeld = false
	self.lastCastRequestAt = -math.huge
	self.lastCastRequest = nil :: MagicServiceUtils.CastRequest?
	self.inventoryState = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	self.character = nil :: Model?
	self.equippedItemId = nil :: string?
	self.equippedTool = nil :: Tool?
	self.visualPools = {} :: { [string]: { VisualPoolEntry } }
	self.activeVisuals = {} :: { [string]: ActiveVisual }
	self.visualAccumulator = 0
	self.lastHeldTickAt = -math.huge
	self.runtimeContext = nil
	self.hapticsModule = nil
	self.gamepadNav = nil

	self.visualFolder = WorkspaceFolders.GetOrCreateFolderInGame(CLIENT_VISUAL_FOLDER_NAME)

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)
	self.janitor:GiveChore(function()
		for _, pool in pairs(self.visualPools :: { [string]: { VisualPoolEntry } }) do
			for _, entry in pool do
				if entry.part.Parent ~= nil then
					entry.part:Destroy()
				end
			end
		end
		self.visualPools = {}
		self.activeVisuals = {}
	end)

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character: Model)
		self:OnCharacterAdded(character)
	end))

	self:BindInputRouter()

	self.janitor:GiveChore(RunService.RenderStepped:Connect(function(dt: number)
		if self.inputHeld and os.clock() - self.lastHeldTickAt >= MagicServiceUtils.CLIENT_CAST_REQUEST_INTERVAL then
			self.lastHeldTickAt = os.clock()
			self:StepHeldCast()
		end

		local visualAccumulator = (self.visualAccumulator :: number) + dt
		self.visualAccumulator = visualAccumulator
		local steps = 0
		while visualAccumulator >= CLIENT_VISUAL_STEP and steps < 4 do
			visualAccumulator -= CLIENT_VISUAL_STEP
			self.visualAccumulator = visualAccumulator
			steps += 1
			self:StepVisuals(CLIENT_VISUAL_STEP)
		end
		if steps >= 4 then
			self.visualAccumulator = 0
		end
	end))

	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: InventoryState)
			self:OnInventoryStateChanged(nextState)
		end))
	end

	if self.localPlayer.Character ~= nil then
		self:OnCharacterAdded(self.localPlayer.Character)
	end
	self:OnInventoryStateChanged(InventoryServiceClient.state)
	self:RequestSync()
	self:RefreshEquipped()
end

function MagicServiceClient.GetState(self: MagicServiceClient): ReplicatedState
	return MagicServiceUtils.CoerceReplicatedState(self.state, createDefaultReplicatedState())
end

function MagicServiceClient.Destroy(self: MagicServiceClient)
	self:SetInputHeld(false, "Destroy")
	if self.characterJanitor ~= nil then
		self.characterJanitor:Destroy()
	end
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end
type MagicServiceClient = typeof(MagicServiceClient) & {
	runtimeContext: any?,
	hapticsModule: any?,
	gamepadNav: any?,
	localPlayer: Player,
	janitor: JanitorClass,
	characterJanitor: JanitorClass,
	stateChanged: SignalObject,
	state: ReplicatedState,
	inventoryState: InventoryState,
	inputHeld: boolean,
	lastCastRequestAt: number,
	lastHeldTickAt: number,
	lastCastRequest: MagicServiceUtils.CastRequest?,
	character: Model?,
	equippedItemId: string?,
	equippedTool: Tool?,
	visualFolder: Folder,
	visualPools: { [string]: { VisualPoolEntry } },
	activeVisuals: { [string]: ActiveVisual },
	visualAccumulator: number,
}

return MagicServiceClient :: MagicServiceClient
