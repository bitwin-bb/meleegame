--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Promise = require(ReplicatedStorage.Packages.Promise)
local RaycastHitbox = require(ReplicatedStorage.Packages.RaycastHitbox)
local CameraShaker = require(ReplicatedStorage.Packages.EZCameraShake)
local CameraShakeGate = require(ReplicatedStorage.Shared.Modules.Core.CameraShakeGate)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local Melee = require(ReplicatedStorage.Shared.Classes.Melee)
local AnimationServiceUtils = require(ReplicatedStorage.Shared.Services.AnimationService.AnimationServiceUtils)
local InventoryServiceClient = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceClient)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local MeleeServiceUtils = require(ReplicatedStorage.Shared.Services.MeleeService.MeleeServiceUtils)
local RagdollServiceClient = require(ReplicatedStorage.Shared.Services.RagdollService.RagdollServiceClient)
local SoundServiceClient = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceClient)

type MeleeWeaponConfig = MeleeServiceUtils.MeleeWeaponConfig
type InventoryState = InventoryServiceUtils.InventoryState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type MeleeController = {
	inputBegan: (self: MeleeController, triggerRaw: any) -> boolean,
	inputEnded: (self: MeleeController, triggerRaw: any) -> boolean,
	setCharacter: (self: MeleeController, characterRaw: any) -> (),
	on: (self: MeleeController, signalNameRaw: any, callback: (...any) -> ()) -> RBXScriptConnection?,
	destroy: (self: MeleeController) -> (),
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

local ATTACK_USER_INPUT_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

local ATTACK_KEY_CODES = {
	[Enum.KeyCode.ButtonR2] = true,
}
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
local MELEE_CAMERA_SHAKE_MAX_TRANSLATION = 0.55
local MELEE_CAMERA_SHAKE_MAX_ROTATION_RADIANS = math.rad(11)
local MELEE_CAMERA_SHAKE_DAMAGE_FOR_MAX_INTENSITY = 60

local function isAttackInput(inputObject: InputObject): boolean
	if ATTACK_USER_INPUT_TYPES[inputObject.UserInputType] then
		return true
	end
	if ATTACK_KEY_CODES[inputObject.KeyCode] then
		return true
	end
	return false
end

local function resolveHumanoidFromCharacter(character: Model?): Humanoid?
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

local function resolveRootPart(character: Model?): BasePart?
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
	local swingIndexText = string.match(normalized, "^swing([123])")
	if swingIndexText == nil then
		return nil
	end
	return "swing" .. swingIndexText
end

local function resolveToolHandlePart(toolRaw: any): BasePart?
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

local function resolveCharacterHandPart(character: Model?): BasePart?
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

local function resolveMeleeDebugHitboxEnabledFromConfigs(): boolean
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
	if not MeleeServiceUtils.areAnimationConfigsEquivalent(lhs.animations, rhs.animations) then
		return false
	end

	return true
end

function MeleeServiceClient.init(self: MeleeServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("MeleeService", self)
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.toolJanitor = Janitor.new()
	self.janitor:GiveChore(self.characterJanitor)
	self.janitor:GiveChore(self.toolJanitor)

	self.inventoryState = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
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
	self.debugHitboxEnabled = resolveMeleeDebugHitboxEnabledFromConfigs()
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

			local boundedShake = CameraShakeGate.gateShakeOffset(shakeCFrame, {
				maxTranslation = MELEE_CAMERA_SHAKE_MAX_TRANSLATION,
				maxRotationRadians = MELEE_CAMERA_SHAKE_MAX_ROTATION_RADIANS,
			})
			camera.CFrame = camera.CFrame * boundedShake
		end) :: any
		return cameraShaker :: CameraShakerObject
	end)
	if cameraShakerOk then
		self.cameraShaker = cameraShakerOrError :: CameraShakerObject
		local startOk, startError = pcall(function()
			local cameraShaker = self.cameraShaker :: CameraShakerObject
			cameraShaker:Start()
		end)
		if not startOk then
			self.cameraShaker = nil
			warn(("[MeleeServiceClient] Failed to start camera shaker: %s"):format(tostring(startError)))
		end
	else
		warn(("[MeleeServiceClient] Failed to create camera shaker: %s"):format(tostring(cameraShakerOrError)))
	end

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)

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
		self:destroyDebugHitbox()
	end)

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character: Model)
		self:onCharacterAdded(character)
	end))

	if not self:bindInputRouter() then
		self.janitor:GiveChore(UserInputService.InputBegan:Connect(function(inputObject: InputObject, gameProcessed: boolean)
			self:onInputBegan(inputObject, gameProcessed)
		end))

		self.janitor:GiveChore(UserInputService.InputEnded:Connect(function(inputObject: InputObject, gameProcessed: boolean)
			self:onInputEnded(inputObject, gameProcessed)
		end))
	end

	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: InventoryState)
			self:onInventoryStateChanged(nextState)
		end))
	end
	if RagdollServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(RagdollServiceClient.stateChanged:Connect(function()
			if self:isAttackBlocked() then
				self:setInputHeld(false, "RagdollChanged")
			end
		end))
	end

	if self.localPlayer.Character ~= nil then
		self:onCharacterAdded(self.localPlayer.Character)
	end

	self:onInventoryStateChanged(InventoryServiceClient.state)

	self.bootstrapPromise = Promise.all({
		self:waitForCharacter(),
		self:waitForInventoryLoaded(),
	})
		:andThen(function()
			self:refreshEquippedWeapon("Bootstrap")
			self:replicateEquippedState(true)
		end)
		:catch(function(err: any)
			warn(("[MeleeServiceClient] Bootstrap failed: %s"):format(tostring(err)))
		end)

	self.janitor:GiveChore(function()
		if self.bootstrapPromise ~= nil then
			self.bootstrapPromise:cancel()
			self.bootstrapPromise = nil
		end
	end)
end

function MeleeServiceClient.bindInputRouter(self: MeleeServiceClient): boolean
	local runtimeContext = CoreRuntime.getClientRuntime()
	if runtimeContext ~= nil and typeof((runtimeContext :: any).init) == "function" then
		local runtimeAny = runtimeContext :: any
		runtimeAny:init()
	end
	self.runtimeContext = runtimeContext
	if runtimeContext == nil then
		return false
	end

	local inputRouter = (runtimeContext :: any).input
	self.hapticsModule = (runtimeContext :: any).haptics
	if inputRouter == nil or typeof((inputRouter :: any).bindAction) ~= "function" then
		return false
	end

	local bound = (inputRouter :: any):bindAction(INPUT_ACTION_ATTACK, function(phase: string)
		if phase == "Began" then
			if not self:isAttackBlocked() then
				self:setInputHeld(true, "PrimaryInputBegan")
			end
		elseif phase == "Ended" then
			self:setInputHeld(false, "PrimaryInputEnded")
		end
		return false
	end, {
		layer = "Gameplay",
		consume = false,
		allowGameProcessed = false,
		allowWhileTyping = false,
		bindings = {
			{
				inputType = Enum.UserInputType.MouseButton1,
			},
			{
				inputType = Enum.UserInputType.Touch,
			},
			{
				keyCode = Enum.KeyCode.ButtonR2,
			},
		},
	})

	if bound ~= true then
		return false
	end

	self.janitor:GiveChore(function()
		if typeof((inputRouter :: any).unbindAction) == "function" then
			local inputRouterAny = inputRouter :: any
			inputRouterAny:unbindAction(INPUT_ACTION_ATTACK)
		end
	end)
	return true
end

function MeleeServiceClient.waitForCharacter(self: MeleeServiceClient)
	local character = self.localPlayer.Character
	if character ~= nil then
		return Promise.resolve(character)
	end
	return Promise.fromEvent(self.localPlayer.CharacterAdded)
end

function MeleeServiceClient.waitForInventoryLoaded(self: MeleeServiceClient)
	local state = self.inventoryState
	if InventoryServiceUtils.isLoadedState(state.loadState) then
		return Promise.resolve(state)
	end
	if InventoryServiceClient.stateChanged == nil then
		return Promise.resolve(state)
	end

	return Promise.fromEvent(InventoryServiceClient.stateChanged, function(nextState: InventoryState): boolean
		return InventoryServiceUtils.isLoadedState(nextState.loadState)
	end)
end

function MeleeServiceClient.destroyActiveMelee(self: MeleeServiceClient)
	self:stopDebugHitbox()

	local activeMelee = self.activeMelee
	self.activeMelee = nil
	if activeMelee == nil then
		return
	end

	pcall(function()
		activeMelee:destroy()
	end)
end

function MeleeServiceClient.replicateEquippedState(self: MeleeServiceClient, forceRaw: any)
	local force = forceRaw == true
	if not force then
		if self.replicatedItemId == self.equippedItemId and self.replicatedSlot == self.equippedSlot then
			return
		end
	end

	self.replicatedItemId = self.equippedItemId
	self.replicatedSlot = self.equippedSlot
	self.networker:fire(MeleeServiceUtils.NETWORK_METHOD_REFRESH_EQUIPPED)
end

function MeleeServiceClient.refreshHumanoidReference(self: MeleeServiceClient)
	self.humanoid = resolveHumanoidFromCharacter(self.character)
end

function MeleeServiceClient.resolveDebugHitboxAnchorPart(self: MeleeServiceClient): BasePart?
	local character = self.character
	local equippedTool = self.equippedTool
	if equippedTool ~= nil and character ~= nil and equippedTool:IsDescendantOf(character) then
		local toolPart = resolveToolHandlePart(equippedTool)
		if toolPart ~= nil then
			return toolPart
		end
	end

	local handPart = resolveCharacterHandPart(character)
	if handPart ~= nil then
		return handPart
	end

	return resolveRootPart(character)
end

function MeleeServiceClient.stopDebugHitbox(self: MeleeServiceClient)
	local debugHitbox = self.debugHitbox
	if debugHitbox == nil then
		return
	end

	pcall(function()
		debugHitbox:HitStop()
	end)
end

function MeleeServiceClient.clearDebugHitboxPoints(self: MeleeServiceClient)
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

function MeleeServiceClient.applyDebugHitboxPoints(self: MeleeServiceClient)
	if not self.debugHitboxEnabled then
		self:clearDebugHitboxPoints()
		return
	end

	local debugHitbox = self.debugHitbox
	local weaponConfig = self.equippedWeaponConfig
	if debugHitbox == nil or weaponConfig == nil then
		self:clearDebugHitboxPoints()
		return
	end

	local anchorPart = self:resolveDebugHitboxAnchorPart()
	if anchorPart == nil then
		self:clearDebugHitboxPoints()
		return
	end

	self:clearDebugHitboxPoints()
	local points = MeleeServiceUtils.buildHitboxPoints(weaponConfig)
	if #points <= 0 then
		return
	end

	self.debugHitboxPointsPart = anchorPart
	self.debugHitboxPoints = points
	pcall(function()
		debugHitbox:SetPoints(anchorPart, points)
	end)
end

function MeleeServiceClient.destroyDebugHitbox(self: MeleeServiceClient)
	self:stopDebugHitbox()
	self:clearDebugHitboxPoints()

	local debugHitbox = self.debugHitbox
	self.debugHitbox = nil
	if debugHitbox ~= nil then
		pcall(function()
			debugHitbox:Destroy()
		end)
	end
end

function MeleeServiceClient.ensureDebugHitbox(self: MeleeServiceClient)
	self:destroyDebugHitbox()
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

	self:applyDebugHitboxPoints()
end

function MeleeServiceClient.isAttackBlocked(self: MeleeServiceClient): boolean
	if not isHumanoidAlive(self.humanoid) then
		return true
	end

	local humanoid = self.humanoid
	if humanoid ~= nil and humanoid.PlatformStand and humanoid:GetState() == Enum.HumanoidStateType.Physics then
		return true
	end

	if RagdollServiceClient.isRagdolled ~= nil and RagdollServiceClient:isRagdolled() then
		return true
	end

	return false
end

function MeleeServiceClient.playToolSoundAssetId(self: MeleeServiceClient, soundAssetIdRaw: any)
	if SoundServiceClient.categoryGroups == nil then
		return
	end
	if typeof(soundAssetIdRaw) ~= "string" and typeof(soundAssetIdRaw) ~= "number" then
		return
	end

	local rootPart = resolveRootPart(self.character)
	SoundServiceClient:playSfx(soundAssetIdRaw, {
		parent = rootPart,
		replaceChannel = false,
		autoDestroy = true,
	})
end

function MeleeServiceClient.resolveToolSound(self: MeleeServiceClient, soundNameRaw: any): string?
	local soundName = trim(soundNameRaw)
	if soundName == "" then
		return nil
	end

	local direct = self.equippedToolSounds[soundName]
	if direct ~= nil then
		return direct
	end
	return self.equippedToolSounds[string.lower(soundName)]
end

function MeleeServiceClient.resolveRandomSwingSound(
	self: MeleeServiceClient,
	swingGroupRaw: any
): string?
	local swingGroup = normalizeSwingSoundGroup(swingGroupRaw)
	if swingGroup == nil then
		return nil
	end

	local pool = self.equippedToolSwingSounds[swingGroup]
	if pool == nil or #pool <= 0 then
		return nil
	end

	local randomIndex = math.random(1, #pool)
	return pool[randomIndex]
end

function MeleeServiceClient.resolveSwingSoundGroupFromContext(
	self: MeleeServiceClient,
	contextRaw: any
): string?
	local context = if typeof(contextRaw) == "table" then contextRaw else {}

	local fromClipName = normalizeSwingSoundGroup(context.clipName)
	if fromClipName ~= nil then
		return fromClipName
	end

	local clipIndexRaw = context.clipIndex
	if typeof(clipIndexRaw) == "number" and clipIndexRaw == clipIndexRaw then
		local clipIndex = math.max(1, math.floor(clipIndexRaw))
		local directGroup = normalizeSwingSoundGroup("swing" .. tostring(clipIndex))
		if directGroup ~= nil and self.equippedToolSwingSounds[directGroup] ~= nil then
			return directGroup
		end
	end

	local swingIndexRaw = context.swingIndex
	if typeof(swingIndexRaw) == "number" and swingIndexRaw == swingIndexRaw then
		local swingIndex = math.max(1, math.floor(swingIndexRaw))
		local cycled = ((swingIndex - 1) % 3) + 1
		return "swing" .. tostring(cycled)
	end

	return nil
end

function MeleeServiceClient.playSwingSoundFromContext(self: MeleeServiceClient, contextRaw: any): boolean
	local swingGroup = self:resolveSwingSoundGroupFromContext(contextRaw)
	if swingGroup == nil then
		return false
	end

	local swingSound = self:resolveRandomSwingSound(swingGroup)
	if swingSound == nil then
		return false
	end

	self:playToolSoundAssetId(swingSound)
	return true
end

function MeleeServiceClient.playToolSoundByEvent(
	self: MeleeServiceClient,
	eventNameRaw: any,
	eventTypeRaw: any,
	fallbackNamesRaw: any
): boolean
	local eventName = trim(eventNameRaw)
	local normalizedEventName = normalizeEventKey(eventName)
	local eventType = trim(eventTypeRaw)
	local normalizedEventType = normalizeEventKey(eventType)
	local fallbackNames = if typeof(fallbackNamesRaw) == "table" then fallbackNamesRaw else {}

	if normalizedEventName ~= "" then
		local eventSound = self:resolveToolSound(eventName)
		if eventSound ~= nil then
			self:playToolSoundAssetId(eventSound)
			return true
		end
		local normalizedSound = self:resolveToolSound(normalizedEventName)
		if normalizedSound ~= nil then
			self:playToolSoundAssetId(normalizedSound)
			return true
		end
	end

	if normalizedEventType ~= "" then
		local typeSound = self:resolveToolSound(eventType)
		if typeSound ~= nil then
			self:playToolSoundAssetId(typeSound)
			return true
		end
		local normalizedTypeSound = self:resolveToolSound(normalizedEventType)
		if normalizedTypeSound ~= nil then
			self:playToolSoundAssetId(normalizedTypeSound)
			return true
		end
	end

	for _, fallbackName in fallbackNames do
		local fallbackSound = self:resolveToolSound(fallbackName)
		if fallbackSound ~= nil then
			self:playToolSoundAssetId(fallbackSound)
			return true
		end
	end

	local perTypeFallbacks = TOOL_SOUND_FALLBACKS_BY_EVENT_TYPE[eventType]
	if perTypeFallbacks ~= nil then
		for _, fallbackName in perTypeFallbacks do
			local fallbackSound = self:resolveToolSound(fallbackName)
			if fallbackSound ~= nil then
				self:playToolSoundAssetId(fallbackSound)
				return true
			end
		end
	end

	return false
end

function MeleeServiceClient.resolveSelectedTool(self: MeleeServiceClient, itemIdRaw: any): Tool?
	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	return MeleeServiceUtils.resolveToolByItemId(self.character, backpack, itemIdRaw)
end

function MeleeServiceClient.bindEquippedTool(self: MeleeServiceClient, toolRaw: any)
	local tool = if typeof(toolRaw) == "Instance" and toolRaw:IsA("Tool") then toolRaw else nil
	if self.equippedTool == tool then
		return
	end

	self.toolJanitor:Clean()
	self.equippedTool = tool
	self.equippedToolSounds = if tool ~= nil then MeleeServiceUtils.resolveToolSounds(tool) else {}
	self.equippedToolSwingSounds = if tool ~= nil then MeleeServiceUtils.resolveToolSwingSounds(tool) else {}

	if tool == nil then
		return
	end

	local function refreshToolBindings(refreshTrigger: string)
		self.equippedToolSounds = MeleeServiceUtils.resolveToolSounds(tool)
		self.equippedToolSwingSounds = MeleeServiceUtils.resolveToolSwingSounds(tool)
		self:refreshEquippedWeapon(refreshTrigger)
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

function MeleeServiceClient.onMeleeAttackStarted(self: MeleeServiceClient, context: { [string]: any })
	local debugHitbox = self.debugHitbox
	if debugHitbox ~= nil then
		self:applyDebugHitboxPoints()
		pcall(function()
			debugHitbox:HitStart()
		end)
	end
	if self.hapticsModule ~= nil and typeof((self.hapticsModule :: any).impactLight) == "function" then
		local hapticsAny = self.hapticsModule :: any
		hapticsAny:impactLight()
	end

	if self:playSwingSoundFromContext(context) then
		return
	end
	self:playToolSoundByEvent("AttackStarted", "AttackStarted", { "Swing", "SwingStart", "startSwing" })
end

function MeleeServiceClient.onMeleeSwingEnded(self: MeleeServiceClient, _context: { [string]: any })
	self:stopDebugHitbox()
end

function MeleeServiceClient.onMeleeAttackFinished(self: MeleeServiceClient, _context: { [string]: any })
	self:stopDebugHitbox()
end

function MeleeServiceClient.onMeleeAnimationEvent(self: MeleeServiceClient, contextRaw: any)
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	local eventName = context.eventName
	local eventType = context.eventType
	self:playToolSoundByEvent(eventName, eventType, nil)
end

function MeleeServiceClient.onCharacterAdded(self: MeleeServiceClient, character: Model)
	self.character = character
	self.characterJanitor:Clean()
	self.toolJanitor:Clean()
	self.equippedTool = nil
	self.equippedToolSounds = {}
	self.equippedToolSwingSounds = {}
	self:refreshHumanoidReference()
	self:ensureDebugHitbox()
	self.characterJanitor:GiveChore(function()
		self:destroyDebugHitbox()
	end)

	local function bindHumanoidSignals(humanoid: Humanoid)
		self.characterJanitor:GiveChore(humanoid.Died:Connect(function()
			self:setInputHeld(false, "HumanoidDied")
		end))
		self.characterJanitor:GiveChore(humanoid.StateChanged:Connect(function()
			if self:isAttackBlocked() then
				self:setInputHeld(false, "HumanoidStateChanged")
			end
		end))
		self.characterJanitor:GiveChore(humanoid.HealthChanged:Connect(function()
			if self:isAttackBlocked() then
				self:setInputHeld(false, "HumanoidHealthChanged")
			end
		end))
	end

	if self.humanoid ~= nil then
		bindHumanoidSignals(self.humanoid)
	end

	local function bindBackpack(backpack: Backpack)
		self.characterJanitor:GiveChore(backpack.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:refreshEquippedWeapon("BackpackToolAdded")
			end
		end))
		self.characterJanitor:GiveChore(backpack.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:refreshEquippedWeapon("BackpackToolRemoved")
			end
		end))
	end

	self.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("BasePart") then
			self:applyDebugHitboxPoints()
		end

		if child:IsA("Humanoid") then
			self:refreshHumanoidReference()
			if child == self.humanoid then
				bindHumanoidSignals(child)
			end
			return
		end
		if child:IsA("Tool") then
			self:refreshEquippedWeapon("CharacterToolAdded")
		end
	end))

	self.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("BasePart") then
			self:applyDebugHitboxPoints()
		end

		if child == self.humanoid then
			self.humanoid = nil
			return
		end
		if child:IsA("Tool") then
			self:refreshEquippedWeapon("CharacterToolRemoved")
		end
	end))

	self.characterJanitor:GiveChore(self.localPlayer.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			bindBackpack(child)
			self:refreshEquippedWeapon("BackpackAdded")
		end
	end))

	local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		bindBackpack(backpack)
	end

	local activeMelee = self.activeMelee
	if activeMelee ~= nil then
		activeMelee:setCharacter(character)
		if self.inputHeld then
			activeMelee:inputBegan("CharacterAdded")
		end
	end

	self:refreshEquippedWeapon("CharacterAdded")
	self:replicateEquippedState(true)
end

function MeleeServiceClient.setInputHeld(self: MeleeServiceClient, isHeld: boolean, trigger: string)
	if isHeld and self:isAttackBlocked() then
		isHeld = false
	end
	if self.inputHeld == isHeld then
		return
	end

	self.inputHeld = isHeld

	local activeMelee = self.activeMelee
	if activeMelee ~= nil then
		if isHeld then
			activeMelee:inputBegan(trigger)
		else
			self:stopDebugHitbox()
			activeMelee:inputEnded(trigger)
		end
	elseif not isHeld then
		self:stopDebugHitbox()
	end

	self.networker:fire(MeleeServiceUtils.NETWORK_METHOD_SET_INPUT_HELD, isHeld)
	if isHeld then
		self:replicateEquippedState(false)
	end
end

function MeleeServiceClient.onInputBegan(self: MeleeServiceClient, inputObject: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if not isAttackInput(inputObject) then
		return
	end
	if self:isAttackBlocked() then
		return
	end

	self:setInputHeld(true, "PrimaryInputBegan")
end

function MeleeServiceClient.onInputEnded(self: MeleeServiceClient, inputObject: InputObject, _gameProcessed: boolean)
	if not isAttackInput(inputObject) then
		return
	end

	self:setInputHeld(false, "PrimaryInputEnded")
end

function MeleeServiceClient.onInventoryStateChanged(self: MeleeServiceClient, stateRaw: any)
	self.inventoryState = InventoryServiceUtils.sanitizeState(stateRaw, self.inventoryState)
	self:refreshEquippedWeapon("InventoryStateChanged")
end

function MeleeServiceClient.refreshEquippedWeapon(self: MeleeServiceClient, triggerRaw: any)
	local itemId, slotIndex = MeleeServiceUtils.resolveSelectedItemIdFromInventoryState(self.inventoryState)
	local trigger = if typeof(triggerRaw) == "string" then triggerRaw else "Refresh"
	local previousEquippedTool = self.equippedTool
	local selectedTool = if itemId ~= nil then self:resolveSelectedTool(itemId) else nil

	self:bindEquippedTool(selectedTool)

	local weaponConfig = if itemId ~= nil then MeleeServiceUtils.resolveWeaponConfig(itemId) else nil
	if selectedTool == nil or not MeleeServiceUtils.isMeleeTool(selectedTool) then
		weaponConfig = nil
	elseif weaponConfig ~= nil then
		local nextWeaponConfig = shallowCopyWeaponConfig(weaponConfig)
		nextWeaponConfig.animations = MeleeServiceUtils.resolveToolAnimationOverrides(selectedTool, weaponConfig.animations)
		weaponConfig = nextWeaponConfig
	end

	if weaponConfig == nil then
		self.equippedItemId = nil
		self.equippedSlot = nil
		self.equippedWeaponConfig = nil
		self:destroyActiveMelee()
		self:applyDebugHitboxPoints()
		self:replicateEquippedState(false)
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
		self:destroyActiveMelee()

		local classConfig = MeleeServiceUtils.createMeleeClassConfig(weaponConfig, {
			character = self.character,
			humanoid = self.humanoid,
			animator = if self.humanoid ~= nil then AnimationServiceUtils.resolveAnimator(self.humanoid) else nil,
			autoRepeatWhileHeld = weaponConfig.autoRepeatWhileHeld,
			animations = weaponConfig.animations,
			callbacks = {
				onAttackStarted = function(_: any, context: { [string]: any })
					self:onMeleeAttackStarted(context)
				end,
				onSwingEnded = function(_: any, context: { [string]: any })
					self:onMeleeSwingEnded(context)
				end,
				onAttackFinished = function(_: any, context: { [string]: any })
					self:onMeleeAttackFinished(context)
				end,
				onAnimationEvent = function(_: any, context: { [string]: any })
					self:onMeleeAnimationEvent(context)
				end,
			},
		})
		if classConfig == nil then
			return
		end

		local meleeController = Melee.new(classConfig) :: any
		if self.character ~= nil then
			meleeController:setCharacter(self.character)
		end
		self.activeMelee = meleeController :: MeleeController
	end

	self:applyDebugHitboxPoints()

	if self.inputHeld and self.activeMelee ~= nil and not self:isAttackBlocked() then
		self.activeMelee:inputBegan(trigger)
	end

	self:replicateEquippedState(false)
end

function MeleeServiceClient.destroy(self: MeleeServiceClient)
	self:setInputHeld(false, "Destroy")
	self:destroyActiveMelee()

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
	resolveDebugHitboxAnchorPart: (self: MeleeServiceClient) -> BasePart?,
	stopDebugHitbox: (self: MeleeServiceClient) -> (),
	clearDebugHitboxPoints: (self: MeleeServiceClient) -> (),
	applyDebugHitboxPoints: (self: MeleeServiceClient) -> (),
	destroyDebugHitbox: (self: MeleeServiceClient) -> (),
	ensureDebugHitbox: (self: MeleeServiceClient) -> (),
	onMeleeSwingEnded: (self: MeleeServiceClient, context: { [string]: any }) -> (),
	onMeleeAttackFinished: (self: MeleeServiceClient, context: { [string]: any }) -> (),
	localPlayer: Player,
	networker: Networker.Client,
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
	equippedToolSounds: { [string]: string },
	equippedToolSwingSounds: { [string]: { string } },
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
