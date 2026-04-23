--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local InventoryServiceClient = require(script:FindFirstAncestor("game").Client.Services.InventoryService.InventoryServiceClient)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryService.InventoryServiceUtils)
local MagicServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.MagicService.MagicServiceUtils)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformService.PlatformServiceClient)

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

local function trim(raw: any): string
	if typeof(raw) ~= "string" then
		return ""
	end
	return string.match(raw, "^%s*(.-)%s*$") or ""
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

local function resolveCharacterRootPart(characterRaw: any): BasePart?
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

local function resolveMouseHitPosition(localPlayer: Player): Vector3?
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

function MagicServiceClient.CreateVisualPart(self: MagicServiceClient, weaponIdRaw: any): BasePart
	local weaponId = trim(weaponIdRaw)
	local part = Instance.new("Part")
	part.Name = ("MagicClientProjectile_%s"):format(if weaponId ~= "" then weaponId else "Unknown")
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
		part = self:createVisualPart(poolKey),
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
	if InventoryServiceClient.getState ~= nil then
		return InventoryServiceClient:getState()
	end
	return InventoryServiceUtils.sanitizeState(
		InventoryServiceClient.state,
		InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	)
end

function MagicServiceClient.ResolveEquippedMagicTool(self: MagicServiceClient): (string?, Tool?)
	local inventoryState = self:getInventoryState()
	local itemId = MagicServiceUtils.resolveSelectedItemIdFromInventoryState(inventoryState)
	if itemId == nil then
		return nil, nil
	end
	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	local tool = MagicServiceUtils.resolveToolByItemId(self.character, backpack, itemId)
	if tool == nil or not MagicServiceUtils.isMagicTool(tool) then
		return itemId, nil
	end
	return itemId, tool
end

function MagicServiceClient.RefreshEquipped(self: MagicServiceClient)
	local itemId, tool = self:resolveEquippedMagicTool()
	self.equippedItemId = itemId
	self.equippedTool = tool
	if self.equippedTool == nil and self.inputHeld then
		self:setInputHeld(false, "Unequipped")
	end
	self.networker:fire(MagicServiceUtils.NETWORK_METHOD_REQUEST_REFRESH_EQUIPPED)
end

function MagicServiceClient.BuildCastRequest(self: MagicServiceClient, triggerRaw: any): MagicServiceUtils.CastRequest
	local trigger = trim(triggerRaw)
	local rootPart = resolveCharacterRootPart(self.character)
	local origin = if rootPart ~= nil then rootPart.Position + Vector3.new(0, 1.35, 0) else Vector3.zero
	local fallbackDirection = if rootPart ~= nil then rootPart.CFrame.LookVector else Vector3.new(0, 0, -1)
	local mousePosition = resolveMouseHitPosition(self.localPlayer)
	local aimDirection = nil :: Vector3?
	if mousePosition ~= nil then
		local offset = mousePosition - origin
		if offset.Magnitude > 1e-4 then
			aimDirection = offset.Unit
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
	if not self:canSendCast() then
		return
	end
	self.lastCastRequestAt = os.clock()
	local castRequest = self:buildCastRequest(triggerRaw)
	self.lastCastRequest = castRequest
	self.networker:fire(MagicServiceUtils.NETWORK_METHOD_REQUEST_CAST, castRequest)
	if self.hapticsModule ~= nil and typeof((self.hapticsModule :: any).confirm) == "function" then
		local hapticsAny = self.hapticsModule :: any
		hapticsAny:confirm()
	end
end

function MagicServiceClient.SetInputHeld(self: MagicServiceClient, isHeld: boolean, triggerRaw: any)
	if self.inputHeld == isHeld then
		return
	end
	self.inputHeld = isHeld

	local castRequest = self:buildCastRequest(triggerRaw)
	self.lastCastRequest = castRequest
	self.networker:fire(MagicServiceUtils.NETWORK_METHOD_REQUEST_SET_INPUT_HELD, isHeld, castRequest)
	if isHeld then
		self:sendCast(triggerRaw)
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
		self.lastCastRequest = self:buildCastRequest("Hold")
	else
		self.lastCastRequest = self:buildCastRequest(self.lastCastRequest.trigger)
	end
	self.networker:fire(MagicServiceUtils.NETWORK_METHOD_REQUEST_SET_INPUT_HELD, true, self.lastCastRequest)
	self:sendCast("Hold")
end

function MagicServiceClient.ApplyState(self: MagicServiceClient, stateRaw: any)
	self.state = MagicServiceUtils.sanitizeReplicatedState(stateRaw, self.state)
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

	self:releaseVisual(castId)
	local entry = self:acquireVisualEntry(weaponId)
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
	self:releaseVisual(payload.castId)
	self:spawnImpactFlash(payload)
end

function MagicServiceClient.StepVisuals(self: MagicServiceClient, dt: number)
	for castId, visual in self.activeVisuals do
		visual.lifetimeRemaining -= dt
		if visual.lifetimeRemaining <= 0 then
			self:releaseVisual(castId)
			continue
		end
		visual.position += visual.velocity * dt
		visual.entry.part.CFrame = CFrame.lookAt(visual.position, visual.position + visual.direction)
	end
end

function MagicServiceClient.BindInputRouter(self: MagicServiceClient): boolean
	local runtimeContext = CoreRuntime.getClientRuntime()
	if runtimeContext ~= nil and typeof((runtimeContext :: any).init) == "function" then
		local runtimeAny = runtimeContext :: any
		runtimeAny:init()
	end
	self.runtimeContext = runtimeContext
	self.hapticsModule = if runtimeContext ~= nil then (runtimeContext :: any).haptics else nil
	if not PlatformServiceClient:isReady() then
		PlatformServiceClient:init()
	end

	local disconnect = PlatformServiceClient:bindAction(INPUT_ACTION_CAST, function(phase: string)
		if phase == "Began" then
			if self.equippedTool ~= nil then
				self:setInputHeld(true, "PrimaryInputBegan")
			end
		elseif phase == "Ended" then
			self:setInputHeld(false, "PrimaryInputEnded")
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
	self.inventoryState = InventoryServiceUtils.sanitizeState(
		stateRaw,
		InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	)
	self:refreshEquipped()
end

function MagicServiceClient.OnCharacterAdded(self: MagicServiceClient, character: Model)
	self.character = character
	self.characterJanitor:Clean()
	local function bindBackpack(backpack: Backpack)
		self.characterJanitor:GiveChore(backpack.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:refreshEquipped()
			end
		end))
		self.characterJanitor:GiveChore(backpack.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:refreshEquipped()
			end
		end))
	end
	self.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:refreshEquipped()
		end
	end))
	self.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:refreshEquipped()
		end
	end))

	self.characterJanitor:GiveChore(self.localPlayer.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			bindBackpack(child)
			self:refreshEquipped()
		end
	end))

	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		bindBackpack(backpack)
	end

	self:refreshEquipped()
end

function MagicServiceClient.RequestSync(self: MagicServiceClient)
	self.networker:fire(MagicServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function MagicServiceClient.Init(self: MagicServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("MagicService", self)
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.janitor:GiveChore(self.characterJanitor)
	self.state = createDefaultReplicatedState()
	self.stateChanged = Signal.new()
	self.inputHeld = false
	self.lastCastRequestAt = -math.huge
	self.lastCastRequest = nil :: MagicServiceUtils.CastRequest?
	self.inventoryState = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	self.character = nil :: Model?
	self.equippedItemId = nil :: string?
	self.equippedTool = nil :: Tool?
	self.visualPools = {} :: { [string]: { VisualPoolEntry } }
	self.activeVisuals = {} :: { [string]: ActiveVisual }
	self.visualAccumulator = 0
	self.lastHeldTickAt = -math.huge
	self.runtimeContext = nil
	self.hapticsModule = nil

	self.visualFolder = WorkspaceFolders.getOrCreateFolderInGame(CLIENT_VISUAL_FOLDER_NAME)

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)
	self.janitor:GiveChore(function()
		for _, pool in self.visualPools do
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
		self:onCharacterAdded(character)
	end))

	self:bindInputRouter()

	self.janitor:GiveChore(RunService.RenderStepped:Connect(function(dt: number)
		if self.inputHeld and os.clock() - self.lastHeldTickAt >= MagicServiceUtils.CLIENT_CAST_REQUEST_INTERVAL then
			self.lastHeldTickAt = os.clock()
			self:stepHeldCast()
		end

		self.visualAccumulator += dt
		local steps = 0
		while self.visualAccumulator >= CLIENT_VISUAL_STEP and steps < 4 do
			self.visualAccumulator -= CLIENT_VISUAL_STEP
			steps += 1
			self:stepVisuals(CLIENT_VISUAL_STEP)
		end
		if steps >= 4 then
			self.visualAccumulator = 0
		end
	end))

	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: InventoryState)
			self:onInventoryStateChanged(nextState)
		end))
	end

	if self.localPlayer.Character ~= nil then
		self:onCharacterAdded(self.localPlayer.Character)
	end
	self:onInventoryStateChanged(InventoryServiceClient.state)
	self:requestSync()
	self:refreshEquipped()
end

function MagicServiceClient.GetState(self: MagicServiceClient): ReplicatedState
	return MagicServiceUtils.sanitizeReplicatedState(self.state, createDefaultReplicatedState())
end

function MagicServiceClient.Destroy(self: MagicServiceClient)
	self:setInputHeld(false, "Destroy")
	if self.characterJanitor ~= nil then
		self.characterJanitor:Destroy()
	end
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

MagicServiceClient.createVisualPart = MagicServiceClient.CreateVisualPart
MagicServiceClient.acquireVisualEntry = MagicServiceClient.AcquireVisualEntry
MagicServiceClient.releaseVisual = MagicServiceClient.ReleaseVisual
MagicServiceClient.getInventoryState = MagicServiceClient.GetInventoryState
MagicServiceClient.resolveEquippedMagicTool = MagicServiceClient.ResolveEquippedMagicTool
MagicServiceClient.refreshEquipped = MagicServiceClient.RefreshEquipped
MagicServiceClient.buildCastRequest = MagicServiceClient.BuildCastRequest
MagicServiceClient.canSendCast = MagicServiceClient.CanSendCast
MagicServiceClient.sendCast = MagicServiceClient.SendCast
MagicServiceClient.setInputHeld = MagicServiceClient.SetInputHeld
MagicServiceClient.stepHeldCast = MagicServiceClient.StepHeldCast
MagicServiceClient.applyState = MagicServiceClient.ApplyState
MagicServiceClient.onCastVisual = MagicServiceClient.OnCastVisual
MagicServiceClient.spawnImpactFlash = MagicServiceClient.SpawnImpactFlash
MagicServiceClient.onImpactVisual = MagicServiceClient.OnImpactVisual
MagicServiceClient.stepVisuals = MagicServiceClient.StepVisuals
MagicServiceClient.bindInputRouter = MagicServiceClient.BindInputRouter
MagicServiceClient.onInventoryStateChanged = MagicServiceClient.OnInventoryStateChanged
MagicServiceClient.onCharacterAdded = MagicServiceClient.OnCharacterAdded
MagicServiceClient.requestSync = MagicServiceClient.RequestSync
MagicServiceClient.init = MagicServiceClient.Init
MagicServiceClient.getState = MagicServiceClient.GetState
MagicServiceClient.destroy = MagicServiceClient.Destroy

type MagicServiceClient = typeof(MagicServiceClient) & {
	runtimeContext: any?,
	hapticsModule: any?,
	localPlayer: Player,
	networker: Networker.Client,
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

