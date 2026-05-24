--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Maid = loader("Maid")
local Rx = loader("Rx")

local Physics = require(script.Parent.Physics)

local Bee = {}
Bee.__index = Bee

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

export type SpawnContext = {
	origin: Vector3,
	targetPlayer: Player?,
	parent: Instance?,
	arenaCFrame: CFrame?,
	owner: any?,
	random: Random?,
	lifetime: number,
	scatterDuration: number,
	scatterSpeed: number,
	speed: number,
	acceleration: number,
	dashSpeed: number,
	damage: number,
	hitRadius: number,
	damagePlayer: ((player: Player, damage: number, owner: any?) -> any)?,
}

export type BurstContext = SpawnContext & {
	count: number,
	spawnRadius: number?,
}

export type BeeRuntime = typeof(setmetatable(
	{} :: {
		maid: MaidClass,
		part: BasePart?,
		position: Vector3,
		velocity: Vector3,
		targetPlayer: Player?,
		arenaCFrame: CFrame?,
		owner: any?,
		random: Random,
		lifetime: number,
		elapsed: number,
		scatterDuration: number,
		scatterSpeed: number,
		speed: number,
		acceleration: number,
		dashSpeed: number,
		damage: number,
		hitRadius: number,
		damagePlayer: ((player: Player, damage: number, owner: any?) -> any)?,
		mode: string,
		modeTime: number,
		nextDashAt: number,
		dashDuration: number,
		lockedDashDirection: Vector3,
		destroyed: boolean,
	},
	Bee
))

local DEFAULT_LIFETIME = 7
local DEFAULT_SCATTER_DURATION = 0.34
local DEFAULT_SCATTER_SPEED = 32
local DEFAULT_SPEED = 50
local DEFAULT_ACCELERATION = 160
local DEFAULT_DASH_SPEED = 90
local DEFAULT_DAMAGE = 11
local DEFAULT_HIT_RADIUS = 3
local DEFAULT_DASH_INTERVAL_MIN = 0.62
local DEFAULT_DASH_INTERVAL_MAX = 1.05
local DEFAULT_DASH_DURATION = 0.18
local MAX_DT = 1 / 20

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

local function safeUnit(vector: Vector3, fallbackRaw: Vector3?): Vector3
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else Vector3.zAxis
	if vector.Magnitude <= 1e-5 then
		if fallback.Magnitude <= 1e-5 then
			return Vector3.zAxis
		end
		return fallback.Unit
	end
	return vector.Unit
end

local function resolveParent(parentRaw: Instance?): Instance
	if parentRaw ~= nil then
		return parentRaw
	end
	return Workspace
end

local function getAliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

local function damagePlayer(
	callback: ((player: Player, damage: number, owner: any?) -> any)?,
	player: Player,
	damage: number,
	owner: any?
)
	if callback ~= nil then
		pcall(function()
			callback(player, damage, owner)
		end)
		return
	end

	local humanoid = getAliveHumanoid(player)
	if humanoid ~= nil then
		humanoid:TakeDamage(damage)
	end
end

local function findHitPlayer(position: Vector3, hitRadius: number, owner: any?): Player?
	for _, player in Players:GetPlayers() do
		if player == owner then
			continue
		end

		if getAliveHumanoid(player) == nil then
			continue
		end

		local center = Physics.GetTargetCenter(player)
		if center == nil then
			continue
		end

		if (center - position).Magnitude <= hitRadius then
			return player
		end
	end
	return nil
end

local function createPart(context: SpawnContext): BasePart
	local hitRadius = sanitizeNumber(context.hitRadius, DEFAULT_HIT_RADIUS, 0.1, 64)
	local part = Instance.new("Part")
	part.Name = "Bee"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = Vector3.new(hitRadius, hitRadius * 0.72, hitRadius)
	part.CFrame = CFrame.new(context.origin)
	part.Parent = resolveParent(context.parent)
	return part
end

local function rollScatterDirection(context: SpawnContext, random: Random): Vector3
	local side = Physics.GetCombatSideVector(context.arenaCFrame)
	local up = Physics.GetCombatUpVector(context.arenaCFrame)
	local sideAmount = random:NextNumber(-1, 1)
	local upAmount = random:NextNumber(-0.35, 0.8)
	return safeUnit(side * sideAmount + up * upAmount, side)
end

local function rollNextDashAt(random: Random): number
	return random:NextNumber(DEFAULT_DASH_INTERVAL_MIN, DEFAULT_DASH_INTERVAL_MAX)
end

function Bee.Spawn(contextRaw: SpawnContext): BeeRuntime
	local context = contextRaw
	local random = if context.random ~= nil then context.random else Random.new()
	local scatterDirection = rollScatterDirection(context, random)
	local part = createPart(context)
	local maid = Maid.new() :: MaidClass
	local position = Physics.ProjectToCombatPlane(context.origin, context.arenaCFrame)

	local self = setmetatable({
		maid = maid,
		part = part,
		position = position,
		velocity = scatterDirection * sanitizeNumber(context.scatterSpeed, DEFAULT_SCATTER_SPEED, 0, 10 ^ 5),
		targetPlayer = context.targetPlayer,
		arenaCFrame = context.arenaCFrame,
		owner = context.owner,
		random = random,
		lifetime = sanitizeNumber(context.lifetime, DEFAULT_LIFETIME, 0.05, 60),
		elapsed = 0,
		scatterDuration = sanitizeNumber(context.scatterDuration, DEFAULT_SCATTER_DURATION, 0, 10),
		scatterSpeed = sanitizeNumber(context.scatterSpeed, DEFAULT_SCATTER_SPEED, 0, 10 ^ 5),
		speed = sanitizeNumber(context.speed, DEFAULT_SPEED, 0, 10 ^ 5),
		acceleration = sanitizeNumber(context.acceleration, DEFAULT_ACCELERATION, 0, 10 ^ 5),
		dashSpeed = sanitizeNumber(context.dashSpeed, DEFAULT_DASH_SPEED, 0, 10 ^ 5),
		damage = sanitizeNumber(context.damage, DEFAULT_DAMAGE, 0, 10 ^ 6),
		hitRadius = sanitizeNumber(context.hitRadius, DEFAULT_HIT_RADIUS, 0.1, 256),
		damagePlayer = context.damagePlayer,
		mode = "Scatter",
		modeTime = 0,
		nextDashAt = rollNextDashAt(random),
		dashDuration = DEFAULT_DASH_DURATION,
		lockedDashDirection = scatterDirection,
		destroyed = false,
	}, Bee) :: BeeRuntime

	maid:GiveTask(part)
	maid:GiveTask(Rx.fromSignal(RunService.Heartbeat):Subscribe(function(dtRaw: number)
		self:Step(dtRaw)
	end))

	return self
end

function Bee.SpawnBurst(contextRaw: BurstContext): { BeeRuntime }
	local context = contextRaw
	local count = math.max(0, math.floor(sanitizeNumber(context.count, 0, 0, 64)))
	local random = if context.random ~= nil then context.random else Random.new()
	local radius = sanitizeNumber(context.spawnRadius, 7, 0, 128)
	local side = Physics.GetCombatSideVector(context.arenaCFrame)
	local up = Physics.GetCombatUpVector(context.arenaCFrame)
	local bees = {}

	for index = 1, count do
		local angle = (index / math.max(1, count)) * math.pi * 2 + random:NextNumber(-0.35, 0.35)
		local origin = context.origin + side * math.cos(angle) * radius + up * math.sin(angle) * radius * 0.55
		local nextContext = table.clone(context)
		nextContext.origin = Physics.ProjectToCombatPlane(origin, context.arenaCFrame)
		nextContext.random = random
		table.insert(bees, Bee.Spawn(nextContext :: SpawnContext))
	end

	return bees
end

function Bee.Step(self: BeeRuntime, dtRaw: any)
	if self.destroyed then
		return
	end

	local dt = sanitizeNumber(dtRaw, 0, 0, MAX_DT)
	if dt <= 0 then
		return
	end

	self.elapsed += dt
	self.modeTime += dt
	if self.elapsed >= self.lifetime then
		self:Destroy()
		return
	end

	local targetPosition = if self.targetPlayer ~= nil then Physics.GetTargetCenter(self.targetPlayer) else nil
	if targetPosition ~= nil then
		targetPosition = Physics.ProjectToCombatPlane(targetPosition, self.arenaCFrame)
	end

	if self.mode == "Scatter" then
		if self.modeTime >= self.scatterDuration then
			self.mode = "Seek"
			self.modeTime = 0
		end
	elseif self.mode == "Dash" then
		self.velocity = self.lockedDashDirection * self.dashSpeed
		if self.modeTime >= self.dashDuration then
			self.mode = "Seek"
			self.modeTime = 0
			self.nextDashAt = rollNextDashAt(self.random)
		end
	elseif targetPosition ~= nil then
		local desiredDirection = safeUnit(targetPosition - self.position, self.lockedDashDirection)
		local desiredVelocity = desiredDirection * self.speed
		self.velocity = Physics.ApproachVelocity(self.velocity, desiredVelocity, self.acceleration * dt)
		if self.modeTime >= self.nextDashAt then
			self.mode = "Dash"
			self.modeTime = 0
			self.lockedDashDirection = desiredDirection
		end
	end

	self.velocity = Physics.ProjectVectorToCombatPlane(self.velocity, self.arenaCFrame)
	self.position = Physics.ProjectToCombatPlane(self.position + self.velocity * dt, self.arenaCFrame)

	local part = self.part
	if part ~= nil then
		local facing = safeUnit(self.velocity, self.lockedDashDirection)
		part.CFrame = CFrame.lookAt(self.position, self.position + facing, Vector3.yAxis)
	end

	local hitPlayer = findHitPlayer(self.position, self.hitRadius, self.owner)
	if hitPlayer == nil then
		return
	end

	damagePlayer(self.damagePlayer, hitPlayer, self.damage, self.owner)
	self:Destroy()
end

function Bee.Destroy(self: BeeRuntime)
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.part = nil
	self.maid:Destroy()
end

Bee.spawn = Bee.Spawn
Bee.spawnBurst = Bee.SpawnBurst
Bee.step = Bee.Step
Bee.destroy = Bee.Destroy

return Bee
