--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local CFrameUtils = require("CFrameUtils")
local Maid = require("Maid")
local Rx = require("Rx")
local Signal = require("Signal")

local Angle = require(script:FindFirstAncestor("game").Shared.Modules.Math.Angle)
local Plane = require(script:FindFirstAncestor("game").Shared.Modules.Math.Plane)
local Vec = require(script:FindFirstAncestor("game").Shared.Modules.Math.Vec)

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> number,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

export type ObservableObject = {
	Subscribe: (
		self: ObservableObject,
		onNext: ((...any) -> ())?,
		onError: ((...any) -> ())?,
		onComplete: (() -> ())?
	) -> any,
	Pipe: (self: ObservableObject, transformers: { any }) -> ObservableObject,
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

export type LockedAxis = "X" | "Y" | "Z"
export type SegmentKind = "Head" | "Body" | "Tail"

export type WormTarget = Vector3 | CFrame | Instance | { [string]: any }
export type WormTargetProvider = ((self: Worm) -> WormTarget?) | { [string]: any }

export type WormSegment = {
	index: number,
	kind: SegmentKind,
	model: Model,
	rootPart: BasePart?,
	previous: WormSegment?,
	owner: Worm,
	ownerId: string,
}

export type WormSegmentTemplates = {
	Head: Model?,
	Body: Model?,
	Tail: Model?,
	head: Model?,
	body: Model?,
	tail: Model?,
}

export type WormCollisionConfig = {
	enabled: boolean?,
	raycastParams: RaycastParams?,
	params: RaycastParams?,
	filterDescendantsInstances: { Instance }?,
	excludeSegments: boolean?,
	lookAheadDistance: number?,
	avoidStrength: number?,
	blockMovement: boolean?,
	surfaceOffset: number?,
}

export type WormBehaviorConfig = {
	targetRefreshInterval: number?,
	idleDirection: Vector3?,
	maxDt: number?,
	canBurrow: boolean?,
}

export type WormConfig = {
	model: Model?,
	templates: WormSegmentTemplates?,
	headTemplate: Model?,
	bodyTemplate: Model?,
	tailTemplate: Model?,
	segmentModels: { Model }?,
	segmentCount: number?,
	bodySegmentCount: number?,
	segmentSpacing: number?,
	spawnParent: Instance?,
	segmentParent: Instance?,
	spawnCFrame: CFrame?,
	autoStart: boolean?,
	destroySegmentsOnDestroy: boolean?,
	anchorSegments: boolean?,
	canCollide: boolean?,
	canTouch: boolean?,
	canQuery: boolean?,
	serverOwned: boolean?,
	createSegmentLinks: boolean?,
	lockedAxis: LockedAxis?,
	lockAxis: LockedAxis?,
	depth: number?,
	lockedDepth: number?,
	planeDepth: number?,
	planeX: number?,
	planeY: number?,
	planeZ: number?,
	twoDPlaneX: number?,
	planeNormal: Vector3?,
	lookUpVector: Vector3?,
	initialDirection: Vector3?,
	speed: number?,
	movementSpeed: number?,
	turnSpeed: number?,
	turnSpeedDegrees: number?,
	acceleration: number?,
	target: WormTarget?,
	targetProvider: WormTargetProvider?,
	targetObservable: ObservableObject?,
	collision: WormCollisionConfig?,
	raycast: WormCollisionConfig?,
	behavior: WormBehaviorConfig?,
}

export type WormMotionSnapshot = {
	headCFrame: CFrame?,
	headPosition: Vector3?,
	velocity: Vector3,
	heading: Vector3,
	speed: number,
	dt: number,
	updatedAt: number,
}

export type WormSnapshot = {
	id: string,
	enabled: boolean,
	running: boolean,
	destroyed: boolean,
	head: Model?,
	segments: { WormSegment },
	segmentModels: { Model },
	segmentCount: number,
	segmentSpacing: number,
	target: WormTarget?,
	targetPosition: Vector3?,
	targetProvider: WormTargetProvider?,
	targetObservable: ObservableObject?,
	headCFrame: CFrame?,
	headPosition: Vector3?,
	velocity: Vector3,
	heading: Vector3,
	speed: number,
	updatedAt: number,
}

type WormSignals = {
	started: SignalObject,
	stopped: SignalObject,
	runningChanged: SignalObject,
	enabledChanged: SignalObject,
	targetChanged: SignalObject,
	targetProviderChanged: SignalObject,
	targetObservableChanged: SignalObject,
	segmentsChanged: SignalObject,
	motionChanged: SignalObject,
	stepped: SignalObject,
	destroying: SignalObject,
	destroyedChanged: SignalObject,
	destroyed: SignalObject,
}

local Worm = {}
Worm.__index = Worm

local DEFAULT_SEGMENT_COUNT = 12
local DEFAULT_SEGMENT_SPACING = 4
local DEFAULT_SPEED = 18
local DEFAULT_TURN_SPEED = math.rad(220)
local DEFAULT_ACCELERATION = 80
local DEFAULT_TARGET_REFRESH_INTERVAL = 0.1
local DEFAULT_MAX_DT = 1 / 15
local DEFAULT_LOOK_AHEAD_DISTANCE = 8
local DEFAULT_AVOID_STRENGTH = 1.8
local DEFAULT_SURFACE_OFFSET = 0.1
local SEGMENT_LINK_OWNER_NAME = "WormOwner"
local SEGMENT_LINK_PREVIOUS_NAME = "WormPreviousSegment"

local AXIS_NORMALS: { [LockedAxis]: Vector3 } = {
	X = Vector3.xAxis,
	Y = Vector3.yAxis,
	Z = Vector3.zAxis,
}

local function createSignals(): WormSignals
	return {
		started = Signal.new() :: any,
		stopped = Signal.new() :: any,
		runningChanged = Signal.new() :: any,
		enabledChanged = Signal.new() :: any,
		targetChanged = Signal.new() :: any,
		targetProviderChanged = Signal.new() :: any,
		targetObservableChanged = Signal.new() :: any,
		segmentsChanged = Signal.new() :: any,
		motionChanged = Signal.new() :: any,
		stepped = Signal.new() :: any,
		destroying = Signal.new() :: any,
		destroyedChanged = Signal.new() :: any,
		destroyed = Signal.new() :: any,
	}
end

local function destroySignals(signals: WormSignals)
	for _, signal in pairs(signals) do
		signal:Destroy()
	end
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	return math.floor(sanitizeNumber(valueRaw, fallback, minimum, maximum))
end

local function resolveLockedAxis(valueRaw: any): LockedAxis
	if typeof(valueRaw) == "string" then
		local upper = string.upper(valueRaw)
		if upper == "X" then
			return "X"
		elseif upper == "Y" then
			return "Y"
		elseif upper == "Z" then
			return "Z"
		end
	end
	return "X"
end

local function resolveAxisDepth(config: WormConfig, axis: LockedAxis): number?
	local lockedDepth = config.lockedDepth or config.depth or config.planeDepth
	if typeof(lockedDepth) == "number" and lockedDepth == lockedDepth then
		return lockedDepth
	end

	if axis == "X" then
		local planeX = config.planeX or config.twoDPlaneX
		if typeof(planeX) == "number" and planeX == planeX then
			return planeX
		end
	elseif axis == "Y" then
		if typeof(config.planeY) == "number" and config.planeY == config.planeY then
			return config.planeY
		end
	elseif typeof(config.planeZ) == "number" and config.planeZ == config.planeZ then
		return config.planeZ
	end

	return nil
end

local function getAxisValue(position: Vector3, axis: LockedAxis): number
	if axis == "X" then
		return position.X
	elseif axis == "Y" then
		return position.Y
	end
	return position.Z
end

local function withAxisValue(position: Vector3, axis: LockedAxis, value: number): Vector3
	if axis == "X" then
		return Vector3.new(value, position.Y, position.Z)
	elseif axis == "Y" then
		return Vector3.new(position.X, value, position.Z)
	end
	return Vector3.new(position.X, position.Y, value)
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

local function resolveTemplateFromContainer(container: Model?, segmentName: string): Model?
	if container == nil then
		return nil
	end

	local direct = container:FindFirstChild(segmentName)
	if direct and direct:IsA("Model") then
		return direct
	end

	local segmentNameLower = string.lower(segmentName)
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("Model") and string.lower(descendant.Name) == segmentNameLower then
			return descendant
		end
	end

	return nil
end

local function configureModelParts(
	model: Model,
	anchorParts: boolean,
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean
)
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		descendant.Anchored = anchorParts
		descendant.CanCollide = canCollide
		descendant.CanTouch = canTouch
		descendant.CanQuery = canQuery
	end
end

local function applyServerOwnership(model: Model)
	if not RunService:IsServer() then
		return
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end
end

local function resolvePositionFromTarget(target: WormTarget?): Vector3?
	if target == nil then
		return nil
	end

	if typeof(target) == "Vector3" then
		return target
	end

	if typeof(target) == "CFrame" then
		return target.Position
	end

	if typeof(target) == "table" then
		local getPosition = (target :: any).GetPosition or (target :: any).getPosition
		if typeof(getPosition) == "function" then
			local ok, positionOrError = pcall(getPosition, target)
			if ok and typeof(positionOrError) == "Vector3" then
				return positionOrError
			end
		end

		local position = (target :: any).Position or (target :: any).position
		if typeof(position) == "Vector3" then
			return position
		end
	end

	if typeof(target) ~= "Instance" then
		return nil
	end

	if target:IsA("BasePart") then
		return target.Position
	end

	if target:IsA("Attachment") then
		return target.WorldPosition
	end

	if target:IsA("Model") then
		local rootPart = resolveRootPart(target)
		if rootPart then
			return rootPart.Position
		end
		return target:GetPivot().Position
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

	if target:IsA("Player") then
		local character = (target :: Player).Character
		local rootPart = resolveRootPart(character)
		if rootPart then
			return rootPart.Position
		end
	end

	return nil
end

local function callTargetProvider(provider: WormTargetProvider?, self: Worm): WormTarget?
	if provider == nil then
		return nil
	end

	if typeof(provider) == "function" then
		local ok, targetOrError = pcall(provider, self)
		if ok then
			return targetOrError
		end
		return nil
	end

	if typeof(provider) ~= "table" then
		return nil
	end

	local getTarget = (provider :: any).GetTarget or (provider :: any).getTarget
	if typeof(getTarget) == "function" then
		local ok, targetOrError = pcall(getTarget, provider, self)
		if ok then
			return targetOrError
		end
	end

	local getPosition = (provider :: any).GetPosition or (provider :: any).getPosition
	if typeof(getPosition) == "function" then
		local ok, positionOrError = pcall(getPosition, provider, self)
		if ok and typeof(positionOrError) == "Vector3" then
			return positionOrError
		end
	end

	return nil
end

export type Worm = typeof(setmetatable(
	{} :: {
		id: string,
		_headTemplate: Model?,
		_bodyTemplate: Model?,
		_tailTemplate: Model?,
		_segmentModels: { Model }?,
		_segmentCount: number,
		_segmentSpacing: number,
		_spawnParent: Instance,
		_segmentParent: Instance?,
		_spawnCFrame: CFrame?,
		_destroySegmentsOnDestroy: boolean,
		_anchorSegments: boolean,
		_canCollide: boolean,
		_canTouch: boolean,
		_canQuery: boolean,
		_serverOwned: boolean,
		_createSegmentLinks: boolean,
		_lockedAxis: LockedAxis?,
		_lockedDepth: number?,
		_planeNormal: Vector3,
		_planeDistance: number?,
		_lookUpVector: Vector3,
		_initialDirection: Vector3,
		_heading: Vector3,
		_velocity: Vector3,
		_speed: number,
		_turnSpeed: number,
		_acceleration: number,
		_target: WormTarget?,
		_targetProvider: WormTargetProvider?,
		_targetObservable: ObservableObject?,
		_targetRefreshInterval: number,
		_targetRefreshElapsed: number,
		_collisionEnabled: boolean,
		_collisionRaycastParams: RaycastParams?,
		_collisionFilterDescendants: { Instance }?,
		_collisionExcludeSegments: boolean,
		_collisionLookAheadDistance: number,
		_collisionAvoidStrength: number,
		_collisionBlockMovement: boolean,
		_collisionSurfaceOffset: number,
		_canBurrow: boolean,
		_maxDt: number,
		_enabled: boolean,
		_isRunning: boolean,
		_isDestroyed: boolean,
		_ownsSegments: boolean,
		_head: WormSegment?,
		_segments: { WormSegment },
		_signals: WormSignals,
		_observables: { [string]: ObservableObject },
		_maid: MaidClass,
		_stepMaid: MaidClass,
		_targetObservableMaid: MaidClass,
	},
	Worm
))

local function resolveLookUpVector(self: Worm, directionRaw: Vector3): Vector3
	local direction = Vec.unit(directionRaw, self._heading)
	local lookUpVector = Vec.unit(self._lookUpVector, Vector3.yAxis)
	if math.abs(lookUpVector:Dot(direction)) < 0.98 then
		return lookUpVector
	end

	local planeNormal = Vec.unit(self._planeNormal, Vector3.xAxis)
	if math.abs(planeNormal:Dot(direction)) < 0.98 then
		return planeNormal
	end

	return Vec.orthogonal(direction)
end

local function cloneSegments(segments: { WormSegment }): { WormSegment }
	local copy = table.create(#segments)
	for index, segment in ipairs(segments) do
		copy[index] = segment
	end
	return copy
end

local function cloneSegmentModels(segments: { WormSegment }): { Model }
	local models = table.create(#segments)
	for index, segment in ipairs(segments) do
		models[index] = segment.model
	end
	return models
end

function Worm._getOrCreateObservable(self: Worm, key: string, create: () -> ObservableObject): ObservableObject
	local cached = self._observables[key]
	if cached then
		return cached
	end

	local observable = create()
	self._observables[key] = observable
	return observable
end

function Worm._observeEventSignal(self: Worm, key: string, signal: SignalObject): ObservableObject
	return self:_getOrCreateObservable(key, function()
		return Rx.fromSignal(signal):Pipe({
			Rx.share(),
		})
	end)
end

function Worm._observeStateSignal(
	self: Worm,
	key: string,
	signal: SignalObject,
	getCurrent: () -> any
): ObservableObject
	return self:_getOrCreateObservable(key, function()
		return Rx.fromSignal(signal):Pipe({
			Rx.map(function()
				return getCurrent()
			end),
			Rx.start(getCurrent),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.GetMotionSnapshot(self: Worm, dt: number?): WormMotionSnapshot
	local head = self._head
	local headCFrame = if head then head.model:GetPivot() else nil

	return {
		headCFrame = headCFrame,
		headPosition = if headCFrame then headCFrame.Position else nil,
		velocity = self._velocity,
		heading = self._heading,
		speed = self._velocity.Magnitude,
		dt = dt or 0,
		updatedAt = os.clock(),
	}
end

function Worm.GetSnapshot(self: Worm): WormSnapshot
	local segments = self:GetSegments()
	local motion = self:GetMotionSnapshot()

	return {
		id = self.id,
		enabled = self._enabled,
		running = self._isRunning,
		destroyed = self._isDestroyed,
		head = self:GetHead(),
		segments = segments,
		segmentModels = cloneSegmentModels(segments),
		segmentCount = #segments,
		segmentSpacing = self._segmentSpacing,
		target = self._target,
		targetPosition = resolvePositionFromTarget(self._target),
		targetProvider = self._targetProvider,
		targetObservable = self._targetObservable,
		headCFrame = motion.headCFrame,
		headPosition = motion.headPosition,
		velocity = motion.velocity,
		heading = motion.heading,
		speed = motion.speed,
		updatedAt = motion.updatedAt,
	}
end

function Worm._projectPosition(self: Worm, position: Vector3): Vector3
	local lockedAxis = self._lockedAxis
	local lockedDepth = self._lockedDepth
	if lockedAxis ~= nil and lockedDepth ~= nil then
		return withAxisValue(position, lockedAxis, lockedDepth)
	end

	local planeDistance = self._planeDistance
	if planeDistance == nil then
		return position
	end

	return Plane.closestPoint({
		normal = self._planeNormal,
		distance = planeDistance,
	}, position)
end

function Worm._projectDirection(self: Worm, direction: Vector3): Vector3
	local planeNormal = self._planeNormal
	return direction - planeNormal * direction:Dot(planeNormal)
end

function Worm._ensurePlaneDepth(self: Worm, position: Vector3)
	if self._lockedDepth == nil and self._lockedAxis ~= nil then
		self._lockedDepth = getAxisValue(position, self._lockedAxis)
	end

	if self._planeDistance == nil then
		self._planeDistance = self._planeNormal:Dot(position)
	end
end

function Worm._createSegmentCFrame(self: Worm, positionRaw: Vector3, directionRaw: Vector3): CFrame
	local position = self:_projectPosition(positionRaw)
	local direction = Vec.unit(self:_projectDirection(directionRaw), self._heading)
	local lookTarget = position + direction
	return CFrameUtils.lookAt(position, lookTarget, resolveLookUpVector(self, direction))
end

function Worm._pivotSegment(self: Worm, segment: WormSegment, cframeRaw: CFrame)
	local position = self:_projectPosition(cframeRaw.Position)
	local direction = self:_projectDirection(cframeRaw.LookVector)
	local cframe = self:_createSegmentCFrame(position, direction)

	segment.model:PivotTo(cframe)

	local rootPart = segment.rootPart
	if rootPart ~= nil then
		local velocity = rootPart.AssemblyLinearVelocity
		local angularVelocity = rootPart.AssemblyAngularVelocity
		if velocity.Magnitude > 0 then
			rootPart.AssemblyLinearVelocity = self:_projectDirection(velocity)
		end
		if angularVelocity.Magnitude > 0 then
			rootPart.AssemblyAngularVelocity = self:_projectDirection(angularVelocity)
		end
	end
end

function Worm._refreshCollisionRaycastParams(self: Worm)
	if self._canBurrow or not self._collisionEnabled then
		self._collisionRaycastParams = nil
		return
	end

	if self._collisionRaycastParams ~= nil then
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = false

	local filter = {}
	for _, instance in self._collisionFilterDescendants do
		table.insert(filter, instance)
	end

	if self._collisionExcludeSegments then
		for _, segment in self._segments do
			table.insert(filter, segment.model)
		end
	end

	raycastParams.FilterDescendantsInstances = filter
	self._collisionRaycastParams = raycastParams
end

function Worm._resolveHeadDirection(self: Worm, headPosition: Vector3, dt: number): Vector3
	self._targetRefreshElapsed += dt
	if
		self._targetProvider ~= nil
		and (self._target == nil or self._targetRefreshElapsed >= self._targetRefreshInterval)
	then
		self._targetRefreshElapsed = 0
		local previousTarget = self._target
		local nextTarget = callTargetProvider(self._targetProvider, self)
		if nextTarget ~= previousTarget then
			self._target = nextTarget
			self._signals.targetChanged:Fire(nextTarget, previousTarget)
		end
	end

	local targetPosition = resolvePositionFromTarget(self._target)
	if targetPosition == nil then
		return Vec.unit(self:_projectDirection(self._heading), self._initialDirection)
	end

	local projectedTargetPosition = self:_projectPosition(targetPosition)
	local desiredDirection = self:_projectDirection(projectedTargetPosition - headPosition)
	return Vec.unit(desiredDirection, self._heading)
end

function Worm._applyTerrainAvoidance(self: Worm, position: Vector3, desiredDirection: Vector3): Vector3
	if self._canBurrow or not self._collisionEnabled then
		return desiredDirection
	end

	self:_refreshCollisionRaycastParams()
	local raycastParams = self._collisionRaycastParams
	if raycastParams == nil then
		return desiredDirection
	end

	local castDirection = Vec.unit(desiredDirection, self._heading) * self._collisionLookAheadDistance
	local hit = Workspace:Raycast(position, castDirection, raycastParams)
	if hit == nil then
		return desiredDirection
	end

	local projectedNormal = self:_projectDirection(hit.Normal)
	if projectedNormal.Magnitude <= 0.001 then
		return desiredDirection
	end

	local avoidedDirection = desiredDirection + projectedNormal.Unit * self._collisionAvoidStrength
	return Vec.unit(self:_projectDirection(avoidedDirection), desiredDirection)
end

function Worm._rotateDirectionToward(
	self: Worm,
	currentDirectionRaw: Vector3,
	desiredDirectionRaw: Vector3,
	dt: number
): Vector3
	local currentDirection = Vec.unit(self:_projectDirection(currentDirectionRaw), self._heading)
	local desiredDirection = Vec.unit(self:_projectDirection(desiredDirectionRaw), currentDirection)
	local angle = Angle.signed3D(currentDirection, desiredDirection, self._planeNormal)
	local maxAngle = self._turnSpeed * dt

	if math.abs(angle) <= maxAngle then
		return desiredDirection
	end

	local stepAngle = math.sign(angle) * maxAngle
	local rotatedDirection = CFrame.fromAxisAngle(self._planeNormal, stepAngle):VectorToWorldSpace(currentDirection)
	return Vec.unit(self:_projectDirection(rotatedDirection), desiredDirection)
end

function Worm._resolveBlockedHeadPosition(self: Worm, previousPosition: Vector3, desiredPosition: Vector3): Vector3
	if self._canBurrow or not self._collisionEnabled or not self._collisionBlockMovement then
		return desiredPosition
	end

	self:_refreshCollisionRaycastParams()
	local raycastParams = self._collisionRaycastParams
	if raycastParams == nil then
		return desiredPosition
	end

	local delta = desiredPosition - previousPosition
	if delta.Magnitude <= 0.001 then
		return desiredPosition
	end

	local hit = Workspace:Raycast(previousPosition, delta, raycastParams)
	if hit == nil then
		return desiredPosition
	end

	local safeDistance = math.max(0, hit.Distance - self._collisionSurfaceOffset)
	return self:_projectPosition(previousPosition + delta.Unit * safeDistance)
end

function Worm._updateHead(self: Worm, dt: number)
	local head = self._head
	if head == nil then
		return
	end

	local headPosition = self:_projectPosition(head.model:GetPivot().Position)
	local desiredDirection = self:_resolveHeadDirection(headPosition, dt)
	desiredDirection = self:_applyTerrainAvoidance(headPosition, desiredDirection)

	local currentDirection = if self._velocity.Magnitude > 0.001 then self._velocity else self._heading
	local steeredDirection = self:_rotateDirectionToward(currentDirection, desiredDirection, dt)
	local desiredVelocity = steeredDirection * self._speed
	self._velocity = Vec.moveTowards(self:_projectDirection(self._velocity), desiredVelocity, self._acceleration * dt)
	self._velocity = self:_projectDirection(self._velocity)

	local moveDirection = if self._velocity.Magnitude > 0.001 then self._velocity.Unit else steeredDirection
	self._heading = Vec.unit(self:_projectDirection(moveDirection), self._heading)

	local desiredPosition = self:_projectPosition(headPosition + self._velocity * dt)
	local resolvedPosition = self:_resolveBlockedHeadPosition(headPosition, desiredPosition)
	if (resolvedPosition - desiredPosition).Magnitude > 0.001 then
		self._velocity = Vector3.zero
	end

	self:_pivotSegment(head, self:_createSegmentCFrame(resolvedPosition, self._heading))
end

function Worm._updateFollowerSegments(self: Worm)
	for index = 2, #self._segments do
		local segment = self._segments[index]
		local previous = segment.previous
		if previous == nil then
			continue
		end

		local previousPosition = self:_projectPosition(previous.model:GetPivot().Position)
		local currentPosition = self:_projectPosition(segment.model:GetPivot().Position)
		local direction = self:_projectDirection(previousPosition - currentPosition)
		if direction.Magnitude <= 0.001 then
			direction = self:_projectDirection(previous.model:GetPivot().LookVector)
		end

		direction = Vec.unit(direction, self._heading)
		local nextPosition = previousPosition - direction * self._segmentSpacing
		self:_pivotSegment(segment, self:_createSegmentCFrame(nextPosition, direction))
	end
end

function Worm._step(self: Worm, dtRaw: number)
	if self._isDestroyed or not self._isRunning or not self._enabled then
		return
	end

	local dt = math.min(math.max(dtRaw, 0), self._maxDt)
	if dt <= 0 then
		return
	end

	self:_updateHead(dt)
	self:_updateFollowerSegments()

	local motion = self:GetMotionSnapshot(dt)
	self._signals.motionChanged:Fire(motion)
	self._signals.stepped:Fire(dt, motion)
end

function Worm._resolveSegmentTemplates(config: WormConfig): (Model?, Model?, Model?)
	local templates = if typeof(config.templates) == "table" then config.templates else nil
	local container = config.model

	local headTemplate = config.headTemplate
	if headTemplate == nil and templates ~= nil then
		headTemplate = templates.Head or templates.head
	end
	if headTemplate == nil then
		headTemplate = resolveTemplateFromContainer(container, "Head")
	end

	local bodyTemplate = config.bodyTemplate
	if bodyTemplate == nil and templates ~= nil then
		bodyTemplate = templates.Body or templates.body
	end
	if bodyTemplate == nil then
		bodyTemplate = resolveTemplateFromContainer(container, "Body")
	end

	local tailTemplate = config.tailTemplate
	if tailTemplate == nil and templates ~= nil then
		tailTemplate = templates.Tail or templates.tail
	end
	if tailTemplate == nil then
		tailTemplate = resolveTemplateFromContainer(container, "Tail")
	end

	return headTemplate, bodyTemplate, tailTemplate
end

function Worm._clearSegments(self: Worm)
	for _, segment in self._segments do
		if self._ownsSegments and segment.model ~= nil then
			segment.model:Destroy()
		end
	end

	table.clear(self._segments)
	self._head = nil
	self._collisionRaycastParams = nil
end

function Worm._createSegmentLink(model: Model, linkName: string, value: Instance?)
	local existing = model:FindFirstChild(linkName)
	if existing and existing:IsA("ObjectValue") then
		existing.Value = value
		return
	end

	local objectValue = Instance.new("ObjectValue")
	objectValue.Name = linkName
	objectValue.Value = value
	objectValue.Parent = model
end

function Worm._createSegment(
	self: Worm,
	template: Model,
	kind: SegmentKind,
	index: number,
	previous: WormSegment?
): WormSegment
	local model = template:Clone()
	model.Name = if kind == "Head"
		then "WormHead"
		else if kind == "Tail" then "WormTail" else "WormBody" .. tostring(index - 1)
	model.Parent = self._segmentParent or self._spawnParent

	local rootPart = resolveRootPart(model)
	if model.PrimaryPart == nil and rootPart ~= nil then
		model.PrimaryPart = rootPart
	end

	configureModelParts(model, self._anchorSegments, self._canCollide, self._canTouch, self._canQuery)
	if self._serverOwned then
		applyServerOwnership(model)
	end

	model:SetAttribute("WormOwnerId", self.id)
	model:SetAttribute("WormSegmentIndex", index)
	model:SetAttribute("WormSegmentKind", kind)
	model:SetAttribute("WormPreviousIndex", if previous ~= nil then previous.index else nil)

	local segment: WormSegment = {
		index = index,
		kind = kind,
		model = model,
		rootPart = rootPart,
		previous = previous,
		owner = self,
		ownerId = self.id,
	}

	if self._createSegmentLinks then
		local ownerModel = if self._head ~= nil then self._head.model else model
		Worm._createSegmentLink(model, SEGMENT_LINK_OWNER_NAME, ownerModel)
		Worm._createSegmentLink(model, SEGMENT_LINK_PREVIOUS_NAME, if previous ~= nil then previous.model else nil)
	end

	return segment
end

function Worm._useExistingSegments(self: Worm, segmentModels: { Model }): boolean
	if #segmentModels < 2 then
		return false
	end

	for index, model in segmentModels do
		if typeof(model) ~= "Instance" or not model:IsA("Model") then
			return false
		end

		local kind: SegmentKind = if index == 1 then "Head" else if index == #segmentModels then "Tail" else "Body"
		local previous = self._segments[index - 1]
		local rootPart = resolveRootPart(model)
		if model.PrimaryPart == nil and rootPart ~= nil then
			model.PrimaryPart = rootPart
		end

		local segment: WormSegment = {
			index = index,
			kind = kind,
			model = model,
			rootPart = rootPart,
			previous = previous,
			owner = self,
			ownerId = self.id,
		}

		model:SetAttribute("WormOwnerId", self.id)
		model:SetAttribute("WormSegmentIndex", index)
		model:SetAttribute("WormSegmentKind", kind)
		model:SetAttribute("WormPreviousIndex", if previous ~= nil then previous.index else nil)
		table.insert(self._segments, segment)

		if index == 1 then
			self._head = segment
		end
	end

	if self._createSegmentLinks and self._head ~= nil then
		for _, segment in self._segments do
			Worm._createSegmentLink(segment.model, SEGMENT_LINK_OWNER_NAME, self._head.model)
			Worm._createSegmentLink(
				segment.model,
				SEGMENT_LINK_PREVIOUS_NAME,
				if segment.previous ~= nil then segment.previous.model else nil
			)
		end
	end

	self._segmentCount = #self._segments
	self._ownsSegments = false
	return true
end

function Worm._buildSegments(self: Worm, spawnCFrame: CFrame)
	if #self._segments > 0 then
		return
	end

	local segmentModels = self._segmentModels
	local usedExistingSegments = false
	if segmentModels ~= nil then
		usedExistingSegments = self:_useExistingSegments(segmentModels)
	end

	if not usedExistingSegments then
		local headTemplate = assert(self._headTemplate, "Worm requires a Head model template")
		local bodyTemplate = assert(self._bodyTemplate, "Worm requires a Body model template")
		local tailTemplate = assert(self._tailTemplate, "Worm requires a Tail model template")

		for index = 1, self._segmentCount do
			local kind: SegmentKind = if index == 1
				then "Head"
				else if index == self._segmentCount then "Tail" else "Body"
			local template = if kind == "Head"
				then headTemplate
				else if kind == "Tail" then tailTemplate else bodyTemplate
			local previous = self._segments[index - 1]
			local segment = self:_createSegment(template, kind, index, previous)
			table.insert(self._segments, segment)
			if kind == "Head" then
				self._head = segment
			end
		end

		self._ownsSegments = true
	end

	if self._createSegmentLinks and self._head ~= nil then
		for _, segment in self._segments do
			Worm._createSegmentLink(segment.model, SEGMENT_LINK_OWNER_NAME, self._head.model)
		end
	end

	local startPosition = self:_projectPosition(spawnCFrame.Position)
	local startDirection = Vec.unit(self:_projectDirection(spawnCFrame.LookVector), self._initialDirection)
	self._heading = startDirection

	for index, segment in self._segments do
		local segmentPosition = startPosition - startDirection * self._segmentSpacing * (index - 1)
		self:_pivotSegment(segment, self:_createSegmentCFrame(segmentPosition, startDirection))
	end
end

function Worm.New(configRaw: WormConfig?): Worm
	local config = if typeof(configRaw) == "table" then configRaw :: WormConfig else {} :: WormConfig
	local lockedAxis = resolveLockedAxis(config.lockedAxis or config.lockAxis)
	local lockedDepth = resolveAxisDepth(config, lockedAxis)
	local planeNormal = if typeof(config.planeNormal) == "Vector3" and config.planeNormal.Magnitude > 0
		then config.planeNormal.Unit
		else AXIS_NORMALS[lockedAxis]
	local collisionConfig: WormCollisionConfig = if typeof(config.collision) == "table"
		then config.collision :: WormCollisionConfig
		else if typeof(config.raycast) == "table"
			then config.raycast :: WormCollisionConfig
			else {} :: WormCollisionConfig
	local behaviorConfig: WormBehaviorConfig = if typeof(config.behavior) == "table"
		then config.behavior :: WormBehaviorConfig
		else {} :: WormBehaviorConfig
	local speed = sanitizeNumber(config.movementSpeed or config.speed, DEFAULT_SPEED, 0, nil)
	local turnSpeed = if typeof(config.turnSpeedDegrees) == "number"
		then math.rad(config.turnSpeedDegrees)
		else sanitizeNumber(config.turnSpeed, DEFAULT_TURN_SPEED, 0, nil)
	local acceleration = sanitizeNumber(config.acceleration, DEFAULT_ACCELERATION, 0, nil)
	local bodySegmentCount = config.bodySegmentCount
	local segmentCount = if typeof(bodySegmentCount) == "number"
		then math.max(2, math.floor(bodySegmentCount) + 2)
		else sanitizeInteger(config.segmentCount, DEFAULT_SEGMENT_COUNT, 2, 512)
	local headTemplate, bodyTemplate, tailTemplate = Worm._resolveSegmentTemplates(config)
	local fallbackDirection = Vec.orthogonal(planeNormal)
	local initialDirection = if typeof(config.initialDirection) == "Vector3"
			and config.initialDirection.Magnitude > 0
		then config.initialDirection.Unit
		else if typeof(behaviorConfig.idleDirection) == "Vector3"
				and behaviorConfig.idleDirection.Magnitude > 0
			then behaviorConfig.idleDirection.Unit
			else fallbackDirection
	initialDirection = Vec.unit(initialDirection - planeNormal * initialDirection:Dot(planeNormal), fallbackDirection)
	local collisionEnabled = sanitizeBoolean(collisionConfig.enabled, false)
	local segmentModels: { Model }? = if typeof(config.segmentModels) == "table" then config.segmentModels else nil
	local segmentSpacing: number = sanitizeNumber(config.segmentSpacing, DEFAULT_SEGMENT_SPACING, 0.05, nil)
	local spawnParent: Instance = if typeof(config.spawnParent) == "Instance" then config.spawnParent else Workspace
	local segmentParent: Instance? = if typeof(config.segmentParent) == "Instance" then config.segmentParent else nil
	local spawnCFrame: CFrame? = if typeof(config.spawnCFrame) == "CFrame" then config.spawnCFrame else nil
	local destroySegmentsOnDestroy: boolean = sanitizeBoolean(config.destroySegmentsOnDestroy, true)
	local anchorSegments: boolean = sanitizeBoolean(config.anchorSegments, true)
	local canCollide: boolean = sanitizeBoolean(config.canCollide, false)
	local canTouch: boolean = sanitizeBoolean(config.canTouch, true)
	local canQuery: boolean = sanitizeBoolean(config.canQuery, true)
	local serverOwned: boolean = sanitizeBoolean(config.serverOwned, true)
	local createSegmentLinks: boolean = sanitizeBoolean(config.createSegmentLinks, true)
	local lookUpVector: Vector3 = if typeof(config.lookUpVector) == "Vector3"
			and config.lookUpVector.Magnitude > 0
		then config.lookUpVector.Unit
		else Vector3.yAxis
	local targetRefreshInterval: number =
		sanitizeNumber(behaviorConfig.targetRefreshInterval, DEFAULT_TARGET_REFRESH_INTERVAL, 0, nil)
	local collisionRaycastParams: RaycastParams? = collisionConfig.raycastParams or collisionConfig.params
	local collisionFilterDescendants: { Instance } = if typeof(collisionConfig.filterDescendantsInstances)
			== "table"
		then collisionConfig.filterDescendantsInstances
		else {}
	local collisionExcludeSegments: boolean = sanitizeBoolean(collisionConfig.excludeSegments, true)
	local collisionLookAheadDistance: number =
		sanitizeNumber(collisionConfig.lookAheadDistance, DEFAULT_LOOK_AHEAD_DISTANCE, 0.1, nil)
	local collisionAvoidStrength: number = sanitizeNumber(collisionConfig.avoidStrength, DEFAULT_AVOID_STRENGTH, 0, nil)
	local collisionBlockMovement: boolean = sanitizeBoolean(collisionConfig.blockMovement, false)
	local collisionSurfaceOffset: number = sanitizeNumber(collisionConfig.surfaceOffset, DEFAULT_SURFACE_OFFSET, 0, nil)
	local canBurrow: boolean = sanitizeBoolean(behaviorConfig.canBurrow, not collisionEnabled)
	local maxDt: number = sanitizeNumber(behaviorConfig.maxDt, DEFAULT_MAX_DT, 1 / 240, 1)
	local signals: WormSignals = createSignals()

	local self = setmetatable({
		id = HttpService:GenerateGUID(false),
		_headTemplate = headTemplate,
		_bodyTemplate = bodyTemplate,
		_tailTemplate = tailTemplate,
		_segmentModels = segmentModels,
		_segmentCount = segmentCount,
		_segmentSpacing = segmentSpacing,
		_spawnParent = spawnParent,
		_segmentParent = segmentParent,
		_spawnCFrame = spawnCFrame,
		_destroySegmentsOnDestroy = destroySegmentsOnDestroy,
		_anchorSegments = anchorSegments,
		_canCollide = canCollide,
		_canTouch = canTouch,
		_canQuery = canQuery,
		_serverOwned = serverOwned,
		_createSegmentLinks = createSegmentLinks,
		_lockedAxis = lockedAxis,
		_lockedDepth = lockedDepth,
		_planeNormal = planeNormal,
		_planeDistance = nil :: number?,
		_lookUpVector = lookUpVector,
		_initialDirection = initialDirection,
		_heading = initialDirection,
		_velocity = Vector3.zero,
		_speed = speed,
		_turnSpeed = turnSpeed,
		_acceleration = acceleration,
		_target = config.target,
		_targetProvider = config.targetProvider,
		_targetObservable = nil :: ObservableObject?,
		_targetRefreshInterval = targetRefreshInterval,
		_targetRefreshElapsed = math.huge,
		_collisionEnabled = collisionEnabled,
		_collisionRaycastParams = collisionRaycastParams,
		_collisionFilterDescendants = collisionFilterDescendants,
		_collisionExcludeSegments = collisionExcludeSegments,
		_collisionLookAheadDistance = collisionLookAheadDistance,
		_collisionAvoidStrength = collisionAvoidStrength,
		_collisionBlockMovement = collisionBlockMovement,
		_collisionSurfaceOffset = collisionSurfaceOffset,
		_canBurrow = canBurrow,
		_maxDt = maxDt,
		_enabled = true,
		_isRunning = false,
		_isDestroyed = false,
		_ownsSegments = false,
		_head = nil :: WormSegment?,
		_segments = {} :: { WormSegment },
		_signals = signals,
		_observables = {} :: { [string]: ObservableObject },
		_maid = Maid.new() :: MaidClass,
		_stepMaid = Maid.new() :: MaidClass,
		_targetObservableMaid = Maid.new() :: MaidClass,
	}, Worm) :: Worm

	self._maid:GiveTask(self._targetObservableMaid)
	self._maid:GiveTask(function()
		table.clear(self._observables)
		destroySignals(signals)
	end)

	if config.targetObservable ~= nil then
		self:SetTargetObservable(config.targetObservable)
	end

	if config.autoStart == true then
		self:Start(config.spawnCFrame)
	end

	return self
end

function Worm.Start(self: Worm, spawnCFrameRaw: CFrame?): Model?
	if self._isDestroyed then
		return nil
	end
	if self._isRunning then
		return if self._head ~= nil then self._head.model else nil
	end

	local spawnCFrame = spawnCFrameRaw or self._spawnCFrame or CFrame.new()
	self:_ensurePlaneDepth(spawnCFrame.Position)
	self:_buildSegments(spawnCFrame)
	self._isRunning = true
	self._stepMaid:DoCleaning()
	self._stepMaid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
		self:_step(dt)
	end))

	local headModel = if self._head ~= nil then self._head.model else nil
	self._signals.segmentsChanged:Fire(self:GetSegments())
	self._signals.runningChanged:Fire(true)
	self._signals.started:Fire(headModel)
	self._signals.motionChanged:Fire(self:GetMotionSnapshot(0))

	return headModel
end

function Worm.Stop(self: Worm, removeSegments: boolean?)
	if self._isDestroyed then
		return
	end

	local wasRunning = self._isRunning
	self._stepMaid:DoCleaning()
	self._isRunning = false
	self._velocity = Vector3.zero
	self._signals.motionChanged:Fire(self:GetMotionSnapshot(0))

	if removeSegments == true then
		self:_clearSegments()
		self._signals.segmentsChanged:Fire(self:GetSegments())
	end

	if wasRunning then
		self._signals.runningChanged:Fire(false)
		self._signals.stopped:Fire(removeSegments == true)
	end
end

function Worm.Destroy(self: Worm)
	if self._isDestroyed then
		return
	end

	self._signals.destroying:Fire()
	self:Stop(false)
	self._isDestroyed = true
	self._targetObservableMaid:DoCleaning()
	self._signals.destroyedChanged:Fire(true)
	self._stepMaid:Destroy()

	if self._destroySegmentsOnDestroy then
		self:_clearSegments()
		self._signals.segmentsChanged:Fire(self:GetSegments())
	end

	self._signals.destroyed:Fire()
	self._maid:Destroy()
end

function Worm.SetTarget(self: Worm, target: WormTarget?)
	local previousTarget = self._target
	if previousTarget == target then
		self._targetRefreshElapsed = math.huge
		return
	end

	self._target = target
	self._targetRefreshElapsed = math.huge
	self._signals.targetChanged:Fire(target, previousTarget)
end

function Worm.SetTargetProvider(self: Worm, targetProvider: WormTargetProvider?)
	local previousProvider = self._targetProvider
	if previousProvider == targetProvider then
		self._targetRefreshElapsed = math.huge
		return
	end

	self._targetProvider = targetProvider
	self._targetRefreshElapsed = math.huge
	self._signals.targetProviderChanged:Fire(targetProvider, previousProvider)
end

function Worm.SetTargetObservable(self: Worm, targetObservable: ObservableObject?)
	local previousObservable = self._targetObservable
	if previousObservable == targetObservable then
		return
	end

	self._targetObservableMaid:DoCleaning()
	self._targetObservable = targetObservable
	self._signals.targetObservableChanged:Fire(targetObservable, previousObservable)

	if targetObservable ~= nil then
		self._targetObservableMaid:GiveTask(targetObservable:Subscribe(function(target: WormTarget?)
			self:SetTarget(target)
		end))
	end
end

function Worm.GetHead(self: Worm): Model?
	local head = self._head
	return if head ~= nil then head.model else nil
end

function Worm.GetSegments(self: Worm): { WormSegment }
	local segments = table.create(#self._segments)
	for index, segment in self._segments do
		segments[index] = segment
	end
	return segments
end

function Worm.SetEnabled(self: Worm, enabled: boolean)
	if self._enabled == enabled then
		return
	end

	self._enabled = enabled
	if not enabled then
		self._velocity = Vector3.zero
		self._signals.motionChanged:Fire(self:GetMotionSnapshot(0))
	end
	self._signals.enabledChanged:Fire(enabled)
end

function Worm.ObserveStarted(self: Worm): ObservableObject
	return self:_observeEventSignal("started", self._signals.started)
end

function Worm.ObserveStopped(self: Worm): ObservableObject
	return self:_observeEventSignal("stopped", self._signals.stopped)
end

function Worm.ObserveDestroying(self: Worm): ObservableObject
	return self:_observeEventSignal("destroying", self._signals.destroying)
end

function Worm.ObserveStepped(self: Worm): ObservableObject
	return self:_observeEventSignal("stepped", self._signals.stepped)
end

function Worm.ObserveEnabled(self: Worm): ObservableObject
	return self:_observeStateSignal("enabled", self._signals.enabledChanged, function()
		return self._enabled
	end)
end

function Worm.ObserveRunning(self: Worm): ObservableObject
	return self:_observeStateSignal("running", self._signals.runningChanged, function()
		return self._isRunning
	end)
end

function Worm.ObserveDestroyed(self: Worm): ObservableObject
	return self:_observeStateSignal("destroyed", self._signals.destroyedChanged, function()
		return self._isDestroyed
	end)
end

function Worm.ObserveTarget(self: Worm): ObservableObject
	return self:_observeStateSignal("target", self._signals.targetChanged, function()
		return self._target
	end)
end

function Worm.ObserveTargetProvider(self: Worm): ObservableObject
	return self:_observeStateSignal("targetProvider", self._signals.targetProviderChanged, function()
		return self._targetProvider
	end)
end

function Worm.ObserveTargetObservable(self: Worm): ObservableObject
	return self:_observeStateSignal("targetObservable", self._signals.targetObservableChanged, function()
		return self._targetObservable
	end)
end

function Worm.ObserveSegments(self: Worm): ObservableObject
	return self:_observeStateSignal("segments", self._signals.segmentsChanged, function()
		return cloneSegments(self._segments)
	end)
end

function Worm.ObserveSegment(self: Worm, segmentIndex: number): ObservableObject
	return self:_getOrCreateObservable("segment:" .. tostring(segmentIndex), function()
		return self:ObserveSegments():Pipe({
			Rx.map(function(segments: { WormSegment })
				return segments[segmentIndex]
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveSegmentModels(self: Worm): ObservableObject
	return self:_getOrCreateObservable("segmentModels", function()
		return self:ObserveSegments():Pipe({
			Rx.map(function(segments: { WormSegment })
				return cloneSegmentModels(segments)
			end),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveHead(self: Worm): ObservableObject
	return self:_getOrCreateObservable("head", function()
		return self:ObserveSegment(1):Pipe({
			Rx.map(function(segment: WormSegment?)
				return if segment then segment.model else nil
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveMotion(self: Worm): ObservableObject
	return self:_getOrCreateObservable("motion", function()
		return Rx.fromSignal(self._signals.motionChanged):Pipe({
			Rx.start(function()
				return self:GetMotionSnapshot()
			end),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveHeadCFrame(self: Worm): ObservableObject
	return self:_getOrCreateObservable("headCFrame", function()
		return self:ObserveMotion():Pipe({
			Rx.map(function(motion: WormMotionSnapshot)
				return motion.headCFrame
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveHeadPosition(self: Worm): ObservableObject
	return self:_getOrCreateObservable("headPosition", function()
		return self:ObserveMotion():Pipe({
			Rx.map(function(motion: WormMotionSnapshot)
				return motion.headPosition
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveVelocity(self: Worm): ObservableObject
	return self:_getOrCreateObservable("velocity", function()
		return self:ObserveMotion():Pipe({
			Rx.map(function(motion: WormMotionSnapshot)
				return motion.velocity
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveHeading(self: Worm): ObservableObject
	return self:_getOrCreateObservable("heading", function()
		return self:ObserveMotion():Pipe({
			Rx.map(function(motion: WormMotionSnapshot)
				return motion.heading
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveSpeed(self: Worm): ObservableObject
	return self:_getOrCreateObservable("speed", function()
		return self:ObserveMotion():Pipe({
			Rx.map(function(motion: WormMotionSnapshot)
				return motion.speed
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveTargetPosition(self: Worm): ObservableObject
	return self:_getOrCreateObservable("targetPosition", function()
		return Rx.combineLatestDefer({
			target = self:ObserveTarget(),
			motion = self:ObserveMotion(),
		}):Pipe({
			Rx.map(function()
				return resolvePositionFromTarget(self._target)
			end),
			Rx.distinct(),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveSegmentCFrames(self: Worm): ObservableObject
	return self:_getOrCreateObservable("segmentCFrames", function()
		return self:ObserveMotion():Pipe({
			Rx.map(function()
				local cframes = table.create(#self._segments)
				for index, segment in self._segments do
					cframes[index] = segment.model:GetPivot()
				end
				return cframes
			end),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveSegmentPositions(self: Worm): ObservableObject
	return self:_getOrCreateObservable("segmentPositions", function()
		return self:ObserveSegmentCFrames():Pipe({
			Rx.map(function(cframes: { CFrame })
				local positions = table.create(#cframes)
				for index, cframe in cframes do
					positions[index] = cframe.Position
				end
				return positions
			end),
			Rx.shareReplay(1),
		})
	end)
end

function Worm.ObserveSnapshot(self: Worm): ObservableObject
	return self:_getOrCreateObservable("snapshot", function()
		return Rx.combineLatestDefer({
			enabled = self:ObserveEnabled(),
			running = self:ObserveRunning(),
			destroyed = self:ObserveDestroyed(),
			target = self:ObserveTarget(),
			targetProvider = self:ObserveTargetProvider(),
			targetObservable = self:ObserveTargetObservable(),
			segments = self:ObserveSegments(),
			motion = self:ObserveMotion(),
		}):Pipe({
			Rx.map(function()
				return self:GetSnapshot()
			end),
			Rx.shareReplay(1),
		})
	end)
end

Worm.new = Worm.New
Worm.start = Worm.Start
Worm.stop = Worm.Stop
Worm.destroy = Worm.Destroy
Worm.setTarget = Worm.SetTarget
Worm.setTargetProvider = Worm.SetTargetProvider
Worm.setTargetObservable = Worm.SetTargetObservable
Worm.getHead = Worm.GetHead
Worm.getSegments = Worm.GetSegments
Worm.setEnabled = Worm.SetEnabled
Worm.getMotionSnapshot = Worm.GetMotionSnapshot
Worm.getSnapshot = Worm.GetSnapshot
Worm.observeStarted = Worm.ObserveStarted
Worm.observeStopped = Worm.ObserveStopped
Worm.observeDestroying = Worm.ObserveDestroying
Worm.observeStepped = Worm.ObserveStepped
Worm.observeEnabled = Worm.ObserveEnabled
Worm.observeRunning = Worm.ObserveRunning
Worm.observeDestroyed = Worm.ObserveDestroyed
Worm.observeTarget = Worm.ObserveTarget
Worm.observeTargetProvider = Worm.ObserveTargetProvider
Worm.observeTargetObservable = Worm.ObserveTargetObservable
Worm.observeSegments = Worm.ObserveSegments
Worm.observeSegment = Worm.ObserveSegment
Worm.observeSegmentModels = Worm.ObserveSegmentModels
Worm.observeHead = Worm.ObserveHead
Worm.observeMotion = Worm.ObserveMotion
Worm.observeHeadCFrame = Worm.ObserveHeadCFrame
Worm.observeHeadPosition = Worm.ObserveHeadPosition
Worm.observeVelocity = Worm.ObserveVelocity
Worm.observeHeading = Worm.ObserveHeading
Worm.observeSpeed = Worm.ObserveSpeed
Worm.observeTargetPosition = Worm.ObserveTargetPosition
Worm.observeSegmentCFrames = Worm.ObserveSegmentCFrames
Worm.observeSegmentPositions = Worm.ObserveSegmentPositions
Worm.observeSnapshot = Worm.ObserveSnapshot

return Worm
