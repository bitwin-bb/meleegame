--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Signal = require(ReplicatedStorage.Packages.Signal)

local Npc = {}
Npc.__index = Npc

export type NpcState = "Idle" | "Moving" | "Attacking" | "Dead"

export type NpcStatsConfig = {
	maxHp: number?,
	hp: number?,
	damage: number?,
	defense: number?,
}

export type NpcMovementConfig = {
	walkSpeed: number?,
	jumpPower: number?,
	canMove: boolean?,
	canWander: boolean?,
	wanderRadius: number?,
	wanderInterval: number?,
	thinkInterval: number?,
	detectionRange: number?,
	loseTargetRange: number?,
	moveRepathDistance: number?,
	autoRotate: boolean?,
}

export type NpcCombatConfig = {
	attackRange: number?,
	attackCooldown: number?,
	minDamage: number?,
	damageVariance: number?,
	targetPlayers: boolean?,
	targetNpcs: boolean?,
	allowFriendlyFire: boolean?,
}

export type NpcBehaviorConfig = {
	acquireTarget: ((self: any) -> any?)?,
	shouldTarget: ((self: any, target: any) -> boolean)?,
	onSpawn: ((self: any) -> ())?,
	onThink: ((self: any, dt: number) -> ())?,
	onAttack: ((self: any, target: any, damage: number) -> ())?,
	onDamageTaken: ((self: any, damage: number, source: any?, hp: number) -> ())?,
	onDeath: ((self: any, killer: any?) -> ())?,
}

export type NpcLifecycleConfig = {
	spawnParent: Instance?,
	spawnCFrame: CFrame?,
	autoStart: boolean?,
	autoDestroyModelOnDeath: boolean?,
}

export type NpcConfig = {
	archetype: string?,
	displayName: string?,
	faction: string?,
	model: Instance? | string?,
	modelName: string?,
	ownerPlayer: Player?,
	stats: NpcStatsConfig?,
	movement: NpcMovementConfig?,
	combat: NpcCombatConfig?,
	behavior: NpcBehaviorConfig?,
	lifecycle: NpcLifecycleConfig?,
	tags: { [string]: boolean }?,
	hp: number?,
	maxHp: number?,
	damage: number?,
	dmg: number?,
	defense: number?,
	def: number?,
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type NpcSignals = {
	spawned: SignalObject,
	stateChanged: SignalObject,
	targetChanged: SignalObject,
	damaged: SignalObject,
	attacked: SignalObject,
	died: SignalObject,
}

type RuntimeMovementConfig = {
	walkSpeed: number,
	jumpPower: number,
	canMove: boolean,
	canWander: boolean,
	wanderRadius: number,
	wanderInterval: number,
	thinkInterval: number,
	detectionRange: number,
	loseTargetRange: number,
	moveRepathDistance: number,
	autoRotate: boolean,
}

type RuntimeCombatConfig = {
	attackRange: number,
	attackCooldown: number,
	minDamage: number,
	damageVariance: number,
	targetPlayers: boolean,
	targetNpcs: boolean,
	allowFriendlyFire: boolean,
}

type RuntimeLifecycleConfig = {
	spawnParent: Instance,
	spawnCFrame: CFrame?,
	autoStart: boolean,
	autoDestroyModelOnDeath: boolean,
}

type NormalizedNpcConfig = {
	archetype: string,
	displayName: string,
	faction: string,
	ownerPlayer: Player?,
	modelTemplate: Model?,
	stats: {
		maxHp: number,
		hp: number,
		damage: number,
		defense: number,
	},
	movement: RuntimeMovementConfig,
	combat: RuntimeCombatConfig,
	behavior: NpcBehaviorConfig,
	lifecycle: RuntimeLifecycleConfig,
	tags: { [string]: boolean },
}

export type Npc = typeof(setmetatable(
	{} :: {
		_isNpcInstance: boolean,
		_isDestroyed: boolean,
		uniqueId: string,
		archetype: string,
		displayName: string,
		faction: string,
		ownerPlayer: Player?,
		modelTemplate: Model?,
		model: Model?,
		humanoid: Humanoid?,
		rootPart: BasePart?,
		maxHp: number,
		hp: number,
		damage: number,
		defense: number,
		dmg: number,
		def: number,
		movement: RuntimeMovementConfig,
		combat: RuntimeCombatConfig,
		behavior: NpcBehaviorConfig,
		lifecycle: RuntimeLifecycleConfig,
		tags: { [string]: boolean },
		signals: NpcSignals,
		state: NpcState,
		currentTarget: any?,
		spawnCFrame: CFrame?,
		isSpawned: boolean,
		isAlive: boolean,
		npcs: { [string]: Npc },
		_thinkAccumulator: number,
		_lastAttackAt: number,
		_lastWanderAt: number,
		_lastMoveTarget: Vector3?,
		_heartbeatConnection: RBXScriptConnection?,
	},
	Npc
))
export type npc = Npc

local DEFAULT_ARCHETYPE = "GenericNpc"
local DEFAULT_FACTION = "Neutral"
local DEFAULT_MAX_HP = 100
local DEFAULT_DAMAGE = 10
local DEFAULT_DEFENSE = 0

local DEFAULT_WALK_SPEED = 8
local DEFAULT_JUMP_POWER = 50
local DEFAULT_DETECTION_RANGE = 45
local DEFAULT_LOSE_TARGET_RANGE = 65
local DEFAULT_WANDER_RADIUS = 25
local DEFAULT_WANDER_INTERVAL = 2.5
local DEFAULT_THINK_INTERVAL = 0.2
local DEFAULT_MOVE_REPATH_DISTANCE = 2

local DEFAULT_ATTACK_RANGE = 4
local DEFAULT_ATTACK_COOLDOWN = 1.1
local DEFAULT_MIN_DAMAGE = 1
local DEFAULT_DAMAGE_VARIANCE = 0.1

local ACTIVE_NPCS_BY_ID: { [string]: Npc } = {}
local ACTIVE_NPCS_BY_MODEL: { [Model]: Npc } = {}

local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local npcAssetFolder = if assetsFolder then assetsFolder:FindFirstChild("Npcs") else nil
local NPC_ASSET_FOLDER: Instance? = npcAssetFolder

local RANDOM = Random.new()

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	local numeric = fallback
	if typeof(value) == "number" and value == value then
		numeric = value
	end

	if minimum ~= nil and numeric < minimum then
		numeric = minimum
	end

	if maximum ~= nil and numeric > maximum then
		numeric = maximum
	end

	return numeric
end

local function sanitizeString(value: any, fallback: string): string
	if typeof(value) ~= "string" then
		return fallback
	end
	if value == "" then
		return fallback
	end
	return value
end

local function sanitizeBoolean(value: any, fallback: boolean): boolean
	if typeof(value) == "boolean" then
		return value
	end
	return fallback
end

local function sanitizeTags(rawTags: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if typeof(rawTags) ~= "table" then
		return out
	end

	for key, value in rawTags do
		if typeof(key) == "string" then
			out[key] = value == true
		end
	end

	return out
end

local function asPlayer(value: any): Player?
	if typeof(value) == "Instance" and value:IsA("Player") then
		return value
	end
	return nil
end

local function asFunction(value: any): ((...any) -> ())?
	if typeof(value) == "function" then
		return value
	end
	return nil
end

local function splitModelPathTokens(modelPath: string): { string }
	local normalized = string.gsub(modelPath, "\\", "/")
	normalized = string.gsub(normalized, "%.", "/")

	local out = {}
	for token in string.gmatch(normalized, "[^/]+") do
		if token ~= "" then
			table.insert(out, token)
		end
	end
	return out
end

local function resolveModelFromAssetFolder(modelName: string): Model?
	if NPC_ASSET_FOLDER == nil then
		return nil
	end

	local pathTokens = splitModelPathTokens(modelName)
	if #pathTokens > 1 then
		local cursor: Instance? = NPC_ASSET_FOLDER
		for _, token in pathTokens do
			if cursor == nil then
				return nil
			end
			cursor = cursor:FindFirstChild(token)
		end

		if cursor and cursor:IsA("Model") then
			return cursor
		end
	end

	local candidate = NPC_ASSET_FOLDER:FindFirstChild(modelName)
	if candidate and candidate:IsA("Model") then
		return candidate
	end

	local targetName = if #pathTokens > 0 then pathTokens[#pathTokens] else modelName
	local targetNameLower = string.lower(targetName)
	for _, descendant in NPC_ASSET_FOLDER:GetDescendants() do
		if descendant:IsA("Model") and string.lower(descendant.Name) == targetNameLower then
			return descendant
		end
	end

	return nil
end

local function resolveModelTemplate(rawModel: any, rawModelName: any, archetype: string): Model?
	if typeof(rawModel) == "Instance" and rawModel:IsA("Model") then
		return rawModel
	end

	if typeof(rawModel) == "string" and rawModel ~= "" then
		local byRawModelName = resolveModelFromAssetFolder(rawModel)
		if byRawModelName then
			return byRawModelName
		end
	end

	if typeof(rawModelName) == "string" and rawModelName ~= "" then
		local byModelName = resolveModelFromAssetFolder(rawModelName)
		if byModelName then
			return byModelName
		end
	end

	if archetype ~= "" then
		local byArchetype = resolveModelFromAssetFolder(archetype)
		if byArchetype then
			return byArchetype
		end
	end

	return nil
end

local function resolveHumanoidFromModel(model: Model?): Humanoid?
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
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

local function isNpcInstance(value: any): boolean
	return typeof(value) == "table" and (value :: any)._isNpcInstance == true
end

local function resolveModelFromTarget(target: any): Model?
	if target == nil then
		return nil
	end

	if isNpcInstance(target) then
		return (target :: Npc).model
	end

	if typeof(target) ~= "Instance" then
		return nil
	end

	if target:IsA("Player") then
		local character = target.Character
		if character and character:IsA("Model") then
			return character
		end
		return nil
	end

	if target:IsA("Model") then
		return target
	end

	if target:IsA("Humanoid") then
		local parentModel = target.Parent
		if parentModel and parentModel:IsA("Model") then
			return parentModel
		end
		return nil
	end

	if target:IsA("BasePart") then
		return target:FindFirstAncestorOfClass("Model")
	end

	return nil
end

local function resolveHumanoidFromTarget(target: any): Humanoid?
	if target == nil then
		return nil
	end

	if isNpcInstance(target) then
		return (target :: Npc).humanoid
	end

	if typeof(target) == "Instance" and target:IsA("Humanoid") then
		return target
	end

	local model = resolveModelFromTarget(target)
	return resolveHumanoidFromModel(model)
end

local function resolvePositionFromTarget(target: any): Vector3?
	if target == nil then
		return nil
	end

	if typeof(target) == "Vector3" then
		return target
	end

	if isNpcInstance(target) then
		return (target :: Npc):getPosition()
	end

	if typeof(target) == "Instance" then
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
	end

	local model = resolveModelFromTarget(target)
	local rootPart = resolveRootPart(model)
	if rootPart then
		return rootPart.Position
	end

	return nil
end

local function resolveNpcFromTarget(target: any): Npc?
	if isNpcInstance(target) then
		return target :: Npc
	end

	local model = resolveModelFromTarget(target)
	if model == nil then
		return nil
	end

	return ACTIVE_NPCS_BY_MODEL[model]
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection then
		connection:Disconnect()
	end
end

local function normalizeConfig(
	configOrHp: NpcConfig | number,
	damage: number?,
	defense: number?,
	legacyModel: Instance?
): NormalizedNpcConfig
	local rawConfig: any = {}
	local legacyHp = DEFAULT_MAX_HP
	local legacyDamage = DEFAULT_DAMAGE
	local legacyDefense = DEFAULT_DEFENSE
	local legacyTemplate: any = legacyModel

	if typeof(configOrHp) == "table" then
		rawConfig = configOrHp
		if rawConfig.model ~= nil then
			legacyTemplate = rawConfig.model
		end
	else
		legacyHp = sanitizeNumber(configOrHp, DEFAULT_MAX_HP, 1, nil)
		legacyDamage = sanitizeNumber(damage, DEFAULT_DAMAGE, 0, nil)
		legacyDefense = sanitizeNumber(defense, DEFAULT_DEFENSE, 0, nil)
	end

	local rawStats = if typeof(rawConfig.stats) == "table" then rawConfig.stats else {}
	local maxHp = sanitizeNumber(rawStats.maxHp or rawConfig.maxHp or rawConfig.hp, legacyHp, 1, nil)
	local hp = sanitizeNumber(rawStats.hp or rawConfig.hp, maxHp, 0, maxHp)
	local baseDamage = sanitizeNumber(rawStats.damage or rawConfig.damage or rawConfig.dmg, legacyDamage, 0, nil)
	local baseDefense = sanitizeNumber(rawStats.defense or rawConfig.defense or rawConfig.def, legacyDefense, 0, nil)

	local archetype = sanitizeString(rawConfig.archetype, DEFAULT_ARCHETYPE)
	local displayName = sanitizeString(rawConfig.displayName, archetype)
	local faction = sanitizeString(rawConfig.faction, DEFAULT_FACTION)
	local ownerPlayer = asPlayer(rawConfig.ownerPlayer)

	local modelTemplate = resolveModelTemplate(legacyTemplate, rawConfig.modelName, archetype)

	local rawMovement = if typeof(rawConfig.movement) == "table" then rawConfig.movement else {}
	local detectionRange = sanitizeNumber(rawMovement.detectionRange, DEFAULT_DETECTION_RANGE, 0, nil)
	local loseTargetRange = sanitizeNumber(rawMovement.loseTargetRange, DEFAULT_LOSE_TARGET_RANGE, detectionRange, nil)

	local movement: RuntimeMovementConfig = {
		walkSpeed = sanitizeNumber(rawMovement.walkSpeed, DEFAULT_WALK_SPEED, 0, nil),
		jumpPower = sanitizeNumber(rawMovement.jumpPower, DEFAULT_JUMP_POWER, 0, nil),
		canMove = sanitizeBoolean(rawMovement.canMove, true),
		canWander = sanitizeBoolean(rawMovement.canWander, true),
		wanderRadius = sanitizeNumber(rawMovement.wanderRadius, DEFAULT_WANDER_RADIUS, 0, nil),
		wanderInterval = sanitizeNumber(rawMovement.wanderInterval, DEFAULT_WANDER_INTERVAL, 0.1, nil),
		thinkInterval = sanitizeNumber(rawMovement.thinkInterval, DEFAULT_THINK_INTERVAL, 0.03, nil),
		detectionRange = detectionRange,
		loseTargetRange = loseTargetRange,
		moveRepathDistance = sanitizeNumber(rawMovement.moveRepathDistance, DEFAULT_MOVE_REPATH_DISTANCE, 0, nil),
		autoRotate = sanitizeBoolean(rawMovement.autoRotate, true),
	}

	local rawCombat = if typeof(rawConfig.combat) == "table" then rawConfig.combat else {}
	local combat: RuntimeCombatConfig = {
		attackRange = sanitizeNumber(rawCombat.attackRange, DEFAULT_ATTACK_RANGE, 0, nil),
		attackCooldown = sanitizeNumber(rawCombat.attackCooldown, DEFAULT_ATTACK_COOLDOWN, 0, nil),
		minDamage = sanitizeNumber(rawCombat.minDamage, DEFAULT_MIN_DAMAGE, 0, nil),
		damageVariance = sanitizeNumber(rawCombat.damageVariance, DEFAULT_DAMAGE_VARIANCE, 0, 1),
		targetPlayers = sanitizeBoolean(rawCombat.targetPlayers, true),
		targetNpcs = sanitizeBoolean(rawCombat.targetNpcs, true),
		allowFriendlyFire = sanitizeBoolean(rawCombat.allowFriendlyFire, false),
	}

	local rawLifecycle = if typeof(rawConfig.lifecycle) == "table" then rawConfig.lifecycle else {}
	local spawnParent = if typeof(rawLifecycle.spawnParent) == "Instance" then rawLifecycle.spawnParent else Workspace
	local spawnCFrame = if typeof(rawLifecycle.spawnCFrame) == "CFrame" then rawLifecycle.spawnCFrame else nil
	local lifecycle: RuntimeLifecycleConfig = {
		spawnParent = spawnParent,
		spawnCFrame = spawnCFrame,
		autoStart = sanitizeBoolean(rawLifecycle.autoStart, false),
		autoDestroyModelOnDeath = sanitizeBoolean(rawLifecycle.autoDestroyModelOnDeath, true),
	}

	local rawBehavior = if typeof(rawConfig.behavior) == "table" then rawConfig.behavior else {}
	local behavior: NpcBehaviorConfig = {
		acquireTarget = asFunction(rawBehavior.acquireTarget) :: any,
		shouldTarget = asFunction(rawBehavior.shouldTarget) :: any,
		onSpawn = asFunction(rawBehavior.onSpawn) :: any,
		onThink = asFunction(rawBehavior.onThink) :: any,
		onAttack = asFunction(rawBehavior.onAttack) :: any,
		onDamageTaken = asFunction(rawBehavior.onDamageTaken) :: any,
		onDeath = asFunction(rawBehavior.onDeath) :: any,
	}

	return {
		archetype = archetype,
		displayName = displayName,
		faction = faction,
		ownerPlayer = ownerPlayer,
		modelTemplate = modelTemplate,
		stats = {
			maxHp = maxHp,
			hp = hp,
			damage = baseDamage,
			defense = baseDefense,
		},
		movement = movement,
		combat = combat,
		behavior = behavior,
		lifecycle = lifecycle,
		tags = sanitizeTags(rawConfig.tags),
	}
end

local function registerNpc(npcObject: Npc)
	ACTIVE_NPCS_BY_ID[npcObject.uniqueId] = npcObject
	if npcObject.model ~= nil then
		ACTIVE_NPCS_BY_MODEL[npcObject.model] = npcObject
	end
end

local function unregisterNpc(npcObject: Npc)
	ACTIVE_NPCS_BY_ID[npcObject.uniqueId] = nil
	if npcObject.model ~= nil then
		ACTIVE_NPCS_BY_MODEL[npcObject.model] = nil
	end
end

function Npc.New(configOrHp: NpcConfig | number, damage: number?, defense: number?, model: Instance?): Npc
	local normalized = normalizeConfig(configOrHp, damage, defense, model)

	local self = setmetatable({
		_isNpcInstance = true,
		_isDestroyed = false,
		uniqueId = HttpService:GenerateGUID(false),
		archetype = normalized.archetype,
		displayName = normalized.displayName,
		faction = normalized.faction,
		ownerPlayer = normalized.ownerPlayer,
		modelTemplate = normalized.modelTemplate,
		model = nil,
		humanoid = nil,
		rootPart = nil,
		maxHp = normalized.stats.maxHp,
		hp = normalized.stats.hp,
		damage = normalized.stats.damage,
		defense = normalized.stats.defense,
		dmg = normalized.stats.damage,
		def = normalized.stats.defense,
		movement = normalized.movement,
		combat = normalized.combat,
		behavior = normalized.behavior,
		lifecycle = normalized.lifecycle,
		tags = normalized.tags,
		signals = {
			spawned = Signal.new(),
			stateChanged = Signal.new(),
			targetChanged = Signal.new(),
			damaged = Signal.new(),
			attacked = Signal.new(),
			died = Signal.new(),
		},
		state = "Idle" :: NpcState,
		currentTarget = nil,
		spawnCFrame = normalized.lifecycle.spawnCFrame,
		isSpawned = false,
		isAlive = false,
		npcs = ACTIVE_NPCS_BY_ID,
		_thinkAccumulator = 0,
		_lastAttackAt = -math.huge,
		_lastWanderAt = 0,
		_lastMoveTarget = nil,
		_heartbeatConnection = nil,
	}, Npc)

	if self.lifecycle.autoStart then
		self:start(self.lifecycle.spawnCFrame)
	end

	return self
end

function Npc.IsNpc(value: any): boolean
	return isNpcInstance(value)
end

function Npc.GetById(uniqueId: string): Npc?
	return ACTIVE_NPCS_BY_ID[uniqueId]
end

function Npc.GetByModel(model: Model?): Npc?
	if model == nil then
		return nil
	end
	return ACTIVE_NPCS_BY_MODEL[model]
end

function Npc.GetAllActive(): { Npc }
	local out = {}
	for _, candidate in ACTIVE_NPCS_BY_ID do
		table.insert(out, candidate)
	end
	return out
end

function Npc._setState(self: Npc, nextState: NpcState)
	if self.state == nextState then
		return
	end

	local previousState = self.state
	self.state = nextState
	self.signals.stateChanged:Fire(nextState, previousState)
end

function Npc._rebuildRigRefs(self: Npc)
	local model = self.model
	if model == nil then
		self.humanoid = nil
		self.rootPart = nil
		return
	end

	self.humanoid = resolveHumanoidFromModel(model)
	self.rootPart = resolveRootPart(model)

	if model.PrimaryPart == nil and self.rootPart ~= nil then
		model.PrimaryPart = self.rootPart
	end

	if self.humanoid then
		self.humanoid.WalkSpeed = self.movement.walkSpeed
		self.humanoid.AutoRotate = self.movement.autoRotate
		if self.humanoid.UseJumpPower then
			self.humanoid.JumpPower = self.movement.jumpPower
		else
			self.humanoid.JumpHeight = math.max(0, self.movement.jumpPower * 0.06)
		end
	end
end

function Npc._disconnectRuntime(self: Npc)
	disconnectConnection(self._heartbeatConnection)
	self._heartbeatConnection = nil
	self._thinkAccumulator = 0
	self._lastMoveTarget = nil
end

function Npc._startThinkLoop(self: Npc)
	if self._heartbeatConnection ~= nil then
		return
	end

	self._heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:_onHeartbeat(dt)
	end)
end

function Npc.Start(self: Npc, spawnCFrame: CFrame?): Model?
	if self._isDestroyed then
		return nil
	end

	if self.isSpawned and self.model ~= nil then
		return self.model
	end

	if self.modelTemplate == nil then
		return nil
	end

	local model = self.modelTemplate:Clone()
	model.Parent = self.lifecycle.spawnParent

	local desiredCFrame = if spawnCFrame ~= nil then spawnCFrame else self.lifecycle.spawnCFrame
	if desiredCFrame ~= nil then
		model:PivotTo(desiredCFrame)
	end

	self.model = model
	self:_rebuildRigRefs()
	self.spawnCFrame = model:GetPivot()

	if self.hp <= 0 then
		self.hp = self.maxHp
	end

	self.isSpawned = true
	self.isAlive = true
	self._lastAttackAt = -math.huge
	self._lastWanderAt = os.clock()
	self:_setState("Idle")

	registerNpc(self)

	self:_startThinkLoop()
	self.signals.spawned:Fire(model)

	local onSpawn = self.behavior.onSpawn
	if onSpawn then
		onSpawn(self)
	end

	return model
end

function Npc.Respawn(self: Npc, spawnCFrame: CFrame?): Model?
	if self.model then
		unregisterNpc(self)
		self.model:Destroy()
	end

	self.model = nil
	self.humanoid = nil
	self.rootPart = nil
	self.isSpawned = false
	self.isAlive = false
	self.hp = self.maxHp

	return self:start(spawnCFrame)
end

function Npc.Stop(self: Npc, removeModel: boolean?)
	if self._isDestroyed then
		return
	end

	unregisterNpc(self)
	self:_disconnectRuntime()
	self:clearTarget()
	self.isAlive = false

	if self.state ~= "Dead" then
		self:_setState("Idle")
	end

	if removeModel == true and self.model ~= nil then
		self.model:Destroy()
		self.model = nil
		self.humanoid = nil
		self.rootPart = nil
		self.isSpawned = false
	end
end

function Npc.Destroy(self: Npc)
	if self._isDestroyed then
		return
	end

	self:stop(true)
	self._isDestroyed = true

	for _, signalObject in self.signals do
		signalObject:Destroy()
	end
end

function Npc.GetPosition(self: Npc): Vector3?
	local rootPart = self.rootPart
	if rootPart then
		return rootPart.Position
	end

	if self.model then
		return self.model:GetPivot().Position
	end

	return nil
end

function Npc.GetDistanceTo(self: Npc, target: any): number?
	local ownPosition = self:getPosition()
	local targetPosition = resolvePositionFromTarget(target)
	if ownPosition == nil or targetPosition == nil then
		return nil
	end

	return (targetPosition - ownPosition).Magnitude
end
function Npc.IsTargetValid(self: Npc, target: any): boolean
	if target == nil then
		return false
	end

	local targetPosition = resolvePositionFromTarget(target)
	local ownPosition = self:getPosition()
	if targetPosition == nil or ownPosition == nil then
		return false
	end

	if typeof(target) == "Vector3" then
		return true
	end

	local targetNpc = resolveNpcFromTarget(target)
	if targetNpc ~= nil then
		if targetNpc == self then
			return false
		end
		if not targetNpc.isAlive then
			return false
		end
		if (not self.combat.allowFriendlyFire) and targetNpc.faction == self.faction then
			return false
		end
	end

	local targetIsAlive = false
	if targetNpc ~= nil then
		targetIsAlive = targetNpc.isAlive
	else
		local targetHumanoid = resolveHumanoidFromTarget(target)
		if targetHumanoid ~= nil and targetHumanoid.Health > 0 then
			targetIsAlive = true
		end
	end
	if not targetIsAlive then
		return false
	end

	local distance = (targetPosition - ownPosition).Magnitude
	if distance > self.movement.loseTargetRange then
		return false
	end

	local shouldTarget = self.behavior.shouldTarget
	if shouldTarget then
		return shouldTarget(self, target)
	end

	return true
end

function Npc._isFriendlyPlayer(self: Npc, player: Player): boolean
	if self.combat.allowFriendlyFire then
		return false
	end

	if self.ownerPlayer and player == self.ownerPlayer then
		return true
	end

	local playerTeam = player.Team
	if playerTeam and playerTeam.Name == self.faction then
		return true
	end

	return false
end

function Npc.AcquireTarget(self: Npc): any?
	local customAcquire = self.behavior.acquireTarget
	if customAcquire then
		local customTarget = customAcquire(self)
		if customTarget ~= nil and self:isTargetValid(customTarget) then
			return customTarget
		end
	end

	local ownPosition = self:getPosition()
	if ownPosition == nil then
		return nil
	end

	local detectionRangeSquared = self.movement.detectionRange * self.movement.detectionRange
	local nearestDistanceSquared = detectionRangeSquared
	local nearestTarget: any = nil

	local function considerTarget(candidateTarget: any)
		local candidatePosition = resolvePositionFromTarget(candidateTarget)
		if candidatePosition == nil then
			return
		end

		local offset = candidatePosition - ownPosition
		local distanceSquared = offset:Dot(offset)
		if distanceSquared > nearestDistanceSquared then
			return
		end

		if not self:isTargetValid(candidateTarget) then
			return
		end

		nearestDistanceSquared = distanceSquared
		nearestTarget = candidateTarget
	end

	if self.combat.targetPlayers then
		for _, player in Players:GetPlayers() do
			if not self:_isFriendlyPlayer(player) then
				considerTarget(player)
			end
		end
	end

	if self.combat.targetNpcs then
		for _, npcObject in ACTIVE_NPCS_BY_ID do
			if npcObject ~= self then
				considerTarget(npcObject)
			end
		end
	end

	return nearestTarget
end

function Npc.SetTarget(self: Npc, target: any?): boolean
	if target == nil then
		self:clearTarget()
		return false
	end

	if not self:isTargetValid(target) then
		return false
	end

	local previousTarget = self.currentTarget
	self.currentTarget = target
	self.signals.targetChanged:Fire(target, previousTarget)
	return true
end

function Npc.ClearTarget(self: Npc)
	if self.currentTarget == nil then
		return
	end

	local previousTarget = self.currentTarget
	self.currentTarget = nil
	self.signals.targetChanged:Fire(nil, previousTarget)
end

function Npc.MoveTo(self: Npc, targetPosition: Vector3): boolean
	if self._isDestroyed or not self.isAlive then
		return false
	end
	if not self.movement.canMove then
		return false
	end

	if self.model == nil then
		return false
	end

	local rootPart = self.rootPart
	if rootPart == nil then
		self:_rebuildRigRefs()
		rootPart = self.rootPart
		if rootPart == nil then
			return false
		end
	end

	if self._lastMoveTarget ~= nil then
		local distanceToPreviousMoveTarget = (targetPosition - self._lastMoveTarget).Magnitude
		if distanceToPreviousMoveTarget < self.movement.moveRepathDistance then
			return true
		end
	end
	self._lastMoveTarget = targetPosition

	if self.humanoid then
		self.humanoid:MoveTo(targetPosition)
	else
		local direction = targetPosition - rootPart.Position
		local destination = CFrame.new(targetPosition)
		if direction.Magnitude > 0.01 then
			destination = CFrame.lookAt(targetPosition, targetPosition + direction.Unit, Vector3.new(0, 1, 0))
		end
		self.model:PivotTo(destination)
	end

	self:_setState("Moving")
	return true
end

function Npc.MoveInDirection(self: Npc, direction: Vector3, distance: number?): boolean
	local ownPosition = self:getPosition()
	if ownPosition == nil then
		return false
	end
	if direction.Magnitude <= 0 then
		return false
	end

	local moveDistance = sanitizeNumber(distance, 1, 0, nil)
	local moveTarget = ownPosition + direction.Unit * moveDistance
	return self:moveTo(moveTarget)
end

function Npc.StopMoving(self: Npc)
	if self.humanoid then
		self.humanoid:Move(Vector3.zero, true)
	end
	self._lastMoveTarget = nil
	if self.state ~= "Dead" then
		self:_setState("Idle")
	end
end

function Npc.Jump(self: Npc): boolean
	if self._isDestroyed or not self.isAlive then
		return false
	end
	if self.humanoid == nil then
		return false
	end

	self.humanoid.Jump = true
	return true
end

function Npc.RollDamage(self: Npc, rawDamage: number?): number
	local damage = sanitizeNumber(rawDamage, self.damage, 0, nil)
	if damage <= 0 then
		return 0
	end

	local variance = self.combat.damageVariance
	if variance > 0 then
		local multiplier = RANDOM:NextNumber(1 - variance, 1 + variance)
		damage *= multiplier
	end

	damage = math.floor(damage + 0.5)
	return math.max(self.combat.minDamage, damage)
end

function Npc.TakeDamage(self: Npc, rawDamage: number, source: any?): number
	if self._isDestroyed or not self.isAlive then
		return 0
	end

	local incomingDamage = sanitizeNumber(rawDamage, 0, 0, nil)
	if incomingDamage <= 0 then
		return 0
	end

	local mitigatedDamage = incomingDamage - self.defense
	if mitigatedDamage <= 0 then
		mitigatedDamage = self.combat.minDamage
	end
	mitigatedDamage = math.floor(mitigatedDamage + 0.5)

	self.hp = math.max(0, self.hp - mitigatedDamage)
	self.signals.damaged:Fire(mitigatedDamage, source, self.hp)

	local onDamageTaken = self.behavior.onDamageTaken
	if onDamageTaken then
		onDamageTaken(self, mitigatedDamage, source, self.hp)
	end

	if self.hp <= 0 then
		self:die(source)
	end

	return mitigatedDamage
end

function Npc.Heal(self: Npc, rawAmount: number): number
	if self._isDestroyed then
		return 0
	end

	local healAmount = sanitizeNumber(rawAmount, 0, 0, nil)
	if healAmount <= 0 then
		return 0
	end

	local hpBefore = self.hp
	self.hp = math.min(self.maxHp, self.hp + healAmount)
	return self.hp - hpBefore
end

function Npc.GiveDamage(self: Npc, target: any, rawDamage: number?): number
	if self._isDestroyed or not self.isAlive then
		return 0
	end

	local finalDamage = self:rollDamage(rawDamage)
	if finalDamage <= 0 then
		return 0
	end

	local targetNpc = resolveNpcFromTarget(target)
	if targetNpc ~= nil then
		if targetNpc == self then
			return 0
		end
		return targetNpc:takeDamage(finalDamage, self)
	end

	local targetHumanoid = resolveHumanoidFromTarget(target)
	if targetHumanoid == nil or targetHumanoid.Health <= 0 then
		return 0
	end

	targetHumanoid:TakeDamage(finalDamage)
	return finalDamage
end

function Npc.CanAttackTarget(self: Npc, target: any): boolean
	if self._isDestroyed or not self.isAlive then
		return false
	end
	if not self:isTargetValid(target) then
		return false
	end

	local ownPosition = self:getPosition()
	local targetPosition = resolvePositionFromTarget(target)
	if ownPosition == nil or targetPosition == nil then
		return false
	end

	return (targetPosition - ownPosition).Magnitude <= self.combat.attackRange
end

function Npc.Attack(self: Npc, target: any?): (boolean, number)
	if self._isDestroyed or not self.isAlive then
		return false, 0
	end

	local targetObject = if target ~= nil then target else self.currentTarget
	if targetObject == nil then
		return false, 0
	end

	local now = os.clock()
	local timeSinceLastAttack = now - self._lastAttackAt
	if timeSinceLastAttack < self.combat.attackCooldown then
		return false, 0
	end

	if not self:canAttackTarget(targetObject) then
		return false, 0
	end

	local damageDealt = self:giveDamage(targetObject)
	if damageDealt <= 0 then
		return false, 0
	end

	self._lastAttackAt = now
	self:_setState("Attacking")
	self.signals.attacked:Fire(targetObject, damageDealt)

	local onAttack = self.behavior.onAttack
	if onAttack then
		onAttack(self, targetObject, damageDealt)
	end

	return true, damageDealt
end

function Npc._tryWander(self: Npc)
	if not self.movement.canWander or not self.movement.canMove then
		return
	end
	if self.spawnCFrame == nil then
		return
	end

	local now = os.clock()
	local elapsed = now - self._lastWanderAt
	if elapsed < self.movement.wanderInterval then
		return
	end

	self._lastWanderAt = now

	local angle = RANDOM:NextNumber(0, math.pi * 2)
	local radius = RANDOM:NextNumber(0, self.movement.wanderRadius)
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local destination = self.spawnCFrame.Position + offset
	self:moveTo(destination)
end

function Npc._tickBehavior(self: Npc, dt: number)
	local onThink = self.behavior.onThink
	if onThink then
		onThink(self, dt)
	end

	local currentTarget = self.currentTarget
	if currentTarget ~= nil and not self:isTargetValid(currentTarget) then
		self:clearTarget()
		currentTarget = nil
	end

	if currentTarget == nil then
		local acquired = self:acquireTarget()
		if acquired ~= nil then
			self:setTarget(acquired)
			currentTarget = self.currentTarget
		end
	end

	if currentTarget ~= nil then
		if self:canAttackTarget(currentTarget) then
			local attacked = self:attack(currentTarget)
			if not attacked then
				local targetPosition = resolvePositionFromTarget(currentTarget)
				if targetPosition then
					self:moveTo(targetPosition)
				end
			end
		else
			local targetPosition = resolvePositionFromTarget(currentTarget)
			if targetPosition then
				self:moveTo(targetPosition)
			else
				self:clearTarget()
			end
		end
		return
	end

	self:_tryWander()
	if self.state ~= "Dead" and self.state ~= "Moving" then
		self:_setState("Idle")
	end
end

function Npc._onHeartbeat(self: Npc, dt: number)
	if self._isDestroyed or not self.isAlive then
		return
	end

	self._thinkAccumulator += dt
	if self._thinkAccumulator < self.movement.thinkInterval then
		return
	end

	local thinkDt = self._thinkAccumulator
	self._thinkAccumulator = 0
	self:_tickBehavior(thinkDt)
end

function Npc.Die(self: Npc, killer: any?)
	if self._isDestroyed or not self.isAlive then
		return
	end

	self.isAlive = false
	self.hp = 0
	self:clearTarget()
	self:_disconnectRuntime()
	unregisterNpc(self)
	self:_setState("Dead")

	self.signals.died:Fire(killer)

	local onDeath = self.behavior.onDeath
	if onDeath then
		onDeath(self, killer)
	end

	if self.lifecycle.autoDestroyModelOnDeath and self.model ~= nil then
		self.model:Destroy()
		self.model = nil
		self.humanoid = nil
		self.rootPart = nil
		self.isSpawned = false
	end
end

Npc.new = Npc.New
Npc.isNpc = Npc.IsNpc
Npc.getById = Npc.GetById
Npc.getByModel = Npc.GetByModel
Npc.getAllActive = Npc.GetAllActive
Npc.start = Npc.Start
Npc.respawn = Npc.Respawn
Npc.stop = Npc.Stop
Npc.destroy = Npc.Destroy
Npc.getPosition = Npc.GetPosition
Npc.getDistanceTo = Npc.GetDistanceTo
Npc.isTargetValid = Npc.IsTargetValid
Npc.acquireTarget = Npc.AcquireTarget
Npc.setTarget = Npc.SetTarget
Npc.clearTarget = Npc.ClearTarget
Npc.moveTo = Npc.MoveTo
Npc.moveInDirection = Npc.MoveInDirection
Npc.stopMoving = Npc.StopMoving
Npc.jump = Npc.Jump
Npc.rollDamage = Npc.RollDamage
Npc.takeDamage = Npc.TakeDamage
Npc.heal = Npc.Heal
Npc.giveDamage = Npc.GiveDamage
Npc.canAttackTarget = Npc.CanAttackTarget
Npc.attack = Npc.Attack
Npc.die = Npc.Die

return Npc
