--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Magic = require(script:FindFirstAncestor("game").Shared.Classes.Magic)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ServerBinderSupport = require(script:FindFirstAncestor("game").Server.Binders.ServerBinderSupport)
local MagicServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.MagicService.MagicServiceUtils)
local PlayerServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerService.PlayerServiceUtils)
local InventoryServiceServer = require(script:FindFirstAncestor("game").Server.Services.InventoryService.InventoryServiceServer)
local ManaServiceServer = require(script:FindFirstAncestor("game").Server.Services.ManaService.ManaServiceServer)
local BossServiceServer = require(script:FindFirstAncestor("game").Server.Services.BossService.BossServiceServer)
local NpcServiceServer = require(script:FindFirstAncestor("game").Server.Services.NpcService.NpcServiceServer)
local HpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpService.HpServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)

type WeaponRuntimeConfig = MagicServiceUtils.WeaponRuntimeConfig
type ModifierStats = MagicServiceUtils.ModifierStats
type CastStats = MagicServiceUtils.CastStats
type CastRequest = MagicServiceUtils.CastRequest

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type MagicController = {
	bindTool: (self: MagicController, toolRaw: any) -> boolean,
	unbindTool: (self: MagicController) -> (),
	setCharacter: (self: MagicController, characterRaw: any) -> (),
	setOwnerPlayer: (self: MagicController, playerRaw: any) -> (),
	queueCast: (self: MagicController, triggerRaw: any) -> boolean,
	resolveBoundWeaponConfig: (self: MagicController) -> any,
	destroy: (self: MagicController) -> (),
	cooldownUntil: number,
	weaponConfig: any,
}

type InventoryServiceServerObject = {
	getState: (self: InventoryServiceServerObject, player: Player) -> any,
}

type ManaServiceState = {
	mana: number,
	maxMana: number,
	regenPerSecond: number,
}

type ManaServiceServerObject = {
	getState: (self: ManaServiceServerObject, player: Player) -> ManaServiceState,
	canConsumeMana: (self: ManaServiceServerObject, player: Player?, amountRaw: any, contextRaw: any) -> boolean,
	consumeMana: (self: ManaServiceServerObject, player: Player?, amountRaw: any, contextRaw: any) -> boolean,
}

type NpcServiceServerObject = {
	damageNpcFromHitPart: (
		self: NpcServiceServerObject,
		hitPartRaw: any,
		damageRaw: any,
		source: any?
	) -> number,
}

type BossServiceServerObject = {
	damageBossFromHitPart: (
		self: BossServiceServerObject,
		hitPartRaw: any,
		damageRaw: any,
		sourceRaw: any?,
		damageContextRaw: any?
	) -> number,
}

type HpServiceServerObject = {
	healPlayer: (self: HpServiceServerObject, player: Player, amountRaw: any) -> number?,
}

type PlayerRuntime = {
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
	character: Model?,
	humanoid: Humanoid?,
	rootPart: BasePart?,
	inputHeld: boolean,
	lastAimRequest: CastRequest,
	lastAimDirection: Vector3,
	lastCastRequestAt: number,
	requestWindowStartedAt: number,
	requestsInWindow: number,
	lastStatePushAt: number,
	equippedItemId: string?,
	equippedSlot: number?,
	equippedTool: Tool?,
	magicController: MagicController?,
	weaponCooldowns: { [string]: number },
	pendingPreparedCast: { itemId: string, config: WeaponRuntimeConfig, stats: CastStats, castRequest: CastRequest }?,
	pendingCastByToken: {
		[number]: { itemId: string, config: WeaponRuntimeConfig, stats: CastStats, castRequest: CastRequest },
	},
	committedCastByToken: {
		[number]: { itemId: string, config: WeaponRuntimeConfig, stats: CastStats, castRequest: CastRequest },
	},
}

local MagicServiceServer = {}

local STATE_PUSH_INTERVAL = 0.15
local CAST_REQUEST_INTERVAL = 1 / 90
local CAST_REQUESTS_PER_SECOND_LIMIT = 30
local PROJECTILE_FIXED_STEP = 1 / 60
local PROJECTILE_MAX_OVERLAP_PARTS = 64

local function trim(raw: any): string
	if typeof(raw) ~= "string" then
		return ""
	end
	return string.match(raw, "^%s*(.-)%s*$") or ""
end

local function setCooldownValue(cooldowns: { [string]: number }, itemIdRaw: any, expiresAt: number)
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return
	end
	cooldowns[itemId] = expiresAt
	cooldowns[string.lower(itemId)] = expiresAt
end

local function getCooldownValue(cooldowns: { [string]: number }, itemIdRaw: any): number
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return 0
	end
	return cooldowns[itemId] or cooldowns[string.lower(itemId)] or 0
end

local function shallowCopy(sourceRaw: any): { [string]: any }
	local output = {}
	if typeof(sourceRaw) ~= "table" then
		return output
	end
	for key, value in sourceRaw do
		if typeof(key) == "string" then
			output[key] = value
		end
	end
	return output
end

local function looksLikeMagicDefinition(definitionRaw: any): boolean
	if typeof(definitionRaw) ~= "table" then
		return false
	end
	local definition = definitionRaw :: { [string]: any }
	if typeof(definition.magicWeapon) == "table" or typeof(definition.magic) == "table" then
		return true
	end

	local typeToken =
		string.lower(trim(definition.itemType or definition.type or definition.weaponType or definition.class))
	typeToken = string.gsub(typeToken, "[%s_%-]+", "")
	if typeToken == "magicweapon" or typeToken == "magic" or typeToken == "staff" or typeToken == "spell" then
		return true
	end

	local hasMagicLikeStats = definition.manaCost ~= nil
		or definition.castTime ~= nil
		or definition.onHitEffects ~= nil
		or definition.effects ~= nil
		or definition.projectile ~= nil
	return hasMagicLikeStats
end

local function shouldSilenceModuleRequireError(errorRaw: any): boolean
	local message = string.lower(trim(errorRaw))
	if message == "" then
		return false
	end
	if string.find(message, "did not return exactly one value", 1, true) ~= nil then
		return true
	end
	return false
end

local function resolveCastToken(contextRaw: any): number
	if typeof(contextRaw) ~= "table" then
		return -1
	end
	local context = contextRaw :: { [string]: any }
	local castTokenRaw = context.castToken
	if typeof(castTokenRaw) ~= "number" or castTokenRaw ~= castTokenRaw then
		return -1
	end
	local castToken = math.floor(castTokenRaw)
	if castToken <= 0 then
		return -1
	end
	return castToken
end

function MagicServiceServer.CreateRuntime(self: MagicServiceServer): PlayerRuntime
	return {
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		character = nil,
		humanoid = nil,
		rootPart = nil,
		inputHeld = false,
		lastAimRequest = {
			trigger = "None",
			aimDirection = nil,
			aimPosition = nil,
		},
		lastAimDirection = Vector3.new(0, 0, -1),
		lastCastRequestAt = -math.huge,
		requestWindowStartedAt = os.clock(),
		requestsInWindow = 0,
		lastStatePushAt = 0,
		equippedItemId = nil,
		equippedSlot = nil,
		equippedTool = nil,
		magicController = nil,
		weaponCooldowns = {},
		pendingPreparedCast = nil,
		pendingCastByToken = {},
		committedCastByToken = {},
	}
end

function MagicServiceServer.GetRuntime(self: MagicServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end
	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function MagicServiceServer.ResolveRuntimeByMagic(
	self: MagicServiceServer,
	magicControllerRaw: any
): (Player?, PlayerRuntime?)
	if typeof(magicControllerRaw) ~= "table" then
		return nil, nil
	end
	for player, runtime in self.playerRuntimes do
		if runtime.magicController == magicControllerRaw then
			return player, runtime
		end
	end
	return nil, nil
end

function MagicServiceServer.ResolveManaStateSnapshot(self: MagicServiceServer, player: Player): (number, number, number)
	local mana = MagicServiceUtils.DEFAULT_MAX_MANA
	local maxMana = MagicServiceUtils.DEFAULT_MAX_MANA
	local regenPerSecond = MagicServiceUtils.DEFAULT_MANA_REGEN
	local manaService = self.manaService
	if manaService == nil then
		return mana, maxMana, regenPerSecond
	end

	local success, manaStateOrError = pcall(function()
		return manaService:getState(player)
	end)
	if not success then
		return mana, maxMana, regenPerSecond
	end
	if typeof(manaStateOrError) ~= "table" then
		return mana, maxMana, regenPerSecond
	end

	local manaState = manaStateOrError :: { [string]: any }
	if typeof(manaState.mana) == "number" and manaState.mana == manaState.mana then
		mana = manaState.mana
	end
	if typeof(manaState.maxMana) == "number" and manaState.maxMana == manaState.maxMana then
		maxMana = manaState.maxMana
	end
	if typeof(manaState.regenPerSecond) == "number" and manaState.regenPerSecond == manaState.regenPerSecond then
		regenPerSecond = manaState.regenPerSecond
	end
	return mana, maxMana, regenPerSecond
end

function MagicServiceServer.PushState(self: MagicServiceServer, player: Player, runtime: PlayerRuntime)
	local now = os.clock()
	if now - runtime.lastStatePushAt < STATE_PUSH_INTERVAL then
		return
	end
	runtime.lastStatePushAt = now
	local mana, maxMana, regenPerSecond = self:resolveManaStateSnapshot(player)
	self.networker:fire(player, MagicServiceUtils.CLIENT_METHOD_APPLY_STATE, {
		mana = mana,
		maxMana = maxMana,
		regenPerSecond = regenPerSecond,
		equippedWeaponId = runtime.equippedItemId,
		equippedSlot = runtime.equippedSlot,
		cooldowns = MagicServiceUtils.cooldownsToRemaining(runtime.weaponCooldowns, now),
		updatedAt = now,
	})
end

function MagicServiceServer.GetEquippedMagicToolFromInventory(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime
): (string?, number?, Tool?)
	local inventoryService = self.inventoryService
	if inventoryService == nil then
		return nil, nil, nil
	end
	local inventoryState = inventoryService:getState(player)
	local itemId, selectedSlot = MagicServiceUtils.resolveSelectedItemIdFromInventoryState(inventoryState)
	if itemId == nil then
		return nil, selectedSlot, nil
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = MagicServiceUtils.resolveToolByItemId(runtime.character, backpack, itemId)
	if tool == nil or not MagicServiceUtils.isMagicTool(tool) then
		return itemId, selectedSlot, nil
	end
	return itemId, selectedSlot, tool
end

function MagicServiceServer.RefreshEquippedWeaponFromInventory(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime
)
	local itemId, selectedSlot, tool = self:getEquippedMagicToolFromInventory(player, runtime)
	runtime.equippedItemId = itemId
	runtime.equippedSlot = selectedSlot
	runtime.equippedTool = tool

	local magicController = runtime.magicController
	if magicController == nil then
		return
	end

	if tool ~= nil then
		magicController:bindTool(tool)
		local weaponConfig = magicController:resolveBoundWeaponConfig()
		if typeof(weaponConfig) == "table" then
			local weaponId = trim((weaponConfig :: any).itemId)
			if weaponId ~= "" then
				magicController.cooldownUntil = getCooldownValue(runtime.weaponCooldowns, weaponId)
			end
		end
	else
		magicController:unbindTool()
	end

	self:pushState(player, runtime)
end

function MagicServiceServer.GetDefinitionOverride(self: MagicServiceServer, itemIdRaw: any): any?
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return nil
	end
	return self.definitionOverrides[itemId] or self.definitionOverrides[string.lower(itemId)]
end

function MagicServiceServer.BuildRuntimeConfigWithOverrides(
	self: MagicServiceServer,
	weaponConfigRaw: any
): WeaponRuntimeConfig?
	local weaponConfig = if typeof(weaponConfigRaw) == "table" then weaponConfigRaw :: { [string]: any } else nil
	if weaponConfig == nil then
		return nil
	end
	local itemId = trim((weaponConfig :: any).itemId)
	local override = self:getDefinitionOverride(itemId)
	if override == nil then
		return MagicServiceUtils.buildWeaponRuntimeConfig(weaponConfig)
	end

	local patched = shallowCopy(weaponConfig)
	local baseDefinition = if typeof((weaponConfig :: any).definition) == "table"
		then shallowCopy((weaponConfig :: any).definition)
		else {}
	baseDefinition.magicWeapon = override
	patched.definition = baseDefinition
	return MagicServiceUtils.buildWeaponRuntimeConfig(patched)
end

function MagicServiceServer.CollectCastModifiers(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	config: WeaponRuntimeConfig,
	contextRaw: any
): ModifierStats
	local modifiers = {}
	local tool = runtime.equippedTool
	if tool ~= nil then
		table.insert(modifiers, {
			damageMultiplier = tool:GetAttribute("MagicDamageMultiplier"),
			damageBonus = tool:GetAttribute("MagicDamageBonus"),
			manaMultiplier = tool:GetAttribute("MagicManaMultiplier"),
			manaBonus = tool:GetAttribute("MagicManaBonus"),
			cooldownMultiplier = tool:GetAttribute("MagicCooldownMultiplier"),
			cooldownBonus = tool:GetAttribute("MagicCooldownBonus"),
			castTimeMultiplier = tool:GetAttribute("MagicCastTimeMultiplier"),
			castTimeBonus = tool:GetAttribute("MagicCastTimeBonus"),
			knockbackMultiplier = tool:GetAttribute("MagicKnockbackMultiplier"),
			knockbackBonus = tool:GetAttribute("MagicKnockbackBonus"),
			speedMultiplier = tool:GetAttribute("MagicProjectileSpeedMultiplier"),
			speedBonus = tool:GetAttribute("MagicProjectileSpeedBonus"),
			lifetimeMultiplier = tool:GetAttribute("MagicProjectileLifetimeMultiplier"),
			lifetimeBonus = tool:GetAttribute("MagicProjectileLifetimeBonus"),
			pierceBonus = tool:GetAttribute("MagicPierceBonus"),
			projectileCountBonus = tool:GetAttribute("MagicProjectileCountBonus"),
			forceHoming = tool:GetAttribute("MagicForceHoming"),
		})
	end

	for _, provider in self.modifierProviders do
		if typeof(provider) ~= "function" then
			continue
		end
		local ok, providerResult = pcall(provider, self, player, runtime, config, contextRaw)
		if ok and typeof(providerResult) == "table" then
			table.insert(modifiers, providerResult)
		end
	end

	return MagicServiceUtils.mergeModifiers(modifiers)
end

function MagicServiceServer.PrepareControllerStatsForCast(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	castRequest: CastRequest
): boolean
	local magicController = runtime.magicController
	if magicController == nil then
		return false
	end
	local weaponConfigRaw = magicController:resolveBoundWeaponConfig()
	local config = self:buildRuntimeConfigWithOverrides(weaponConfigRaw)
	if config == nil then
		return false
	end

	local modifiers = self:collectCastModifiers(player, runtime, config, castRequest)
	local castStats = MagicServiceUtils.buildCastStats(config, modifiers)

	if typeof(magicController.weaponConfig) == "table" then
		local mutable = magicController.weaponConfig :: { [string]: any }
		mutable.manaCost = castStats.manaCost
		mutable.cooldown = castStats.cooldown
		mutable.castTime = castStats.castTime
		mutable.damage = castStats.damage
		if typeof(mutable.projectile) == "table" then
			local projectile = mutable.projectile :: { [string]: any }
			projectile.speed = castStats.projectileSpeed
			projectile.lifetime = castStats.projectileLifetime
			projectile.pierce = castStats.pierce
			projectile.count = castStats.projectileCount
			projectile.spread = castStats.projectileSpread
		end
	end

	runtime.pendingPreparedCast = {
		itemId = config.itemId,
		config = config,
		stats = castStats,
		castRequest = castRequest,
	}
	return true
end

function MagicServiceServer.OnMagicCastRequested(
	self: MagicServiceServer,
	magicController: MagicController,
	contextRaw: any
): boolean
	local player, runtime = self:resolveRuntimeByMagic(magicController)
	if player == nil or runtime == nil then
		return false
	end
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	if not MagicServiceUtils.isHumanoidAlive(runtime.humanoid) then
		return false
	end
	if MagicServiceUtils.isPlayerStunned(player, runtime.character, runtime.humanoid) then
		return false
	end

	local prepared = runtime.pendingPreparedCast
	if prepared == nil then
		return false
	end
	local now = os.clock()
	if now < getCooldownValue(runtime.weaponCooldowns, prepared.itemId) then
		return false
	end

	local castToken = resolveCastToken(context)
	if castToken < 1 then
		return false
	end
	runtime.pendingCastByToken[castToken] = prepared
	runtime.pendingPreparedCast = nil
	return true
end

function MagicServiceServer.CanConsumeMana(
	self: MagicServiceServer,
	player: Player?,
	amountRaw: number,
	contextRaw: any
): boolean
	if player == nil then
		return false
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end
	local castToken = resolveCastToken(contextRaw)
	if castToken < 1 then
		return false
	end
	local castData = runtime.pendingCastByToken[castToken]
	local manaCost = if castData ~= nil then castData.stats.manaCost else math.max(0, amountRaw)
	local manaService = self.manaService
	if manaService == nil then
		return false
	end
	local context = if typeof(contextRaw) == "table" then shallowCopy(contextRaw) else {}
	context.castToken = castToken
	if castData ~= nil then
		context.itemId = castData.itemId
	end
	local success, canConsumeOrError = pcall(function()
		return manaService:canConsumeMana(player, manaCost, context)
	end)
	if not success then
		return false
	end
	return canConsumeOrError == true
end

function MagicServiceServer.ConsumeMana(
	self: MagicServiceServer,
	player: Player?,
	amountRaw: number,
	contextRaw: any
): boolean
	if player == nil then
		return false
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end
	local castToken = resolveCastToken(contextRaw)
	if castToken < 1 then
		return false
	end
	local castData = runtime.pendingCastByToken[castToken]
	local manaCost = if castData ~= nil then castData.stats.manaCost else math.max(0, amountRaw)
	local manaService = self.manaService
	if manaService == nil then
		return false
	end
	local context = if typeof(contextRaw) == "table" then shallowCopy(contextRaw) else {}
	context.castToken = castToken
	if castData ~= nil then
		context.itemId = castData.itemId
	end
	local success, consumeResultOrError = pcall(function()
		return manaService:consumeMana(player, manaCost, context)
	end)
	if not success then
		return false
	end
	if consumeResultOrError ~= true then
		return false
	end

	if castData ~= nil then
		local cooldownEndsAt = os.clock() + castData.stats.cooldown
		setCooldownValue(runtime.weaponCooldowns, castData.itemId, cooldownEndsAt)
		if runtime.magicController ~= nil then
			runtime.magicController.cooldownUntil = cooldownEndsAt
		end
		runtime.committedCastByToken[castToken] = castData
	end
	self:pushState(player, runtime)
	return true
end

function MagicServiceServer.RequestSync(self: MagicServiceServer, player: Player)
	if self.playerRuntimes[player] == nil then
		self:trackPlayer(player)
		return
	end
	local runtime = self:getRuntime(player)
	self:pushState(player, runtime)
end

function MagicServiceServer.RequestRefreshEquipped(self: MagicServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	self:refreshEquippedWeaponFromInventory(player, runtime)
end

function MagicServiceServer.RequestSetInputHeld(
	self: MagicServiceServer,
	player: Player,
	inputHeldRaw: any,
	castRequestRaw: any
)
	if typeof(inputHeldRaw) ~= "boolean" then
		return
	end
	local runtime = self:getRuntime(player)
	runtime.inputHeld = inputHeldRaw
	runtime.lastAimRequest = MagicServiceUtils.sanitizeCastRequest(castRequestRaw)
	if runtime.lastAimRequest.aimDirection ~= nil and runtime.lastAimRequest.aimDirection.Magnitude > 1e-4 then
		runtime.lastAimDirection = runtime.lastAimRequest.aimDirection.Unit
	end
end

function MagicServiceServer.RequestCast(self: MagicServiceServer, player: Player, castRequestRaw: any)
	local runtime = self:getRuntime(player)
	local now = os.clock()
	if now - runtime.requestWindowStartedAt > 1 then
		runtime.requestWindowStartedAt = now
		runtime.requestsInWindow = 0
	end
	runtime.requestsInWindow += 1
	if runtime.requestsInWindow > CAST_REQUESTS_PER_SECOND_LIMIT then
		return
	end
	if now - runtime.lastCastRequestAt < CAST_REQUEST_INTERVAL then
		return
	end
	runtime.lastCastRequestAt = now

	runtime.lastAimRequest = MagicServiceUtils.sanitizeCastRequest(castRequestRaw)
	if runtime.lastAimRequest.aimDirection ~= nil and runtime.lastAimRequest.aimDirection.Magnitude > 1e-4 then
		runtime.lastAimDirection = runtime.lastAimRequest.aimDirection.Unit
	end

	if not MagicServiceUtils.isHumanoidAlive(runtime.humanoid) then
		return
	end
	if MagicServiceUtils.isPlayerStunned(player, runtime.character, runtime.humanoid) then
		return
	end

	self:refreshEquippedWeaponFromInventory(player, runtime)
	if runtime.magicController == nil or runtime.equippedTool == nil then
		return
	end
	if not self:prepareControllerStatsForCast(player, runtime, runtime.lastAimRequest) then
		return
	end
	runtime.magicController:queueCast(runtime.lastAimRequest.trigger)
end

function MagicServiceServer.CreateProjectilePart(
	self: MagicServiceServer,
	weaponIdRaw: any,
	config: WeaponRuntimeConfig
): BasePart
	local weaponId = trim(weaponIdRaw)
	local template = config.projectile.template
	local part = if template ~= nil then template:Clone() else nil
	if part == nil then
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(0.4, 0.4, 0.4)
	end
	part.Name = ("MagicProjectile_%s"):format(if weaponId ~= "" then weaponId else "Unknown")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = self.projectileFolder
	return part
end

function MagicServiceServer.AcquireProjectilePart(
	self: MagicServiceServer,
	config: WeaponRuntimeConfig
): { part: BasePart, active: boolean, weaponId: string }
	local weaponId = config.itemId
	local pool = self.projectilePools[weaponId]
	if pool == nil then
		pool = {}
		self.projectilePools[weaponId] = pool
	end
	for _, entry in pool do
		if entry.active == false then
			entry.active = true
			return entry
		end
	end
	local entry = {
		part = self:createProjectilePart(weaponId, config),
		active = true,
		weaponId = weaponId,
	}
	table.insert(pool, entry)
	return entry
end

function MagicServiceServer.ReleaseProjectile(self: MagicServiceServer, projectile: any)
	local entry = projectile.poolEntry
	entry.active = false
	entry.part.Transparency = 1
	entry.part.CFrame = CFrame.new(0, -10000, 0)
end

function MagicServiceServer.ResolveCastOriginAndDirection(
	self: MagicServiceServer,
	runtime: PlayerRuntime,
	castRequest: CastRequest
): (Vector3, Vector3)
	local rootPart = runtime.rootPart
	if rootPart == nil then
		return Vector3.zero, Vector3.new(0, 0, -1)
	end
	local origin = rootPart.Position + Vector3.new(0, 1.35, 0)
	local fallback = rootPart.CFrame.LookVector
	local direction = MagicServiceUtils.resolveCastDirection(origin, castRequest, fallback)
	return origin, direction
end

function MagicServiceServer.InvokeWeaponCallback(self: MagicServiceServer, callbackRaw: any, context: { [string]: any })
	if typeof(callbackRaw) ~= "function" then
		return
	end
	pcall(callbackRaw, context)
end

function MagicServiceServer.ResolveHumanoidRootPart(self: MagicServiceServer, humanoid: Humanoid?): BasePart?
	if humanoid == nil then
		return nil
	end
	local model = humanoid.Parent
	if model == nil or not model:IsA("Model") then
		return nil
	end
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end
	if model.PrimaryPart ~= nil and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return nil
end

function MagicServiceServer.CollectOverlapParts(
	self: MagicServiceServer,
	projectile: any,
	position: Vector3,
	radiusRaw: number
): { BasePart }
	local radius = math.max(0.25, radiusRaw)
	local overlapParams = projectile.overlapParams
	if typeof(overlapParams) ~= "OverlapParams" then
		overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = { self.projectileFolder } :: { Instance }
		if projectile.caster.Character ~= nil then
			table.insert(exclude, projectile.caster.Character)
		end
		overlapParams.FilterDescendantsInstances = exclude
		overlapParams.MaxParts = PROJECTILE_MAX_OVERLAP_PARTS
		projectile.overlapParams = overlapParams
	end

	local ok, partsOrError = pcall(function()
		return Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	end)
	if not ok or typeof(partsOrError) ~= "table" then
		return {}
	end

	local parts = {} :: { BasePart }
	for _, part in partsOrError do
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

function MagicServiceServer.IsValidHumanoidTarget(
	self: MagicServiceServer,
	projectile: any,
	humanoid: Humanoid?
): boolean
	if not MagicServiceUtils.isHumanoidAlive(humanoid) then
		return false
	end

	local casterCharacter = projectile.caster.Character
	local targetModel = humanoid.Parent
	if targetModel == nil or not targetModel:IsA("Model") then
		return false
	end
	if targetModel == casterCharacter then
		return false
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	if targetPlayer ~= nil then
		return projectile.config.projectile.canHitPlayers
	end
	return projectile.config.projectile.canHitNpcs
end

function MagicServiceServer.ApplyKnockbackToHumanoid(self: MagicServiceServer, projectile: any, humanoid: Humanoid?)
	local rootPart = self:resolveHumanoidRootPart(humanoid)
	if rootPart == nil then
		return
	end
	rootPart.AssemblyLinearVelocity += projectile.direction * (projectile.stats.knockback * 8) + Vector3.new(0, 6, 0)
end

function MagicServiceServer.DamageHumanoidTarget(
	self: MagicServiceServer,
	projectile: any,
	humanoid: Humanoid?,
	damageRaw: number,
	markHitRaw: any
): boolean
	if not self:isValidHumanoidTarget(projectile, humanoid) then
		return false
	end
	if humanoid == nil then
		return false
	end

	local damage = math.max(0, damageRaw)
	if damage <= 0 then
		return false
	end

	local markHit = markHitRaw ~= false
	if markHit and projectile.hitHumanoids[humanoid] then
		return false
	end

	humanoid:TakeDamage(damage)
	if markHit then
		projectile.hitHumanoids[humanoid] = true
	end
	self:applyKnockbackToHumanoid(projectile, humanoid)
	return true
end

function MagicServiceServer.ApplyStackingStatusEffect(
	self: MagicServiceServer,
	projectile: any,
	effect: any,
	targetHumanoid: Humanoid,
	hitPart: BasePart
)
	local effectsMap = self.activeEffectsByHumanoid[targetHumanoid]
	if effectsMap == nil then
		effectsMap = {}
		self.activeEffectsByHumanoid[targetHumanoid] = effectsMap
	end

	local effectKey = ("%s:%d"):format(effect.effectType, projectile.caster.UserId)
	local existing = effectsMap[effectKey]
	local now = os.clock()
	local stackRule = effect.stackRule
	if existing ~= nil then
		if stackRule == "replace" or stackRule == "nostack" then
			existing.stacks = 1
		elseif stackRule == "stack" or stackRule == "add" or stackRule == "additive" then
			existing.stacks = math.min(effect.maxStacks, existing.stacks + 1)
		elseif stackRule == "max" then
			existing.stacks = math.max(existing.stacks, 1)
		end
		existing.expiresAt = now + effect.duration
		existing.nextTickAt = now + effect.tickInterval
		existing.targetPart = hitPart
		return
	end

	effectsMap[effectKey] = {
		key = effectKey,
		targetHumanoid = targetHumanoid,
		targetPart = hitPart,
		sourcePlayer = projectile.caster,
		definition = effect,
		stacks = 1,
		expiresAt = now + effect.duration,
		nextTickAt = now + effect.tickInterval,
	}
end

function MagicServiceServer.ApplySplashEffect(
	self: MagicServiceServer,
	projectile: any,
	effect: any,
	hitPosition: Vector3,
	hitHumanoid: Humanoid?
)
	local radius = math.max(0, effect.radius)
	if radius <= 0 then
		return
	end
	local damageScale = math.max(0, effect.magnitude)
	if damageScale <= 0 then
		return
	end

	local seenHumanoids = {}
	local seenNpcModels = {}
	if hitHumanoid ~= nil then
		seenHumanoids[hitHumanoid] = true
	end
	local parts = self:collectOverlapParts(projectile, hitPosition, radius)
	for _, part in parts do
		if part == nil then
			continue
		end

		local model = part:FindFirstAncestorOfClass("Model")
		local npcDamaged = false
		if
			model ~= nil
			and not seenNpcModels[model]
			and projectile.config.projectile.canHitNpcs
			and self.npcService ~= nil
		then
			seenNpcModels[model] = true
			local splashNpcDamage =
				self.npcService:damageNpcFromHitPart(part, projectile.stats.damage * damageScale, projectile.caster)
			if splashNpcDamage > 0 then
				npcDamaged = true
			end

			if not npcDamaged and self.bossService ~= nil then
				local splashBossDamage = self.bossService:damageBossFromHitPart(
					part,
					projectile.stats.damage * damageScale,
					projectile.caster,
					"MagicSplash"
				)
				if splashBossDamage > 0 then
					npcDamaged = true
				end
			end
		end

		local humanoid = MagicServiceUtils.resolveHumanoidFromHitPart(part)
		if not npcDamaged and humanoid ~= nil and not seenHumanoids[humanoid] then
			seenHumanoids[humanoid] = true
			local rootPart = self:resolveHumanoidRootPart(humanoid)
			local targetPosition = if rootPart ~= nil then rootPart.Position else part.Position
			local distanceAlpha = math.clamp((targetPosition - hitPosition).Magnitude / math.max(0.001, radius), 0, 1)
			local falloff = math.max(0.2, 1 - distanceAlpha)
			local splashDamage = projectile.stats.damage * damageScale * falloff
			self:damageHumanoidTarget(projectile, humanoid, splashDamage, true)
		end
	end
end

function MagicServiceServer.FindNearestChainTarget(
	self: MagicServiceServer,
	projectile: any,
	originPosition: Vector3,
	radiusRaw: number,
	visited: { [Humanoid]: boolean }
): (Humanoid?, Vector3?)
	local radius = math.max(0.25, radiusRaw)
	local nearest = nil :: Humanoid?
	local nearestPosition = nil :: Vector3?
	local nearestDistance = math.huge
	local parts = self:collectOverlapParts(projectile, originPosition, radius)
	for _, part in parts do
		local humanoid = MagicServiceUtils.resolveHumanoidFromHitPart(part)
		if humanoid == nil or visited[humanoid] then
			continue
		end
		if not self:isValidHumanoidTarget(projectile, humanoid) then
			continue
		end
		local rootPart = self:resolveHumanoidRootPart(humanoid)
		local position = if rootPart ~= nil then rootPart.Position else part.Position
		local distance = (position - originPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = humanoid
			nearestPosition = position
		end
	end
	return nearest, nearestPosition
end

function MagicServiceServer.ApplyChainEffect(
	self: MagicServiceServer,
	projectile: any,
	effect: any,
	hitPosition: Vector3,
	hitHumanoid: Humanoid?
)
	if hitHumanoid == nil then
		return
	end
	local jumpCount = math.max(0, math.floor(effect.jumps))
	if jumpCount <= 0 then
		return
	end

	local visited = {}
	visited[hitHumanoid] = true
	local currentPosition = hitPosition
	local damageScale = math.max(0, effect.magnitude)
	local jumpFalloff = math.clamp(effect.jumpFalloff, 0, 1)

	for _ = 1, jumpCount do
		local targetHumanoid, targetPosition =
			self:findNearestChainTarget(projectile, currentPosition, effect.radius, visited)
		if targetHumanoid == nil or targetPosition == nil then
			break
		end
		visited[targetHumanoid] = true

		local chainDamage = projectile.stats.damage * damageScale
		if self:damageHumanoidTarget(projectile, targetHumanoid, chainDamage, true) then
			for _, listedPlayer in Players:GetPlayers() do
				if PlayerServiceServer:isGameplayActiveForPlayer(listedPlayer) then
					self.networker:fire(listedPlayer, MagicServiceUtils.CLIENT_METHOD_ON_IMPACT_VISUAL, {
						castId = projectile.castId,
						weaponId = projectile.weaponId,
						position = targetPosition,
						normal = nil,
						visualColor = projectile.config.projectile.visualColor,
						visualSize = projectile.config.projectile.visualSize,
						reason = "Chain",
					})
				end
			end
		end

		currentPosition = targetPosition
		damageScale *= jumpFalloff
		if damageScale <= 0 then
			break
		end
	end
end

function MagicServiceServer.ApplyEffectsFromHit(
	self: MagicServiceServer,
	projectile: any,
	hitPart: BasePart,
	hitHumanoid: Humanoid?,
	hitPosition: Vector3
)
	for _, effect in projectile.config.effects do
		if effect.effectType == "lifesteal" then
			local healAmount = math.max(0, projectile.stats.damage * effect.magnitude)
			if healAmount > 0 and self.hpService ~= nil then
				pcall(function()
					self.hpService:healPlayer(projectile.caster, healAmount)
				end)
			end
		elseif effect.effectType == "burn" or effect.effectType == "slow" then
			if hitHumanoid ~= nil then
				self:applyStackingStatusEffect(projectile, effect, hitHumanoid, hitPart)
			end
		elseif effect.effectType == "splash" then
			self:applySplashEffect(projectile, effect, hitPosition, hitHumanoid)
		elseif effect.effectType == "chain" then
			self:applyChainEffect(projectile, effect, hitPosition, hitHumanoid)
		end
	end
end

function MagicServiceServer.ExpireProjectile(
	self: MagicServiceServer,
	projectileId: number,
	reason: string,
	position: Vector3,
	normal: Vector3?
)
	local projectile = self.activeProjectiles[projectileId]
	if projectile == nil then
		return
	end
	self.activeProjectiles[projectileId] = nil
	self:releaseProjectile(projectile)
	for _, listedPlayer in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(listedPlayer) then
			self.networker:fire(listedPlayer, MagicServiceUtils.CLIENT_METHOD_ON_IMPACT_VISUAL, {
				castId = projectile.castId,
				weaponId = projectile.weaponId,
				position = position,
				normal = normal,
				visualColor = projectile.config.projectile.visualColor,
				visualSize = projectile.config.projectile.visualSize,
				reason = reason,
			})
		end
	end
	self:invokeWeaponCallback(projectile.config.callbacks.OnExpire, {
		service = self,
		projectile = projectile,
		position = position,
		normal = normal,
		reason = reason,
	})
end

function MagicServiceServer.HandleProjectileHit(
	self: MagicServiceServer,
	projectileId: number,
	projectile: any,
	hit: any
)
	local hitPart = hit.Instance
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then
		if projectile.config.projectile.collisionBehavior ~= "pierce" then
			self:expireProjectile(projectileId, "WorldHit", hit.Position, hit.Normal)
		end
		return
	end
	local casterCharacter = projectile.caster.Character
	if casterCharacter ~= nil and hitPart:IsDescendantOf(casterCharacter) then
		return
	end

	local damage = projectile.stats.damage
	local didDamage = false
	local npcDamaged = false
	local hitHumanoid = nil :: Humanoid?
	if projectile.config.projectile.canHitNpcs and self.npcService ~= nil then
		local npcDamage = self.npcService:damageNpcFromHitPart(hitPart, damage, projectile.caster)
		if npcDamage > 0 then
			didDamage = true
			npcDamaged = true
		end
	end

	if projectile.config.projectile.canHitNpcs and (not npcDamaged) and self.bossService ~= nil then
		local bossDamage = self.bossService:damageBossFromHitPart(hitPart, damage, projectile.caster, "MagicProjectile")
		if bossDamage > 0 then
			didDamage = true
			npcDamaged = true
		end
	end

	hitHumanoid = MagicServiceUtils.resolveHumanoidFromHitPart(hitPart)
	if (not npcDamaged) and self:damageHumanoidTarget(projectile, hitHumanoid, damage, true) then
		didDamage = true
	end

	if didDamage then
		self:invokeWeaponCallback(projectile.config.callbacks.OnHit, {
			service = self,
			projectile = projectile,
			hitPart = hitPart,
			hitHumanoid = hitHumanoid,
			position = hit.Position,
			normal = hit.Normal,
			damage = damage,
		})
		self:applyEffectsFromHit(projectile, hitPart, hitHumanoid, hit.Position)
		if projectile.pierceRemaining > 0 then
			projectile.pierceRemaining -= 1
			return
		end
		self:expireProjectile(projectileId, "TargetHit", hit.Position, hit.Normal)
		return
	end

	if projectile.config.projectile.collisionBehavior == "pierce" then
		return
	end

	if projectile.config.projectile.destroyOnWorldHit then
		self:expireProjectile(projectileId, "WorldHit", hit.Position, hit.Normal)
	end
end

function MagicServiceServer.FindNearestHomingTarget(self: MagicServiceServer, projectile: any): (Humanoid?, Vector3?)
	local homingRange = projectile.config.projectile.homingRange
	if homingRange <= 0 then
		return nil, nil
	end
	local nearest = nil :: Humanoid?
	local nearestPosition = nil :: Vector3?
	local nearestDistance = math.huge
	local parts = self:collectOverlapParts(projectile, projectile.position, homingRange)
	for _, part in parts do
		local humanoid = MagicServiceUtils.resolveHumanoidFromHitPart(part)
		if humanoid == nil then
			continue
		end
		if projectile.hitHumanoids[humanoid] then
			continue
		end
		if not self:isValidHumanoidTarget(projectile, humanoid) then
			continue
		end
		local rootPart = self:resolveHumanoidRootPart(humanoid)
		local targetPosition = if rootPart ~= nil then rootPart.Position else part.Position
		local distance = (targetPosition - projectile.position).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = humanoid
			nearestPosition = targetPosition
		end
	end
	return nearest, nearestPosition
end

function MagicServiceServer.StepProjectileHoming(self: MagicServiceServer, projectile: any, dt: number)
	if not projectile.stats.homingEnabled then
		projectile.homingTargetHumanoid = nil
		return
	end
	local homingRange = projectile.config.projectile.homingRange
	local targetHumanoid = projectile.homingTargetHumanoid
	local targetPosition = nil :: Vector3?
	if targetHumanoid ~= nil and self:isValidHumanoidTarget(projectile, targetHumanoid) then
		local rootPart = self:resolveHumanoidRootPart(targetHumanoid)
		if rootPart ~= nil then
			local distance = (rootPart.Position - projectile.position).Magnitude
			if distance <= homingRange then
				targetPosition = rootPart.Position
			end
		end
	end

	if targetPosition == nil then
		targetHumanoid, targetPosition = self:findNearestHomingTarget(projectile)
		projectile.homingTargetHumanoid = targetHumanoid
	end
	if targetPosition == nil then
		return
	end

	local desiredDirection = targetPosition - projectile.position
	if desiredDirection.Magnitude <= 1e-4 then
		return
	end
	local turnAlpha = math.clamp(projectile.config.projectile.homingTurnRate * dt, 0, 1)
	local nextDirection = projectile.direction:Lerp(desiredDirection.Unit, turnAlpha)
	if nextDirection.Magnitude <= 1e-4 then
		return
	end
	projectile.direction = nextDirection.Unit
	projectile.velocity = projectile.direction * projectile.stats.projectileSpeed
end

function MagicServiceServer.ResolveProjectileCollision(
	self: MagicServiceServer,
	projectile: any,
	fromPosition: Vector3,
	toPosition: Vector3
): any?
	if projectile.config.projectile.collisionBehavior == "overlap" then
		local parts = self:collectOverlapParts(projectile, toPosition, projectile.config.projectile.radius)
		if #parts <= 0 then
			return nil
		end
		local chosen = parts[1]
		local chosenDistance = (chosen.Position - toPosition).Magnitude
		for index = 2, #parts do
			local candidate = parts[index]
			local distance = (candidate.Position - toPosition).Magnitude
			if distance < chosenDistance then
				chosen = candidate
				chosenDistance = distance
			end
		end
		return {
			Instance = chosen,
			Position = toPosition,
			Normal = -projectile.direction,
		}
	end

	local rayDirection = toPosition - fromPosition
	if rayDirection.Magnitude <= 1e-4 then
		return nil
	end
	return Workspace:Raycast(fromPosition, rayDirection, projectile.raycastParams)
end

function MagicServiceServer.StepProjectiles(self: MagicServiceServer, dt: number)
	for projectileId, projectile in self.activeProjectiles do
		if projectile.lifetimeRemaining <= 0 then
			self:expireProjectile(projectileId, "LifetimeEnded", projectile.position, nil)
			continue
		end

		self:stepProjectileHoming(projectile, dt)
		local fromPosition = projectile.position
		local toPosition = fromPosition + projectile.velocity * dt
		local hit = self:resolveProjectileCollision(projectile, fromPosition, toPosition)
		if hit ~= nil then
			projectile.position = hit.Position
			self:handleProjectileHit(projectileId, projectile, hit)
			if self.activeProjectiles[projectileId] == nil then
				continue
			end
			projectile.poolEntry.part.CFrame =
				CFrame.lookAt(projectile.position, projectile.position + projectile.direction)
		else
			projectile.position = toPosition
			projectile.poolEntry.part.CFrame = CFrame.lookAt(toPosition, toPosition + projectile.direction)
		end

		projectile.lifetimeRemaining -= dt
		self:invokeWeaponCallback(projectile.config.callbacks.OnTick, {
			service = self,
			projectile = projectile,
			dt = dt,
			position = projectile.position,
		})
	end
end

function MagicServiceServer.StepEffects(self: MagicServiceServer, now: number)
	for humanoid, effectsMap in self.activeEffectsByHumanoid do
		if not MagicServiceUtils.isHumanoidAlive(humanoid) then
			self.activeEffectsByHumanoid[humanoid] = nil
			continue
		end

		local maxSlow = 0
		for key, effectRuntime in effectsMap do
			if now >= effectRuntime.expiresAt then
				effectsMap[key] = nil
				continue
			end
			if effectRuntime.definition.effectType == "burn" and now >= effectRuntime.nextTickAt then
				effectRuntime.nextTickAt = now + effectRuntime.definition.tickInterval
				local burnDamage = math.max(0, effectRuntime.definition.magnitude * effectRuntime.stacks)
				if burnDamage > 0 then
					humanoid:TakeDamage(burnDamage)
				end
			elseif effectRuntime.definition.effectType == "slow" then
				local slowAlpha = math.clamp(effectRuntime.definition.magnitude * effectRuntime.stacks, 0, 0.95)
				if slowAlpha > maxSlow then
					maxSlow = slowAlpha
				end
			end
		end

		if next(effectsMap) == nil then
			PlayerServiceUtils.setMovementSpeedMultiplier(
				humanoid,
				PlayerServiceUtils.MAGIC_WALK_SPEED_MULTIPLIER_ATTRIBUTE,
				nil
			)
			self.activeEffectsByHumanoid[humanoid] = nil
		else
			if maxSlow > 0 then
				PlayerServiceUtils.setMovementSpeedMultiplier(
					humanoid,
					PlayerServiceUtils.MAGIC_WALK_SPEED_MULTIPLIER_ATTRIBUTE,
					1 - maxSlow
				)
			else
				PlayerServiceUtils.setMovementSpeedMultiplier(
					humanoid,
					PlayerServiceUtils.MAGIC_WALK_SPEED_MULTIPLIER_ATTRIBUTE,
					nil
				)
			end
		end
	end
end

function MagicServiceServer.SpawnProjectile(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	config: WeaponRuntimeConfig,
	stats: CastStats,
	direction: Vector3,
	origin: Vector3,
	castToken: number,
	projectileIndex: number
)
	local poolEntry = self:acquireProjectilePart(config)
	local castId = ("%d:%d:%d"):format(player.UserId, castToken, projectileIndex)
	local projectileId = self.nextProjectileId + 1
	self.nextProjectileId = projectileId
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local overlapExclude = { self.projectileFolder } :: { Instance }
	if runtime.character ~= nil then
		table.insert(overlapExclude, runtime.character)
	end
	overlapParams.FilterDescendantsInstances = overlapExclude
	overlapParams.MaxParts = PROJECTILE_MAX_OVERLAP_PARTS

	self.activeProjectiles[projectileId] = {
		id = projectileId,
		castId = castId,
		caster = player,
		weaponId = config.itemId,
		config = config,
		stats = stats,
		poolEntry = poolEntry,
		position = origin,
		direction = direction,
		velocity = direction * stats.projectileSpeed,
		lifetimeRemaining = stats.projectileLifetime,
		pierceRemaining = stats.pierce,
		hitHumanoids = {},
		homingTargetHumanoid = nil,
		raycastParams = (function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = { self.projectileFolder } :: { Instance }
			if runtime.character ~= nil then
				table.insert(exclude, runtime.character)
			end
			params.FilterDescendantsInstances = exclude
			params.IgnoreWater = false
			return params
		end)(),
		overlapParams = overlapParams,
	}

	poolEntry.part.CFrame = CFrame.lookAt(origin, origin + direction)
	poolEntry.part.Transparency = 1

	for _, listedPlayer in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(listedPlayer) then
			self.networker:fire(listedPlayer, MagicServiceUtils.CLIENT_METHOD_ON_CAST_VISUAL, {
				castId = castId,
				casterUserId = player.UserId,
				weaponId = config.itemId,
				origin = origin,
				direction = direction,
				speed = stats.projectileSpeed,
				lifetime = stats.projectileLifetime,
				castTime = stats.castTime,
				visualColor = config.projectile.visualColor,
				visualSize = config.projectile.visualSize,
				visualName = config.displayName,
			})
		end
	end
end

function MagicServiceServer.ExecuteCast(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	config: WeaponRuntimeConfig,
	stats: CastStats,
	castRequest: CastRequest,
	castToken: number
)
	local origin, direction = self:resolveCastOriginAndDirection(runtime, castRequest)
	self:invokeWeaponCallback(config.callbacks.OnCast, {
		service = self,
		player = player,
		config = config,
		stats = stats,
		origin = origin,
		direction = direction,
		castToken = castToken,
		castRequest = castRequest,
	})

	if not config.projectile.enabled then
		return
	end
	for projectileIndex = 1, stats.projectileCount do
		local spreadDirection =
			MagicServiceUtils.applySpread(direction, stats.projectileSpread, projectileIndex, stats.projectileCount)
		self:spawnProjectile(player, runtime, config, stats, spreadDirection, origin, castToken, projectileIndex)
	end
end

function MagicServiceServer.OnMagicCastCommitted(
	self: MagicServiceServer,
	magicController: MagicController,
	contextRaw: any
)
	local player, runtime = self:resolveRuntimeByMagic(magicController)
	if player == nil or runtime == nil then
		return
	end
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	local castToken = resolveCastToken(context)
	if castToken < 1 then
		return
	end
	local castData = runtime.committedCastByToken[castToken] or runtime.pendingCastByToken[castToken]
	runtime.pendingCastByToken[castToken] = nil
	runtime.committedCastByToken[castToken] = nil
	if castData == nil then
		return
	end
	self:executeCast(player, runtime, castData.config, castData.stats, castData.castRequest, castToken)
end

function MagicServiceServer.StepHeldInput(self: MagicServiceServer)
	for player, runtime in self.playerRuntimes do
		if runtime.inputHeld and os.clock() - runtime.lastCastRequestAt >= 0.12 then
			self:requestCast(player, runtime.lastAimRequest)
		end
	end
end

function MagicServiceServer.OnHeartbeat(self: MagicServiceServer, dt: number)
	self.fixedStepAccumulator += dt
	local steps = 0
	while self.fixedStepAccumulator >= PROJECTILE_FIXED_STEP and steps < 4 do
		self.fixedStepAccumulator -= PROJECTILE_FIXED_STEP
		steps += 1
		self:stepHeldInput()
		self:stepProjectiles(PROJECTILE_FIXED_STEP)
		self:stepEffects(os.clock())
	end
	if steps >= 4 then
		self.fixedStepAccumulator = 0
	end
end

function MagicServiceServer.BindCharacter(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	character: Model
)
	runtime.characterJanitor:Clean()
	runtime.character = character
	runtime.humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	runtime.rootPart = if rootPart ~= nil and rootPart:IsA("BasePart") then rootPart else nil

	if runtime.magicController ~= nil then
		runtime.magicController:setCharacter(character)
	end

	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			runtime.humanoid = child
		elseif child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
			runtime.rootPart = child
		elseif child:IsA("Tool") then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))
	runtime.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if child == runtime.humanoid then
			runtime.humanoid = nil
		elseif child == runtime.rootPart then
			runtime.rootPart = nil
		elseif child:IsA("Tool") then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))

	self:refreshEquippedWeaponFromInventory(player, runtime)
end

function MagicServiceServer.BindBackpack(
	self: MagicServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	backpack: Backpack
)
	runtime.playerJanitor:GiveChore(backpack.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))
	runtime.playerJanitor:GiveChore(backpack.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))
end

function MagicServiceServer.CreateMagicController(self: MagicServiceServer, player: Player, runtime: PlayerRuntime)
	if runtime.magicController ~= nil then
		runtime.magicController:destroy()
	end
	local controller = Magic.new({
		ownerPlayer = player,
		character = runtime.character,
		service = self,
		expectedItemType = "magicWeapon",
		autoRepeatWhileHeld = false,
		allowQueueOnCooldown = true,
		validateDefinitionItemType = true,
	}) :: any
	runtime.magicController = controller
end

function MagicServiceServer.TrackPlayer(self: MagicServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.playerJanitor:Clean()
	runtime.characterJanitor:Clean()
	runtime.character = nil
	runtime.humanoid = nil
	runtime.rootPart = nil
	runtime.inputHeld = false
	runtime.weaponCooldowns = {}
	runtime.pendingPreparedCast = nil
	runtime.pendingCastByToken = {}
	runtime.committedCastByToken = {}
	runtime.lastAimRequest = {
		trigger = "None",
		aimDirection = nil,
		aimPosition = nil,
	}
	runtime.lastAimDirection = Vector3.new(0, 0, -1)

	self:createMagicController(player, runtime)

	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:bindCharacter(player, runtime, character)
	end))
	runtime.playerJanitor:GiveChore(player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			self:bindBackpack(player, runtime, child)
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))

	if player.Character ~= nil then
		self:bindCharacter(player, runtime, player.Character)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		self:bindBackpack(player, runtime, backpack)
	end
	self:pushState(player, runtime)
end

function MagicServiceServer.UntrackPlayer(self: MagicServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end
	if runtime.magicController ~= nil then
		runtime.magicController:destroy()
		runtime.magicController = nil
	end
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function MagicServiceServer.RegisterModifierProvider(
	self: MagicServiceServer,
	providerNameRaw: any,
	callbackRaw: any
): boolean
	local providerName = trim(providerNameRaw)
	if providerName == "" or typeof(callbackRaw) ~= "function" then
		return false
	end
	self.modifierProviders[providerName] = callbackRaw
	return true
end

function MagicServiceServer.UnregisterModifierProvider(self: MagicServiceServer, providerNameRaw: any): boolean
	local providerName = trim(providerNameRaw)
	if providerName == "" then
		return false
	end
	if self.modifierProviders[providerName] == nil then
		return false
	end
	self.modifierProviders[providerName] = nil
	return true
end

function MagicServiceServer.RegisterWeaponDefinition(
	self: MagicServiceServer,
	itemIdRaw: any,
	definitionRaw: any
): boolean
	local itemId = trim(itemIdRaw)
	if itemId == "" or typeof(definitionRaw) ~= "table" then
		return false
	end
	if not looksLikeMagicDefinition(definitionRaw) then
		return false
	end
	self.definitionOverrides[itemId] = definitionRaw
	self.definitionOverrides[string.lower(itemId)] = definitionRaw
	return true
end

function MagicServiceServer.RegisterWeaponModule(self: MagicServiceServer, moduleScriptRaw: any): boolean
	if typeof(moduleScriptRaw) ~= "Instance" or not moduleScriptRaw:IsA("ModuleScript") then
		return false
	end
	local moduleScript = moduleScriptRaw :: ModuleScript
	local ok, moduleResultOrError = pcall(require, moduleScript)
	if not ok then
		if shouldSilenceModuleRequireError(moduleResultOrError) then
			return false
		end
		return false
	end
	if typeof(moduleResultOrError) ~= "table" then
		return false
	end
	local moduleResult = moduleResultOrError :: { [any]: any }
	local didRegister = false

	local function registerEntry(itemIdRaw: any, definitionRaw: any)
		local itemId = trim(itemIdRaw)
		if itemId == "" or typeof(definitionRaw) ~= "table" then
			return
		end
		if self:registerWeaponDefinition(itemId, definitionRaw) then
			didRegister = true
		end
	end

	registerEntry(moduleResult.itemId or moduleResult.id or moduleScript.Name, moduleResult)
	if typeof(moduleResult.definition) == "table" then
		registerEntry(
			(moduleResult.definition :: any).itemId or (moduleResult.definition :: any).id or moduleScript.Name,
			moduleResult.definition
		)
	end
	for key, value in moduleResult do
		if typeof(value) ~= "table" then
			continue
		end
		registerEntry((value :: any).itemId or (value :: any).id or key, value)
	end

	return didRegister
end

function MagicServiceServer.RegisterDefinitionsFromFolder(self: MagicServiceServer, folderRaw: any): number
	if typeof(folderRaw) ~= "Instance" or not folderRaw:IsA("Folder") then
		return 0
	end
	local registered = 0
	for _, child in (folderRaw :: Folder):GetChildren() do
		if child:IsA("ModuleScript") and self:registerWeaponModule(child) then
			registered += 1
		end
	end
	return registered
end

function MagicServiceServer.Init(self: MagicServiceServer)
	self.networker = Networker.server.new("MagicService", self, {
		self.RequestSync,
		self.RequestRefreshEquipped,
		self.RequestSetInputHeld,
		self.RequestCast,
	})
	self.inventoryService = InventoryServiceServer :: InventoryServiceServerObject
	self.manaService = ManaServiceServer :: ManaServiceServerObject
	self.npcService = NpcServiceServer :: NpcServiceServerObject
	self.bossService = BossServiceServer :: BossServiceServerObject
	self.hpService = HpServiceServer :: HpServiceServerObject
	self.playerRuntimes = {}
	self.projectilePools = {}
	self.activeProjectiles = {}
	self.activeEffectsByHumanoid = {}
	self.modifierProviders = {}
	self.definitionOverrides = {}
	self.nextProjectileId = 0
	self.fixedStepAccumulator = 0
	self.projectileFolder = MagicServiceUtils.ensureProjectileFolder()
	self.binders = NevermoreSupport.getService(ServerBinderSupport)

	local gameRoot = script:FindFirstAncestor("game")
	local sharedRoot = if gameRoot ~= nil then gameRoot:FindFirstChild("Shared") else nil
	local modulesRoot = if sharedRoot ~= nil then sharedRoot:FindFirstChild("Modules") else nil
	if modulesRoot ~= nil and modulesRoot:IsA("Folder") then
		local itemsFolder = modulesRoot:FindFirstChild("Items")
		if itemsFolder ~= nil and itemsFolder:IsA("Folder") then
			self:registerDefinitionsFromFolder(itemsFolder)
		end

		local gameFolder = modulesRoot:FindFirstChild("Game")
		if gameFolder ~= nil and gameFolder:IsA("Folder") then
			local magicFolder = gameFolder:FindFirstChild("MagicWeapons")
			if magicFolder ~= nil and magicFolder:IsA("Folder") then
				self:registerDefinitionsFromFolder(magicFolder)
			end
		end
	end

	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self:trackPlayer(player)
		end
	end
	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self:trackPlayer(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:onHeartbeat(dt)
	end)
end

function MagicServiceServer.Destroy(self: MagicServiceServer)
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	for player in self.playerRuntimes do
		self:untrackPlayer(player)
	end

	for _, pool in self.projectilePools do
		for _, entry in pool do
			if entry.part.Parent ~= nil then
				entry.part:Destroy()
			end
		end
	end
	self.projectilePools = {}
	self.activeProjectiles = {}

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

MagicServiceServer.createRuntime = MagicServiceServer.CreateRuntime
MagicServiceServer.getRuntime = MagicServiceServer.GetRuntime
MagicServiceServer.resolveRuntimeByMagic = MagicServiceServer.ResolveRuntimeByMagic
MagicServiceServer.resolveManaStateSnapshot = MagicServiceServer.ResolveManaStateSnapshot
MagicServiceServer.pushState = MagicServiceServer.PushState
MagicServiceServer.getEquippedMagicToolFromInventory = MagicServiceServer.GetEquippedMagicToolFromInventory
MagicServiceServer.refreshEquippedWeaponFromInventory = MagicServiceServer.RefreshEquippedWeaponFromInventory
MagicServiceServer.getDefinitionOverride = MagicServiceServer.GetDefinitionOverride
MagicServiceServer.buildRuntimeConfigWithOverrides = MagicServiceServer.BuildRuntimeConfigWithOverrides
MagicServiceServer.collectCastModifiers = MagicServiceServer.CollectCastModifiers
MagicServiceServer.prepareControllerStatsForCast = MagicServiceServer.PrepareControllerStatsForCast
MagicServiceServer.onMagicCastRequested = MagicServiceServer.OnMagicCastRequested
MagicServiceServer.canConsumeMana = MagicServiceServer.CanConsumeMana
MagicServiceServer.consumeMana = MagicServiceServer.ConsumeMana
MagicServiceServer.requestSync = MagicServiceServer.RequestSync
MagicServiceServer.requestRefreshEquipped = MagicServiceServer.RequestRefreshEquipped
MagicServiceServer.requestSetInputHeld = MagicServiceServer.RequestSetInputHeld
MagicServiceServer.requestCast = MagicServiceServer.RequestCast
MagicServiceServer.createProjectilePart = MagicServiceServer.CreateProjectilePart
MagicServiceServer.acquireProjectilePart = MagicServiceServer.AcquireProjectilePart
MagicServiceServer.releaseProjectile = MagicServiceServer.ReleaseProjectile
MagicServiceServer.resolveCastOriginAndDirection = MagicServiceServer.ResolveCastOriginAndDirection
MagicServiceServer.invokeWeaponCallback = MagicServiceServer.InvokeWeaponCallback
MagicServiceServer.resolveHumanoidRootPart = MagicServiceServer.ResolveHumanoidRootPart
MagicServiceServer.collectOverlapParts = MagicServiceServer.CollectOverlapParts
MagicServiceServer.isValidHumanoidTarget = MagicServiceServer.IsValidHumanoidTarget
MagicServiceServer.applyKnockbackToHumanoid = MagicServiceServer.ApplyKnockbackToHumanoid
MagicServiceServer.damageHumanoidTarget = MagicServiceServer.DamageHumanoidTarget
MagicServiceServer.applyStackingStatusEffect = MagicServiceServer.ApplyStackingStatusEffect
MagicServiceServer.applySplashEffect = MagicServiceServer.ApplySplashEffect
MagicServiceServer.findNearestChainTarget = MagicServiceServer.FindNearestChainTarget
MagicServiceServer.applyChainEffect = MagicServiceServer.ApplyChainEffect
MagicServiceServer.applyEffectsFromHit = MagicServiceServer.ApplyEffectsFromHit
MagicServiceServer.expireProjectile = MagicServiceServer.ExpireProjectile
MagicServiceServer.handleProjectileHit = MagicServiceServer.HandleProjectileHit
MagicServiceServer.findNearestHomingTarget = MagicServiceServer.FindNearestHomingTarget
MagicServiceServer.stepProjectileHoming = MagicServiceServer.StepProjectileHoming
MagicServiceServer.resolveProjectileCollision = MagicServiceServer.ResolveProjectileCollision
MagicServiceServer.stepProjectiles = MagicServiceServer.StepProjectiles
MagicServiceServer.stepEffects = MagicServiceServer.StepEffects
MagicServiceServer.spawnProjectile = MagicServiceServer.SpawnProjectile
MagicServiceServer.executeCast = MagicServiceServer.ExecuteCast
MagicServiceServer.onMagicCastCommitted = MagicServiceServer.OnMagicCastCommitted
MagicServiceServer.stepHeldInput = MagicServiceServer.StepHeldInput
MagicServiceServer.onHeartbeat = MagicServiceServer.OnHeartbeat
MagicServiceServer.bindCharacter = MagicServiceServer.BindCharacter
MagicServiceServer.bindBackpack = MagicServiceServer.BindBackpack
MagicServiceServer.createMagicController = MagicServiceServer.CreateMagicController
MagicServiceServer.trackPlayer = MagicServiceServer.TrackPlayer
MagicServiceServer.untrackPlayer = MagicServiceServer.UntrackPlayer
MagicServiceServer.registerModifierProvider = MagicServiceServer.RegisterModifierProvider
MagicServiceServer.unregisterModifierProvider = MagicServiceServer.UnregisterModifierProvider
MagicServiceServer.registerWeaponDefinition = MagicServiceServer.RegisterWeaponDefinition
MagicServiceServer.registerWeaponModule = MagicServiceServer.RegisterWeaponModule
MagicServiceServer.registerDefinitionsFromFolder = MagicServiceServer.RegisterDefinitionsFromFolder
MagicServiceServer.init = MagicServiceServer.Init
MagicServiceServer.destroy = MagicServiceServer.Destroy

type MagicServiceServer = typeof(MagicServiceServer) & {
	networker: Networker.Server,
	inventoryService: InventoryServiceServerObject,
	manaService: ManaServiceServerObject?,
	npcService: NpcServiceServerObject?,
	bossService: BossServiceServerObject?,
	hpService: HpServiceServerObject?,
	playerRuntimes: { [Player]: PlayerRuntime },
	projectilePools: { [string]: { [string]: any } },
	activeProjectiles: { [number]: any },
	activeEffectsByHumanoid: { [Humanoid]: { [string]: any } },
	modifierProviders: { [string]: (...any) -> any },
	definitionOverrides: { [string]: any },
	projectileFolder: Folder,
	nextProjectileId: number,
	fixedStepAccumulator: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return MagicServiceServer :: MagicServiceServer
