--!strict
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Curve = require(ReplicatedStorage.Shared.Modules.Math.Curve)
local Ease = require(ReplicatedStorage.Shared.Modules.Math.Ease)
local Vec = require(ReplicatedStorage.Shared.Modules.Math.Vec)

local Gib = {}
Gib.__index = Gib

export type GibConfig = {
	source: BasePart?,
	part: BasePart?,
	parent: Instance?,
	originCFrame: CFrame?,
	restCFrame: CFrame?,
	restPosition: Vector3?,
	raycastParams: RaycastParams?,
	arcHeight: number?,
	travelTime: number?,
	lifetime: number?,
	rotationVelocity: Vector3?,
	restDistance: NumberRange?,
	anchoredAtRest: boolean?,
	canCollide: boolean?,
	canTouch: boolean?,
	canQuery: boolean?,
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

export type Gib = typeof(setmetatable(
	{} :: {
		janitor: JanitorClass,
		random: Random,
		part: BasePart,
		startCFrame: CFrame,
		restCFrame: CFrame,
		raycastParams: RaycastParams?,
		controlPoint: Vector3,
		rotationVelocity: Vector3,
		travelTime: number,
		lifetime: number,
		restDistance: NumberRange,
		anchoredAtRest: boolean,
		elapsed: number,
		isPlaying: boolean,
		isLanded: boolean,
		isDestroyed: boolean,
		motionConnection: RBXScriptConnection?,
	},
	Gib
))

local DEFAULT_TRAVEL_TIME = 0.48
local DEFAULT_ARC_HEIGHT = 5.5
local DEFAULT_LIFETIME = 10
local DEFAULT_REST_DISTANCE = NumberRange.new(2, 6)
local DEFAULT_ROTATION_VELOCITY = Vector3.new(math.pi * 1.2, math.pi * 0.75, math.pi * 1.6)

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeVector3(valueRaw: any, fallback: Vector3): Vector3
	if typeof(valueRaw) == "Vector3" then
		return valueRaw
	end
	return fallback
end

local function sanitizeRestRange(rangeRaw: any, fallback: NumberRange): NumberRange
	if typeof(rangeRaw) == "NumberRange" then
		local minimum = math.min(rangeRaw.Min, rangeRaw.Max)
		local maximum = math.max(rangeRaw.Min, rangeRaw.Max)
		return NumberRange.new(minimum, maximum)
	end
	return fallback
end

local function ensurePartSource(config: GibConfig): BasePart
	local source = config.source
	if source == nil then
		source = config.part
	end
	if source ~= nil then
		return source
	end

	local fallback = Instance.new("Part")
	fallback.Name = "GibSource"
	fallback.Size = Vector3.new(1, 1, 1)
	fallback.Material = Enum.Material.SmoothPlastic
	fallback.Color = Color3.fromRGB(117, 0, 0)
	fallback.CanCollide = true
	return fallback
end

local function clearConstraintsAndJoints(part: BasePart)
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("Constraint") or descendant:IsA("JointInstance") or descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
end

local function quadraticBezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	return Curve.quadratic(a, b, c, t)
end

local function quadraticTangent(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	return Curve.quadraticTangent(a, b, c, t)
end

local function easeInOutSine(alpha: number): number
	return Ease.inOutSine(alpha)
end

local function randomUnitVector2D(randomObject: Random): Vector3
	local angle = randomObject:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function resolveRestPosition(self: Gib, startCFrame: CFrame): Vector3
	local distance = self.random:NextNumber(self.restDistance.Min, self.restDistance.Max)
	local direction = randomUnitVector2D(self.random)
	local planarOffset = direction * distance
	local candidate = startCFrame.Position + planarOffset

	local raycastParams = self.raycastParams
	if raycastParams ~= nil then
		local castOrigin = candidate + Vector3.new(0, 40, 0)
		local castDirection = Vector3.new(0, -120, 0)
		local raycast = Workspace:Raycast(castOrigin, castDirection, raycastParams)
		if raycast ~= nil then
			local y = raycast.Position.Y + self.part.Size.Y * 0.5
			return Vector3.new(candidate.X, y, candidate.Z)
		end
	end

	return Vector3.new(candidate.X, startCFrame.Position.Y, candidate.Z)
end

function Gib.new(configRaw: GibConfig?): Gib
	local config = if typeof(configRaw) == "table" then (configRaw :: GibConfig) else ({} :: GibConfig)
	local source = ensurePartSource(config)
	local clone = source:Clone()
	clearConstraintsAndJoints(clone)
	clone.Name = (source.Name ~= "" and source.Name or "GibSource") .. "_Runtime"

	local startCFrame = if typeof(config.originCFrame) == "CFrame" then config.originCFrame else source.CFrame
	local restCFrame = config.restCFrame
	local parent = if typeof(config.parent) == "Instance" then config.parent else Workspace

	local self = setmetatable({
		janitor = Janitor.new(),
		random = Random.new(),
		part = clone,
		startCFrame = startCFrame,
		restCFrame = if typeof(restCFrame) == "CFrame" then restCFrame else CFrame.new(),
		raycastParams = config.raycastParams,
		controlPoint = Vector3.zero,
		rotationVelocity = sanitizeVector3(config.rotationVelocity, DEFAULT_ROTATION_VELOCITY),
		travelTime = sanitizeNumber(config.travelTime, DEFAULT_TRAVEL_TIME, 0.1, 12),
		lifetime = sanitizeNumber(config.lifetime, DEFAULT_LIFETIME, 0.05, 120),
		restDistance = sanitizeRestRange(config.restDistance, DEFAULT_REST_DISTANCE),
		anchoredAtRest = sanitizeBoolean(config.anchoredAtRest, true),
		elapsed = 0,
		isPlaying = false,
		isLanded = false,
		isDestroyed = false,
		motionConnection = nil,
	}, Gib)

	clone.Anchored = true
	clone.CanCollide = sanitizeBoolean(config.canCollide, true)
	clone.CanTouch = sanitizeBoolean(config.canTouch, false)
	clone.CanQuery = sanitizeBoolean(config.canQuery, false)
	clone.CFrame = startCFrame
	clone.AssemblyLinearVelocity = Vector3.zero
	clone.AssemblyAngularVelocity = Vector3.zero

	local restPosition = config.restPosition
	if typeof(restPosition) ~= "Vector3" then
		restPosition = resolveRestPosition(self, startCFrame)
	end

	local randomYaw = self.random:NextNumber(-math.pi, math.pi)
	local defaultRestRotation = CFrame.Angles(0, randomYaw, 0)
	if typeof(restCFrame) == "CFrame" then
		self.restCFrame = restCFrame
	else
		self.restCFrame = CFrame.new(restPosition) * defaultRestRotation
	end

	local arcHeight = sanitizeNumber(config.arcHeight, DEFAULT_ARC_HEIGHT, 0, 200)
	local midpoint = (self.startCFrame.Position + self.restCFrame.Position) * 0.5
	self.controlPoint = midpoint + Vector3.new(0, arcHeight, 0)

	clone.Parent = parent
	self.janitor:GiveChore(function()
		if clone.Parent ~= nil then
			clone:Destroy()
		end
	end)

	return self
end

function Gib._step(self: Gib, dt: number)
	if self.isDestroyed or self.isLanded then
		return
	end

	self.elapsed += dt
	local alpha = math.clamp(self.elapsed / self.travelTime, 0, 1)
	local eased = easeInOutSine(alpha)

	local startPosition = self.startCFrame.Position
	local restPosition = self.restCFrame.Position
	local position = quadraticBezier(startPosition, self.controlPoint, restPosition, eased)
	local tangent = quadraticTangent(startPosition, self.controlPoint, restPosition, eased)
	if tangent.Magnitude <= 1e-4 then
		tangent = restPosition - startPosition
	end

	local spin = self.rotationVelocity * (self.elapsed / self.travelTime)
	local cframe = CFrame.lookAt(position, position + Vec.unit(tangent, Vector3.new(0, 0, -1)), Vector3.yAxis)
	self.part.CFrame = cframe * CFrame.Angles(spin.X, spin.Y, spin.Z)

	if alpha >= 1 then
		self:land()
	end
end

function Gib.play(self: Gib): Gib
	if self.isDestroyed or self.isPlaying then
		return self
	end

	self.isPlaying = true
	self.motionConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:_step(dt)
	end)
	self.janitor:GiveChore(self.motionConnection)

	return self
end

function Gib.land(self: Gib)
	if self.isDestroyed or self.isLanded then
		return
	end

	self.isLanded = true
	self.isPlaying = false
	if self.motionConnection ~= nil then
		self.motionConnection:Disconnect()
		self.motionConnection = nil
	end

	self.part.CFrame = self.restCFrame
	self.part.AssemblyLinearVelocity = Vector3.zero
	self.part.AssemblyAngularVelocity = Vector3.zero
	self.part.Anchored = self.anchoredAtRest

	local snapshot = self
	task.delay(self.lifetime, function()
		if snapshot.isDestroyed then
			return
		end
		snapshot:destroy()
	end)
end

function Gib.destroy(self: Gib)
	if self.isDestroyed then
		return
	end
	self.isDestroyed = true
	self.isPlaying = false
	self.motionConnection = nil
	self.janitor:Destroy()
end

return Gib
