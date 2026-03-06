--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Npc = require(script.Parent.Parent)
local HopMotion = require(ReplicatedStorage.Shared.Modules.Math.HopMotion)

type NpcBehaviorConfig = Npc.NpcBehaviorConfig
type NpcConfig = Npc.NpcConfig
type BaseNpc = Npc.Npc
type HopMotionClass = HopMotion.HopMotion
type HopStep = HopMotion.HopStep

local DEFAULT_REST_DURATION = 3
local DEFAULT_HOP_DURATION = 0.45
local DEFAULT_HOP_DISTANCE = 8
local DEFAULT_HOP_MIN_ARC_HEIGHT = 1
local DEFAULT_HOP_MAX_ARC_HEIGHT = 7
local DEFAULT_HOP_SPRING_FREQUENCY = 10
local DEFAULT_HOP_SPRING_DAMPING = 1
local DEFAULT_IDLE_MIN_SPEED = 0.65
local DEFAULT_IDLE_MAX_SPEED = 1.7
local DEFAULT_ONE_SHOT_DURATION = 0.25
local DEFAULT_HOP_BLOCKCAST_PADDING = 0.08
local DEFAULT_HOP_GROUND_PROBE_UP = 8
local DEFAULT_HOP_GROUND_PROBE_DOWN = 20
local DEFAULT_HOP_PENETRATION_LIFT_STEPS = 10
local DEFAULT_HOP_PENETRATION_LIFT_STEP = 0.35
local DEFAULT_HOP_OVERLAP_MAX_PARTS = 24

local REQUIRED_ANIMATIONS = { "Hurt", "Idle", "Jump", "Land" }

type SlimeTracks = {
	Hurt: AnimationTrack?,
	Idle: AnimationTrack?,
	Jump: AnimationTrack?,
	Land: AnimationTrack?,
}

type SlimeConfig = NpcConfig & {
	slimeType: string?,
	variant: string?,
	aggroOnPlayer: boolean?,
	aggroOnPlayers: boolean?,
	passiveUntilHit: boolean?,
	lockTo2DPlane: boolean?,
	planeX: number?,
	twoDPlaneX: number?,
	restDuration: number?,
	hopDuration: number?,
	hopDistance: number?,
	hopMinArcHeight: number?,
	hopMaxArcHeight: number?,
	hopArcHeight: number?,
	hopMotionSpring: {
		frequency: number?,
		damping: number?,
	}?,
	idleAnimationMinSpeed: number?,
	idleAnimationMaxSpeed: number?,
}

local Slime = {}
Slime.__index = Slime
setmetatable(Slime, { __index = Npc })

export type Slime = BaseNpc & {
	aggroOnPlayer: boolean,
	passiveUntilHit: boolean,
	hasBeenHit: boolean,
	isGreenSlime: boolean,
	restDuration: number,
	hopDuration: number,
	hopDistance: number,
	hopMinArcHeight: number,
	hopMaxArcHeight: number,
	hopArcHeight: number?,
	idleAnimationMinSpeed: number,
	idleAnimationMaxSpeed: number,
	_isResting: boolean,
	restElapsed: number,
	hopElapsed: number,
	_slimeAnimationsLoaded: boolean,
	_slimeAnimations: SlimeTracks,
	_slimeActiveOneShot: string?,
	_baseCanMove: boolean,
	lockTo2DPlane: boolean,
	planeX: number?,
	_hopMotion: HopMotionClass,
	_hopMotionConnection: RBXScriptConnection?,
	_hopDestination: Vector3?,
	_hopRootWasAnchored: boolean?,
	_hopRaycastParams: RaycastParams?,
	_hopOverlapParams: OverlapParams?,
	_hopSupportsBlockcast: boolean?,
	_lastResolvedHopPosition: Vector3?,
	_random: Random,
	setAggroOnPlayer: (self: Slime, enabled: boolean) -> (),
}

local function toBoolean(value: any, fallback: boolean): boolean
	if typeof(value) == "boolean" then
		return value
	end
	return fallback
end

local function toNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	local output = if typeof(value) == "number" and value == value then value else fallback
	if minimum ~= nil and output < minimum then
		output = minimum
	end
	if maximum ~= nil and output > maximum then
		output = maximum
	end
	return output
end

local function toOptionalNumber(value: any): number?
	if typeof(value) == "number" and value == value then
		return value
	end
	return nil
end

local function normalizeToken(value: string): string
	return string.lower(string.gsub(value, "[%s_%-%.]", ""))
end

local function resolveSlimeLabel(config: { [string]: any }): string
	local candidates = {
		config.slimeType,
		config.variant,
		config.archetype,
		config.displayName,
		config.modelName,
	}
	for _, value in candidates do
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return ""
end

local function isGreenVariant(slimeLabel: string): boolean
	if slimeLabel == "" then
		return false
	end
	local normalized = normalizeToken(slimeLabel)
	return normalized == "green"
		or normalized == "greenslime"
		or string.find(normalized, "greenslime", 1, true) ~= nil
end

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function resolvePlayerFromTarget(target: any): Player?
	if target == nil then
		return nil
	end

	if typeof(target) == "Instance" then
		if target:IsA("Player") then
			return target
		end

		if target:IsA("Model") then
			return Players:GetPlayerFromCharacter(target)
		end

		if target:IsA("Humanoid") then
			local parent = target.Parent
			if parent and parent:IsA("Model") then
				return Players:GetPlayerFromCharacter(parent)
			end
		end

		if target:IsA("BasePart") then
			local characterModel = target:FindFirstAncestorOfClass("Model")
			if characterModel then
				return Players:GetPlayerFromCharacter(characterModel)
			end
		end
	end

	return nil
end

local function resolvePositionFromTarget(target: any): Vector3?
	if target == nil then
		return nil
	end

	if typeof(target) == "Vector3" then
		return target
	end

	if typeof(target) == "table" then
		local getter = (target :: any).getPosition
		if typeof(getter) == "function" then
			local ok, result = pcall(getter, target)
			if ok and typeof(result) == "Vector3" then
				return result
			end
		end
	end

	if typeof(target) ~= "Instance" then
		return nil
	end

	if target:IsA("BasePart") then
		return target.Position
	end

	if target:IsA("Player") then
		local character = target.Character
		local rootPart = resolveRootPart(character)
		if rootPart then
			return rootPart.Position
		end
		return nil
	end

	if target:IsA("Model") then
		local rootPart = resolveRootPart(target)
		if rootPart then
			return rootPart.Position
		end
		return nil
	end

	if target:IsA("Humanoid") then
		local character = target.Parent
		if character and character:IsA("Model") then
			local rootPart = resolveRootPart(character)
			if rootPart then
				return rootPart.Position
			end
		end
	end

	return nil
end

local function resolveTrack(animator: Animator, animation: Animation): AnimationTrack?
	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[SlimeAi] Failed loading animation track:", tostring(trackOrErr))
		return nil
	end

	local track = trackOrErr :: AnimationTrack
	return track
end

local function findAnimationByName(model: Model, expectedName: string): Animation?
	local expectedToken = normalizeToken(expectedName)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Animation") and normalizeToken(descendant.Name) == expectedToken then
			return descendant
		end
	end
	return nil
end

function Slime:_isAggroEnabled(): boolean
	if not self.aggroOnPlayer then
		return false
	end
	if self.passiveUntilHit and not self.hasBeenHit then
		return false
	end
	return true
end

function Slime:_resolve2DPlaneX(): number?
	if not self.lockTo2DPlane then
		return nil
	end

	if self.planeX ~= nil then
		return self.planeX
	end

	local position = self:getPosition()
	if position == nil then
		return nil
	end

	self.planeX = position.X
	return self.planeX
end

function Slime:_projectTo2DPlane(position: Vector3): Vector3
	local planeX = self:_resolve2DPlaneX()
	if planeX == nil then
		return position
	end
	return Vector3.new(planeX, position.Y, position.Z)
end

function Slime:_enforce2DPlane()
	local planeX = self:_resolve2DPlaneX()
	if planeX == nil then
		return
	end

	local model = self.model
	local rootPart = self.rootPart

	if rootPart ~= nil then
		local rootPosition = rootPart.Position
		if math.abs(rootPosition.X - planeX) > 0.001 then
			local fixedPosition = Vector3.new(planeX, rootPosition.Y, rootPosition.Z)
			local lookVector = rootPart.CFrame.LookVector
			local projectedLook = Vector3.new(0, 0, lookVector.Z)
			if projectedLook.Magnitude <= 0.001 then
				projectedLook = Vector3.new(0, 0, 1)
			end
			rootPart.CFrame = CFrame.lookAt(fixedPosition, fixedPosition + projectedLook.Unit, Vector3.yAxis)
		end

		local velocity = rootPart.AssemblyLinearVelocity
		if math.abs(velocity.X) > 0.001 then
			rootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, velocity.Z)
		end
		return
	end

	if model == nil then
		return
	end

	local pivot = model:GetPivot()
	local pivotPosition = pivot.Position
	if math.abs(pivotPosition.X - planeX) <= 0.001 then
		return
	end

	local fixedPosition = Vector3.new(planeX, pivotPosition.Y, pivotPosition.Z)
	local lookVector = pivot.LookVector
	local projectedLook = Vector3.new(0, 0, lookVector.Z)
	if projectedLook.Magnitude <= 0.001 then
		projectedLook = Vector3.new(0, 0, 1)
	end

	model:PivotTo(CFrame.lookAt(fixedPosition, fixedPosition + projectedLook.Unit, Vector3.yAxis))
end

function Slime:setAggroOnPlayer(enabled: boolean)
	self.aggroOnPlayer = enabled
	if self:_isAggroEnabled() then
		return
	end

	local currentTarget = self.currentTarget
	if currentTarget ~= nil and resolvePlayerFromTarget(currentTarget) ~= nil then
		self:clearTarget()
	end
end

function Slime:_loadSlimeAnimations()
	if self.model == nil then
		return
	end

	local animator: Animator? = nil
	local humanoid = self.humanoid
	if humanoid ~= nil then
		animator = humanoid:FindFirstChildOfClass("Animator")
		if animator == nil then
			local nextAnimator = Instance.new("Animator")
			nextAnimator.Name = "Animator"
			nextAnimator.Parent = humanoid
			animator = nextAnimator
		end
	end

	if animator == nil then
		local animationController = self.model:FindFirstChildOfClass("AnimationController")
		if animationController == nil then
			for _, descendant in self.model:GetDescendants() do
				if descendant:IsA("AnimationController") then
					animationController = descendant
					break
				end
			end
		end

		if animationController == nil then
			local generatedController = Instance.new("AnimationController")
			generatedController.Name = "AnimationController"
			generatedController.Parent = self.model
			animationController = generatedController
		end

		animator = animationController:FindFirstChildOfClass("Animator")
		if animator == nil then
			local nextAnimator = Instance.new("Animator")
			nextAnimator.Name = "Animator"
			nextAnimator.Parent = animationController
			animator = nextAnimator
		end
	end

	if animator == nil then
		return
	end

	self._slimeAnimations = {
		Hurt = nil,
		Idle = nil,
		Jump = nil,
		Land = nil,
	}

	for _, animationName in REQUIRED_ANIMATIONS do
		local animation = findAnimationByName(self.model, animationName)
		if animation == nil then
			continue
		end

		local track = resolveTrack(animator, animation)
		if track == nil then
			continue
		end

		if animationName == "Idle" then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Idle
		else
			track.Looped = false
			track.Priority = Enum.AnimationPriority.Action
		end

		if animationName == "Hurt" then
			self._slimeAnimations.Hurt = track
		elseif animationName == "Idle" then
			self._slimeAnimations.Idle = track
		elseif animationName == "Jump" then
			self._slimeAnimations.Jump = track
		else
			self._slimeAnimations.Land = track
		end
	end

	self._slimeAnimationsLoaded = true
end

function Slime:_stopOneShotAnimations()
	local hurtTrack = self._slimeAnimations.Hurt
	local jumpTrack = self._slimeAnimations.Jump
	local landTrack = self._slimeAnimations.Land

	if hurtTrack and hurtTrack.IsPlaying then
		hurtTrack:Stop(0.03)
	end
	if jumpTrack and jumpTrack.IsPlaying then
		jumpTrack:Stop(0.03)
	end
	if landTrack and landTrack.IsPlaying then
		landTrack:Stop(0.03)
	end

	self._slimeActiveOneShot = nil
end

function Slime:_playIdleAnimation(speed: number?)
	if self._slimeActiveOneShot ~= nil then
		return
	end

	local idleTrack = self._slimeAnimations.Idle
	if idleTrack == nil then
		return
	end

	local playbackSpeed = toNumber(speed, self.idleAnimationMinSpeed, 0.05, 8)
	if not idleTrack.IsPlaying then
		self:_stopOneShotAnimations()
		idleTrack:Play(0.08, 1, playbackSpeed)
	else
		idleTrack:AdjustSpeed(playbackSpeed)
	end
end

function Slime:_playOneShotAnimation(animationName: "Hurt" | "Jump" | "Land")
	local track = (self._slimeAnimations :: any)[animationName] :: AnimationTrack?
	if track == nil then
		return
	end

	self:_stopOneShotAnimations()

	local idleTrack = self._slimeAnimations.Idle
	if idleTrack and idleTrack.IsPlaying then
		idleTrack:Stop(0.06)
	end

	self._slimeActiveOneShot = animationName
	track:Play(0.04, 1, 1)

	local animationDuration = track.Length
	if animationDuration <= 0 then
		animationDuration = DEFAULT_ONE_SHOT_DURATION
	end

	task.delay(animationDuration, function()
		if (self :: any)._isDestroyed then
			return
		end
		if self._slimeActiveOneShot ~= animationName then
			return
		end

		self._slimeActiveOneShot = nil
		if self.isAlive and self._isResting then
			self:_playIdleAnimation()
		end
	end)
end

function Slime:_updateIdleSpeed()
	if not self._isResting then
		return
	end

	local alpha = math.clamp(self.restElapsed / self.restDuration, 0, 1)
	local speed = self.idleAnimationMinSpeed + (self.idleAnimationMaxSpeed - self.idleAnimationMinSpeed) * alpha
	self:_playIdleAnimation(speed)
end

function Slime:_resolveHopDestination(): Vector3?
	local currentPosition = self:getPosition()
	if currentPosition == nil then
		return nil
	end
	currentPosition = self:_projectTo2DPlane(currentPosition)

	local hopDestination: Vector3? = nil
	local currentTarget = self.currentTarget
	if currentTarget ~= nil and self:isTargetValid(currentTarget) then
		local targetPosition = resolvePositionFromTarget(currentTarget)
		if targetPosition ~= nil then
			targetPosition = self:_projectTo2DPlane(targetPosition)
			local deltaZ = targetPosition.Z - currentPosition.Z
			if math.abs(deltaZ) > 0.05 then
				local hopStep = math.min(self.hopDistance, math.abs(deltaZ))
				hopDestination = currentPosition + Vector3.new(0, 0, math.sign(deltaZ) * hopStep)
			end
		end
	end

	if hopDestination == nil then
		local directionSign = if self._random:NextNumber() >= 0.5 then 1 else -1
		hopDestination = currentPosition + Vector3.new(0, 0, directionSign * self.hopDistance)
	end

	return self:_projectTo2DPlane(hopDestination)
end

function Slime:_refreshHopCollisionQueryParams()
	local model = self.model
	if model == nil then
		self._hopRaycastParams = nil
		self._hopOverlapParams = nil
		self._hopSupportsBlockcast = nil
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { model }
	raycastParams.IgnoreWater = false
	self._hopRaycastParams = raycastParams

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { model }
	overlapParams.MaxParts = DEFAULT_HOP_OVERLAP_MAX_PARTS
	self._hopOverlapParams = overlapParams
	self._hopSupportsBlockcast = nil
end

function Slime:_resolveHopHalfExtents(): Vector3
	local rootPart = self.rootPart
	if rootPart ~= nil then
		local size = rootPart.Size
		return Vector3.new(math.max(0.6, size.X * 0.45), math.max(0.6, size.Y * 0.5), math.max(0.6, size.Z * 0.45))
	end
	return Vector3.new(1.3, 1, 1.3)
end

function Slime:_resolveGroundSnapY(position: Vector3, halfExtents: Vector3): number?
	local raycastParams = self._hopRaycastParams
	if raycastParams == nil then
		return nil
	end

	local origin = position + Vector3.new(0, DEFAULT_HOP_GROUND_PROBE_UP, 0)
	local direction = Vector3.new(0, -(DEFAULT_HOP_GROUND_PROBE_UP + DEFAULT_HOP_GROUND_PROBE_DOWN), 0)
	local hit = Workspace:Raycast(origin, direction, raycastParams)
	if hit == nil then
		return nil
	end
	if not hit.Instance:IsA("BasePart") then
		return nil
	end
	if not hit.Instance.CanCollide then
		return nil
	end

	return hit.Position.Y + halfExtents.Y + DEFAULT_HOP_BLOCKCAST_PADDING
end

function Slime:_hasBlockingOverlap(position: Vector3, lookDirectionRaw: Vector3): boolean
	local overlapParams = self._hopOverlapParams
	if overlapParams == nil then
		return false
	end

	local lookDirection = lookDirectionRaw
	if lookDirection.Magnitude <= 0.001 then
		lookDirection = Vector3.new(0, 0, 1)
	end

	local halfExtents = self:_resolveHopHalfExtents()
	local boxCFrame = CFrame.lookAt(position, position + lookDirection.Unit, Vector3.yAxis)
	local parts = Workspace:GetPartBoundsInBox(boxCFrame, halfExtents * 2, overlapParams)
	for _, part in parts do
		if part:IsA("BasePart") and part.CanCollide then
			return true
		end
	end
	return false
end

function Slime:_resolveHopCollisionPosition(
	previousPositionRaw: Vector3,
	desiredPositionRaw: Vector3,
	lookDirectionRaw: Vector3
): Vector3
	local previousPosition = self:_projectTo2DPlane(previousPositionRaw)
	local desiredPosition = self:_projectTo2DPlane(desiredPositionRaw)
	local lookDirection = lookDirectionRaw
	if lookDirection.Magnitude <= 0.001 then
		lookDirection = Vector3.new(0, 0, 1)
	end

	local raycastParams = self._hopRaycastParams
	local halfExtents = self:_resolveHopHalfExtents()
	local resolvedPosition = desiredPosition
	local delta = desiredPosition - previousPosition

	if raycastParams ~= nil and delta.Magnitude > 1e-4 then
		local hit: RaycastResult? = nil
		if self._hopSupportsBlockcast ~= false then
			local ok, result = pcall(function()
				return Workspace:Blockcast(CFrame.new(previousPosition), halfExtents * 2, delta, raycastParams)
			end)
			if ok then
				self._hopSupportsBlockcast = true
				hit = result
			else
				self._hopSupportsBlockcast = false
			end
		end
		if hit == nil then
			hit = Workspace:Raycast(previousPosition, delta, raycastParams)
		end

		if hit ~= nil and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
			local safeDistance = math.max(0, hit.Distance - DEFAULT_HOP_BLOCKCAST_PADDING)
			resolvedPosition = previousPosition + delta.Unit * safeDistance
		end
	end

	local groundedY = self:_resolveGroundSnapY(resolvedPosition, halfExtents)
	if groundedY ~= nil and resolvedPosition.Y < groundedY then
		resolvedPosition = Vector3.new(resolvedPosition.X, groundedY, resolvedPosition.Z)
	end

	if self:_hasBlockingOverlap(resolvedPosition, lookDirection) then
		local foundValidPosition = false
		for stepIndex = 1, DEFAULT_HOP_PENETRATION_LIFT_STEPS do
			local raisedPosition = resolvedPosition + Vector3.new(0, DEFAULT_HOP_PENETRATION_LIFT_STEP * stepIndex, 0)
			local raisedGroundedY = self:_resolveGroundSnapY(raisedPosition, halfExtents)
			if raisedGroundedY ~= nil and raisedPosition.Y < raisedGroundedY then
				raisedPosition = Vector3.new(raisedPosition.X, raisedGroundedY, raisedPosition.Z)
			end
			if not self:_hasBlockingOverlap(raisedPosition, lookDirection) then
				resolvedPosition = raisedPosition
				foundValidPosition = true
				break
			end
		end

		if not foundValidPosition then
			resolvedPosition = previousPosition
		end
	end

	return self:_projectTo2DPlane(resolvedPosition)
end

function Slime:_resolveEmbeddedRestState()
	local rootPart = self.rootPart
	if rootPart == nil then
		return
	end
	if self._hopRaycastParams == nil or self._hopOverlapParams == nil then
		self:_refreshHopCollisionQueryParams()
	end

	local lookSign = if math.abs(rootPart.CFrame.LookVector.Z) > 0.001 then math.sign(rootPart.CFrame.LookVector.Z) else 1
	local lookDirection = Vector3.new(0, 0, lookSign)
	local currentPosition = self:_projectTo2DPlane(rootPart.Position)
	if not self:_hasBlockingOverlap(currentPosition, lookDirection) then
		return
	end

	local resolvedPosition = self:_resolveHopCollisionPosition(currentPosition, currentPosition, lookDirection)
	if (resolvedPosition - currentPosition).Magnitude <= 1e-4 then
		return
	end

	rootPart.CFrame = CFrame.lookAt(resolvedPosition, resolvedPosition + lookDirection, Vector3.yAxis)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	self._lastResolvedHopPosition = resolvedPosition
end

function Slime:_applyHopTransform(positionRaw: any, velocityRaw: any)
	if typeof(positionRaw) ~= "Vector3" then
		return
	end
	if self._hopRaycastParams == nil or self._hopOverlapParams == nil then
		self:_refreshHopCollisionQueryParams()
	end

	local desiredPosition = self:_projectTo2DPlane(positionRaw)
	local velocity = if typeof(velocityRaw) == "Vector3" then velocityRaw else Vector3.zero
	local lookSign = if math.abs(velocity.Z) > 0.001 then math.sign(velocity.Z) else 0
	if lookSign == 0 and self._hopDestination ~= nil then
		local zDelta = self._hopDestination.Z - desiredPosition.Z
		if math.abs(zDelta) > 0.001 then
			lookSign = math.sign(zDelta)
		end
	end
	if lookSign == 0 then
		lookSign = 1
	end

	local lookDirection = Vector3.new(0, 0, lookSign)
	local previousPosition = self._lastResolvedHopPosition
	if previousPosition == nil then
		local rootPart = self.rootPart
		if rootPart ~= nil then
			previousPosition = self:_projectTo2DPlane(rootPart.Position)
		else
			previousPosition = desiredPosition
		end
	end

	local position = self:_resolveHopCollisionPosition(previousPosition, desiredPosition, lookDirection)
	self._lastResolvedHopPosition = position
	local zVelocity = velocity.Z
	if math.abs(position.Z - previousPosition.Z) <= 1e-4 then
		zVelocity = 0
	end

	local rootPart = self.rootPart
	if rootPart ~= nil then
		rootPart.CFrame = CFrame.lookAt(position, position + lookDirection, Vector3.yAxis)
		rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, zVelocity)
		rootPart.AssemblyAngularVelocity = Vector3.zero
		return
	end

	local model = self.model
	if model ~= nil then
		model:PivotTo(CFrame.lookAt(position, position + lookDirection, Vector3.yAxis))
	end
end

function Slime:_startHopMotion(destinationRaw: any): boolean
	if typeof(destinationRaw) ~= "Vector3" then
		return false
	end

	local startPosition = self:getPosition()
	if startPosition == nil then
		return false
	end

	local projectedStart = self:_projectTo2DPlane(startPosition)
	local projectedDestination = self:_projectTo2DPlane(destinationRaw)
	local arcHeight = self.hopArcHeight
	local horizontalDelta = projectedDestination - projectedStart
	local horizontalDistance = Vector3.new(horizontalDelta.X, 0, horizontalDelta.Z).Magnitude
	if arcHeight == nil then
		arcHeight = HopMotion.computeArcHeight(horizontalDistance, self.hopMinArcHeight, self.hopMaxArcHeight)
	end

	local rootPart = self.rootPart
	if rootPart ~= nil then
		self._hopRootWasAnchored = rootPart.Anchored
		rootPart.Anchored = true
	end

	self._hopDestination = projectedDestination
	self._lastResolvedHopPosition = projectedStart
	self._hopMotion:start(projectedStart, projectedDestination, self.hopDuration, arcHeight)
	self:_applyHopTransform(projectedStart, Vector3.zero)
	return true
end

function Slime:_stopHopMotion(snapToDestinationRaw: any)
	local snapToDestination = snapToDestinationRaw == true
	self._hopMotion:stop(snapToDestination)
	if snapToDestination and self._hopDestination ~= nil then
		self:_applyHopTransform(self._hopDestination, Vector3.zero)
	end

	local rootPart = self.rootPart
	if rootPart ~= nil and self._hopRootWasAnchored ~= nil then
		rootPart.Anchored = self._hopRootWasAnchored
	end
	self._hopRootWasAnchored = nil
	self._lastResolvedHopPosition = nil
	self._hopDestination = nil
end

function Slime:_updateHopMotion(dt: number)
	if self._isResting then
		return
	end
	if not self._hopMotion:isActive() then
		return
	end

	local step: HopStep = self._hopMotion:step(dt)
	self:_applyHopTransform(step.position, step.velocity)
	if step.completed then
		self:_finishHop()
	end
end

function Slime:_connectHopMotionHeartbeat()
	if self._hopMotionConnection ~= nil then
		return
	end

	self._hopMotionConnection = RunService.Heartbeat:Connect(function(dt: number)
		if (self :: any)._isDestroyed then
			self:_disconnectHopMotionHeartbeat()
			return
		end
		self:_updateHopMotion(dt)
		self:_enforce2DPlane()
	end)
end

function Slime:_disconnectHopMotionHeartbeat()
	if self._hopMotionConnection ~= nil then
		self._hopMotionConnection:Disconnect()
		self._hopMotionConnection = nil
	end
end

function Slime:_beginRest()
	self._isResting = true
	self.restElapsed = 0
	self.hopElapsed = 0
	self.movement.canMove = false
	self:_stopHopMotion(true)
	self:stopMoving()
	self:_playIdleAnimation(self.idleAnimationMinSpeed)
end

function Slime:_beginHop()
	if not self.isAlive then
		return
	end
	if not self._baseCanMove then
		return
	end

	local hopDestination = self:_resolveHopDestination()
	if hopDestination == nil then
		return
	end

	self._isResting = false
	self.restElapsed = self.restDuration
	self.hopElapsed = 0
	self.movement.canMove = false

	self:_playOneShotAnimation("Jump")
	self:jump()
	if not self:_startHopMotion(hopDestination) then
		self:_beginRest()
	end
end

function Slime:_finishHop()
	if not self.isAlive or self._isResting then
		return
	end

	self:_stopHopMotion(true)
	self.movement.canMove = false
	self:stopMoving()
	self:_playOneShotAnimation("Land")
	self:_beginRest()
end

function Slime:_slimeOnSpawn()
	self._baseCanMove = self.movement.canMove
	self._slimeAnimationsLoaded = false
	self._slimeActiveOneShot = nil
	if self.passiveUntilHit then
		self.hasBeenHit = false
	end

	self:_refreshHopCollisionQueryParams()
	self._lastResolvedHopPosition = self:getPosition()
	self:_connectHopMotionHeartbeat()
	self:_loadSlimeAnimations()
	self:_beginRest()
	self:_enforce2DPlane()
end

function Slime:_slimeOnThink(dt: number)
	if not self.isAlive then
		return
	end
	self:_enforce2DPlane()
	if self._isResting then
		self:_resolveEmbeddedRestState()
	end

	if not self._slimeAnimationsLoaded then
		self:_loadSlimeAnimations()
	end

	if not self:_isAggroEnabled() then
		local currentTarget = self.currentTarget
		if currentTarget ~= nil and resolvePlayerFromTarget(currentTarget) ~= nil then
			self:clearTarget()
		end
	end

	if self._isResting then
		self.restElapsed = math.min(self.restDuration, self.restElapsed + dt)
		self:_updateIdleSpeed()
		if self.restElapsed >= self.restDuration then
			self:_beginHop()
		end
		return
	end

	self.hopElapsed += dt
	if not self._hopMotion:isActive() and self.hopElapsed >= self.hopDuration then
		self:_finishHop()
	end
end

function Slime:_slimeOnDamage(source: any?)
	self:_playOneShotAnimation("Hurt")

	if self.passiveUntilHit and not self.hasBeenHit then
		self.hasBeenHit = true
	end

	if source ~= nil and self:isTargetValid(source) then
		self:setTarget(source)
	end
end

function Slime:_slimeOnDeath()
	self:_disconnectHopMotionHeartbeat()
	self:_stopHopMotion(false)
	self:_stopOneShotAnimations()
	self._lastResolvedHopPosition = nil
	self._hopRaycastParams = nil
	self._hopOverlapParams = nil

	local idleTrack = self._slimeAnimations.Idle
	if idleTrack and idleTrack.IsPlaying then
		idleTrack:Stop(0.04)
	end
end

function Slime.new(configRaw: SlimeConfig?): Slime
	local config = if typeof(configRaw) == "table" then table.clone(configRaw :: any) else {}
	local baseBehavior = if typeof(config.behavior) == "table"
		then config.behavior :: NpcBehaviorConfig
		else ({} :: NpcBehaviorConfig)

	local movement = if typeof(config.movement) == "table" then table.clone(config.movement) else {}
	if movement.canWander == nil then
		movement.canWander = false
	end
	if movement.thinkInterval == nil then
		movement.thinkInterval = 0.1
	end
	config.movement = movement

	local lifecycle = if typeof(config.lifecycle) == "table" then table.clone(config.lifecycle) else {}
	local autoStart = toBoolean(lifecycle.autoStart, false)
	lifecycle.autoStart = false
	config.lifecycle = lifecycle

	local slimeLabel = resolveSlimeLabel(config :: { [string]: any })
	local isGreen = isGreenVariant(slimeLabel)

	local aggroRaw = config.aggroOnPlayer
	if aggroRaw == nil then
		aggroRaw = config.aggroOnPlayers
	end

	local behavior: NpcBehaviorConfig = {
		acquireTarget = baseBehavior.acquireTarget,
		onAttack = baseBehavior.onAttack,
		shouldTarget = function(self: Slime, target: any): boolean
			local targetPlayer = resolvePlayerFromTarget(target)
			if targetPlayer ~= nil and not self:_isAggroEnabled() then
				return false
			end

			local userShouldTarget = baseBehavior.shouldTarget
			if userShouldTarget ~= nil then
				return userShouldTarget(self, target)
			end
			return true
		end,
		onSpawn = function(self: Slime)
			self:_slimeOnSpawn()
			local userOnSpawn = baseBehavior.onSpawn
			if userOnSpawn ~= nil then
				userOnSpawn(self)
			end
		end,
		onThink = function(self: Slime, dt: number)
			self:_slimeOnThink(dt)
			local userOnThink = baseBehavior.onThink
			if userOnThink ~= nil then
				userOnThink(self, dt)
			end
		end,
		onDamageTaken = function(self: Slime, damage: number, source: any?, hp: number)
			self:_slimeOnDamage(source)
			local userOnDamageTaken = baseBehavior.onDamageTaken
			if userOnDamageTaken ~= nil then
				userOnDamageTaken(self, damage, source, hp)
			end
		end,
		onDeath = function(self: Slime, killer: any?)
			self:_slimeOnDeath()
			local userOnDeath = baseBehavior.onDeath
			if userOnDeath ~= nil then
				userOnDeath(self, killer)
			end
		end,
	}
	config.behavior = behavior

	local npcObject = Npc.new(config :: NpcConfig)
	local self = setmetatable(npcObject :: any, Slime) :: Slime

	local planeXRaw = if config.planeX ~= nil then config.planeX else config.twoDPlaneX
	local hopMotionSpringRaw = if typeof(config.hopMotionSpring) == "table" then config.hopMotionSpring else {}
	local hopMotionSpring = {
		frequency = toNumber(
			(hopMotionSpringRaw :: any).frequency,
			DEFAULT_HOP_SPRING_FREQUENCY,
			0.01,
			120
		),
		damping = toNumber((hopMotionSpringRaw :: any).damping, DEFAULT_HOP_SPRING_DAMPING, 0, 20),
	}

	self.aggroOnPlayer = toBoolean(aggroRaw, true)
	self.passiveUntilHit = toBoolean(config.passiveUntilHit, isGreen)
	self.hasBeenHit = false
	self.isGreenSlime = isGreen
	self.restDuration = toNumber(config.restDuration, DEFAULT_REST_DURATION, 0.1, 30)
	self.hopDuration = toNumber(config.hopDuration, DEFAULT_HOP_DURATION, 0.05, 10)
	self.hopDistance = toNumber(config.hopDistance, DEFAULT_HOP_DISTANCE, 1, 100)
	self.hopMinArcHeight = toNumber(config.hopMinArcHeight, DEFAULT_HOP_MIN_ARC_HEIGHT, 0, 50)
	self.hopMaxArcHeight = toNumber(config.hopMaxArcHeight, DEFAULT_HOP_MAX_ARC_HEIGHT, self.hopMinArcHeight, 100)
	self.hopArcHeight = toOptionalNumber(config.hopArcHeight)
	self.idleAnimationMinSpeed = toNumber(config.idleAnimationMinSpeed, DEFAULT_IDLE_MIN_SPEED, 0.05, 8)
	self.idleAnimationMaxSpeed = toNumber(config.idleAnimationMaxSpeed, DEFAULT_IDLE_MAX_SPEED, self.idleAnimationMinSpeed, 12)
	self._isResting = true
	self.restElapsed = 0
	self.hopElapsed = 0
	self._slimeAnimationsLoaded = false
	self._slimeAnimations = {
		Hurt = nil,
		Idle = nil,
		Jump = nil,
		Land = nil,
	}
	self._slimeActiveOneShot = nil
	self._baseCanMove = self.movement.canMove
	self.lockTo2DPlane = toBoolean(config.lockTo2DPlane, true)
	self.planeX = toOptionalNumber(planeXRaw)
	self._hopMotion = HopMotion.new({
		duration = self.hopDuration,
		minArcHeight = self.hopMinArcHeight,
		maxArcHeight = self.hopMaxArcHeight,
		arcHeight = self.hopArcHeight,
		spring = hopMotionSpring,
	})
	self._hopMotionConnection = nil
	self._hopDestination = nil
	self._hopRootWasAnchored = nil
	self._hopRaycastParams = nil
	self._hopOverlapParams = nil
	self._hopSupportsBlockcast = nil
	self._lastResolvedHopPosition = nil
	self._random = Random.new()

	if self.passiveUntilHit and not self.hasBeenHit then
		local currentTarget = self.currentTarget
		if currentTarget ~= nil and resolvePlayerFromTarget(currentTarget) ~= nil then
			self:clearTarget()
		end
	end

	if autoStart then
		self:start(self.lifecycle.spawnCFrame)
	end

	return self
end

return Slime
