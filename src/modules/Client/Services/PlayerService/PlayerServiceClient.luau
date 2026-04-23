--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Ripple = require(ReplicatedStorage.Packages.Ripple)
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local CmdrUtils = require(script:FindFirstAncestor("game").Shared.Cmdr.CmdrUtils)
local PlayerServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerService.PlayerServiceUtils)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformService.PlatformServiceClient)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioService.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioService.AudioServiceUtils)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationService.WorldGenerationServiceClient)

type FacingSign = PlayerServiceUtils.FacingSign
type CharacterRig = PlayerServiceUtils.CharacterRig
type MoveSpringOptions = PlayerServiceUtils.MoveSpringOptions
type NumberMotion = Ripple.Motion<number>

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local PlayerServiceClient = {}
local MOVE_RENDERSTEP_NAME = "PlayerService_UpdateMovement"
local GROUNDED_CONTACT_MAX_DISTANCE = 0.85
local FLOOR_CONTACT_MAX_VERTICAL_SPEED = 2.5
local HURT_FEEDBACK_MIN_INTERVAL = 0.06
local HURT_SOUND_PLAYBACK_SPEED_MIN = 0.95
local HURT_SOUND_PLAYBACK_SPEED_MAX = 1.08
local WORLD_UNLOCK_REQUIRED_SURFACE_HITS = 1
local WORLD_UNLOCK_MIN_SURFACE_NORMAL_Y = 0.5
local WORLD_UNLOCK_REQUEST_MIN_INTERVAL = 0.1
local RANDOM = Random.new()
local PLAYER_AUDIO = (AudioRegistry :: any).Player or {}
local PLAYER_HURT_AUDIO = PLAYER_AUDIO.Hurt or {}

local AIRBORNE_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local function isAirborneState(state: Enum.HumanoidStateType): boolean
	return AIRBORNE_STATES[state] == true
end

local function isGroundHitContact(hit: RaycastResult?): boolean
	return hit ~= nil and hit.Distance <= GROUNDED_CONTACT_MAX_DISTANCE
end

local function shouldRefreshRigFromCharacterChild(child: Instance): boolean
	if child:IsA("Tool") then
		return false
	end
	return true
end

function PlayerServiceClient.Init(self: PlayerServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("PlayerService", self)
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.janitor:GiveChore(self.characterJanitor)

	self.horizontalDeadzone = PlayerServiceUtils.DEFAULT_HORIZONTAL_DEADZONE
	self.moveAxisDeadzone = PlayerServiceUtils.DEFAULT_MOVE_AXIS_DEADZONE
	self.sidewaysMoveScale = PlayerServiceUtils.DEFAULT_SIDEWAYS_MOVE_SCALE
	self.accelerationExponent = PlayerServiceUtils.DEFAULT_ACCELERATION_EXPONENT
	self.moveSpring = PlayerServiceUtils.DEFAULT_MOVE_SPRING
	self.facingSign = PlayerServiceUtils.DEFAULT_FACING_SIGN
	self.moveAxisMotion = Ripple.createMotion(0)
	self.characterRig = nil
	self.lockedDepthX = nil
	self.leftFoot = nil
	self.rightFoot = nil
	self.groundRaycastParams = nil
	self.groundRaycastDistance = PlayerServiceUtils.DEFAULT_GROUND_RAYCAST_DISTANCE
	self.landingSoundCooldown = PlayerServiceUtils.DEFAULT_LANDING_SOUND_COOLDOWN
	self.landingMinImpactSpeed = PlayerServiceUtils.DEFAULT_LANDING_MIN_IMPACT_SPEED
	self.mouseFacingEnabled = true
	self.mouseFacingDeadzonePixels = PlayerServiceUtils.DEFAULT_MOUSE_FACING_DEADZONE_PIXELS
	self.mouseFacingFlipHysteresisPixels = PlayerServiceUtils.DEFAULT_MOUSE_FACING_FLIP_HYSTERESIS_PIXELS
	self.mouseFacingFlipMinInterval = PlayerServiceUtils.DEFAULT_MOUSE_FACING_FLIP_MIN_INTERVAL
	self.lastFacingFlipAt = -math.huge
	self.headLookMaxYawDegrees = PlayerServiceUtils.DEFAULT_HEAD_LOOK_MAX_YAW_DEGREES
	self.neckJoint = nil
	self.neckBaseC0 = nil
	self.headPart = nil
	self.movementLocked = false
	self.moveLeftValue = 0
	self.moveRightValue = 0
	self.moveUpValue = 0
	self.moveDownValue = 0
	self.jumpActionValue = 0
	self.flyEnabled = false
	self.flySpeed = CmdrUtils.DEFAULT_FLY_SPEED
	self.worldUnlockPending = false
	self.worldUnlockCheckAccumulator = 0
	self.worldUnlockCheckInterval = PlayerServiceUtils.DEFAULT_WORLD_UNLOCK_CHECK_INTERVAL
	self.worldUnlockRaycastDistance = PlayerServiceUtils.DEFAULT_WORLD_UNLOCK_RAYCAST_DISTANCE
	self.worldUnlockRaycastParams = nil
	self.lastWorldUnlockRequestAt = -math.huge
	self.worldUnlockConsecutiveSurfaceHits = 0
	self.wasGrounded = false
	self.maxAirborneDownwardSpeed = 0
	self.lastLandingAt = 0
	self.lastHurtFeedbackAt = 0
	self.hurtSoundAssetIds = {}

	self:refreshHurtSoundTemplates()

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.moveAxisMotion:destroy()
	end)
	self.janitor:GiveChore(function()
		RunService:UnbindFromRenderStep(MOVE_RENDERSTEP_NAME)
	end)
	self:bindPlatformInputs()

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character)
		self:onCharacterAdded(character)
	end))
	self.janitor:GiveChore(
		self.localPlayer
			:GetAttributeChangedSignal(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE)
			:Connect(function()
				local movementLockAttribute =
					self.localPlayer:GetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE)
				if typeof(movementLockAttribute) == "boolean" then
					self:applyMovementLock(movementLockAttribute)
				end
			end)
	)
	self.janitor:GiveChore(
		self.localPlayer:GetAttributeChangedSignal(CmdrUtils.FLY_ENABLED_ATTRIBUTE):Connect(function()
			self:refreshCmdrFlyState()
		end)
	)
	self.janitor:GiveChore(self.localPlayer:GetAttributeChangedSignal(CmdrUtils.FLY_SPEED_ATTRIBUTE):Connect(function()
		self:refreshCmdrFlyState()
	end))

	if self.localPlayer.Character then
		self:onCharacterAdded(self.localPlayer.Character)
	end
	local movementLockAttribute = self.localPlayer:GetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE)
	if typeof(movementLockAttribute) == "boolean" then
		self:applyMovementLock(movementLockAttribute)
	end
	self:refreshCmdrFlyState()

	self.networker:fire("requestState")
end

function PlayerServiceClient.ResetMovementInputState(self: PlayerServiceClient)
	self.moveLeftValue = 0
	self.moveRightValue = 0
	self.moveUpValue = 0
	self.moveDownValue = 0
	self.jumpActionValue = 0
end

function PlayerServiceClient.SetMovementActionValue(self: PlayerServiceClient, actionNameRaw: any, valueRaw: any)
	local actionName = if typeof(actionNameRaw) == "string" then actionNameRaw else ""
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then math.clamp(valueRaw, 0, 1) else 0
	local actions = PlatformServiceClient.ACTIONS

	if actionName == actions.MOVE_LEFT then
		self.moveLeftValue = value
	elseif actionName == actions.MOVE_RIGHT then
		self.moveRightValue = value
	elseif actionName == actions.MOVE_UP then
		self.moveUpValue = value
	elseif actionName == actions.MOVE_DOWN then
		self.moveDownValue = value
	end
end

function PlayerServiceClient.GetHorizontalMoveAxis(self: PlayerServiceClient): number
	return math.clamp(self.moveRightValue - self.moveLeftValue, -1, 1)
end

function PlayerServiceClient.GetVerticalMoveAxis(self: PlayerServiceClient): number
	return math.clamp(math.max(self.moveUpValue, self.jumpActionValue) - self.moveDownValue, -1, 1)
end

function PlayerServiceClient.RefreshPlatformInputMode(self: PlayerServiceClient)
	local shouldUseMouseFacing = true
	if PlatformServiceClient:isReady() then
		shouldUseMouseFacing = PlatformServiceClient:isKeyboardMouse()
	end
	self:setMouseFacingEnabled(shouldUseMouseFacing)
end

function PlayerServiceClient.BindPlatformInputs(self: PlayerServiceClient)
	if not PlatformServiceClient:isReady() then
		PlatformServiceClient:init()
	end

	local function bindMovementAction(actionName: string)
		local disconnect = PlatformServiceClient:bindAction(actionName, function(_phase: string, context: any)
			self:setMovementActionValue(actionName, context.value)
			return false
		end)
		if disconnect ~= nil then
			self.janitor:GiveChore(disconnect)
		end
	end

	local actions = PlatformServiceClient.ACTIONS
	bindMovementAction(actions.MOVE_LEFT)
	bindMovementAction(actions.MOVE_RIGHT)
	bindMovementAction(actions.MOVE_UP)
	bindMovementAction(actions.MOVE_DOWN)
	local jumpDisconnect = PlatformServiceClient:bindAction(actions.JUMP, function(phase: string, context: any)
		self:onJumpAction(phase, context)
		return false
	end)
	if jumpDisconnect ~= nil then
		self.janitor:GiveChore(jumpDisconnect)
	end

	self:resetMovementInputState()
	self:refreshPlatformInputMode()
	self.janitor:GiveChore(PlatformServiceClient:onPlatformChanged(function()
		self:resetMovementInputState()
		self:refreshPlatformInputMode()
	end))
end

function PlayerServiceClient.RefreshHurtSoundTemplates(self: PlayerServiceClient)
	self.hurtSoundAssetIds = AudioServiceUtils.collectSoundAssetIds(PLAYER_HURT_AUDIO)
end

function PlayerServiceClient.PickHurtSoundAssetId(self: PlayerServiceClient): string?
	if #self.hurtSoundAssetIds == 0 then
		self:refreshHurtSoundTemplates()
	end
	local count = #self.hurtSoundAssetIds
	if count <= 0 then
		return nil
	end

	return self.hurtSoundAssetIds[RANDOM:NextInteger(1, count)]
end

function PlayerServiceClient.PlayHurtFeedback(self: PlayerServiceClient)
	local now = os.clock()
	if now - self.lastHurtFeedbackAt < HURT_FEEDBACK_MIN_INTERVAL then
		return
	end
	self.lastHurtFeedbackAt = now

	local hurtSoundAssetId = self:pickHurtSoundAssetId()
	if hurtSoundAssetId then
		local soundParent = if self.characterRig and self.characterRig.rootPart then self.characterRig.rootPart else nil
		AudioServiceClient:playSfx(hurtSoundAssetId, {
			parent = soundParent,
			playbackSpeed = RANDOM:NextNumber(HURT_SOUND_PLAYBACK_SPEED_MIN, HURT_SOUND_PLAYBACK_SPEED_MAX),
		})
	end
end

function PlayerServiceClient.OnDamaged(self: PlayerServiceClient, damageAmountRaw: any)
	local amount = if typeof(damageAmountRaw) == "number" and damageAmountRaw == damageAmountRaw
		then math.max(0, damageAmountRaw)
		else 0
	if amount <= 0 then
		return
	end
	local rig = self.characterRig
	if rig == nil then
		return
	end
	if not PlayerServiceUtils.isHumanoidAlive(rig.humanoid) then
		return
	end

	self:playHurtFeedback()
end

function PlayerServiceClient.EmitBloodEffect(_self: PlayerServiceClient, _characterRaw: any, _originPartRaw: any)
	return
end

function PlayerServiceClient.ResolveCurrentRig(self: PlayerServiceClient, character: Model)
	local rig = PlayerServiceUtils.resolveCharacterRig(character)
	if not rig then
		PlayerServiceUtils.resetNeckLook(self.neckJoint, self.neckBaseC0)
		self.characterRig = nil
		self.lockedDepthX = nil
		self.leftFoot = nil
		self.rightFoot = nil
		self.groundRaycastParams = nil
		self.neckJoint = nil
		self.neckBaseC0 = nil
		self.headPart = nil
		self.worldUnlockRaycastParams = nil
		self.wasGrounded = false
		self.maxAirborneDownwardSpeed = 0
		return
	end

	self.characterRig = rig
	self.lockedDepthX = rig.rootPart.Position.X
	self.moveAxisMotion:immediate(0)
	self.leftFoot, self.rightFoot = PlayerServiceUtils.resolveFootParts(rig.character)
	self.groundRaycastParams = PlayerServiceUtils.createGroundRaycastParams(rig.character)
	local nextNeckJoint = PlayerServiceUtils.resolveNeckJoint(rig.character)
	if self.neckJoint ~= nextNeckJoint then
		PlayerServiceUtils.resetNeckLook(self.neckJoint, self.neckBaseC0)
		self.neckJoint = nextNeckJoint
		self.neckBaseC0 = if nextNeckJoint then nextNeckJoint.C0 else nil
	elseif nextNeckJoint ~= nil and self.neckBaseC0 == nil then
		self.neckBaseC0 = nextNeckJoint.C0
	end
	self.headPart = PlayerServiceUtils.resolveHeadPart(rig.character)
	self.maxAirborneDownwardSpeed = 0
	local groundHit = PlayerServiceUtils.sampleGroundFromFeet(
		self.leftFoot,
		self.rightFoot,
		rig.rootPart,
		self.groundRaycastParams,
		self.groundRaycastDistance
	)
	local verticalSpeed = rig.rootPart.AssemblyLinearVelocity.Y
	local hasGroundMaterial = rig.humanoid.FloorMaterial ~= Enum.Material.Air
	local groundedByFloorMaterial = hasGroundMaterial and math.abs(verticalSpeed) <= FLOOR_CONTACT_MAX_VERTICAL_SPEED
	self.wasGrounded = not isAirborneState(rig.humanoid:GetState())
		and (isGroundHitContact(groundHit) or groundedByFloorMaterial)
	self.lastLandingAt = os.clock()
	PlayerServiceUtils.applyCharacterSettings(rig.humanoid)
	PlayerServiceUtils.snapRootPartFacing(rig.rootPart, self.facingSign)
	self.worldUnlockRaycastParams = PlayerServiceUtils.createWorldUnlockRaycastParams(rig.character)
end

function PlayerServiceClient.ApplyMovementLock(self: PlayerServiceClient, movementLockedRaw: any)
	local movementLocked = if typeof(movementLockedRaw) == "boolean" then movementLockedRaw else self.movementLocked
	self.movementLocked = movementLocked
	if movementLocked then
		self:resetMovementInputState()
		self.worldUnlockPending = true
		self.worldUnlockCheckAccumulator = self.worldUnlockCheckInterval
		self.worldUnlockConsecutiveSurfaceHits = 0
		self.moveAxisMotion:immediate(0)
	else
		self.worldUnlockPending = false
		self.worldUnlockConsecutiveSurfaceHits = 0
	end
end

function PlayerServiceClient.RefreshCmdrFlyState(self: PlayerServiceClient)
	local wasFlying = self.flyEnabled
	self.flyEnabled = self.localPlayer:GetAttribute(CmdrUtils.FLY_ENABLED_ATTRIBUTE) == true
	self.flySpeed =
		CmdrUtils.sanitizeFlySpeed(self.localPlayer:GetAttribute(CmdrUtils.FLY_SPEED_ATTRIBUTE), self.flySpeed)

	if wasFlying and not self.flyEnabled and self.characterRig ~= nil then
		self.characterRig.rootPart.AssemblyLinearVelocity = Vector3.zero
		self.characterRig.rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function PlayerServiceClient.CanUnlockFromWorldSurface(self: PlayerServiceClient, rig: CharacterRig): boolean
	local raycastParams = self.worldUnlockRaycastParams
	if raycastParams == nil then
		raycastParams = PlayerServiceUtils.createWorldUnlockRaycastParams(rig.character)
		self.worldUnlockRaycastParams = raycastParams
	end

	local hit = PlayerServiceUtils.sampleGroundFromFeet(
		self.leftFoot,
		self.rightFoot,
		rig.rootPart,
		raycastParams,
		math.max(self.groundRaycastDistance, self.worldUnlockRaycastDistance)
	)
	if hit == nil then
		return false
	end

	local hitPart = hit.Instance
	if not hitPart:IsA("BasePart") then
		return false
	end
	if hit.Normal.Y < WORLD_UNLOCK_MIN_SURFACE_NORMAL_Y then
		return false
	end

	return PlayerServiceUtils.isSurfaceTerrainPart(hitPart)
end

function PlayerServiceClient.TryResolveWorldUnlock(self: PlayerServiceClient, rig: CharacterRig, deltaTime: number)
	if not self.movementLocked or not self.worldUnlockPending then
		return
	end

	self.worldUnlockCheckAccumulator += deltaTime
	if self.worldUnlockCheckAccumulator < self.worldUnlockCheckInterval then
		return
	end
	self.worldUnlockCheckAccumulator = 0

	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return
	end
	local worldState = WorldGenerationServiceClient:getState()
	if not worldState.ready then
		return
	end
	if not self:canUnlockFromWorldSurface(rig) then
		self.worldUnlockConsecutiveSurfaceHits = 0
		return
	end
	self.worldUnlockConsecutiveSurfaceHits += 1
	if self.worldUnlockConsecutiveSurfaceHits < WORLD_UNLOCK_REQUIRED_SURFACE_HITS then
		return
	end

	local now = os.clock()
	if now - self.lastWorldUnlockRequestAt < WORLD_UNLOCK_REQUEST_MIN_INTERVAL then
		return
	end
	self.lastWorldUnlockRequestAt = now
	self.networker:fire(PlayerServiceUtils.NETWORK_METHOD_SET_WORLD_READY_FOR_MOVEMENT, true)
end

function PlayerServiceClient.RequestJump(self: PlayerServiceClient): boolean
	local rig = self.characterRig
	if rig == nil then
		return false
	end
	if self.flyEnabled or self.movementLocked then
		return false
	end
	if not PlayerServiceUtils.isHumanoidAlive(rig.humanoid) then
		return false
	end

	rig.humanoid.Jump = true
	return true
end

function PlayerServiceClient.ApplyJumpInput(self: PlayerServiceClient, rig: CharacterRig): boolean
	local shouldJump = self.jumpActionValue > 0
		and not self.flyEnabled
		and not self.movementLocked
		and PlayerServiceUtils.isHumanoidAlive(rig.humanoid)

	rig.humanoid.Jump = shouldJump
	return shouldJump
end

function PlayerServiceClient.OnJumpAction(self: PlayerServiceClient, phaseRaw: any, contextRaw: any)
	local phase = if phaseRaw == "Changed" or phaseRaw == "Ended" then phaseRaw else "Began"
	local value = if typeof(contextRaw) == "table"
			and typeof((contextRaw :: any).value) == "number"
			and (contextRaw :: any).value == (contextRaw :: any).value
		then math.clamp((contextRaw :: any).value, 0, 1)
		else if phase == "Ended" then 0 else 1

	self.jumpActionValue = value
	if self.flyEnabled then
		return
	end
	if phase ~= "Began" or value <= 0 then
		return
	end

	self:requestJump()
end

function PlayerServiceClient.OnCharacterAdded(self: PlayerServiceClient, character: Model)
	self.characterJanitor:Clean()
	PlayerServiceUtils.resetNeckLook(self.neckJoint, self.neckBaseC0)
	self.characterRig = nil
	self.leftFoot = nil
	self.rightFoot = nil
	self.groundRaycastParams = nil
	self.neckJoint = nil
	self.neckBaseC0 = nil
	self.headPart = nil
	self.worldUnlockRaycastParams = nil
	self.lastFacingFlipAt = -math.huge
	self.wasGrounded = false
	self.maxAirborneDownwardSpeed = 0
	self.lastHurtFeedbackAt = 0
	self:resetMovementInputState()

	RunService:UnbindFromRenderStep(MOVE_RENDERSTEP_NAME)

	self:resolveCurrentRig(character)
	self:applyMovementLock(true)
	local movementLockAttribute = self.localPlayer:GetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE)
	if typeof(movementLockAttribute) == "boolean" then
		self:applyMovementLock(movementLockAttribute)
	end

	self.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if shouldRefreshRigFromCharacterChild(child) then
			self:resolveCurrentRig(character)
		end
	end))

	self.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if shouldRefreshRigFromCharacterChild(child) then
			self:resolveCurrentRig(character)
		end
	end))

	RunService:BindToRenderStep(MOVE_RENDERSTEP_NAME, Enum.RenderPriority.Input.Value + 10, function(deltaTime)
		self:updateFacingFromMovement(deltaTime)
	end)
	self.characterJanitor:GiveChore(function()
		RunService:UnbindFromRenderStep(MOVE_RENDERSTEP_NAME)
	end)
end

function PlayerServiceClient.GetMouseFacing(self: PlayerServiceClient, rig: CharacterRig): FacingSign?
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		return nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local facingViewportPosition, isFacingPointOnScreen = currentCamera:WorldToViewportPoint(rig.rootPart.Position)
	if not isFacingPointOnScreen then
		return nil
	end

	return PlayerServiceUtils.getFacingFromScreenX(
		mouseLocation.X,
		facingViewportPosition.X,
		self.mouseFacingDeadzonePixels
	)
end

function PlayerServiceClient.GetMouseLookState(self: PlayerServiceClient, rig: CharacterRig): (FacingSign?, number?)
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		return nil, nil
	end

	local lookOriginPart = if self.headPart and self.headPart.Parent ~= nil then self.headPart else rig.rootPart
	local lookOriginViewportPosition, isLookOriginOnScreen = currentCamera:WorldToViewportPoint(lookOriginPart.Position)
	if not isLookOriginOnScreen then
		return nil, nil
	end
	local rootViewportPosition, isRootOnScreen = currentCamera:WorldToViewportPoint(rig.rootPart.Position)
	if not isRootOnScreen then
		return nil, nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local screenLookAngleRadians = PlayerServiceUtils.getScreenLookAngleRadians(
		mouseLocation.X,
		mouseLocation.Y,
		lookOriginViewportPosition.X,
		lookOriginViewportPosition.Y
	)
	if screenLookAngleRadians == nil then
		return nil, 0
	end

	local relativeLookAngleRadians =
		PlayerServiceUtils.getRelativeLookAngleRadians(screenLookAngleRadians, self.facingSign)
	local desiredFacing = PlayerServiceUtils.getFacingFlipFromScreenX(
		mouseLocation.X,
		rootViewportPosition.X,
		self.facingSign,
		self.mouseFacingFlipHysteresisPixels
	)
	if desiredFacing ~= nil then
		relativeLookAngleRadians = PlayerServiceUtils.getRelativeLookAngleRadians(screenLookAngleRadians, desiredFacing)
	end

	return desiredFacing, PlayerServiceUtils.clampLookAngleRadians(relativeLookAngleRadians, self.headLookMaxYawDegrees)
end

function PlayerServiceClient.ApplyHeadLook(self: PlayerServiceClient, lookAngleRadians: number?)
	if lookAngleRadians == nil then
		PlayerServiceUtils.resetNeckLook(self.neckJoint, self.neckBaseC0)
		return
	end

	PlayerServiceUtils.applyNeckLookAngle(self.neckJoint, self.neckBaseC0, lookAngleRadians, self.headLookMaxYawDegrees)
end

function PlayerServiceClient.UpdateFlyingMovement(self: PlayerServiceClient, rig: CharacterRig)
	if not PlayerServiceUtils.isHumanoidAlive(rig.humanoid) then
		self:applyHeadLook(nil)
		return
	end

	local mouseFacing: FacingSign? = nil
	local lookAngleRadians: number? = nil
	if self.mouseFacingEnabled then
		mouseFacing, lookAngleRadians = self:getMouseLookState(rig)
	end

	local horizontalAxis = self:getHorizontalMoveAxis()
	local verticalAxis = self:getVerticalMoveAxis()

	local desiredFacing = mouseFacing
	if desiredFacing == nil and horizontalAxis ~= 0 then
		desiredFacing = PlayerServiceUtils.sanitizeFacingSign(horizontalAxis, self.facingSign)
	end

	local now = os.clock()
	local didUpdateFacing = false
	local canFlipFacing = (now - self.lastFacingFlipAt) >= self.mouseFacingFlipMinInterval
	if desiredFacing ~= nil and desiredFacing ~= self.facingSign then
		if (not self.mouseFacingEnabled) or canFlipFacing then
			self:setFacing(desiredFacing, true)
			self.lastFacingFlipAt = now
			didUpdateFacing = true
		end
	end

	if self.mouseFacingEnabled and didUpdateFacing then
		local _, refreshedLookAngleRadians = self:getMouseLookState(rig)
		lookAngleRadians = refreshedLookAngleRadians
	end

	self:applyHeadLook(if self.mouseFacingEnabled then lookAngleRadians else nil)
	rig.humanoid.Jump = false

	rig.humanoid:Move(Vector3.zero, false)
	if rig.humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
		rig.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	local flySpeed = CmdrUtils.sanitizeFlySpeed(self.flySpeed, CmdrUtils.DEFAULT_FLY_SPEED)
	rig.rootPart.AssemblyLinearVelocity = Vector3.new(0, verticalAxis * flySpeed, -horizontalAxis * flySpeed)
	rig.rootPart.AssemblyAngularVelocity = Vector3.zero
	PlayerServiceUtils.applySidewaysConstraint(rig.rootPart, self.lockedDepthX)
	PlayerServiceUtils.ensureRootPartUpright(
		rig.rootPart,
		self.facingSign,
		PlayerServiceUtils.DEFAULT_ROOT_UPRIGHT_TOLERANCE_DEGREES
	)

	self.worldUnlockPending = false
	self.worldUnlockConsecutiveSurfaceHits = 0
	self.wasGrounded = false
	self.maxAirborneDownwardSpeed = 0
	self.lastLandingAt = now
end

function PlayerServiceClient.UpdateFacingFromMovement(self: PlayerServiceClient, deltaTime: number)
	local rig = self.characterRig
	if not rig then
		return
	end
	if rig.rootPart.Parent == nil or rig.humanoid.Parent == nil then
		self:resolveCurrentRig(rig.character)
		return
	end

	if self.flyEnabled then
		self:updateFlyingMovement(rig)
		return
	end

	if self.movementLocked then
		self.moveAxisMotion:immediate(0)
		rig.humanoid.Jump = false
		rig.humanoid:Move(Vector3.zero, false)
		rig.rootPart.AssemblyLinearVelocity = Vector3.zero
		rig.rootPart.AssemblyAngularVelocity = Vector3.zero
		if
			PlayerServiceUtils.isHumanoidAlive(rig.humanoid)
			and rig.humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
		then
			rig.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		PlayerServiceUtils.applySidewaysConstraint(rig.rootPart, self.lockedDepthX)
		self:applyHeadLook(nil)
		self:tryResolveWorldUnlock(rig, deltaTime)
		return
	end

	local mouseFacing: FacingSign? = nil
	local lookAngleRadians: number? = nil
	if self.mouseFacingEnabled then
		mouseFacing, lookAngleRadians = self:getMouseLookState(rig)
	end

	local rawAxis = self:getHorizontalMoveAxis()
	self.moveAxisMotion:spring(rawAxis, self.moveSpring)

	local smoothedAxis = self.moveAxisMotion:step(deltaTime)
	local curvedAxis = PlayerServiceUtils.applyAccelerationCurve(smoothedAxis, self.accelerationExponent)
	if math.abs(curvedAxis) <= self.moveAxisDeadzone then
		curvedAxis = 0
	end

	self:applyJumpInput(rig)
	rig.humanoid:Move(PlayerServiceUtils.getSidewaysMoveVector(curvedAxis, self.sidewaysMoveScale), false)
	PlayerServiceUtils.applySidewaysConstraint(rig.rootPart, self.lockedDepthX)
	PlayerServiceUtils.ensureRootPartUpright(
		rig.rootPart,
		self.facingSign,
		PlayerServiceUtils.DEFAULT_ROOT_UPRIGHT_TOLERANCE_DEGREES
	)

	local shouldUseKeyboardFacing = (not self.mouseFacingEnabled) or lookAngleRadians == nil
	local desiredFacing = mouseFacing
	if desiredFacing == nil and rawAxis ~= 0 and shouldUseKeyboardFacing then
		desiredFacing = PlayerServiceUtils.sanitizeFacingSign(rawAxis, self.facingSign)
	end
	local didUpdateFacing = false
	local now = os.clock()
	local canFlipFacing = (now - self.lastFacingFlipAt) >= self.mouseFacingFlipMinInterval
	if desiredFacing ~= nil and desiredFacing ~= self.facingSign then
		if (not self.mouseFacingEnabled) or canFlipFacing then
			self:setFacing(desiredFacing, true)
			self.lastFacingFlipAt = now
			didUpdateFacing = true
		end
	end
	if self.mouseFacingEnabled and didUpdateFacing then
		local _, refreshedLookAngleRadians = self:getMouseLookState(rig)
		lookAngleRadians = refreshedLookAngleRadians
	end

	self:applyHeadLook(if self.mouseFacingEnabled then lookAngleRadians else nil)
	self:updateGroundedState(rig, os.clock())
end

function PlayerServiceClient.UpdateGroundedState(self: PlayerServiceClient, rig: CharacterRig, now: number)
	local groundHit = PlayerServiceUtils.sampleGroundFromFeet(
		self.leftFoot,
		self.rightFoot,
		rig.rootPart,
		self.groundRaycastParams,
		self.groundRaycastDistance
	)
	local humanoid = rig.humanoid
	local humanoidState = humanoid:GetState()
	local hasGroundMaterial = humanoid.FloorMaterial ~= Enum.Material.Air
	local verticalSpeed = rig.rootPart.AssemblyLinearVelocity.Y
	local groundedByRay = isGroundHitContact(groundHit)
	local groundedByFloorMaterial = hasGroundMaterial and math.abs(verticalSpeed) <= FLOOR_CONTACT_MAX_VERTICAL_SPEED
	local isGrounded = not isAirborneState(humanoidState) and (groundedByRay or groundedByFloorMaterial)
	local downwardSpeed = math.max(0, -rig.rootPart.AssemblyLinearVelocity.Y)

	if isGrounded then
		if not self.wasGrounded then
			local landingMaterial = if groundedByRay and groundHit ~= nil
				then groundHit.Material
				else humanoid.FloorMaterial
			local impactSpeed = math.max(self.maxAirborneDownwardSpeed, downwardSpeed)
			if landingMaterial ~= Enum.Material.Air then
				self:tryPlayLandingSound(rig, landingMaterial, impactSpeed, now)
			end
		end
		self.maxAirborneDownwardSpeed = 0
	else
		self.maxAirborneDownwardSpeed = math.max(self.maxAirborneDownwardSpeed, downwardSpeed)
	end

	self.wasGrounded = isGrounded
end

function PlayerServiceClient.TryPlayLandingSound(
	self: PlayerServiceClient,
	rig: CharacterRig,
	material: Enum.Material,
	impactSpeed: number,
	now: number
)
	if impactSpeed < self.landingMinImpactSpeed then
		return
	end
	if now - self.lastLandingAt < self.landingSoundCooldown then
		return
	end
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	local soundAssetId, soundOptions =
		PlayerServiceUtils.resolveLandingSoundAssetIdAndOptions(rig.rootPart, material, impactSpeed)
	if soundAssetId == nil or soundOptions == nil then
		return
	end

	local playedSound = AudioServiceClient:playSfx(soundAssetId, soundOptions)
	if playedSound then
		self.lastLandingAt = now
	end
end

function PlayerServiceClient.SetFacing(self: PlayerServiceClient, facingSignRaw: any, replicateToServer: boolean?)
	local nextFacing = PlayerServiceUtils.sanitizeFacingSign(facingSignRaw, self.facingSign)
	if nextFacing == self.facingSign then
		return
	end

	self.facingSign = nextFacing

	local rig = self.characterRig
	if rig then
		PlayerServiceUtils.applyCharacterSettings(rig.humanoid)
		PlayerServiceUtils.snapRootPartFacing(rig.rootPart, self.facingSign)
	end

	if replicateToServer then
		self.networker:fire("setFacing", self.facingSign)
	end
end

function PlayerServiceClient.ApplyFacing(self: PlayerServiceClient, facingSignRaw: any)
	self:setFacing(facingSignRaw, false)
end

function PlayerServiceClient.SetMouseFacingEnabled(self: PlayerServiceClient, enabled: boolean)
	if self.mouseFacingEnabled == enabled then
		return
	end

	self.mouseFacingEnabled = enabled
	if not enabled then
		self:applyHeadLook(nil)
	end
end

function PlayerServiceClient.EnableMouseFacing(self: PlayerServiceClient)
	self:setMouseFacingEnabled(true)
end

function PlayerServiceClient.DisableMouseFacing(self: PlayerServiceClient)
	self:setMouseFacingEnabled(false)
end

function PlayerServiceClient.IsMouseFacingEnabled(self: PlayerServiceClient): boolean
	return self.mouseFacingEnabled
end

function PlayerServiceClient.Destroy(self: PlayerServiceClient)
	PlayerServiceUtils.resetNeckLook(self.neckJoint, self.neckBaseC0)

	if self.characterJanitor then
		self.characterJanitor:Destroy()
	end

	if self.janitor then
		self.janitor:Destroy()
	end
end

PlayerServiceClient.init = PlayerServiceClient.Init
PlayerServiceClient.refreshHurtSoundTemplates = PlayerServiceClient.RefreshHurtSoundTemplates
PlayerServiceClient.pickHurtSoundAssetId = PlayerServiceClient.PickHurtSoundAssetId
PlayerServiceClient.playHurtFeedback = PlayerServiceClient.PlayHurtFeedback
PlayerServiceClient.onDamaged = PlayerServiceClient.OnDamaged
PlayerServiceClient.emitBloodEffect = PlayerServiceClient.EmitBloodEffect
PlayerServiceClient.resolveCurrentRig = PlayerServiceClient.ResolveCurrentRig
PlayerServiceClient.resetMovementInputState = PlayerServiceClient.ResetMovementInputState
PlayerServiceClient.setMovementActionValue = PlayerServiceClient.SetMovementActionValue
PlayerServiceClient.getHorizontalMoveAxis = PlayerServiceClient.GetHorizontalMoveAxis
PlayerServiceClient.getVerticalMoveAxis = PlayerServiceClient.GetVerticalMoveAxis
PlayerServiceClient.refreshPlatformInputMode = PlayerServiceClient.RefreshPlatformInputMode
PlayerServiceClient.bindPlatformInputs = PlayerServiceClient.BindPlatformInputs
PlayerServiceClient.applyMovementLock = PlayerServiceClient.ApplyMovementLock
PlayerServiceClient.refreshCmdrFlyState = PlayerServiceClient.RefreshCmdrFlyState
PlayerServiceClient.canUnlockFromWorldSurface = PlayerServiceClient.CanUnlockFromWorldSurface
PlayerServiceClient.tryResolveWorldUnlock = PlayerServiceClient.TryResolveWorldUnlock
PlayerServiceClient.requestJump = PlayerServiceClient.RequestJump
PlayerServiceClient.applyJumpInput = PlayerServiceClient.ApplyJumpInput
PlayerServiceClient.onJumpAction = PlayerServiceClient.OnJumpAction
PlayerServiceClient.onCharacterAdded = PlayerServiceClient.OnCharacterAdded
PlayerServiceClient.getMouseFacing = PlayerServiceClient.GetMouseFacing
PlayerServiceClient.getMouseLookState = PlayerServiceClient.GetMouseLookState
PlayerServiceClient.applyHeadLook = PlayerServiceClient.ApplyHeadLook
PlayerServiceClient.updateFlyingMovement = PlayerServiceClient.UpdateFlyingMovement
PlayerServiceClient.updateFacingFromMovement = PlayerServiceClient.UpdateFacingFromMovement
PlayerServiceClient.updateGroundedState = PlayerServiceClient.UpdateGroundedState
PlayerServiceClient.tryPlayLandingSound = PlayerServiceClient.TryPlayLandingSound
PlayerServiceClient.setFacing = PlayerServiceClient.SetFacing
PlayerServiceClient.applyFacing = PlayerServiceClient.ApplyFacing
PlayerServiceClient.setMouseFacingEnabled = PlayerServiceClient.SetMouseFacingEnabled
PlayerServiceClient.enableMouseFacing = PlayerServiceClient.EnableMouseFacing
PlayerServiceClient.disableMouseFacing = PlayerServiceClient.DisableMouseFacing
PlayerServiceClient.isMouseFacingEnabled = PlayerServiceClient.IsMouseFacingEnabled
PlayerServiceClient.destroy = PlayerServiceClient.Destroy

type PlayerServiceClient = typeof(PlayerServiceClient) & {
	refreshHurtSoundTemplates: (self: PlayerServiceClient) -> (),
	pickHurtSoundAssetId: (self: PlayerServiceClient) -> string?,
	playHurtFeedback: (self: PlayerServiceClient) -> (),
	onDamaged: (self: PlayerServiceClient, damageAmountRaw: any) -> (),
	emitBloodEffect: (self: PlayerServiceClient, characterRaw: any, originPartRaw: any) -> (),
	resetMovementInputState: (self: PlayerServiceClient) -> (),
	setMovementActionValue: (self: PlayerServiceClient, actionNameRaw: any, valueRaw: any) -> (),
	getHorizontalMoveAxis: (self: PlayerServiceClient) -> number,
	getVerticalMoveAxis: (self: PlayerServiceClient) -> number,
	refreshPlatformInputMode: (self: PlayerServiceClient) -> (),
	bindPlatformInputs: (self: PlayerServiceClient) -> (),
	requestJump: (self: PlayerServiceClient) -> boolean,
	applyJumpInput: (self: PlayerServiceClient, rig: CharacterRig) -> boolean,
	onJumpAction: (self: PlayerServiceClient, phaseRaw: any, contextRaw: any) -> (),
	getMouseFacing: (self: PlayerServiceClient, rig: CharacterRig) -> FacingSign?,
	getMouseLookState: (self: PlayerServiceClient, rig: CharacterRig) -> (FacingSign?, number?),
	applyHeadLook: (self: PlayerServiceClient, lookAngleRadians: number?) -> (),
	applyMovementLock: (self: PlayerServiceClient, movementLockedRaw: any) -> (),
	canUnlockFromWorldSurface: (self: PlayerServiceClient, rig: CharacterRig) -> boolean,
	tryResolveWorldUnlock: (self: PlayerServiceClient, rig: CharacterRig, deltaTime: number) -> (),
	setMouseFacingEnabled: (self: PlayerServiceClient, enabled: boolean) -> (),
	enableMouseFacing: (self: PlayerServiceClient) -> (),
	disableMouseFacing: (self: PlayerServiceClient) -> (),
	isMouseFacingEnabled: (self: PlayerServiceClient) -> boolean,
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	characterJanitor: JanitorClass,
	horizontalDeadzone: number,
	moveAxisDeadzone: number,
	sidewaysMoveScale: number,
	accelerationExponent: number,
	moveSpring: MoveSpringOptions,
	facingSign: FacingSign,
	moveAxisMotion: NumberMotion,
	characterRig: CharacterRig?,
	lockedDepthX: number?,
	leftFoot: BasePart?,
	rightFoot: BasePart?,
	groundRaycastParams: RaycastParams?,
	groundRaycastDistance: number,
	landingSoundCooldown: number,
	landingMinImpactSpeed: number,
	mouseFacingEnabled: boolean,
	mouseFacingDeadzonePixels: number,
	mouseFacingFlipHysteresisPixels: number,
	mouseFacingFlipMinInterval: number,
	lastFacingFlipAt: number,
	headLookMaxYawDegrees: number,
	neckJoint: Motor6D?,
	neckBaseC0: CFrame?,
	headPart: BasePart?,
	movementLocked: boolean,
	moveLeftValue: number,
	moveRightValue: number,
	moveUpValue: number,
	moveDownValue: number,
	jumpActionValue: number,
	worldUnlockPending: boolean,
	worldUnlockCheckAccumulator: number,
	worldUnlockCheckInterval: number,
	worldUnlockRaycastDistance: number,
	worldUnlockRaycastParams: RaycastParams?,
	worldUnlockConsecutiveSurfaceHits: number,
	lastWorldUnlockRequestAt: number,
	wasGrounded: boolean,
	maxAirborneDownwardSpeed: number,
	lastLandingAt: number,
	lastHurtFeedbackAt: number,
	hurtSoundAssetIds: { string },
}

return PlayerServiceClient :: PlayerServiceClient

