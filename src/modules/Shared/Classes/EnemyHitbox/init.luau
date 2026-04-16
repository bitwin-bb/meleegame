--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SpatialHash = require(script.Utils.SpatialHash)

local EnemyHitbox = {}
EnemyHitbox.__index = EnemyHitbox

export type EnemyConfig = {
	id: string,
	owner: any?,
	model: Model?,
	getModel: ((owner: any) -> Model?)?,
	getCenter: ((owner: any) -> Vector3?)?,
	getAlive: ((owner: any) -> boolean)?,
	getDamage: ((owner: any) -> number)?,
	getAttackCooldown: ((owner: any) -> number)?,
	getHurtboxSize: ((owner: any, model: Model?, rootPart: BasePart?) -> Vector3?)?,
	getAttackSize: ((owner: any, model: Model?, rootPart: BasePart?) -> Vector3?)?,
	canHitPlayer: ((owner: any, player: Player) -> boolean)?,
	onHitPlayer: ((owner: any, player: Player, damage: number) -> ())?,
}

export type EnemyHitboxConfig = {
	cellSize: number?,
	playerCellSize: number?,
	playerHitboxSizePadding: Vector3?,
}

type EnemyRecord = {
	id: string,
	config: EnemyConfig,
	owner: any?,
	model: Model?,
	rootPart: BasePart?,
	center: Vector3,
	hurtboxSize: Vector3,
	attackSize: Vector3,
	aabbMin: Vector3,
	aabbMax: Vector3,
	attackAabbMin: Vector3,
	attackAabbMax: Vector3,
	alive: boolean,
	damage: number,
	attackCooldown: number,
	nextDamageAtByPlayer: { [Player]: number },
}

type PlayerRecord = {
	id: string,
	player: Player,
	humanoid: Humanoid,
	rootPart: BasePart,
	aabbMin: Vector3,
	aabbMax: Vector3,
}

export type EnemyHitbox = typeof(setmetatable(
	{} :: {
		enemySpatial: SpatialHash.SpatialHash<EnemyRecord>,
		playerSpatial: SpatialHash.SpatialHash<PlayerRecord>,
		enemiesById: { [string]: EnemyRecord },
		enemyIdByModel: { [Model]: string },
		playersById: { [string]: PlayerRecord },
		playerHitboxSizePadding: Vector3,
		heartbeatConnection: RBXScriptConnection?,
		destroyed: boolean,
	},
	EnemyHitbox
))

local DEFAULT_CELL_SIZE = 8
local DEFAULT_PLAYER_CELL_SIZE = 8
local DEFAULT_PLAYER_HITBOX_PADDING = Vector3.new(1.2, 1.6, 1.2)
local DEFAULT_HURTBOX_SIZE = Vector3.new(4, 3, 4)
local DEFAULT_ATTACK_SIZE = Vector3.new(5.5, 3.5, 5.5)
local DEFAULT_ATTACK_COOLDOWN = 0.85
local DEFAULT_DAMAGE = 6

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

local function sanitizeVector3(valueRaw: any, fallback: Vector3, minimumComponent: number): Vector3
	if typeof(valueRaw) ~= "Vector3" then
		return fallback
	end

	return Vector3.new(
		math.max(minimumComponent, math.abs(valueRaw.X)),
		math.max(minimumComponent, math.abs(valueRaw.Y)),
		math.max(minimumComponent, math.abs(valueRaw.Z))
	)
end

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local rootPartCandidate = model:FindFirstChild("HumanoidRootPart")
	if rootPartCandidate ~= nil and rootPartCandidate:IsA("BasePart") then
		return rootPartCandidate
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function resolveCharacterRoot(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil, nil
	end

	local rootPartCandidate = character:FindFirstChild("HumanoidRootPart")
	local rootPart = if rootPartCandidate ~= nil and rootPartCandidate:IsA("BasePart") then rootPartCandidate else nil
	if rootPart == nil then
		local primary = character.PrimaryPart
		if primary ~= nil and primary:IsA("BasePart") then
			rootPart = primary
		end
	end

	return humanoid, rootPart
end

local function runCallback(callback: ((...any) -> any)?, defaultValue: any, ...: any): any
	if typeof(callback) ~= "function" then
		return defaultValue
	end

	local ok, result = pcall(callback, ...)
	if ok then
		return result
	end

	return defaultValue
end

function EnemyHitbox.New(configRaw: EnemyHitboxConfig?): EnemyHitbox
	local config = if typeof(configRaw) == "table" then configRaw else {}

	local self = setmetatable({
		enemySpatial = SpatialHash.new(sanitizeNumber(config.cellSize, DEFAULT_CELL_SIZE, 0.5, 256)),
		playerSpatial = SpatialHash.new(sanitizeNumber(config.playerCellSize, DEFAULT_PLAYER_CELL_SIZE, 0.5, 256)),
		enemiesById = {},
		enemyIdByModel = {},
		playersById = {},
		playerHitboxSizePadding = sanitizeVector3(config.playerHitboxSizePadding, DEFAULT_PLAYER_HITBOX_PADDING, 0),
		heartbeatConnection = nil,
		destroyed = false,
	}, EnemyHitbox)

	self.heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_step()
	end)

	return self
end

function EnemyHitbox.Destroy(self: EnemyHitbox)
	if self.destroyed then
		return
	end
	self.destroyed = true

	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	table.clear(self.enemyIdByModel)
	table.clear(self.enemiesById)
	table.clear(self.playersById)
	self.enemySpatial:clear()
	self.playerSpatial:clear()
end

function EnemyHitbox.RegisterEnemy(self: EnemyHitbox, configRaw: any): boolean
	if typeof(configRaw) ~= "table" then
		return false
	end

	local config = configRaw :: EnemyConfig
	if typeof(config.id) ~= "string" or config.id == "" then
		return false
	end

	self:unregisterEnemy(config.id)

	local record: EnemyRecord = {
		id = config.id,
		config = config,
		owner = config.owner,
		model = config.model,
		rootPart = nil,
		center = Vector3.zero,
		hurtboxSize = DEFAULT_HURTBOX_SIZE,
		attackSize = DEFAULT_ATTACK_SIZE,
		aabbMin = Vector3.zero,
		aabbMax = Vector3.zero,
		attackAabbMin = Vector3.zero,
		attackAabbMax = Vector3.zero,
		alive = false,
		damage = DEFAULT_DAMAGE,
		attackCooldown = DEFAULT_ATTACK_COOLDOWN,
		nextDamageAtByPlayer = {},
	}

	self.enemiesById[record.id] = record
	self:_refreshEnemy(record)
	return true
end

function EnemyHitbox.UnregisterEnemy(self: EnemyHitbox, enemyIdRaw: any)
	if typeof(enemyIdRaw) ~= "string" or enemyIdRaw == "" then
		return
	end

	local record = self.enemiesById[enemyIdRaw]
	if record == nil then
		return
	end

	if record.model ~= nil and self.enemyIdByModel[record.model] == record.id then
		self.enemyIdByModel[record.model] = nil
	end

	table.clear(record.nextDamageAtByPlayer)
	self.enemySpatial:remove(record.id)
	self.enemiesById[record.id] = nil
end

function EnemyHitbox.SetEnemyModel(self: EnemyHitbox, enemyIdRaw: any, modelRaw: any)
	if typeof(enemyIdRaw) ~= "string" or enemyIdRaw == "" then
		return
	end

	local record = self.enemiesById[enemyIdRaw]
	if record == nil then
		return
	end

	local nextModel = if typeof(modelRaw) == "Instance" and modelRaw:IsA("Model") then modelRaw else nil
	record.config.model = nextModel
	record.model = nextModel
	self:_refreshEnemy(record)
end

function EnemyHitbox.SetEnemyAlive(self: EnemyHitbox, enemyIdRaw: any, aliveRaw: any)
	if typeof(enemyIdRaw) ~= "string" or enemyIdRaw == "" then
		return
	end

	local record = self.enemiesById[enemyIdRaw]
	if record == nil then
		return
	end

	record.alive = aliveRaw == true
	if not record.alive then
		self.enemySpatial:remove(record.id)
	end
end

function EnemyHitbox.ResolveEnemyIdFromModel(self: EnemyHitbox, modelRaw: any): string?
	if typeof(modelRaw) ~= "Instance" or not modelRaw:IsA("Model") then
		return nil
	end

	local cursor: Instance? = modelRaw
	while cursor ~= nil do
		if cursor:IsA("Model") then
			local enemyId = self.enemyIdByModel[cursor]
			if enemyId ~= nil then
				return enemyId
			end
		end
		cursor = cursor.Parent
	end

	return nil
end

function EnemyHitbox.ResolveEnemyIdFromPart(self: EnemyHitbox, partRaw: any): string?
	if typeof(partRaw) ~= "Instance" or not partRaw:IsA("BasePart") then
		return nil
	end

	local part = partRaw :: BasePart
	local enemyIdFromModel = self:resolveEnemyIdFromModel(part:FindFirstAncestorOfClass("Model"))
	return enemyIdFromModel
end

function EnemyHitbox._refreshPlayers(self: EnemyHitbox)
	local alivePlayerIds: { [string]: true } = {}

	for _, player in Players:GetPlayers() do
		local humanoid, rootPart = resolveCharacterRoot(player)
		if humanoid == nil or rootPart == nil then
			continue
		end

		local playerId = tostring(player.UserId)
		alivePlayerIds[playerId] = true

		local hitboxSize = rootPart.Size + self.playerHitboxSizePadding
		local aabbMin, aabbMax = SpatialHash.aabbFromCenterSize(rootPart.Position, hitboxSize)
		local record: PlayerRecord = {
			id = playerId,
			player = player,
			humanoid = humanoid,
			rootPart = rootPart,
			aabbMin = aabbMin,
			aabbMax = aabbMax,
		}

		self.playersById[playerId] = record
		self.playerSpatial:upsert(playerId, aabbMin, aabbMax, record)
	end

	for playerId, record in self.playersById do
		if alivePlayerIds[playerId] ~= true then
			self.playersById[playerId] = nil
			self.playerSpatial:remove(playerId)
			for _, enemyRecord in self.enemiesById do
				enemyRecord.nextDamageAtByPlayer[record.player] = nil
			end
		end
	end
end

function EnemyHitbox._refreshEnemy(self: EnemyHitbox, record: EnemyRecord)
	local config = record.config
	local owner = record.owner

	local previousModel = record.model
	local nextModel = config.model
	if nextModel == nil then
		nextModel = runCallback(config.getModel, nil, owner)
	end
	if typeof(nextModel) ~= "Instance" or not nextModel:IsA("Model") then
		nextModel = nil
	end

	if previousModel ~= nil and previousModel ~= nextModel and self.enemyIdByModel[previousModel] == record.id then
		self.enemyIdByModel[previousModel] = nil
	end

	record.model = nextModel
	if nextModel ~= nil then
		self.enemyIdByModel[nextModel] = record.id
	end

	local rootPart = resolveRootPart(nextModel)
	record.rootPart = rootPart

	local aliveFromCallback = runCallback(config.getAlive, true, owner)
	record.alive = aliveFromCallback and nextModel ~= nil and rootPart ~= nil
	if not record.alive then
		self.enemySpatial:remove(record.id)
		return
	end

	local center = runCallback(config.getCenter, nil, owner)
	if typeof(center) ~= "Vector3" then
		if rootPart ~= nil then
			center = rootPart.Position
		elseif nextModel ~= nil then
			center = nextModel:GetPivot().Position
		else
			center = Vector3.zero
		end
	end

	local rootSize = if rootPart ~= nil then rootPart.Size else DEFAULT_HURTBOX_SIZE
	local hurtboxSize = sanitizeVector3(
		runCallback(config.getHurtboxSize, nil, owner, nextModel, rootPart),
		Vector3.new(math.max(2, rootSize.X), math.max(2, rootSize.Y), math.max(2, rootSize.Z)),
		0.5
	)
	local attackSize = sanitizeVector3(
		runCallback(config.getAttackSize, nil, owner, nextModel, rootPart),
		Vector3.new(
			math.max(hurtboxSize.X, rootSize.X + 1.5),
			math.max(hurtboxSize.Y, rootSize.Y + 0.5),
			math.max(hurtboxSize.Z, rootSize.Z + 2)
		),
		0.5
	)

	local aabbMin, aabbMax = SpatialHash.aabbFromCenterSize(center, hurtboxSize)
	local attackAabbMin, attackAabbMax = SpatialHash.aabbFromCenterSize(center, attackSize)
	record.center = center
	record.hurtboxSize = hurtboxSize
	record.attackSize = attackSize
	record.aabbMin = aabbMin
	record.aabbMax = aabbMax
	record.attackAabbMin = attackAabbMin
	record.attackAabbMax = attackAabbMax
	record.damage = sanitizeNumber(runCallback(config.getDamage, DEFAULT_DAMAGE, owner), DEFAULT_DAMAGE, 0, 100000)
	record.attackCooldown =
		sanitizeNumber(runCallback(config.getAttackCooldown, DEFAULT_ATTACK_COOLDOWN, owner), DEFAULT_ATTACK_COOLDOWN, 0.05, 30)

	self.enemySpatial:upsert(record.id, aabbMin, aabbMax, record)
end

function EnemyHitbox._processEnemyAttacks(self: EnemyHitbox, now: number)
	for _, record in self.enemiesById do
		if record.alive ~= true then
			continue
		end
		if record.damage <= 0 then
			continue
		end

		local canHitPlayerCallback = record.config.canHitPlayer
		local onHitPlayerCallback = record.config.onHitPlayer
		if typeof(onHitPlayerCallback) ~= "function" then
			continue
		end

		local candidates = self.playerSpatial:queryAabb(record.attackAabbMin, record.attackAabbMax)
		if #candidates <= 0 then
			continue
		end

		for _, entry in candidates do
			local playerRecord = entry.payload
			local player = playerRecord.player
			if playerRecord.humanoid.Health <= 0 then
				continue
			end

			local nextAllowedAt = record.nextDamageAtByPlayer[player]
			if nextAllowedAt ~= nil and now < nextAllowedAt then
				continue
			end

			local canHitPlayer = runCallback(canHitPlayerCallback, true, record.owner, player)
			if not canHitPlayer then
				continue
			end

			if not SpatialHash.aabbIntersects(
				record.attackAabbMin,
				record.attackAabbMax,
				playerRecord.aabbMin,
				playerRecord.aabbMax
			) then
				continue
			end

			record.nextDamageAtByPlayer[player] = now + record.attackCooldown
			runCallback(onHitPlayerCallback, nil, record.owner, player, record.damage)
		end
	end
end

function EnemyHitbox._step(self: EnemyHitbox)
	if self.destroyed then
		return
	end

	self:_refreshPlayers()
	for _, record in self.enemiesById do
		self:_refreshEnemy(record)
	end
	self:_processEnemyAttacks(os.clock())
end

EnemyHitbox.new = EnemyHitbox.New
EnemyHitbox.destroy = EnemyHitbox.Destroy
EnemyHitbox.registerEnemy = EnemyHitbox.RegisterEnemy
EnemyHitbox.unregisterEnemy = EnemyHitbox.UnregisterEnemy
EnemyHitbox.setEnemyModel = EnemyHitbox.SetEnemyModel
EnemyHitbox.setEnemyAlive = EnemyHitbox.SetEnemyAlive
EnemyHitbox.resolveEnemyIdFromModel = EnemyHitbox.ResolveEnemyIdFromModel
EnemyHitbox.resolveEnemyIdFromPart = EnemyHitbox.ResolveEnemyIdFromPart

return EnemyHitbox
