local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HopMotion = require("HopMotion")
local Npc = require("Npc")

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
local DEFAULT_HOP_BLOCKCAST_PADDING = 0.08
local DEFAULT_HOP_GROUND_PROBE_UP = 8
local DEFAULT_HOP_GROUND_PROBE_DOWN = 20
local DEFAULT_HOP_PENETRATION_LIFT_STEPS = 10
local DEFAULT_HOP_PENETRATION_LIFT_STEP = 0.35
local DEFAULT_HOP_OVERLAP_MAX_PARTS = 24

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
}

local Slime = {}
Slime.__index = Slime
setmetatable(Slime, { __index = Npc })

export type Slime = BaseNpc & typeof(Slime) & {
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
	_isResting: boolean,
	restElapsed: number,
	hopElapsed: number,
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
	_facingSign: number,
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
	local normalized = string.gsub(value, "[%s_%-%.]", "")
	return string.lower(normalized)
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
	return normalized == "green" or normalized == "greenslime" or string.find(normalized, "greenslime", 1, true) ~= nil
end

local function resolveFacingSign(valueRaw: any, fallback: number): number
	local sign = if typeof(valueRaw) == "number" then math.sign(valueRaw) else 0
	if sign == 0 then
		sign = math.sign(fallback)
	end
	if sign == 0 then
		return 1
	end
	return sign
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

function Slime._configureRootPhysics(self: Slime)
	local rootPart = self.rootPart
	if rootPart == nil then
		return
	end

	rootPart.Anchored = false
	rootPart.CanCollide = true
	rootPart.CanQuery = true
	rootPart.CanTouch = true
	rootPart.Massless = false
	rootPart.CustomPhysicalProperties = PhysicalProperties.new(1, 0.8, 0, 1, 1)
	rootPart.AssemblyAngularVelocity = Vector3.zero

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
end

function Slime._isAggroEnabled(self: Slime): boolean
	if not self.aggroOnPlayer then
		return false
	end
	if self.passiveUntilHit and not self.hasBeenHit then
		return false
	end
	return true
end

function Slime._resolve2DPlaneX(self: Slime): number?
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

function Slime._projectTo2DPlane(self: Slime, position: Vector3): Vector3
	local planeX = self:_resolve2DPlaneX()
	if planeX == nil then
		return position
	end
	return Vector3.new(planeX, position.Y, position.Z)
end

function Slime._enforce2DPlane(self: Slime)
	local planeX = self:_resolve2DPlaneX()
	if planeX == nil then
		return
	end

	local model = self.model
	local rootPart = self.rootPart

	if rootPart ~= nil then
		local rootPosition = rootPart.Position
		local shouldRealign = math.abs(rootPosition.X - planeX) > 0.001
			or rootPart.CFrame.UpVector.Y < 0.999
			or rootPart.CFrame.RightVector.X < 0.999
		if shouldRealign then
			local fixedPosition = Vector3.new(planeX, rootPosition.Y, rootPosition.Z)
			local lookVector = rootPart.CFrame.LookVector
			self._facingSign = resolveFacingSign(lookVector.Z, self._facingSign)
			rootPart.CFrame = CFrame.new(fixedPosition)
		end

		local velocity = rootPart.AssemblyLinearVelocity
		if math.abs(velocity.X) > 0.001 then
			rootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, velocity.Z)
		end
		rootPart.AssemblyAngularVelocity = Vector3.zero
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
	self._facingSign = resolveFacingSign(lookVector.Z, self._facingSign)

	model:PivotTo(CFrame.new(fixedPosition))
end

function Slime.SetAggroOnPlayer(self: Slime, enabled: boolean)
	self.aggroOnPlayer = enabled
	if self:_isAggroEnabled() then
		return
	end

	local currentTarget = self.currentTarget
	if currentTarget ~= nil and resolvePlayerFromTarget(currentTarget) ~= nil then
		self:clearTarget()
	end
end

function Slime._resolveHopDestination(self: Slime): Vector3?
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

	local resolvedHopDestination: Vector3 = hopDestination or currentPosition
	local projectedDestination: Vector3? = self:_projectTo2DPlane(resolvedHopDestination) :: any
	if projectedDestination == nil then
		return currentPosition
	end
	return projectedDestination
end

function Slime._refreshHopCollisionQueryParams(self: Slime)
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

function Slime._resolveHopHalfExtents(self: Slime): Vector3
	local rootPart = self.rootPart
	if rootPart ~= nil then
		local size = rootPart.Size
		return Vector3.new(math.max(0.6, size.X * 0.45), math.max(0.6, size.Y * 0.5), math.max(0.6, size.Z * 0.45))
	end
	return Vector3.new(1.3, 1, 1.3)
end

function Slime._resolveGroundSnapY(self: Slime, position: Vector3, halfExtents: Vector3): number?
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

function Slime._hasBlockingOverlap(self: Slime, position: Vector3, lookDirectionRaw: Vector3): boolean
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

function Slime._resolveHopCollisionPosition(
	self: Slime,
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

function Slime._resolveEmbeddedRestState(self: Slime)
	local rootPart = self.rootPart
	if rootPart == nil then
		return
	end
	if self._hopRaycastParams == nil or self._hopOverlapParams == nil then
		self:_refreshHopCollisionQueryParams()
	end

	local lookSign = resolveFacingSign(self._facingSign, 1)
	local lookDirection = Vector3.new(0, 0, lookSign)
	local currentPosition = self:_projectTo2DPlane(rootPart.Position)
	if not self:_hasBlockingOverlap(currentPosition, lookDirection) then
		return
	end

	local resolvedPosition = self:_resolveHopCollisionPosition(currentPosition, currentPosition, lookDirection)
	if (resolvedPosition - currentPosition).Magnitude <= 1e-4 then
		return
	end

	rootPart.CFrame = CFrame.new(resolvedPosition)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	self._lastResolvedHopPosition = resolvedPosition
end

function Slime._applyHopTransform(self: Slime, positionRaw: any, velocityRaw: any)
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
		lookSign = resolveFacingSign(self._facingSign, 1)
	end
	self._facingSign = lookSign

	local lookDirection = Vector3.new(0, 0, lookSign)
	local previousPositionRaw = self._lastResolvedHopPosition
	if previousPositionRaw == nil then
		local rootPart = self.rootPart
		if rootPart ~= nil then
			previousPositionRaw = self:_projectTo2DPlane(rootPart.Position)
		else
			previousPositionRaw = desiredPosition
		end
	end
	local previousPosition: Vector3 = previousPositionRaw or desiredPosition

	local position: Vector3? =
		self:_resolveHopCollisionPosition(previousPosition, desiredPosition, lookDirection) :: any
	if position == nil then
		position = desiredPosition
	end
	local resolvedPosition = (position :: any) :: Vector3
	self._lastResolvedHopPosition = resolvedPosition
	local zVelocity = velocity.Z
	if math.abs(resolvedPosition.Z - previousPosition.Z) <= 1e-4 then
		zVelocity = 0
	end

	local rootPart = self.rootPart
	if rootPart ~= nil then
		rootPart.CFrame = CFrame.new(resolvedPosition)
		rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, zVelocity)
		rootPart.AssemblyAngularVelocity = Vector3.zero
		return
	end

	local model = self.model
	if model ~= nil then
		model:PivotTo(CFrame.new(resolvedPosition))
	end
end

function Slime._startHopMotion(self: Slime, destinationRaw: any): boolean
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

function Slime._stopHopMotion(self: Slime, snapToDestinationRaw: any)
	local snapToDestination = snapToDestinationRaw == true
	self._hopMotion:stop(snapToDestination)
	if snapToDestination and self._hopDestination ~= nil then
		self:_applyHopTransform(self._hopDestination, Vector3.zero)
	end

	local rootPart = self.rootPart
	if rootPart ~= nil and self._hopRootWasAnchored ~= nil then
		rootPart.Anchored = self._hopRootWasAnchored
	end
	self:_configureRootPhysics()
	self._hopRootWasAnchored = nil
	self._lastResolvedHopPosition = nil
	self._hopDestination = nil
end

function Slime._updateHopMotion(self: Slime, dt: number)
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

function Slime._connectHopMotionHeartbeat(self: Slime)
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

function Slime._disconnectHopMotionHeartbeat(self: Slime)
	if self._hopMotionConnection ~= nil then
		self._hopMotionConnection:Disconnect()
		self._hopMotionConnection = nil
	end
end

function Slime._beginRest(self: Slime)
	self._isResting = true
	self.restElapsed = 0
	self.hopElapsed = 0
	self.movement.canMove = false
	self:_stopHopMotion(true)
	self:stopMoving()
end

function Slime._beginHop(self: Slime)
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

	self:jump()
	if not self:_startHopMotion(hopDestination) then
		self:_beginRest()
	end
end

function Slime._finishHop(self: Slime)
	if not self.isAlive or self._isResting then
		return
	end

	self:_stopHopMotion(true)
	self.movement.canMove = false
	self:stopMoving()
	self:_beginRest()
end

function Slime._slimeOnSpawn(self: Slime)
	self._baseCanMove = self.movement.canMove
	if self.passiveUntilHit then
		self.hasBeenHit = false
	end

	self:_configureRootPhysics()
	self:_refreshHopCollisionQueryParams()
	self._lastResolvedHopPosition = self:getPosition()
	self:_connectHopMotionHeartbeat()
	self:_beginRest()
	self:_enforce2DPlane()
end

function Slime._slimeOnThink(self: Slime, dt: number)
	if not self.isAlive then
		return
	end
	self:_enforce2DPlane()
	if self._isResting then
		self:_resolveEmbeddedRestState()
	end

	if not self:_isAggroEnabled() then
		local currentTarget = self.currentTarget
		if currentTarget ~= nil and resolvePlayerFromTarget(currentTarget) ~= nil then
			self:clearTarget()
		end
	end

	if self._isResting then
		self.restElapsed = math.min(self.restDuration, self.restElapsed + dt)
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

function Slime._slimeOnDamage(self: Slime, source: any?)
	if self.passiveUntilHit and not self.hasBeenHit then
		self.hasBeenHit = true
	end

	if source ~= nil and self:isTargetValid(source) then
		self:setTarget(source)
	end
end

function Slime._slimeOnDeath(self: Slime)
	self:_disconnectHopMotionHeartbeat()
	self:_stopHopMotion(false)
	self._lastResolvedHopPosition = nil
	self._hopRaycastParams = nil
	self._hopOverlapParams = nil
end

function Slime.New(configRaw: SlimeConfig?): Slime
	local config = (
		if typeof(configRaw) == "table" then Sift.Dictionary.copy(configRaw :: any) else {} :: any
	) :: SlimeConfig & {
		[string]: any,
	}
	local baseBehavior = if typeof(config.behavior) == "table"
		then config.behavior :: NpcBehaviorConfig
		else {} :: NpcBehaviorConfig

	local movement = (
		if typeof(config.movement) == "table" then Sift.Dictionary.copy(config.movement) else {} :: any
	) :: {
		[string]: any,
	}
	if movement.canWander == nil then
		movement.canWander = false
	end
	if movement.thinkInterval == nil then
		movement.thinkInterval = 0.1
	end
	config.movement = movement

	local lifecycle = (
		if typeof(config.lifecycle) == "table" then Sift.Dictionary.copy(config.lifecycle) else {} :: any
	) :: {
		[string]: any,
	}
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
	local hopMotionSpringRaw = if typeof(config.hopMotionSpring) == "table" then config.hopMotionSpring else {} :: any
	local hopMotionSpring = {
		frequency = toNumber((hopMotionSpringRaw :: any).frequency, DEFAULT_HOP_SPRING_FREQUENCY, 0.01, 120),
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
	self._isResting = true
	self.restElapsed = 0
	self.hopElapsed = 0
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
	self._facingSign = 1
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

Slime.setAggroOnPlayer = Slime.SetAggroOnPlayer
Slime.new = Slime.New

return Slime
