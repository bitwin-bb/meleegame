local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")

local BossServiceUtils = require("BossServiceUtils")
local EyeOfCthulhuServantRoot = require("EyeOfCthulhuServantRoot")
local WorkspaceFolders = require("WorkspaceFolders")

export type ServantRuntime = {
	model: Model,
	part: BasePart,
	position: Vector3,
	velocity: Vector3,
	age: number,
	damageCooldownByUserId: { [number]: number },
	maid: any,
}

export type SpawnConfig = {
	servantId: number,
	parent: Instance,
	spawnPosition: Vector3,
	facing: Vector3,
	initialVelocity: Vector3,
}

export type StepConfig = {
	dt: number,
	now: number,
	targetPosition: Vector3?,
	planeX: number?,
	speed: number,
	turnAcceleration: number,
	lifetime: number,
	radius: number,
	cooldown: number,
	damagePlayer: (Player) -> any,
}

local Servant = {}

local DEFAULT_SERVANT_FOLDER_NAME = "BossServants"

function Servant.GetFolder(): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(DEFAULT_SERVANT_FOLDER_NAME)
end

function Servant.CountActive(servants: { [number]: ServantRuntime }): number
	local count = 0
	for _ in servants do
		count += 1
	end
	return count
end

local function destroyServant(servant: ServantRuntime)
	servant.maid:Destroy()
end

function Servant.Spawn(servants: { [number]: ServantRuntime }, config: SpawnConfig): (boolean, number)
	local servantId = config.servantId
	local model = EyeOfCthulhuServantRoot.createModel({
		name = "ServantOfCthulhu",
		cframe = BossServiceUtils.sideViewLookCFrame(config.spawnPosition, config.facing),
		parent = config.parent,
	})
	local rootPart = model.PrimaryPart
	if rootPart == nil then
		model:Destroy()
		return false, servantId
	end

	local maid = Maid.new()
	maid:GiveTask(model)
	servants[servantId] = {
		model = model,
		part = rootPart,
		position = config.spawnPosition,
		velocity = config.initialVelocity,
		age = 0,
		damageCooldownByUserId = {},
		maid = maid,
	}

	return true, servantId + 1
end

function Servant.ClearAll(servants: { [number]: ServantRuntime })
	for servantId, servant in servants do
		destroyServant(servant)
		servants[servantId] = nil
	end
end

function Servant.StepAll(servants: { [number]: ServantRuntime }, config: StepConfig)
	for servantId, servant in servants do
		if servant.model.Parent == nil or servant.part.Parent == nil then
			destroyServant(servant)
			servants[servantId] = nil
			continue
		end

		servant.age += config.dt
		if servant.age >= config.lifetime then
			destroyServant(servant)
			servants[servantId] = nil
			continue
		end

		local facing = servant.velocity
		if config.targetPosition ~= nil then
			local desiredDirection =
				BossServiceUtils.projectVectorToPlaneX(config.targetPosition - servant.position, config.planeX)
			if desiredDirection.Magnitude > 1e-4 then
				facing = desiredDirection
				local desiredVelocity = desiredDirection.Unit * config.speed
				servant.velocity = BossServiceUtils.moveTowardsVector(
					servant.velocity,
					desiredVelocity,
					config.turnAcceleration * config.dt
				)
			end
		end

		servant.position =
			BossServiceUtils.projectPositionToPlaneX(servant.position + servant.velocity * config.dt, config.planeX)
		servant.part.CFrame = BossServiceUtils.sideViewLookCFrame(servant.position, facing)

		for _, player in Players:GetPlayers() do
			if not BossServiceUtils.isPlayerAlive(player) then
				continue
			end
			local rootPart = BossServiceUtils.resolveCharacterRootPart(player)
			if rootPart == nil then
				continue
			end
			if
				(BossServiceUtils.projectPositionToPlaneX(rootPart.Position, config.planeX) - servant.position).Magnitude
				> config.radius
			then
				continue
			end
			local lastDamageAt = servant.damageCooldownByUserId[player.UserId] or -math.huge
			if config.now - lastDamageAt < config.cooldown then
				continue
			end
			if config.damagePlayer(player) ~= nil then
				servant.damageCooldownByUserId[player.UserId] = config.now
			end
		end
	end
end

Servant.getFolder = Servant.GetFolder
Servant.countActive = Servant.CountActive
Servant.spawn = Servant.Spawn
Servant.clearAll = Servant.ClearAll
Servant.stepAll = Servant.StepAll

return Servant
