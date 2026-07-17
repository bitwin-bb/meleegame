local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require("Maid")
local Rx: any = require("Rx")

local Physics = require("Physics")

local Stinger = {}
Stinger.__index = Stinger

type MaidClass = any

export type FireContext = {
	origin: Vector3,
	direction: Vector3?,
	targetPlayer: Player?,
	targetPosition: Vector3?,
	targetVelocity: Vector3?,
	predictionTime: number?,
	spreadDegrees: number?,
	speed: number,
	lifetime: number,
	owner: any?,
	damage: number,
	hitRadius: number,
	parent: Instance?,
	arenaCFrame: CFrame?,
	random: Random?,
	damagePlayer: ((player: Player, damage: number, owner: any?) -> any)?,
}

export type StingerProjectile = typeof(setmetatable(
	{} :: {
		maid: MaidClass,
		part: BasePart?,
		position: Vector3,
		velocity: Vector3,
		direction: Vector3,
		lifetime: number,
		elapsed: number,
		damage: number,
		hitRadius: number,
		owner: any?,
		arenaCFrame: CFrame?,
		damagePlayer: ((player: Player, damage: number, owner: any?) -> any)?,
		destroyed: boolean,
	},
	Stinger
))

local DEFAULT_SPEED = 120
local DEFAULT_LIFETIME = 4
local DEFAULT_HIT_RADIUS = 2.5
local DEFAULT_DAMAGE = 18
local MAX_DT = 1 / 20

local function coerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
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

local function getParent(parentRaw: Instance?): Instance
	if parentRaw ~= nil then
		return parentRaw
	end
	return Workspace
end

local function createPart(context: FireContext, direction: Vector3): BasePart
	local hitRadius = coerceNumber(context.hitRadius, DEFAULT_HIT_RADIUS, 0.1, 64)
	local part = Instance.new("Part")
	part.Name = "Stinger"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = Vector3.new(math.max(0.28, hitRadius * 0.28), math.max(0.28, hitRadius * 0.28), 2.4)
	part.CFrame = CFrame.lookAt(context.origin, context.origin + direction, Vector3.yAxis)
	part.Parent = getParent(context.parent)
	return part
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

local function getTargetPoint(context: FireContext): Vector3?
	if typeof(context.targetPosition) == "Vector3" then
		return context.targetPosition
	end

	local targetPlayer = context.targetPlayer
	if targetPlayer == nil then
		return nil
	end

	local center = Physics.GetTargetCenter(targetPlayer)
	if center == nil then
		return nil
	end

	local velocity = if typeof(context.targetVelocity) == "Vector3"
		then context.targetVelocity
		else Physics.GetTargetVelocity(targetPlayer)
	local predictionTime = coerceNumber(context.predictionTime, 0, 0, 3)
	return center + velocity * predictionTime
end

local function getDirection(context: FireContext): Vector3
	local direction = if typeof(context.direction) == "Vector3" then context.direction else Vector3.zero
	if direction.Magnitude <= 1e-5 then
		local targetPoint = getTargetPoint(context)
		if targetPoint ~= nil then
			direction = targetPoint - context.origin
		end
	end

	direction = safeUnit(Physics.ProjectVectorToCombatPlane(direction, context.arenaCFrame), Vector3.zAxis)

	local spreadDegrees = coerceNumber(context.spreadDegrees, 0, 0, 90)
	if spreadDegrees > 0 then
		local random = if context.random ~= nil then context.random else Random.new()
		local spread = random:NextNumber(-spreadDegrees, spreadDegrees)
		direction = Physics.RotateVectorInCombatPlane(direction, spread, context.arenaCFrame)
	end

	return safeUnit(direction, Vector3.zAxis)
end

function Stinger.Fire(contextRaw: FireContext): StingerProjectile
	local context = contextRaw
	local direction = getDirection(context)
	local speed = coerceNumber(context.speed, DEFAULT_SPEED, 0, 10 ^ 6)
	local lifetime = coerceNumber(context.lifetime, DEFAULT_LIFETIME, 0.05, 60)
	local hitRadius = coerceNumber(context.hitRadius, DEFAULT_HIT_RADIUS, 0.1, 256)
	local damage = coerceNumber(context.damage, DEFAULT_DAMAGE, 0, 10 ^ 6)
	local part = createPart(context, direction)
	local maid = Maid.new() :: MaidClass

	local self = setmetatable({
		maid = maid,
		part = part,
		position = Physics.ProjectToCombatPlane(context.origin, context.arenaCFrame),
		velocity = direction * speed,
		direction = direction,
		lifetime = lifetime,
		elapsed = 0,
		damage = damage,
		hitRadius = hitRadius,
		owner = context.owner,
		arenaCFrame = context.arenaCFrame,
		damagePlayer = context.damagePlayer,
		destroyed = false,
	}, Stinger) :: StingerProjectile

	maid:GiveTask(part)
	maid:GiveTask(Rx.fromSignal(RunService.Heartbeat):Subscribe(function(dtRaw: number)
		self:Step(dtRaw)
	end))

	return self
end

function Stinger.Step(self: StingerProjectile, dtRaw: any)
	if self.destroyed then
		return
	end

	local dt = coerceNumber(dtRaw, 0, 0, MAX_DT)
	if dt <= 0 then
		return
	end

	self.elapsed += dt
	if self.elapsed >= self.lifetime then
		self:Destroy()
		return
	end

	self.position = Physics.ProjectToCombatPlane(self.position + self.velocity * dt, self.arenaCFrame)

	local part = self.part
	if part ~= nil then
		part.CFrame = CFrame.lookAt(self.position, self.position + self.direction, Vector3.yAxis)
	end

	local hitPlayer = findHitPlayer(self.position, self.hitRadius, self.owner)
	if hitPlayer == nil then
		return
	end

	damagePlayer(self.damagePlayer, hitPlayer, self.damage, self.owner)
	self:Destroy()
end

function Stinger.Destroy(self: StingerProjectile)
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.part = nil
	self.maid:Destroy()
end
return Stinger
