--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioServiceUtils)
local InstanceUtils = require(script:FindFirstAncestor("game").Shared.Modules.Platform.InstanceUtils)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local NpcServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.NpcServiceUtils)
local SlimeAi = require(script:FindFirstAncestor("game").Shared.Classes.Npc.AiTypes.slime)
local StringUtils = require(script:FindFirstAncestor("game").Shared.Modules.Core.StringUtils)

type SlimeSpawnConfig = NpcServiceUtils.SlimeSpawnConfig
type NpcRuntimeState = NpcServiceUtils.NpcRuntimeState
type Runtime = any
type Service = any

local Slime = {}

local DEFAULT_SLIME_HP = 14
local DEFAULT_RUNTIME_HURTBOX_SIZE = Vector3.new(4, 3, 4)
local DEFAULT_SLIME_DAMAGE_BLOOD_AMOUNT = 50
local DEFAULT_SLIME_DEATH_BLOOD_AMOUNT = 100
local DEFAULT_SLIME_BLOOD_POOL_SIZE = NumberRange.new(0.95, 1.7)
local DEFAULT_SLIME_BLOOD_POOL_SIZE_Y = NumberRange.new(0.16, 0.28)
local DEFAULT_SLIME_BLOOD_POOL_STARTING_SIZE = Vector3.new(0.2, 0.42, 0.2)
local DEFAULT_SLIME_BLOOD_POOL_MAX_SIZE = 1.8
local DEFAULT_SLIME_BLOOD_POOL_EXPANSE_DIVIDER = 2
local SLIME_GEL_DROP_ITEM_ID = "Gel"
local SLIME_GEL_DROP_AMOUNT = 1

local NPC_AUDIO = (AudioRegistry :: any).Npcs or {}
local SLIME_AUDIO = (NPC_AUDIO :: any).Slimes or {}
local DEFAULT_SLIME_AUDIO_BINDINGS = (SLIME_AUDIO :: any).Default or {}
local GREEN_SLIME_AUDIO_BINDINGS = (SLIME_AUDIO :: any).GreenSlime or DEFAULT_SLIME_AUDIO_BINDINGS
local SLIME_AUDIO_KEY_BY_TOKEN = {
	jump = "Jump",
	land = "Land",
	hurt = "Hurt",
	hit = "Hurt",
	death = "Death",
}

function Slime.Init(_self: typeof(Slime), _service: Service)
	return
end

function Slime.IsRuntime(_self: typeof(Slime), runtime: Runtime): boolean
	return runtime ~= nil and runtime.npcType == "Slime"
end

function Slime.GetModel(_self: typeof(Slime), runtime: Runtime): Model?
	return runtime.slime.model
end

function Slime.GetPosition(_self: typeof(Slime), runtime: Runtime): Vector3?
	return runtime.slime:getPosition()
end

function Slime.SyncVitals(_self: typeof(Slime), runtime: Runtime)
	local slime = runtime.slime
	runtime.maxHp = slime.maxHp
	runtime.hp = math.clamp(slime.hp, 0, slime.maxHp)
	runtime.isAlive = slime.isAlive
end

function Slime.ResolveSoundSource(_self: typeof(Slime), service: Service, runtime: Runtime, soundNameRaw: any): any?
	if typeof(soundNameRaw) ~= "string" or soundNameRaw == "" then
		return nil
	end

	local token = StringUtils.compactToken(soundNameRaw)
	local soundKey = SLIME_AUDIO_KEY_BY_TOKEN[token]
	if soundKey ~= nil then
		local bindings = if (runtime.slime :: any).isGreenSlime
			then GREEN_SLIME_AUDIO_BINDINGS
			else DEFAULT_SLIME_AUDIO_BINDINGS
		local soundAssetIds = AudioServiceUtils.collectSoundAssetIds(bindings[soundKey])
		if #soundAssetIds > 0 then
			return soundAssetIds[service.random:NextInteger(1, #soundAssetIds)]
		end
	end

	return NpcServiceUtils.findDescendantByNameOfClass(runtime.slime.model, soundNameRaw, "Sound")
end

function Slime.GetGoreConfig(_self: typeof(Slime)): { [string]: any }
	return {
		damageBloodAmount = DEFAULT_SLIME_DAMAGE_BLOOD_AMOUNT,
		deathBloodAmount = DEFAULT_SLIME_DEATH_BLOOD_AMOUNT,
		bloodSettings = {
			DefaultSize = DEFAULT_SLIME_BLOOD_POOL_SIZE,
			SizeY = DEFAULT_SLIME_BLOOD_POOL_SIZE_Y,
			StartingSize = DEFAULT_SLIME_BLOOD_POOL_STARTING_SIZE,
			MaximumSize = DEFAULT_SLIME_BLOOD_POOL_MAX_SIZE,
			ExpanseDivider = DEFAULT_SLIME_BLOOD_POOL_EXPANSE_DIVIDER,
		},
	}
end

function Slime.RegisterEnemyHitbox(_self: typeof(Slime), service: Service, runtime: Runtime)
	local enemyHitbox = service.enemyHitbox
	if enemyHitbox == nil then
		return
	end

	local runtimeId = runtime.id
	local didRegister = enemyHitbox:registerEnemy({
		id = runtimeId,
		owner = runtime,
		model = runtime.slime.model,
		getModel = function(ownerRuntime: Runtime): Model?
			return ownerRuntime.slime.model
		end,
		getCenter = function(ownerRuntime: Runtime): Vector3?
			local center = service:resolveRuntimeHurtbox(ownerRuntime)
			return center
		end,
		getAlive = function(ownerRuntime: Runtime): boolean
			return ownerRuntime.isAlive and not ownerRuntime.isRemoving and ownerRuntime.slime.isAlive
		end,
		getDamage = function(ownerRuntime: Runtime): number
			return service:sanitizeNumber(ownerRuntime.slime.damage, 0, 0, 100000)
		end,
		getAttackCooldown = function(ownerRuntime: Runtime): number
			return service:sanitizeNumber(ownerRuntime.slime.combat.attackCooldown, 0.85, 0.05, 30)
		end,
		getHurtboxSize = function(ownerRuntime: Runtime, _model: Model?, _rootPart: BasePart?): Vector3
			local _, hurtboxSize = service:resolveRuntimeHurtbox(ownerRuntime)
			return hurtboxSize
		end,
		getAttackSize = function(ownerRuntime: Runtime, model: Model?, rootPart: BasePart?): Vector3
			local basePart = if rootPart ~= nil then rootPart else InstanceUtils.resolveModelRootPart(model)
			local baseSize = if basePart ~= nil then basePart.Size else DEFAULT_RUNTIME_HURTBOX_SIZE
			local slime = ownerRuntime.slime
			local attackRange = service:sanitizeNumber(slime.combat.attackRange, 3.5, 0.5, 25)
			local hopReach = service:sanitizeNumber(slime.hopDistance, 6, 1, 60) * 0.5
			local effectiveReach = math.max(attackRange, hopReach, 4)
			return Vector3.new(
				math.max(4, baseSize.X + 2),
				math.max(3, baseSize.Y + 1),
				math.max(6, baseSize.Z + effectiveReach * 2)
			)
		end,
		canHitPlayer = function(ownerRuntime: Runtime, player: Player): boolean
			local slime = ownerRuntime.slime
			if ownerRuntime.isRemoving or not ownerRuntime.isAlive or not slime.isAlive then
				return false
			end
			if not slime.aggroOnPlayer then
				return false
			end
			if slime.passiveUntilHit and not slime.hasBeenHit then
				return false
			end

			local distance = slime:getDistanceTo(player)
			if distance == nil then
				return false
			end
			local maxContactDistance = math.max(5.5, service:sanitizeNumber(slime.hopDistance, 6, 1, 60) * 0.5 + 2)
			return distance <= maxContactDistance
		end,
		onHitPlayer = function(ownerRuntime: Runtime, player: Player, damage: number)
			service:onEnemyHitPlayer(ownerRuntime.id, player, damage)
		end,
	})

	if didRegister then
		runtime.enemyHitboxId = runtimeId
	end
end

function Slime.ResolveRuntimeState(_self: typeof(Slime), _service: Service, runtime: Runtime): NpcRuntimeState
	local npc = runtime.npc
	if not runtime.isAlive then
		return "Dead"
	end
	if not runtime.biomeReady then
		return "AwaitingBiome"
	end
	if os.clock() - runtime.lastEnemyHitAt <= 0.25 then
		return "Attacking"
	end

	local currentTarget = npc.currentTarget
	local hasTarget = currentTarget ~= nil and npc:isTargetValid(currentTarget)
	if hasTarget then
		if npc:canAttackTarget(currentTarget) then
			return "Attacking"
		end
		return "Aggro"
	end

	if npc.state == "Moving" then
		return "Searching"
	end
	return "Idle"
end

function Slime.Spawn(_self: typeof(Slime), service: Service, spawnConfig: SlimeSpawnConfig): Runtime?
	local modelName = if spawnConfig.modelHierarchy ~= nil and spawnConfig.modelHierarchy ~= ""
		then spawnConfig.modelHierarchy
		else spawnConfig.modelName

	local slime = SlimeAi.new({
		archetype = spawnConfig.slimeType,
		displayName = spawnConfig.displayName,
		modelName = modelName,
		slimeType = spawnConfig.slimeType,
		hp = DEFAULT_SLIME_HP,
		maxHp = DEFAULT_SLIME_HP,
		aggroOnPlayer = spawnConfig.aggroOnPlayer,
		passiveUntilHit = spawnConfig.passiveUntilHit,
		lockTo2DPlane = true,
		planeX = spawnConfig.planeX,
		restDuration = spawnConfig.restDuration,
		hopDuration = spawnConfig.hopDuration,
		hopDistance = spawnConfig.hopDistance,
		movement = {
			canWander = false,
			thinkInterval = 0.1,
			autoRotate = false,
		},
		combat = {
			attackRange = 0,
			attackCooldown = 1.1,
		},
		lifecycle = {
			spawnParent = service.npcFolder,
			autoDestroyModelOnDeath = true,
			autoStart = false,
		},
	})

	local model = slime:start(spawnConfig.spawnCFrame)
	if model == nil then
		slime:destroy()
		return nil
	end

	local runtimeJanitor = Janitor.new()
	local animationEventJanitor = Janitor.new()
	runtimeJanitor:GiveChore(animationEventJanitor)

	local defaultAnimationEvents = NpcServiceUtils.createDefaultSlimeAnimationEvents()
	local runtime = {
		id = slime.uniqueId,
		entityId = if typeof(spawnConfig.slimeType) == "string" and spawnConfig.slimeType ~= ""
			then spawnConfig.slimeType
			else if typeof(spawnConfig.modelName) == "string" and spawnConfig.modelName ~= ""
				then spawnConfig.modelName
				else spawnConfig.displayName,
		npcType = "Slime",
		displayName = spawnConfig.displayName,
		npc = slime,
		slime = slime,
		hp = slime.hp,
		maxHp = slime.maxHp,
		isAlive = slime.isAlive,
		state = "Dormant",
		lastReason = "spawn",
		biomeName = "Unknown",
		biomeReady = false,
		animationEvents = NpcServiceUtils.sanitizeAnimationEventsByTrack(
			spawnConfig.animationEvents,
			defaultAnimationEvents
		),
		stateGraph = NpcServiceUtils.createDefaultStateMachineGraph(),
		updatedAt = os.clock(),
		janitor = runtimeJanitor,
		animationEventJanitor = animationEventJanitor,
		animationEventsBound = false,
		isRemoving = false,
		deathGoreEmitted = false,
		enemyHitboxId = nil,
		lastEnemyHitAt = -math.huge,
		lastPreDamageSlimeBloodAt = -math.huge,
	}

	service:trackRuntime(runtime)
	service:transitionRuntimeState(runtime, "Spawning", "spawn", true)
	service:updateRuntime(runtime, "spawn", true)
	service:broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_ADDED, service:createSnapshot(runtime))
	return runtime
end

function Slime.SpawnLoot(_self: typeof(Slime), service: Service, runtime: Runtime)
	local lootService = service.lootService
	if lootService == nil then
		return
	end

	local deathPosition = runtime.slime:getPosition()
	if deathPosition == nil then
		local rootPart = InstanceUtils.resolveModelRootPart(runtime.slime.model)
		if rootPart ~= nil then
			deathPosition = rootPart.Position
		end
	end
	if deathPosition == nil then
		return
	end

	lootService:spawnLootRuntime(SLIME_GEL_DROP_ITEM_ID, SLIME_GEL_DROP_AMOUNT, deathPosition, {
		sourceType = runtime.displayName,
	})
	lootService:spawnDropsFromSource(runtime.displayName, deathPosition, {
		sourceType = runtime.displayName,
	})
end

Slime.init = Slime.Init
Slime.isRuntime = Slime.IsRuntime
Slime.getModel = Slime.GetModel
Slime.getPosition = Slime.GetPosition
Slime.syncVitals = Slime.SyncVitals
Slime.resolveSoundSource = Slime.ResolveSoundSource
Slime.getGoreConfig = Slime.GetGoreConfig
Slime.registerEnemyHitbox = Slime.RegisterEnemyHitbox
Slime.resolveRuntimeState = Slime.ResolveRuntimeState
Slime.spawn = Slime.Spawn
Slime.spawnLoot = Slime.SpawnLoot

return Slime
