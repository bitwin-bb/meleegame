--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstanceUtils = require(script:FindFirstAncestor("game").Shared.Features.platform.modules.InstanceUtils)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local NpcServiceUtils = require(script:FindFirstAncestor("game").Shared.Features.npc.NpcServiceUtils)
local SlimeAi = require(script:FindFirstAncestor("game").Shared.Features.npc.classes.Npc.slime)
local SlimeRoot = require(script:FindFirstAncestor("game").Shared.Features.npc.components.SlimeRoot)

type SlimeSpawnConfig = NpcServiceUtils.SlimeSpawnConfig
type NpcRuntimeState = NpcServiceUtils.NpcRuntimeState
type Runtime = any
type Service = any

local Slime = {}

local DEFAULT_SLIME_HP = 14
local DEFAULT_RUNTIME_HURTBOX_SIZE = Vector3.new(4, 3, 4)
local SLIME_GEL_DROP_ITEM_ID = "Gel"
local SLIME_GEL_DROP_AMOUNT = 1
local SLIME_IDLE_MIN_FRAME_RATE = 3
local SLIME_IDLE_MAX_FRAME_RATE = 13

type SpriteState = {
	spritePhase: string,
	spriteFrame: number?,
	spriteFrameRate: number?,
	spritePhaseElapsed: number?,
	spritePhaseDuration: number?,
	spriteFacingSign: number?,
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

function Slime.RegisterEnemyHitbox(_self: any, service: Service, runtime: Runtime): ()
	local enemyHitbox = service.enemyHitbox
	if enemyHitbox == nil then
		return
	end

	local runtimeId = runtime.id
	local didRegister = (enemyHitbox.registerEnemy :: any)(enemyHitbox, {
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

function Slime.GetSpriteState(_self: typeof(Slime), _service: Service, runtime: Runtime): SpriteState
	local slime = runtime.slime
	if runtime.isAlive ~= true or slime.isAlive ~= true then
		return {
			spritePhase = "Dead",
			spriteFrame = 2,
			spriteFrameRate = 1,
			spriteFacingSign = slime._facingSign,
		}
	end

	if slime._isResting then
		local restDuration = math.max(0.001, slime.restDuration)
		local restAlpha = math.clamp(slime.restElapsed / restDuration, 0, 1)
		local easedAlpha = restAlpha * restAlpha
		return {
			spritePhase = "Idle",
			spriteFrameRate = SLIME_IDLE_MIN_FRAME_RATE
				+ (SLIME_IDLE_MAX_FRAME_RATE - SLIME_IDLE_MIN_FRAME_RATE) * easedAlpha,
			spritePhaseElapsed = slime.restElapsed,
			spritePhaseDuration = restDuration,
			spriteFacingSign = slime._facingSign,
		}
	end

	local hopDuration = math.max(0.001, slime.hopDuration)
	return {
		spritePhase = "Hop",
		spriteFrameRate = 1,
		spritePhaseElapsed = slime.hopElapsed,
		spritePhaseDuration = hopDuration,
		spriteFacingSign = slime._facingSign,
	}
end

function Slime.Spawn(_self: typeof(Slime), service: Service, spawnConfig: SlimeSpawnConfig): Runtime?
	local slime = SlimeAi.new({
		archetype = spawnConfig.slimeType,
		displayName = spawnConfig.displayName,
		modelFactory = function(): Model
			return SlimeRoot.createModel({
				name = spawnConfig.modelName,
				hp = DEFAULT_SLIME_HP,
				size = DEFAULT_RUNTIME_HURTBOX_SIZE,
			})
		end,
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
		stateGraph = NpcServiceUtils.createDefaultStateMachineGraph(),
		updatedAt = os.clock(),
		janitor = runtimeJanitor,
		isRemoving = false,
		enemyHitboxId = nil,
		lastEnemyHitAt = -math.huge,
		lastSpriteStateKey = nil,
	}

	service:trackRuntime(runtime)
	service:transitionRuntimeState(runtime, "Spawning", "spawn", true)
	service:updateRuntime(runtime, "spawn", true)
	service:broadcast(NpcServiceUtils.CLIENT_METHOD_NPC_ADDED, service:createSnapshot(runtime))
	return runtime
end

function Slime.SpawnLoot(_self: any, service: Service, runtime: Runtime): ()
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

	;(lootService.spawnLootRuntime :: any)(lootService, SLIME_GEL_DROP_ITEM_ID, SLIME_GEL_DROP_AMOUNT, deathPosition, {
		sourceType = runtime.displayName,
	})
	;(lootService.spawnDropsFromSource :: any)(lootService, runtime.displayName, deathPosition, {
		sourceType = runtime.displayName,
	})
end

Slime.init = Slime.Init
Slime.isRuntime = Slime.IsRuntime
Slime.getModel = Slime.GetModel
Slime.getPosition = Slime.GetPosition
Slime.syncVitals = Slime.SyncVitals
Slime.registerEnemyHitbox = Slime.RegisterEnemyHitbox
Slime.resolveRuntimeState = Slime.ResolveRuntimeState
Slime.getSpriteState = Slime.GetSpriteState
Slime.spawn = Slime.Spawn
Slime.spawnLoot = Slime.SpawnLoot

return Slime
