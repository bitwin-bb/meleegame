local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CameraShaker = require("EZCameraShake")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local MeleeServicePackets = require("NetPacketsShared").MeleeService

local function sendPacket(methodName: string, ...: any)
	local packet = MeleeServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for MeleeService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local AnimationServiceUtils = require("AnimationServiceUtils")
local AudioServiceClient = require("AudioServiceClient")
local BuildServiceClient = require("BuildServiceClient")
local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local InventoryServiceClient = require("InventoryServiceClient")
local InventoryServiceUtils = require("InventoryServiceUtils")
local Melee = require("Melee")
local MeleeServiceUtils = require("MeleeServiceUtils")
local PlatformServiceClient = require("PlatformServiceClient")
local Promise: any = require("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end
local RagdollServiceClient = require("AquariaRagdollServiceClient")
local RaycastHitbox: any = require("RaycastHitbox")

type MeleeWeaponConfig = MeleeServiceUtils.MeleeWeaponConfig
type InventoryState = InventoryServiceUtils.InventoryState

type JanitorClass = any

type MeleeController = {
	InputBegan: (self: MeleeController, triggerRaw: any) -> boolean,
	InputEnded: (self: MeleeController, triggerRaw: any) -> boolean,
	SetCharacter: (self: MeleeController, characterRaw: any) -> (),
	On: (self: MeleeController, signalNameRaw: any, callback: (...any) -> ()) -> any,
	Destroy: (self: MeleeController) -> (),
}

type CameraShakerObject = {
	Start: (self: CameraShakerObject) -> (),
	Stop: (self: CameraShakerObject) -> (),
	ShakeOnce: (
		self: CameraShakerObject,
		magnitude: number,
		roughness: number,
		fadeInTime: number?,
		fadeOutTime: number?,
		posInfluence: Vector3?,
		rotInfluence: Vector3?
	) -> any,
}

type HitboxObject = {
	RaycastParams: RaycastParams?,
	Visualizer: boolean,
	DebugLog: boolean,
	HitStart: (self: HitboxObject, seconds: number?) -> (),
	HitStop: (self: HitboxObject) -> (),
	Destroy: (self: HitboxObject) -> (),
	SetPoints: (self: HitboxObject, object: BasePart | Bone, vectorPoints: { Vector3 }, group: string?) -> (),
	RemovePoints: (self: HitboxObject, object: BasePart | Bone, vectorPoints: { Vector3 }) -> (),
}

local MeleeServiceClient = {}

local INPUT_ACTION_ATTACK = "MeleeService.Attack"

local TOOL_SOUND_FALLBACKS_BY_EVENT_TYPE: { [string]: { string } } = {
	AttackStarted = { "AttackStarted", "Swing", "SwingStart", "startSwing" },
	Marker = { "Marker", "Swing", "SwingStart", "startSwing" },
	Keyframe = { "Keyframe", "Swing", "SwingStart", "startSwing" },
	AttackFinished = { "AttackFinished", "SwingEnd", "endSwing" },
}

local MELEE_CAMERA_SHAKE_RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local MELEE_CAMERA_SHAKE_MIN_MAGNITUDE = 1.35
local MELEE_CAMERA_SHAKE_MAX_MAGNITUDE = 2.2
local MELEE_CAMERA_SHAKE_MIN_ROUGHNESS = 13
local MELEE_CAMERA_SHAKE_MAX_ROUGHNESS = 18
local MELEE_CAMERA_SHAKE_FADE_IN = 0.01
local MELEE_CAMERA_SHAKE_FADE_OUT = 0.18
local MELEE_CAMERA_SHAKE_MIN_POSITION_INFLUENCE = Vector3.new(0.12, 0.09, 0.12)
local MELEE_CAMERA_SHAKE_MAX_POSITION_INFLUENCE = Vector3.new(0.18, 0.13, 0.18)
local MELEE_CAMERA_SHAKE_MIN_ROTATION_INFLUENCE = Vector3.new(1.35, 1.75, 1.35)
local MELEE_CAMERA_SHAKE_MAX_ROTATION_INFLUENCE = Vector3.new(1.75, 2.15, 1.75)
local MELEE_CAMERA_SHAKE_MIN_INTERVAL = 0.06
local MELEE_CAMERA_SHAKE_DAMAGE_FOR_MAX_INTENSITY = 60

local function promiseAll(promises: { any }): any
	if #promises <= 0 then
		return fulfilledPromise()
	end

	local results = table.create(#promises)
	local remaining = #promises

	local aggregatePromise = Promise.new(function(fulfill, reject)
		local settled = false

		local function rejectOnce(...)
			if settled then
				return
			end
			settled = true
			reject(...)
		end

		local function GetOne(index: number, ...)
			if settled then
				return
			end
			results[index] = table.pack(...)
			remaining -= 1
			if remaining <= 0 then
				settled = true
				fulfill(results)
			end
		end

		for index, nextPromise in promises do
			nextPromise:Then(function(...)
				GetOne(index, ...)
			end, rejectOnce)
		end
	end)

	aggregatePromise:Finally(function()
		for _, nextPromise in promises do
			if nextPromise ~= nil and typeof((nextPromise :: any).Destroy) == "function" then
				(nextPromise :: any):Destroy()
			end
		end
	end)

	return aggregatePromise
end

local function promiseFromSignal(signal: any, predicate: ((...any) -> boolean)?): any
	local connection = nil :: RBXScriptConnection?
	local promise = Promise.new(function(fulfill, reject)
		local settled = false

		local function cleanup()
			if connection ~= nil then
				connection:Disconnect()
				connection = nil
			end
		end

		local function settle(callback: (...any) -> (), ...)
			if settled then
				return
			end
			settled = true
			cleanup()
			callback(...)
		end

		connection = signal:Connect(function(...)
			if predicate ~= nil and not predicate(...) then
				return
			end
			settle(fulfill, ...)
		end)

		if connection == nil then
			settle(reject, "Failed to connect signal")
		end
	end)

	promise:Finally(function()
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
	end)

	return promise
end

local function GetHumanoidFromCharacter(character: Model?): Humanoid?
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		return humanoid
	end
	return nil
end

local function isHumanoidAlive(humanoid: Humanoid?): boolean
	if humanoid == nil then
		return false
	end
	if humanoid.Health <= 0 then
		return false
	end
	return humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function GetRootPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local rootPartCandidate = character:FindFirstChild("HumanoidRootPart")
	if rootPartCandidate ~= nil and rootPartCandidate:IsA("BasePart") then
		return rootPartCandidate
	end
	return nil
end

local function normalizeEventKey(valueRaw: any): string
	local value = string.lower(trim(valueRaw))
	if value == "" then
		return ""
	end
	value = string.gsub(value, "[%s_%-]+", "")
	return value
end

local function normalizeSwingSoundGroup(valueRaw: any): string?
	local normalized = normalizeEventKey(valueRaw)
	if normalized == "" then
		return nil
	end
	local swingIndexText = string.match(normalized, "^swing(%d+)$")
	if swingIndexText == nil then
		return nil
	end
	return "swing" .. swingIndexText
end

local function isStartSwingEvent(valueRaw: any): boolean
	local normalized = normalizeEventKey(valueRaw)
	return normalized == "startswing" or normalized == "swingstart"
end

local function GetOrderedSwingGroups(swingSounds: { [string]: { string } }): { string }
	local indexedGroups = {}
	for groupName, pool in swingSounds do
		if typeof(groupName) ~= "string" or typeof(pool) ~= "table" or #pool <= 0 then
			continue
		end

		local swingIndexText = string.match(groupName, "^swing(%d+)$")
		local swingIndex = if swingIndexText ~= nil then tonumber(swingIndexText) else nil
		if swingIndex ~= nil then
			table.insert(indexedGroups, {
				groupName = groupName,
				swingIndex = swingIndex,
			})
		end
	end

	table.sort(indexedGroups, function(lhs, rhs)
		if lhs.swingIndex == rhs.swingIndex then
			return lhs.groupName < rhs.groupName
		end
		return lhs.swingIndex < rhs.swingIndex
	end)

	local orderedGroups = {}
	for _, entry in indexedGroups do
		orderedGroups[#orderedGroups + 1] = entry.groupName
	end
	return orderedGroups
end

local function GetToolHandlePart(toolRaw: any): BasePart?
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		return nil
	end

	local tool = toolRaw :: Tool
	local handleCandidate = tool:FindFirstChild("Handle")
	if handleCandidate ~= nil and handleCandidate:IsA("BasePart") then
		return handleCandidate
	end

	local directBasePart = tool:FindFirstChildWhichIsA("BasePart")
	if directBasePart ~= nil then
		return directBasePart
	end

	return tool:FindFirstChildWhichIsA("BasePart", true)
end

local function GetCharacterHandPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end

	for _, partName in { "RightHand", "Right Arm", "RightLowerArm", "RightUpperArm", "LeftHand", "Left Arm" } do
		local candidate = character:FindFirstChild(partName)
		if candidate ~= nil and candidate:IsA("BasePart") then
			return candidate
		end
	end

	return nil
end

local function GetMeleeDebugHitboxEnabledFromConfigs(): boolean
	if typeof(Configs) ~= "table" then
		return false
	end

	local meleeSettings = (Configs :: any).meleeSettings
	if typeof(meleeSettings) ~= "table" then
		return false
	end

	local debugEnabled = (meleeSettings :: any).debugHitboxEnabled
	if typeof(debugEnabled) ~= "boolean" then
		return false
	end

	return debugEnabled
end

local function shallowCopyWeaponConfig(weaponConfig: MeleeWeaponConfig): MeleeWeaponConfig
	return {
		itemId = weaponConfig.itemId,
		displayName = weaponConfig.displayName,
		damage = weaponConfig.damage,
		cooldown = weaponConfig.cooldown,
		slashCooldown = weaponConfig.slashCooldown,
		slashResetCooldown = weaponConfig.slashResetCooldown,
		swingDuration = weaponConfig.swingDuration,
		hitboxDuration = weaponConfig.hitboxDuration,
		range = weaponConfig.range,
		width = weaponConfig.width,
		height = weaponConfig.height,
		pointCount = weaponConfig.pointCount,
		autoRepeatWhileHeld = weaponConfig.autoRepeatWhileHeld,
		canHitPlayers = weaponConfig.canHitPlayers,
		canHitNpcs = weaponConfig.canHitNpcs,
		animations = weaponConfig.animations,
	}
end

local function isWeaponConfigEquivalent(lhsRaw: any, rhsRaw: any): boolean
	if lhsRaw == rhsRaw then
		return true
	end
	if typeof(lhsRaw) ~= "table" or typeof(rhsRaw) ~= "table" then
		return false
	end

	local lhs = lhsRaw :: MeleeWeaponConfig
	local rhs = rhsRaw :: MeleeWeaponConfig
	if lhs.itemId ~= rhs.itemId then
		return false
	end
	if lhs.displayName ~= rhs.displayName then
		return false
	end
	if lhs.damage ~= rhs.damage then
		return false
	end
	if lhs.cooldown ~= rhs.cooldown then
		return false
	end
	if lhs.slashCooldown ~= rhs.slashCooldown then
		return false
	end
	if lhs.slashResetCooldown ~= rhs.slashResetCooldown then
		return false
	end
	if lhs.swingDuration ~= rhs.swingDuration then
		return false
	end
	if lhs.hitboxDuration ~= rhs.hitboxDuration then
		return false
	end
	if lhs.range ~= rhs.range then
		return false
	end
	if lhs.width ~= rhs.width then
		return false
	end
	if lhs.height ~= rhs.height then
		return false
	end
	if lhs.pointCount ~= rhs.pointCount then
		return false
	end
	if lhs.autoRepeatWhileHeld ~= rhs.autoRepeatWhileHeld then
		return false
	end
	if lhs.canHitPlayers ~= rhs.canHitPlayers then
		return false
	end
	if lhs.canHitNpcs ~= rhs.canHitNpcs then
		return false
	end
	if not MeleeServiceUtils.AreAnimationConfigsEquivalent(lhs.animations, rhs.animations) then
		return false
	end

	return true
end

function MeleeServiceClient.Init(self: MeleeServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.toolJanitor = Janitor.new()
	self.janitor:GiveChore(self.characterJanitor)
	self.janitor:GiveChore(self.toolJanitor)

	self.inventoryState = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	self.character = nil :: Model?
	self.humanoid = nil :: Humanoid?
	self.inputHeld = false
	self.activeMelee = nil :: MeleeController?
	self.equippedItemId = nil :: string?
	self.equippedSlot = nil :: number?
	self.equippedWeaponConfig = nil :: MeleeWeaponConfig?
	self.equippedTool = nil :: Tool?
	self.equippedToolSounds = {} :: { [string]: string }
	self.equippedToolSwingSounds = {} :: { [string]: { string } }
	self.replicatedItemId = nil :: string?
	self.replicatedSlot = nil :: number?
	self.cameraShaker = nil :: CameraShakerObject?
	self.lastSwingCameraShakeAt = -math.huge
	self.debugHitboxEnabled = GetMeleeDebugHitboxEnabledFromConfigs()
	self.debugHitbox = nil :: HitboxObject?
	self.debugHitboxPointsPart = nil :: BasePart?
	self.debugHitboxPoints = {} :: { Vector3 }
	self.runtimeContext = nil
	self.hapticsModule = nil

	local cameraShakerOk, cameraShakerOrError = pcall(function()
		local cameraShaker = CameraShaker.new(MELEE_CAMERA_SHAKE_RENDER_PRIORITY, function(shakeCFrame: CFrame)
			local camera = Workspace.CurrentCamera
			if camera == nil then
				return
			end

			camera.CFrame = camera.CFrame * shakeCFrame
		end) :: any
		return cameraShaker :: CameraShakerObject
	end)
	if cameraShakerOk then
		self.cameraShaker = cameraShakerOrError :: CameraShakerObject
		local startOk = pcall(function()
			local cameraShaker = self.cameraShaker :: CameraShakerObject
			cameraShaker:Start()
		end)
		if not startOk then
			self.cameraShaker = nil
		end
	end

	self.janitor:GiveChore(function()
		local activeCameraShaker = self.cameraShaker
		self.cameraShaker = nil
		if activeCameraShaker ~= nil then
			pcall(function()
				activeCameraShaker:Stop()
			end)
		end
	end)

	self.janitor:GiveChore(function()
		self:DestroyDebugHitbox()
	end)

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character: Model)
		self:OnCharacterAdded(character)
	end))

	self:BindInputRouter()

	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: InventoryState)
			self:OnInventoryStateChanged(nextState)
		end))
	end
	if RagdollServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(RagdollServiceClient.stateChanged:Connect(function()
			if self:IsAttackBlocked() then
				self:SetInputHeld(false, "RagdollChanged")
			end
		end))
	end

	if self.localPlayer.Character ~= nil then
		self:OnCharacterAdded(self.localPlayer.Character)
	end

	self:OnInventoryStateChanged(InventoryServiceClient.state)

	self.bootstrapPromise = promiseAll({
			self:WaitForCharacter(),
			self:WaitForInventoryLoaded(),
		})
		:Then(function()
			self:RefreshEquippedWeapon("Bootstrap")
			self:ReplicateEquippedState(true)
		end)
		:Catch(function(_err: any) end)

	self.janitor:GiveChore(function()
		if self.bootstrapPromise ~= nil then
			self.bootstrapPromise:Destroy()
			self.bootstrapPromise = nil
		end
	end)
end

function MeleeServiceClient.BindInputRouter(self: MeleeServiceClient): boolean
	local runtimeContext = CoreRuntime.GetClientRuntime()
	if runtimeContext ~= nil and typeof((runtimeContext :: any).Init) == "function" then
		local runtimeAny = runtimeContext :: any
		runtimeAny:Init()
	end
	self.runtimeContext = runtimeContext
	self.hapticsModule = if runtimeContext ~= nil then (runtimeContext :: any).haptics else nil
	if not PlatformServiceClient:IsReady() then
		PlatformServiceClient:Init()
	end

	local disconnect = PlatformServiceClient:BindAction(INPUT_ACTION_ATTACK, function(phase: string)
		if phase == "Began" then
			if not self:IsAttackBlocked() then
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

function MeleeServiceClient.WaitForCharacter(self: MeleeServiceClient)
	local character = self.localPlayer.Character
	if character ~= nil then
		return fulfilledPromise(character)
	end
	return promiseFromSignal(self.localPlayer.CharacterAdded)
end

function MeleeServiceClient.WaitForInventoryLoaded(self: MeleeServiceClient)
	local state = self.inventoryState
	if InventoryServiceUtils.IsLoadedState(state.loadState) then
		return fulfilledPromise(state)
	end
	if InventoryServiceClient.stateChanged == nil then
		return fulfilledPromise(state)
	end

	return promiseFromSignal(InventoryServiceClient.stateChanged, function(nextState: InventoryState): boolean
		return InventoryServiceUtils.IsLoadedState(nextState.loadState)
	end)
end

function MeleeServiceClient.DestroyActiveMelee(self: MeleeServiceClient)
	self:StopDebugHitbox()

	local activeMelee = self.activeMelee
	self.activeMelee = nil
	if activeMelee == nil then
		return
	end

	pcall(function()
		activeMelee:Destroy()
	end)
end

function MeleeServiceClient.ReplicateEquippedState(self: MeleeServiceClient, forceRaw: any)
	local force = forceRaw == true
	if not force then
		if self.replicatedItemId == self.equippedItemId and self.replicatedSlot == self.equippedSlot then
			return
		end
	end

	self.replicatedItemId = self.equippedItemId
	self.replicatedSlot = self.equippedSlot
	sendPacket(MeleeServiceUtils.NETWORK_METHOD_REFRESH_EQUIPPED)
end

function MeleeServiceClient.RefreshHumanoidReference(self: MeleeServiceClient)
	self.humanoid = GetHumanoidFromCharacter(self.character)
end

function MeleeServiceClient.GetDebugHitboxAnchorPart(self: MeleeServiceClient): BasePart?
	local character = self.character
	local equippedTool = self.equippedTool
	if equippedTool ~= nil and character ~= nil and equippedTool:IsDescendantOf(character) then
		local toolPart = GetToolHandlePart(equippedTool)
		if toolPart ~= nil then
			return toolPart
		end
	end

	local handPart = GetCharacterHandPart(character)
	if handPart ~= nil then
		return handPart
	end

	return GetRootPart(character)
end

function MeleeServiceClient.StopDebugHitbox(self: MeleeServiceClient)
	local debugHitbox = self.debugHitbox
	if debugHitbox == nil then
		return
	end

	pcall(function()
		debugHitbox:HitStop()
	end)
end

function MeleeServiceClient.ClearDebugHitboxPoints(self: MeleeServiceClient)
	local debugHitbox = self.debugHitbox
	local pointsPart = self.debugHitboxPointsPart
	local points = self.debugHitboxPoints
	if debugHitbox ~= nil and pointsPart ~= nil and #points > 0 then
		pcall(function()
			debugHitbox:RemovePoints(pointsPart, points)
		end)
	end

	self.debugHitboxPointsPart = nil
	self.debugHitboxPoints = {}
end

function MeleeServiceClient.ApplyDebugHitboxPoints(self: MeleeServiceClient)
	if not self.debugHitboxEnabled then
		self:ClearDebugHitboxPoints()
		return
	end

	local debugHitbox = self.debugHitbox
	local weaponConfig = self.equippedWeaponConfig
	if debugHitbox == nil or weaponConfig == nil then
		self:ClearDebugHitboxPoints()
		return
	end

	local anchorPart = self:GetDebugHitboxAnchorPart()
	if anchorPart == nil then
		self:ClearDebugHitboxPoints()
		return
	end

	self:ClearDebugHitboxPoints()
	local points = MeleeServiceUtils.BuildHitboxPoints(weaponConfig)
	if #points <= 0 then
		return
	end

	self.debugHitboxPointsPart = anchorPart
	self.debugHitboxPoints = points
	pcall(function()
		debugHitbox:SetPoints(anchorPart, points)
	end)
end

function MeleeServiceClient.DestroyDebugHitbox(self: MeleeServiceClient)
	self:StopDebugHitbox()
	self:ClearDebugHitboxPoints()

	local debugHitbox = self.debugHitbox
	self.debugHitbox = nil
	if debugHitbox ~= nil then
		pcall(function()
			debugHitbox:Destroy()
		end)
	end
end

function MeleeServiceClient.EnsureDebugHitbox(self: MeleeServiceClient)
	self:DestroyDebugHitbox()
	if not self.debugHitboxEnabled then
		return
	end
	if self.character == nil then
		return
	end

	local debugHitbox = RaycastHitbox.new(self.character) :: any
	self.debugHitbox = debugHitbox :: HitboxObject
	debugHitbox.Visualizer = true
	debugHitbox.DebugLog = false

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.character }
	params.IgnoreWater = true
	debugHitbox.RaycastParams = params

	self:ApplyDebugHitboxPoints()
end

function MeleeServiceClient.IsAttackBlocked(self: MeleeServiceClient): boolean
	if not isHumanoidAlive(self.humanoid) then
		return true
	end

	local humanoid = self.humanoid
	if humanoid ~= nil and humanoid.PlatformStand and humanoid:GetState() == Enum.HumanoidStateType.Physics then
		return true
	end

	if RagdollServiceClient.IsRagdolled ~= nil and RagdollServiceClient:IsRagdolled() then
		return true
	end

	return false
end

function MeleeServiceClient.PlayToolSoundAssetId(self: MeleeServiceClient, soundAssetIdRaw: any)
	if AudioServiceClient.categoryGroups == nil then
		return
	end
	if typeof(soundAssetIdRaw) ~= "string" and typeof(soundAssetIdRaw) ~= "number" then
		return
	end

	local rootPart = GetRootPart(self.character)
	AudioServiceClient:PlaySfx(soundAssetIdRaw, {
		parent = rootPart,
		replaceChannel = false,
		autoDestroy = true,
	})
end

function MeleeServiceClient.GetToolSound(self: MeleeServiceClient, soundNameRaw: any): string?
	local soundName = trim(soundNameRaw)
	if soundName == "" then
		return nil
	end

	local equippedToolSounds = self.equippedToolSounds :: { [string]: string }
	local direct = equippedToolSounds[soundName]
	if direct ~= nil then
		return direct
	end
	return equippedToolSounds[string.lower(soundName)]
end

function MeleeServiceClient.GetAndomSwingSound(self: MeleeServiceClient, swingGroupRaw: any): string?
	local swingGroup = normalizeSwingSoundGroup(swingGroupRaw)
	if swingGroup == nil then
		return nil
	end

	local equippedToolSwingSounds = self.equippedToolSwingSounds :: { [string]: { string } }
	local pool = equippedToolSwingSounds[swingGroup]
	if pool == nil or #pool <= 0 then
		return nil
	end

	local randomIndex = math.random(1, #pool)
	return pool[randomIndex]
end

function MeleeServiceClient.GetSwingSoundGroupFromContext(self: MeleeServiceClient, contextRaw: any): string?
	local context = if typeof(contextRaw) == "table" then contextRaw else {} :: any
	local equippedToolSwingSounds = self.equippedToolSwingSounds :: { [string]: { string } }

	local fromClipName = normalizeSwingSoundGroup(context.clipName)
	if fromClipName ~= nil then
		return fromClipName
	end

	local clipIndexRaw = context.clipIndex
	if typeof(clipIndexRaw) == "number" and clipIndexRaw == clipIndexRaw then
		local clipIndex = math.max(1, math.floor(clipIndexRaw))
		local directGroup = normalizeSwingSoundGroup("swing" .. tostring(clipIndex))
		if directGroup ~= nil and equippedToolSwingSounds[directGroup] ~= nil then
			return directGroup
		end
	end

	local swingIndexRaw = context.swingIndex
	if typeof(swingIndexRaw) == "number" and swingIndexRaw == swingIndexRaw then
		local swingIndex = math.max(1, math.floor(swingIndexRaw))
		local orderedGroups = GetOrderedSwingGroups(equippedToolSwingSounds)
		if #orderedGroups > 0 then
			local cycledIndex = ((swingIndex - 1) % #orderedGroups) + 1
			return orderedGroups[cycledIndex]
		end
	end

	return nil
end

function MeleeServiceClient.PlaySwingSoundFromContext(self: MeleeServiceClient, contextRaw: any): boolean
	local swingGroup = self:GetSwingSoundGroupFromContext(contextRaw)
	if swingGroup == nil then
		return false
	end

	local swingSound = self:GetAndomSwingSound(swingGroup)
	if swingSound == nil then
		return false
	end

	self:PlayToolSoundAssetId(swingSound)
	return true
end

function MeleeServiceClient.PlayToolSoundByEvent(
	self: MeleeServiceClient,
	eventNameRaw: any,
	eventTypeRaw: any,
	fallbackNamesRaw: any
): boolean
	local eventName = trim(eventNameRaw)
	local normalizedEventName = normalizeEventKey(eventName)
	local eventType = trim(eventTypeRaw)
	local normalizedEventType = normalizeEventKey(eventType)
	local fallbackNames = if typeof(fallbackNamesRaw) == "table" then fallbackNamesRaw else {} :: any

	if normalizedEventName ~= "" then
		local eventSound = self:GetToolSound(eventName)
		if eventSound ~= nil then
			self:PlayToolSoundAssetId(eventSound)
			return true
		end
		local normalizedSound = self:GetToolSound(normalizedEventName)
		if normalizedSound ~= nil then
			self:PlayToolSoundAssetId(normalizedSound)
			return true
		end
	end

	if normalizedEventType ~= "" then
		local typeSound = self:GetToolSound(eventType)
		if typeSound ~= nil then
			self:PlayToolSoundAssetId(typeSound)
			return true
		end
		local normalizedTypeSound = self:GetToolSound(normalizedEventType)
		if normalizedTypeSound ~= nil then
			self:PlayToolSoundAssetId(normalizedTypeSound)
			return true
		end
	end

	for _, fallbackName in fallbackNames do
		local fallbackSound = self:GetToolSound(fallbackName)
		if fallbackSound ~= nil then
			self:PlayToolSoundAssetId(fallbackSound)
			return true
		end
	end

	local perTypeFallbacks = TOOL_SOUND_FALLBACKS_BY_EVENT_TYPE[eventType]
	if perTypeFallbacks ~= nil then
		for _, fallbackName in perTypeFallbacks do
			local fallbackSound = self:GetToolSound(fallbackName)
			if fallbackSound ~= nil then
				self:PlayToolSoundAssetId(fallbackSound)
				return true
			end
		end
	end

	return false
end

function MeleeServiceClient.GetSelectedTool(self: MeleeServiceClient, itemIdRaw: any): Tool?
	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	return MeleeServiceUtils.GetToolByItemId(self.character, backpack, itemIdRaw)
end

function MeleeServiceClient.BindEquippedTool(self: MeleeServiceClient, toolRaw: any)
	local tool = if typeof(toolRaw) == "Instance" and toolRaw:IsA("Tool") then toolRaw else nil
	if self.equippedTool == tool then
		return
	end

	self.toolJanitor:Clean()
	self.equippedTool = tool
	self.equippedToolSounds = if tool ~= nil then MeleeServiceUtils.GetToolSounds(tool) else {} :: any
	self.equippedToolSwingSounds = if tool ~= nil then MeleeServiceUtils.GetToolSwingSounds(tool) else {} :: any

	if tool == nil then
		return
	end

	local function refreshToolBindings(refreshTrigger: string)
		self.equippedToolSounds = MeleeServiceUtils.GetToolSounds(tool)
		self.equippedToolSwingSounds = MeleeServiceUtils.GetToolSwingSounds(tool)
		self:RefreshEquippedWeapon(refreshTrigger)
	end

	self.toolJanitor:GiveChore(tool.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
		if parent == nil then
			refreshToolBindings("ToolDestroyed")
		end
	end))

	self.toolJanitor:GiveChore(tool.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Animations" or child.Name == "Sounds" then
			refreshToolBindings("ToolFolderChanged")
		end
	end))

	self.toolJanitor:GiveChore(tool.ChildRemoved:Connect(function(child: Instance)
		if child.Name == "Animations" or child.Name == "Sounds" then
			refreshToolBindings("ToolFolderChanged")
		end
	end))

	self.toolJanitor:GiveChore(tool.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("Animation") or descendant:IsA("Sound") then
			refreshToolBindings("ToolContentChanged")
		end
	end))

	self.toolJanitor:GiveChore(tool.DescendantRemoving:Connect(function(descendant: Instance)
		if descendant:IsA("Animation") or descendant:IsA("Sound") then
			refreshToolBindings("ToolContentChanged")
		end
	end))

	for _, attributeName in { "itemType", "ItemType", "itemId", "ItemId", "ittemId", "animationMode", "swingMode" } do
		self.toolJanitor:GiveChore(tool:GetAttributeChangedSignal(attributeName):Connect(function()
			refreshToolBindings("ToolAttributeChanged")
		end))
	end
end

function MeleeServiceClient.IsEquippedAxe(self: MeleeServiceClient): boolean
	return MeleeServiceUtils.GetToolItemType(self.equippedTool) == "axe"
end

function MeleeServiceClient.IsEquippedPickaxe(self: MeleeServiceClient): boolean
	return MeleeServiceUtils.GetToolItemType(self.equippedTool) == "pickaxe"
end

function MeleeServiceClient.OnMeleeAttackStarted(self: MeleeServiceClient, context: { [string]: any })
	local debugHitbox = self.debugHitbox
	if debugHitbox ~= nil then
		self:ApplyDebugHitboxPoints()
		pcall(function()
			debugHitbox:HitStart()
		end)
	end
	if self.hapticsModule ~= nil and typeof((self.hapticsModule :: any).ImpactLight) == "function" then
		local hapticsAny = self.hapticsModule :: any
		hapticsAny:ImpactLight()
	end

	if self:IsEquippedAxe() or self:IsEquippedPickaxe() then
		return
	end

	if self:PlaySwingSoundFromContext(context) then
		return
	end
	self:PlayToolSoundByEvent("AttackStarted", "AttackStarted", { "Swing", "SwingStart", "startSwing" })
end

function MeleeServiceClient.OnMeleeSwingEnded(self: MeleeServiceClient, _context: { [string]: any })
	self:StopDebugHitbox()
end

function MeleeServiceClient.OnMeleeAttackFinished(self: MeleeServiceClient, _context: { [string]: any })
	self:StopDebugHitbox()
end

function MeleeServiceClient.OnMeleeAnimationEvent(self: MeleeServiceClient, contextRaw: any)
	local context = if typeof(contextRaw) == "table" then contextRaw else {} :: any
	local eventName = context.eventName
	local eventType = context.eventType

	local equippedAxe = self:IsEquippedAxe()
	local equippedPickaxe = self:IsEquippedPickaxe()
	if isStartSwingEvent(eventName) and (equippedAxe or equippedPickaxe) then
		if not self:PlaySwingSoundFromContext(context) then
			self:PlayToolSoundByEvent(eventName, eventType, { "Swing", "SwingStart", "startSwing" })
		end
		if equippedAxe then
			(BuildServiceClient :: any):PlayHoveredTreeChopFeedback()
		else
			(BuildServiceClient :: any):PlayHoveredTileBreakFeedback()
		end
		return
	end

	self:PlayToolSoundByEvent(eventName, eventType, nil)
end

function MeleeServiceClient.OnCharacterAdded(self: MeleeServiceClient, character: Model)
	self.character = character
	self.characterJanitor:Clean()
	self.toolJanitor:Clean()
	self.equippedTool = nil
	self.equippedToolSounds = {}
	self.equippedToolSwingSounds = {}
	self:RefreshHumanoidReference()
	self:EnsureDebugHitbox()
	self.characterJanitor:GiveChore(function()
		self:DestroyDebugHitbox()
	end)

	local function bindHumanoidSignals(humanoid: Humanoid)
		self.characterJanitor:GiveChore(humanoid.Died:Connect(function()
			self:SetInputHeld(false, "HumanoidDied")
		end))
		self.characterJanitor:GiveChore(humanoid.StateChanged:Connect(function()
			if self:IsAttackBlocked() then
				self:SetInputHeld(false, "HumanoidStateChanged")
			end
		end))
		self.characterJanitor:GiveChore(humanoid.HealthChanged:Connect(function()
			if self:IsAttackBlocked() then
				self:SetInputHeld(false, "HumanoidHealthChanged")
			end
		end))
	end

	if self.humanoid ~= nil then
		bindHumanoidSignals(self.humanoid)
	end

	local function bindBackpack(backpack: Backpack)
		self.characterJanitor:GiveChore(backpack.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:RefreshEquippedWeapon("BackpackToolAdded")
			end
		end))
		self.characterJanitor:GiveChore(backpack.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:RefreshEquippedWeapon("BackpackToolRemoved")
			end
		end))
	end

	self.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("BasePart") then
			self:ApplyDebugHitboxPoints()
		end

		if child:IsA("Humanoid") then
			self:RefreshHumanoidReference()
			if child == (self.humanoid :: any) then
				bindHumanoidSignals(child)
			end
			return
		end
		if child:IsA("Tool") then
			self:RefreshEquippedWeapon("CharacterToolAdded")
		end
	end))

	self.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("BasePart") then
			self:ApplyDebugHitboxPoints()
		end

		if child == (self.humanoid :: any) then
			self.humanoid = nil
			return
		end
		if child:IsA("Tool") then
			self:RefreshEquippedWeapon("CharacterToolRemoved")
		end
	end))

	self.characterJanitor:GiveChore(self.localPlayer.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			bindBackpack(child)
			self:RefreshEquippedWeapon("BackpackAdded")
		end
	end))

	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		bindBackpack(backpack)
	end

	local activeMelee = self.activeMelee
	if activeMelee ~= nil then
		activeMelee:SetCharacter(character)
		if self.inputHeld then
			activeMelee:InputBegan("CharacterAdded")
		end
	end

	self:RefreshEquippedWeapon("CharacterAdded")
	self:ReplicateEquippedState(true)
end

function MeleeServiceClient.SetInputHeld(self: MeleeServiceClient, isHeld: boolean, trigger: string)
	if isHeld and self:IsAttackBlocked() then
		isHeld = false
	end
	if self.inputHeld == isHeld then
		return
	end

	self.inputHeld = isHeld

	local activeMelee = self.activeMelee
	if activeMelee ~= nil then
		if isHeld then
			activeMelee:InputBegan(trigger)
		else
			self:StopDebugHitbox()
			activeMelee:InputEnded(trigger)
		end
	elseif not isHeld then
		self:StopDebugHitbox()
	end

	sendPacket(MeleeServiceUtils.NETWORK_METHOD_SET_INPUT_HELD, isHeld)
	if isHeld then
		self:ReplicateEquippedState(false)
	end
end

function MeleeServiceClient.OnInventoryStateChanged(self: MeleeServiceClient, stateRaw: any)
	self.inventoryState = InventoryServiceUtils.CoerceState(stateRaw, self.inventoryState)
	self:RefreshEquippedWeapon("InventoryStateChanged")
end

function MeleeServiceClient.RefreshEquippedWeapon(self: MeleeServiceClient, triggerRaw: any)
	local itemId, slotIndex = MeleeServiceUtils.GetSelectedItemIdFromInventoryState(self.inventoryState)
	local trigger = if typeof(triggerRaw) == "string" then triggerRaw else "Refresh"
	local previousEquippedTool = self.equippedTool
	local selectedTool = if itemId ~= nil then self:GetSelectedTool(itemId) else nil

	self:BindEquippedTool(selectedTool)

	local weaponConfig = if itemId ~= nil then MeleeServiceUtils.GetWeaponConfig(itemId) else nil
	if selectedTool == nil or not MeleeServiceUtils.IsMeleeTool(selectedTool) then
		weaponConfig = nil
	elseif weaponConfig ~= nil then
		local nextWeaponConfig = shallowCopyWeaponConfig(weaponConfig)
		nextWeaponConfig.animations =
			MeleeServiceUtils.GetToolAnimationOverrides(selectedTool, weaponConfig.animations)
		weaponConfig = nextWeaponConfig
	end

	if weaponConfig == nil then
		self.equippedItemId = nil
		self.equippedSlot = nil
		self.equippedWeaponConfig = nil
		self:DestroyActiveMelee()
		self:ApplyDebugHitboxPoints()
		self:ReplicateEquippedState(false)
		return
	end

	local shouldRebuild = self.activeMelee == nil
		or self.equippedItemId ~= itemId
		or self.equippedSlot ~= slotIndex
		or previousEquippedTool ~= selectedTool
		or not isWeaponConfigEquivalent(self.equippedWeaponConfig, weaponConfig)

	self.equippedItemId = itemId
	self.equippedSlot = slotIndex
	self.equippedWeaponConfig = weaponConfig

	if shouldRebuild then
		self:DestroyActiveMelee()

		local classConfig = MeleeServiceUtils.CreateMeleeClassConfig(weaponConfig, {
			character = self.character,
			humanoid = self.humanoid,
			animator = if self.humanoid ~= nil then AnimationServiceUtils.GetAnimator(self.humanoid) else nil,
			autoRepeatWhileHeld = weaponConfig.autoRepeatWhileHeld,
			animations = weaponConfig.animations,
			callbacks = {
				onAttackStarted = function(_: any, context: { [string]: any })
					self:OnMeleeAttackStarted(context)
				end,
				onSwingEnded = function(_: any, context: { [string]: any })
					self:OnMeleeSwingEnded(context)
				end,
				onAttackFinished = function(_: any, context: { [string]: any })
					self:OnMeleeAttackFinished(context)
				end,
				onAnimationEvent = function(_: any, context: { [string]: any })
					self:OnMeleeAnimationEvent(context)
				end,
			},
		})
		if classConfig == nil then
			return
		end

		local meleeController = Melee.New(classConfig) :: any
		if self.character ~= nil then
			meleeController:SetCharacter(self.character)
		end
		self.activeMelee = meleeController :: MeleeController
	end

	self:ApplyDebugHitboxPoints()

	if self.inputHeld and self.activeMelee ~= nil and not self:IsAttackBlocked() then
		self.activeMelee:InputBegan(trigger)
	end

	self:ReplicateEquippedState(false)
end

function MeleeServiceClient.Destroy(self: MeleeServiceClient)
	self:SetInputHeld(false, "Destroy")
	self:DestroyActiveMelee()

	if self.toolJanitor ~= nil then
		self.toolJanitor:Destroy()
	end

	if self.characterJanitor ~= nil then
		self.characterJanitor:Destroy()
	end

	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end
type MeleeServiceClient = typeof(MeleeServiceClient) & {
	GetDebugHitboxAnchorPart: (self: MeleeServiceClient) -> BasePart?,
	stopDebugHitbox: (self: MeleeServiceClient) -> (),
	clearDebugHitboxPoints: (self: MeleeServiceClient) -> (),
	applyDebugHitboxPoints: (self: MeleeServiceClient) -> (),
	destroyDebugHitbox: (self: MeleeServiceClient) -> (),
	ensureDebugHitbox: (self: MeleeServiceClient) -> (),
	onMeleeSwingEnded: (self: MeleeServiceClient, context: { [string]: any }) -> (),
	onMeleeAttackFinished: (self: MeleeServiceClient, context: { [string]: any }) -> (),
	localPlayer: Player,
	janitor: JanitorClass,
	characterJanitor: JanitorClass,
	toolJanitor: JanitorClass,
	inventoryState: InventoryState,
	character: Model?,
	humanoid: Humanoid?,
	inputHeld: boolean,
	activeMelee: MeleeController?,
	equippedItemId: string?,
	equippedSlot: number?,
	equippedWeaponConfig: MeleeWeaponConfig?,
	equippedTool: Tool?,
	equippedToolSounds: any,
	equippedToolSwingSounds: any,
	replicatedItemId: string?,
	replicatedSlot: number?,
	cameraShaker: CameraShakerObject?,
	lastSwingCameraShakeAt: number,
	debugHitboxEnabled: boolean,
	debugHitbox: HitboxObject?,
	debugHitboxPointsPart: BasePart?,
	debugHitboxPoints: { Vector3 },
	bootstrapPromise: any?,
	runtimeContext: any?,
	hapticsModule: any?,
}

return MeleeServiceClient :: MeleeServiceClient
