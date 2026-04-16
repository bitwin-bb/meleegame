--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trig = require(script:FindFirstAncestor("game").Shared.Modules.Math.Trig)
local Vec = require(script:FindFirstAncestor("game").Shared.Modules.Math.Vec)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local ResolveToolInstance = require(script:FindFirstAncestor("game").Shared.Modules.Game.ResolveToolInstance)

local MagicServiceUtils = {}

export type EffectDefinition = {
	effectType: string,
	magnitude: number,
	duration: number,
	tickInterval: number,
	stackRule: string,
	maxStacks: number,
	radius: number,
	jumps: number,
	jumpFalloff: number,
}

export type ProjectileRuntimeConfig = {
	enabled: boolean,
	speed: number,
	spread: number,
	count: number,
	lifetime: number,
	pierce: number,
	collisionBehavior: string,
	radius: number,
	homingEnabled: boolean,
	homingRange: number,
	homingTurnRate: number,
	poolSize: number,
	destroyOnWorldHit: boolean,
	canHitPlayers: boolean,
	canHitNpcs: boolean,
	template: BasePart?,
	visualSize: Vector3?,
	visualColor: Color3?,
}

export type WeaponCallbacks = {
	OnCast: ((context: { [string]: any }) -> ())?,
	OnTick: ((context: { [string]: any }) -> ())?,
	OnHit: ((context: { [string]: any }) -> ())?,
	OnExpire: ((context: { [string]: any }) -> ())?,
}

export type WeaponRuntimeConfig = {
	itemId: string,
	displayName: string,
	manaCost: number,
	baseDamage: number,
	knockback: number,
	castTime: number,
	cooldown: number,
	range: number,
	projectile: ProjectileRuntimeConfig,
	effects: { EffectDefinition },
	callbacks: WeaponCallbacks,
	definition: { [string]: any },
}

export type ModifierStats = {
	damageMultiplier: number,
	damageBonus: number,
	manaMultiplier: number,
	manaBonus: number,
	cooldownMultiplier: number,
	cooldownBonus: number,
	castTimeMultiplier: number,
	castTimeBonus: number,
	knockbackMultiplier: number,
	knockbackBonus: number,
	speedMultiplier: number,
	speedBonus: number,
	lifetimeMultiplier: number,
	lifetimeBonus: number,
	pierceBonus: number,
	projectileCountBonus: number,
	forceHoming: boolean?,
}

export type CastStats = {
	damage: number,
	manaCost: number,
	cooldown: number,
	castTime: number,
	knockback: number,
	projectileSpeed: number,
	projectileLifetime: number,
	pierce: number,
	projectileCount: number,
	projectileSpread: number,
	homingEnabled: boolean,
}

export type CastRequest = {
	trigger: string,
	aimDirection: Vector3?,
	aimPosition: Vector3?,
}

export type ReplicatedState = {
	mana: number,
	maxMana: number,
	regenPerSecond: number,
	equippedWeaponId: string?,
	equippedSlot: number?,
	cooldowns: { [string]: number },
	updatedAt: number,
}

MagicServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
MagicServiceUtils.NETWORK_METHOD_REQUEST_REFRESH_EQUIPPED = "requestRefreshEquipped"
MagicServiceUtils.NETWORK_METHOD_REQUEST_SET_INPUT_HELD = "requestSetInputHeld"
MagicServiceUtils.NETWORK_METHOD_REQUEST_CAST = "requestCast"
MagicServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
MagicServiceUtils.CLIENT_METHOD_ON_CAST_VISUAL = "onCastVisual"
MagicServiceUtils.CLIENT_METHOD_ON_IMPACT_VISUAL = "onImpactVisual"
MagicServiceUtils.DEFAULT_MANA_DATA_PATH = { "mana" }
MagicServiceUtils.MAGIC_PROJECTILE_FOLDER_NAME = "MagicProjectiles"
MagicServiceUtils.CLIENT_CAST_REQUEST_INTERVAL = 1 / 20
MagicServiceUtils.DEFAULT_MAX_MANA = 20
MagicServiceUtils.DEFAULT_MANA_REGEN = 8

local ATTACK_SPEED_TO_COOLDOWN = {
	["insanelyfast"] = 0.18,
	["veryfast"] = 0.24,
	["fast"] = 0.32,
	["normalspeed"] = 0.42,
	["normal"] = 0.42,
	["slow"] = 0.6,
	["veryslow"] = 0.82,
}

local KNOCKBACK_MAP = {
	none = 0,
	verylow = 1,
	low = 2,
	medium = 4,
	high = 6,
	veryhigh = 8,
	extreme = 10,
}

local STUN_ATTRIBUTE_NAMES = {
	"Stunned",
	"IsStunned",
	"MagicCastLocked",
	"MagicWeaponService_Stunned",
}

local function trim(raw: any): string
	if typeof(raw) ~= "string" then
		return ""
	end
	return string.match(raw, "^%s*(.-)%s*$") or ""
end

local function token(raw: any): string
	local value = string.lower(trim(raw))
	if value == "" then
		return ""
	end
	return string.gsub(value, "[%s_%-%.]+", "")
end

local function num(raw: any, fallback: number, minValue: number?, maxValue: number?): number
	local value = fallback
	if typeof(raw) == "number" and raw == raw then
		value = raw
	elseif typeof(raw) == "string" then
		local parsed = tonumber(trim(raw))
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end
	if minValue ~= nil and value < minValue then
		value = minValue
	end
	if maxValue ~= nil and value > maxValue then
		value = maxValue
	end
	return value
end

local function int(raw: any, fallback: number, minValue: number?, maxValue: number?): number
	return math.floor(num(raw, fallback, minValue, maxValue))
end

local function bool(raw: any, fallback: boolean): boolean
	if typeof(raw) == "boolean" then
		return raw
	end
	return fallback
end

local function asVector3(raw: any): Vector3?
	if typeof(raw) == "Vector3" then
		return raw
	end
	if typeof(raw) ~= "table" then
		return nil
	end
	local source = raw :: { [string]: any }
	local x = source.x
	if typeof(x) ~= "number" then
		x = source.X
	end
	local y = source.y
	if typeof(y) ~= "number" then
		y = source.Y
	end
	local z = source.z
	if typeof(z) ~= "number" then
		z = source.Z
	end
	if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
		return nil
	end
	return Vector3.new(x, y, z)
end

local function asColor3(raw: any): Color3?
	if typeof(raw) == "Color3" then
		return raw
	end
	if typeof(raw) ~= "table" then
		return nil
	end
	local source = raw :: { [string]: any }
	local r = source.r
	if typeof(r) ~= "number" then
		r = source.R
	end
	local g = source.g
	if typeof(g) ~= "number" then
		g = source.G
	end
	local b = source.b
	if typeof(b) ~= "number" then
		b = source.B
	end
	if typeof(r) ~= "number" or typeof(g) ~= "number" or typeof(b) ~= "number" then
		return nil
	end
	return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

local function knockback(raw: any): number
	if typeof(raw) == "number" then
		return math.max(0, raw)
	end
	local mapped = KNOCKBACK_MAP[token(raw)]
	if mapped ~= nil then
		return mapped
	end
	return 2.5
end

local function attackSpeedCooldown(raw: any): number?
	return ATTACK_SPEED_TO_COOLDOWN[token(raw)]
end

function MagicServiceUtils.IsMagicTool(toolRaw: any): boolean
	local normalized = token(ResolveToolInstance.resolveToolItemType(toolRaw))
	return normalized == "magicweapon" or normalized == "magic" or normalized == "staff" or normalized == "spell"
end

function MagicServiceUtils.ResolveToolItemId(toolRaw: any): string?
	return ResolveToolInstance.resolveToolItemId(toolRaw)
end

function MagicServiceUtils.ResolveToolByItemId(characterRaw: any, backpackRaw: any, itemIdRaw: any): Tool?
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return nil
	end
	local function findIn(containerRaw: any): Tool?
		if typeof(containerRaw) ~= "Instance" then
			return nil
		end
		for _, child in (containerRaw :: Instance):GetChildren() do
			if not child:IsA("Tool") then
				continue
			end
			if MagicServiceUtils.ResolveToolItemId(child) == itemId then
				return child
			end
		end
		return nil
	end
	return findIn(characterRaw) or findIn(backpackRaw)
end

function MagicServiceUtils.ResolveSelectedItemIdFromInventoryState(stateRaw: any): (string?, number?)
	if typeof(stateRaw) ~= "table" then
		return nil, nil
	end
	local state = stateRaw :: { [string]: any }
	local selectedSlot = state.selectedSlot
	if typeof(selectedSlot) ~= "number" then
		return nil, nil
	end
	local slots = state.slots
	if typeof(slots) ~= "table" then
		return nil, math.floor(selectedSlot)
	end
	local slot = slots[math.floor(selectedSlot)]
	if typeof(slot) ~= "table" then
		return nil, math.floor(selectedSlot)
	end
	local stack = (slot :: any).stack
	if typeof(stack) ~= "table" then
		return nil, math.floor(selectedSlot)
	end
	local itemId = trim((stack :: any).itemId)
	if itemId == "" then
		return nil, math.floor(selectedSlot)
	end
	return itemId, math.floor(selectedSlot)
end

function MagicServiceUtils.SanitizeManaState(manaRaw: any): (number, number, number)
	if typeof(manaRaw) ~= "table" then
		return MagicServiceUtils.DEFAULT_MAX_MANA, MagicServiceUtils.DEFAULT_MAX_MANA, MagicServiceUtils.DEFAULT_MANA_REGEN
	end
	local source = manaRaw :: { [string]: any }
	local maxMana = num(
		source.maxMana or source.maximum or source.max,
		MagicServiceUtils.DEFAULT_MAX_MANA,
		1,
		100000
	)
	local mana = num(source.mana or source.current, maxMana, 0, maxMana)
	local regen = num(
		source.regenPerSecond or source.manaRegen or source.regen or source.recovery,
		MagicServiceUtils.DEFAULT_MANA_REGEN,
		0,
		10000
	)
	return mana, maxMana, regen
end

function MagicServiceUtils.SanitizeReplicatedState(raw: any, fallbackRaw: any): ReplicatedState
	local fallback = if typeof(fallbackRaw) == "table"
		then (fallbackRaw :: ReplicatedState)
		else {
			mana = MagicServiceUtils.DEFAULT_MAX_MANA,
			maxMana = MagicServiceUtils.DEFAULT_MAX_MANA,
			regenPerSecond = MagicServiceUtils.DEFAULT_MANA_REGEN,
			equippedWeaponId = nil,
			equippedSlot = nil,
			cooldowns = {},
			updatedAt = os.clock(),
		}
	local source = if typeof(raw) == "table" then (raw :: { [string]: any }) else {}
	local maxMana = num(source.maxMana, fallback.maxMana, 1, 100000)
	local mana = num(source.mana, fallback.mana, 0, maxMana)
	local regenPerSecond = num(source.regenPerSecond, fallback.regenPerSecond, 0, 10000)
	local equippedWeaponId = trim(source.equippedWeaponId)
	local equippedSlotRaw = source.equippedSlot
	local equippedSlot = if typeof(equippedSlotRaw) == "number" and equippedSlotRaw == equippedSlotRaw
		then math.floor(equippedSlotRaw)
		else fallback.equippedSlot
	local cooldowns: { [string]: number } = {}
	if typeof(source.cooldowns) == "table" then
		for key, value in source.cooldowns do
			if typeof(key) ~= "string" then
				continue
			end
			local remaining = num(value, 0, 0, 600)
			if remaining > 0 then
				cooldowns[key] = remaining
			end
		end
	else
		for key, value in fallback.cooldowns do
			cooldowns[key] = value
		end
	end

	return {
		mana = mana,
		maxMana = maxMana,
		regenPerSecond = regenPerSecond,
		equippedWeaponId = if equippedWeaponId ~= "" then equippedWeaponId else nil,
		equippedSlot = equippedSlot,
		cooldowns = cooldowns,
		updatedAt = num(source.updatedAt, fallback.updatedAt, 0, math.huge),
	}
end

function MagicServiceUtils.SanitizeCastRequest(raw: any): CastRequest
	local source = if typeof(raw) == "table" then (raw :: { [string]: any }) else {}
	return {
		trigger = trim(source.trigger) ~= "" and trim(source.trigger) or "Cast",
		aimDirection = asVector3(source.aimDirection),
		aimPosition = asVector3(source.aimPosition),
	}
end

function MagicServiceUtils.ResolveCastDirection(origin: Vector3, castRequestRaw: any, fallbackRaw: any): Vector3
	local request = MagicServiceUtils.SanitizeCastRequest(castRequestRaw)
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else Vector3.new(0, 0, -1)
	local fallbackUnit = Vec.unit(fallback, Vector3.new(0, 0, -1))
	if request.aimDirection ~= nil and request.aimDirection.Magnitude > 1e-4 then
		return Vec.unit(request.aimDirection, fallbackUnit)
	end
	if request.aimPosition ~= nil then
		local offset = request.aimPosition - origin
		if offset.Magnitude > 1e-4 then
			return Vec.unit(offset, fallbackUnit)
		end
	end
	return fallbackUnit
end

function MagicServiceUtils.ApplySpread(directionRaw: Vector3, spreadRaw: any, indexRaw: any, countRaw: any): Vector3
	local direction = Vec.unit(directionRaw, Vector3.new(0, 0, -1))
	local spread = num(spreadRaw, 0, 0, 120)
	local count = int(countRaw, 1, 1, 64)
	if spread <= 1e-3 or count <= 1 then
		return direction
	end
	local index = int(indexRaw, 1, 1, count)
	local alpha = ((index - 1) / (count - 1)) - 0.5
	local yaw = Trig.degToRad(alpha * spread)
	local look = CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, yaw, 0)
	return look.LookVector
end

function MagicServiceUtils.ResolveHumanoidFromHitPart(hitPartRaw: any): Humanoid?
	if typeof(hitPartRaw) ~= "Instance" or not hitPartRaw:IsA("BasePart") then
		return nil
	end
	local model = (hitPartRaw :: BasePart):FindFirstAncestorOfClass("Model")
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function MagicServiceUtils.IsHumanoidAlive(humanoidRaw: any): boolean
	if typeof(humanoidRaw) ~= "Instance" or not humanoidRaw:IsA("Humanoid") then
		return false
	end
	local humanoid = humanoidRaw :: Humanoid
	if humanoid.Health <= 0 then
		return false
	end
	return humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

function MagicServiceUtils.IsPlayerStunned(player: Player, character: Model?, humanoid: Humanoid?): boolean
	local function hasAny(instance: Instance?): boolean
		if instance == nil then
			return false
		end
		for _, attributeName in STUN_ATTRIBUTE_NAMES do
			if instance:GetAttribute(attributeName) == true then
				return true
			end
		end
		return false
	end
	return hasAny(player) or hasAny(character) or hasAny(humanoid)
end

function MagicServiceUtils.BuildWeaponRuntimeConfig(weaponConfigRaw: any): WeaponRuntimeConfig?
	if typeof(weaponConfigRaw) ~= "table" then
		return nil
	end
	local weaponConfig = weaponConfigRaw :: { [string]: any }
	local definition = if typeof(weaponConfig.definition) == "table" then weaponConfig.definition else {}
	local root = if typeof((definition :: any).magicWeapon) == "table"
		then (definition :: any).magicWeapon
		else if typeof((definition :: any).magic) == "table" then (definition :: any).magic else {}
	local stats = if typeof((definition :: any).stats) == "table" then (definition :: any).stats else {}
	local baseProjectile = if typeof(weaponConfig.projectile) == "table" then weaponConfig.projectile else {}
	local projectileExtra = if typeof((root :: any).projectile) == "table"
		then (root :: any).projectile
		else if typeof((definition :: any).projectile) == "table" then (definition :: any).projectile else {}
	local homingRaw = (projectileExtra :: any).homing
	local homingTable = if typeof(homingRaw) == "table" then (homingRaw :: { [string]: any }) else nil
	local collisionBehavior = token((projectileExtra :: any).collisionBehavior)
	local collisionMode = if collisionBehavior == "overlap" or collisionBehavior == "pierce" or collisionBehavior == "raycast"
		then collisionBehavior
		else "raycast"

	local effectsRaw = (root :: any).onHitEffects
		or (root :: any).effects
		or (definition :: any).onHitEffects
		or (definition :: any).effects
	local effects: { EffectDefinition } = {}
	if typeof(effectsRaw) == "table" then
		for _, effectRaw in effectsRaw do
			if typeof(effectRaw) ~= "table" then
				continue
			end
			local effect = effectRaw :: { [string]: any }
			local effectType = token(effect.effectType or effect.type)
			if effectType == "" then
				continue
			end
			table.insert(effects, {
				effectType = effectType,
				magnitude = num(effect.magnitude, if effectType == "lifesteal" then 0.1 else 1, 0, 100000),
				duration = num(effect.duration, if effectType == "burn" or effectType == "slow" then 4 else 0, 0, 60),
				tickInterval = num(effect.tickInterval, 0.5, 0.05, 10),
				stackRule = token(effect.stackRule) ~= "" and token(effect.stackRule) or "refresh",
				maxStacks = int(effect.maxStacks, 1, 1, 99),
				radius = num(effect.radius, 10, 0, 500),
				jumps = int(effect.jumps, 2, 0, 16),
				jumpFalloff = num(effect.jumpFalloff, 0.65, 0, 1),
			})
		end
	end

	local attackSpeedCooldownValue = attackSpeedCooldown((stats :: any).attackSpeed)
	local cooldownFallback =
		if attackSpeedCooldownValue ~= nil then attackSpeedCooldownValue else num(weaponConfig.cooldown, 0.42, 0, 60)
	local callbacksRaw = if typeof((root :: any).callbacks) == "table"
		then (root :: any).callbacks
		else if typeof((definition :: any).callbacks) == "table" then (definition :: any).callbacks else {}

	return {
		itemId = trim(weaponConfig.itemId) ~= "" and trim(weaponConfig.itemId) or "unknownMagicWeapon",
		displayName = trim(weaponConfig.displayName) ~= "" and trim(weaponConfig.displayName) or "Magic Weapon",
		manaCost = num((root :: any).manaCost or weaponConfig.manaCost or (stats :: any).manaCost or (stats :: any).mana, 8, 0, 100000),
		baseDamage = num((root :: any).damage or weaponConfig.damage or (stats :: any).magicDamage or (stats :: any).dmg, 10, 0, 1_000_000),
		knockback = knockback((root :: any).knockback or (definition :: any).knockback or (stats :: any).knockback),
		castTime = num((root :: any).castTime or weaponConfig.castTime, 0.12, 0, 30),
		cooldown = num((root :: any).cooldown or weaponConfig.cooldown, cooldownFallback, 0, 60),
		range = num((root :: any).range or weaponConfig.range or (definition :: any).range, 250, 1, 2000),
		projectile = {
			enabled = bool(baseProjectile.enabled, true),
			speed = num((projectileExtra :: any).speed or baseProjectile.speed, 120, 1, 5000),
			spread = num((projectileExtra :: any).spread or baseProjectile.spread, 0, 0, 120),
			count = int((projectileExtra :: any).count or baseProjectile.count, 1, 1, 32),
			lifetime = num((projectileExtra :: any).lifetime or baseProjectile.lifetime, 2, 0.02, 120),
			pierce = int((projectileExtra :: any).pierce or (projectileExtra :: any).pierceCount or baseProjectile.pierce, 0, 0, 100),
			collisionBehavior = collisionMode,
			radius = num((projectileExtra :: any).radius, 0.5, 0, 64),
			homingEnabled = bool(
				(projectileExtra :: any).homingEnabled
					or (if homingTable ~= nil then homingTable.enabled else nil)
					or (if homingTable ~= nil then true else nil),
				false
			),
			homingRange = num(
				(projectileExtra :: any).homingRange or (if homingTable ~= nil then homingTable.range else nil),
				40,
				0,
				1000
			),
			homingTurnRate = num(
				(projectileExtra :: any).homingTurnRate or (if homingTable ~= nil then homingTable.turnRate else nil),
				4,
				0.01,
				40
			),
			poolSize = int((projectileExtra :: any).poolSize, 16, 1, 512),
			destroyOnWorldHit = bool((projectileExtra :: any).destroyOnWorldHit, true),
			canHitPlayers = bool((projectileExtra :: any).canHitPlayers, true),
			canHitNpcs = bool((projectileExtra :: any).canHitNpcs, true),
			template = if typeof((projectileExtra :: any).template) == "Instance" and (projectileExtra :: any).template:IsA("BasePart")
				then (projectileExtra :: any).template
				else nil,
			visualSize = asVector3((projectileExtra :: any).visualSize or (projectileExtra :: any).size),
			visualColor = asColor3((projectileExtra :: any).visualColor or (projectileExtra :: any).color),
		},
		effects = effects,
		callbacks = {
			OnCast = if typeof((callbacksRaw :: any).OnCast) == "function"
				then (callbacksRaw :: any).OnCast
				else if typeof((callbacksRaw :: any).onCast) == "function" then (callbacksRaw :: any).onCast else nil,
			OnTick = if typeof((callbacksRaw :: any).OnTick) == "function"
				then (callbacksRaw :: any).OnTick
				else if typeof((callbacksRaw :: any).onTick) == "function" then (callbacksRaw :: any).onTick else nil,
			OnHit = if typeof((callbacksRaw :: any).OnHit) == "function"
				then (callbacksRaw :: any).OnHit
				else if typeof((callbacksRaw :: any).onHit) == "function" then (callbacksRaw :: any).onHit else nil,
			OnExpire = if typeof((callbacksRaw :: any).OnExpire) == "function"
				then (callbacksRaw :: any).OnExpire
				else if typeof((callbacksRaw :: any).onExpire) == "function" then (callbacksRaw :: any).onExpire else nil,
		},
		definition = definition,
	}
end

function MagicServiceUtils.CreateDefaultModifier(): ModifierStats
	return {
		damageMultiplier = 1,
		damageBonus = 0,
		manaMultiplier = 1,
		manaBonus = 0,
		cooldownMultiplier = 1,
		cooldownBonus = 0,
		castTimeMultiplier = 1,
		castTimeBonus = 0,
		knockbackMultiplier = 1,
		knockbackBonus = 0,
		speedMultiplier = 1,
		speedBonus = 0,
		lifetimeMultiplier = 1,
		lifetimeBonus = 0,
		pierceBonus = 0,
		projectileCountBonus = 0,
		forceHoming = nil,
	}
end

function MagicServiceUtils.SanitizeModifier(raw: any): ModifierStats
	local source = if typeof(raw) == "table" then (raw :: { [string]: any }) else {}
	local modifier = MagicServiceUtils.CreateDefaultModifier()
	modifier.damageMultiplier = num(source.damageMultiplier, 1, 0, 100)
	modifier.damageBonus = num(source.damageBonus, 0, -100000, 100000)
	modifier.manaMultiplier = num(source.manaMultiplier or source.manaCostMultiplier, 1, 0, 100)
	modifier.manaBonus = num(source.manaBonus or source.manaCostBonus, 0, -100000, 100000)
	modifier.cooldownMultiplier = num(source.cooldownMultiplier, 1, 0, 100)
	modifier.cooldownBonus = num(source.cooldownBonus, 0, -100000, 100000)
	modifier.castTimeMultiplier = num(source.castTimeMultiplier, 1, 0, 100)
	modifier.castTimeBonus = num(source.castTimeBonus, 0, -100000, 100000)
	modifier.knockbackMultiplier = num(source.knockbackMultiplier, 1, 0, 100)
	modifier.knockbackBonus = num(source.knockbackBonus, 0, -100000, 100000)
	modifier.speedMultiplier = num(source.speedMultiplier or source.projectileSpeedMultiplier, 1, 0, 100)
	modifier.speedBonus = num(source.speedBonus or source.projectileSpeedBonus, 0, -100000, 100000)
	modifier.lifetimeMultiplier = num(source.lifetimeMultiplier or source.projectileLifetimeMultiplier, 1, 0, 100)
	modifier.lifetimeBonus = num(source.lifetimeBonus or source.projectileLifetimeBonus, 0, -100000, 100000)
	modifier.pierceBonus = int(source.pierceBonus, 0, -100, 100)
	modifier.projectileCountBonus = int(source.projectileCountBonus, 0, -20, 20)
	if typeof(source.forceHoming) == "boolean" then
		modifier.forceHoming = source.forceHoming
	end
	return modifier
end

function MagicServiceUtils.MergeModifiers(list: { any }): ModifierStats
	local merged = MagicServiceUtils.CreateDefaultModifier()
	for _, raw in list do
		local modifier = MagicServiceUtils.SanitizeModifier(raw)
		merged.damageMultiplier *= modifier.damageMultiplier
		merged.damageBonus += modifier.damageBonus
		merged.manaMultiplier *= modifier.manaMultiplier
		merged.manaBonus += modifier.manaBonus
		merged.cooldownMultiplier *= modifier.cooldownMultiplier
		merged.cooldownBonus += modifier.cooldownBonus
		merged.castTimeMultiplier *= modifier.castTimeMultiplier
		merged.castTimeBonus += modifier.castTimeBonus
		merged.knockbackMultiplier *= modifier.knockbackMultiplier
		merged.knockbackBonus += modifier.knockbackBonus
		merged.speedMultiplier *= modifier.speedMultiplier
		merged.speedBonus += modifier.speedBonus
		merged.lifetimeMultiplier *= modifier.lifetimeMultiplier
		merged.lifetimeBonus += modifier.lifetimeBonus
		merged.pierceBonus += modifier.pierceBonus
		merged.projectileCountBonus += modifier.projectileCountBonus
		if modifier.forceHoming ~= nil then
			merged.forceHoming = modifier.forceHoming
		end
	end
	return merged
end

function MagicServiceUtils.BuildCastStats(config: WeaponRuntimeConfig, modifierRaw: any): CastStats
	local modifier = MagicServiceUtils.SanitizeModifier(modifierRaw)
	local homingEnabled = config.projectile.homingEnabled
	if modifier.forceHoming ~= nil then
		homingEnabled = modifier.forceHoming
	end
	return {
		damage = math.max(0, config.baseDamage * modifier.damageMultiplier + modifier.damageBonus),
		manaCost = math.max(0, config.manaCost * modifier.manaMultiplier + modifier.manaBonus),
		cooldown = math.max(0, config.cooldown * modifier.cooldownMultiplier + modifier.cooldownBonus),
		castTime = math.max(0, config.castTime * modifier.castTimeMultiplier + modifier.castTimeBonus),
		knockback = math.max(0, config.knockback * modifier.knockbackMultiplier + modifier.knockbackBonus),
		projectileSpeed = math.max(1, config.projectile.speed * modifier.speedMultiplier + modifier.speedBonus),
		projectileLifetime = math.max(0.02, config.projectile.lifetime * modifier.lifetimeMultiplier + modifier.lifetimeBonus),
		pierce = math.max(0, config.projectile.pierce + modifier.pierceBonus),
		projectileCount = math.max(1, config.projectile.count + modifier.projectileCountBonus),
		projectileSpread = math.max(0, config.projectile.spread),
		homingEnabled = homingEnabled,
	}
end

function MagicServiceUtils.EnsureProjectileFolder(): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(MagicServiceUtils.MAGIC_PROJECTILE_FOLDER_NAME)
end

function MagicServiceUtils.CooldownsToRemaining(cooldownsRaw: any, now: number): { [string]: number }
	local remaining: { [string]: number } = {}
	if typeof(cooldownsRaw) ~= "table" then
		return remaining
	end
	for weaponId, expiresAtRaw in cooldownsRaw do
		if typeof(weaponId) ~= "string" or typeof(expiresAtRaw) ~= "number" then
			continue
		end
		local delta = expiresAtRaw - now
		if delta > 0 then
			remaining[weaponId] = delta
		end
	end
	return remaining
end

MagicServiceUtils.isMagicTool = MagicServiceUtils.IsMagicTool
MagicServiceUtils.resolveToolItemId = MagicServiceUtils.ResolveToolItemId
MagicServiceUtils.resolveToolByItemId = MagicServiceUtils.ResolveToolByItemId
MagicServiceUtils.resolveSelectedItemIdFromInventoryState = MagicServiceUtils.ResolveSelectedItemIdFromInventoryState
MagicServiceUtils.sanitizeManaState = MagicServiceUtils.SanitizeManaState
MagicServiceUtils.sanitizeReplicatedState = MagicServiceUtils.SanitizeReplicatedState
MagicServiceUtils.sanitizeCastRequest = MagicServiceUtils.SanitizeCastRequest
MagicServiceUtils.resolveCastDirection = MagicServiceUtils.ResolveCastDirection
MagicServiceUtils.applySpread = MagicServiceUtils.ApplySpread
MagicServiceUtils.resolveHumanoidFromHitPart = MagicServiceUtils.ResolveHumanoidFromHitPart
MagicServiceUtils.isHumanoidAlive = MagicServiceUtils.IsHumanoidAlive
MagicServiceUtils.isPlayerStunned = MagicServiceUtils.IsPlayerStunned
MagicServiceUtils.buildWeaponRuntimeConfig = MagicServiceUtils.BuildWeaponRuntimeConfig
MagicServiceUtils.createDefaultModifier = MagicServiceUtils.CreateDefaultModifier
MagicServiceUtils.sanitizeModifier = MagicServiceUtils.SanitizeModifier
MagicServiceUtils.mergeModifiers = MagicServiceUtils.MergeModifiers
MagicServiceUtils.buildCastStats = MagicServiceUtils.BuildCastStats
MagicServiceUtils.ensureProjectileFolder = MagicServiceUtils.EnsureProjectileFolder
MagicServiceUtils.cooldownsToRemaining = MagicServiceUtils.CooldownsToRemaining

return MagicServiceUtils
