--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local Signal = require(ReplicatedStorage.Packages.Signal)

local Magic = {}
Magic.__index = Magic

export type MagicWeaponConfig = {
	itemId: string,
	itemType: string,
	displayName: string,
	description: string,
	damage: number,
	manaCost: number,
	cooldown: number,
	castTime: number,
	range: number,
	autoRepeatWhileHeld: boolean,
	allowQueueOnCooldown: boolean,
	projectile: { [string]: any }?,
	animations: { [string]: any }?,
	definition: { [string]: any },
}

export type MagicServiceAdapter = {
	canConsumeMana: ((self: MagicServiceAdapter, player: Player?, amount: number, context: { [string]: any }) -> boolean?)?,
	hasMana: ((self: MagicServiceAdapter, player: Player?, amount: number, context: { [string]: any }) -> boolean?)?,
	getMana: ((self: MagicServiceAdapter, player: Player?, context: { [string]: any }) -> number?)?,
	consumeMana: ((self: MagicServiceAdapter, player: Player?, amount: number, context: { [string]: any }) -> boolean?)?,
	spendMana: ((self: MagicServiceAdapter, player: Player?, amount: number, context: { [string]: any }) -> boolean?)?,
	onMagicCastRequested: ((self: MagicServiceAdapter, magic: any, context: { [string]: any }) -> boolean?)?,
	onMagicCastCommitted: ((self: MagicServiceAdapter, magic: any, context: { [string]: any }) -> ())?,
}

export type MagicCallbacks = {
	onCastRequested: ((self: Magic, context: { [string]: any }) -> ())?,
	onCastStarted: ((self: Magic, context: { [string]: any }) -> ())?,
	onCastCommitted: ((self: Magic, context: { [string]: any }) -> ())?,
	onCastFinished: ((self: Magic, context: { [string]: any }) -> ())?,
	onCastFailed: ((self: Magic, context: { [string]: any }) -> ())?,
	onWeaponChanged: ((self: Magic, context: { [string]: any }) -> ())?,
	onInputHeldChanged: ((self: Magic, inputHeld: boolean) -> ())?,
	onEnabledChanged: ((self: Magic, enabled: boolean) -> ())?,
}

export type MagicConfig = {
	tool: Tool?,
	character: Model?,
	ownerPlayer: Player?,
	service: MagicServiceAdapter?,
	callbacks: MagicCallbacks?,
	expectedItemType: string?,
	autoRepeatWhileHeld: boolean?,
	validateDefinitionItemType: boolean?,
	allowQueueOnCooldown: boolean?,
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type MagicSignals = {
	castRequested: SignalObject,
	castStarted: SignalObject,
	castCommitted: SignalObject,
	castFinished: SignalObject,
	castFailed: SignalObject,
	weaponChanged: SignalObject,
	inputHeldChanged: SignalObject,
	enabledChanged: SignalObject,
}

export type Magic = typeof(setmetatable(
	{} :: {
		janitor: any,
		toolJanitor: any,
		signals: MagicSignals,
		callbacks: MagicCallbacks,
		service: MagicServiceAdapter?,
		boundTool: Tool?,
		character: Model?,
		ownerPlayer: Player?,
		enabled: boolean,
		inputHeld: boolean,
		autoRepeatWhileHeld: boolean,
		allowQueueOnCooldown: boolean,
		validateDefinitionItemType: boolean,
		expectedItemType: string,
		expectedItemTypeToken: string,
		weaponConfig: MagicWeaponConfig?,
		resolvedItemId: string?,
		resolvedItemType: string?,
		queued: boolean,
		casting: boolean,
		cooldownUntil: number,
		retryToken: number,
		castToken: number,
		destroyed: boolean,
		lastError: string?,
	},
	Magic
))

local DEFAULT_EXPECTED_ITEM_TYPE = "magicWeapon"
local DEFAULT_DAMAGE = 12
local DEFAULT_MANA_COST = 8
local DEFAULT_COOLDOWN = 0.6
local DEFAULT_CAST_TIME = 0.15
local DEFAULT_RANGE = 35
local DEFAULT_AUTO_REPEAT = true
local DEFAULT_ALLOW_QUEUE_ON_COOLDOWN = true
local DEFAULT_VALIDATE_DEFINITION_ITEM_TYPE = true

local ATTACK_SPEED_TO_COOLDOWN = {
	["insanely fast"] = 0.18,
	["very fast"] = 0.24,
	["fast"] = 0.34,
	["normal speed"] = 0.48,
	["normal"] = 0.48,
	["slow"] = 0.66,
	["very slow"] = 0.86,
}

local cachedItemIdLookup: { [string]: string }? = nil
local cachedDefinitions: { [string]: any } = {}
local cachedWeaponConfigs: { [string]: MagicWeaponConfig | false } = {}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeItemId(itemIdRaw: any): string?
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return nil
	end
	return itemId
end

local function sanitizeString(valueRaw: any, fallback: string): string
	local value = trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local numericText = string.match(string.lower(valueRaw), "%-?%d+%.?%d*")
		if numericText ~= nil then
			local parsed = tonumber(numericText)
			if parsed ~= nil and parsed == parsed then
				value = parsed
			end
		end
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function normalizeTypeToken(valueRaw: any): string
	local normalized = string.lower(trim(valueRaw))
	if normalized == "" then
		return ""
	end
	return string.gsub(normalized, "[%s_%-]+", "")
end

local function normalizeTypeLabel(valueRaw: any, fallback: string): string
	local value = trim(valueRaw)
	if value == "" then
		return fallback
	end
	return value
end

local function cloneWeaponConfig(config: MagicWeaponConfig): MagicWeaponConfig
	return {
		itemId = config.itemId,
		itemType = config.itemType,
		displayName = config.displayName,
		description = config.description,
		damage = config.damage,
		manaCost = config.manaCost,
		cooldown = config.cooldown,
		castTime = config.castTime,
		range = config.range,
		autoRepeatWhileHeld = config.autoRepeatWhileHeld,
		allowQueueOnCooldown = config.allowQueueOnCooldown,
		projectile = config.projectile,
		animations = config.animations,
		definition = config.definition,
	}
end

local function areWeaponConfigsEquivalent(lhsRaw: any, rhsRaw: any): boolean
	if lhsRaw == rhsRaw then
		return true
	end
	if typeof(lhsRaw) ~= "table" or typeof(rhsRaw) ~= "table" then
		return false
	end

	local lhs = lhsRaw :: MagicWeaponConfig
	local rhs = rhsRaw :: MagicWeaponConfig
	return lhs.itemId == rhs.itemId
		and lhs.itemType == rhs.itemType
		and lhs.damage == rhs.damage
		and lhs.manaCost == rhs.manaCost
		and lhs.cooldown == rhs.cooldown
		and lhs.castTime == rhs.castTime
		and lhs.range == rhs.range
		and lhs.autoRepeatWhileHeld == rhs.autoRepeatWhileHeld
		and lhs.allowQueueOnCooldown == rhs.allowQueueOnCooldown
end

local function resolveItemIdLookup(): { [string]: string }
	if cachedItemIdLookup ~= nil then
		return cachedItemIdLookup
	end

	cachedItemIdLookup = ItemRegistry.getItemIdLookup()
	return cachedItemIdLookup :: { [string]: string }
end

local function resolveCanonicalItemId(itemIdRaw: any): string?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local lookup = resolveItemIdLookup()
	local canonical = lookup[itemId]
	if canonical == nil then
		canonical = lookup[string.lower(itemId)]
	end
	if canonical ~= nil then
		return canonical
	end

	return nil
end

local function getItemDefinition(itemIdRaw: any): { [string]: any }?
	local rawItemId = sanitizeItemId(itemIdRaw)
	if rawItemId == nil then
		return nil
	end

	local itemId = resolveCanonicalItemId(rawItemId)
	if itemId == nil then
		return nil
	end

	local cached = cachedDefinitions[itemId]
	if cached ~= nil then
		return if cached == false then nil else cached
	end

	local definition = ItemRegistry.resolveDefinition(itemId)
	if definition == nil then
		cachedDefinitions[itemId] = false
		cachedDefinitions[rawItemId] = false
		return nil
	end

	cachedDefinitions[itemId] = definition
	cachedDefinitions[rawItemId] = definition
	return definition
end

local function resolveToolAttributeText(tool: Tool, ...: string): string?
	for _, attributeName in { ... } do
		local attributeValue = sanitizeItemId(tool:GetAttribute(attributeName))
		if attributeValue ~= nil then
			return attributeValue
		end
	end
	return nil
end

function Magic.resolveToolItemId(toolRaw: any): string?
	if typeof(toolRaw) ~= 'Instance' or not toolRaw:IsA('Tool') then
		return nil
	end

	local tool = toolRaw :: Tool
	local itemId = resolveToolAttributeText(tool, 'itemId', 'ItemId', 'ittemId', 'id')
	if itemId == nil then
		itemId = sanitizeItemId(tool.Name)
	end
	if itemId == nil then
		return nil
	end
	return resolveCanonicalItemId(itemId)
end

function Magic.resolveToolItemType(toolRaw: any): string?
	if typeof(toolRaw) ~= 'Instance' or not toolRaw:IsA('Tool') then
		return nil
	end

	local tool = toolRaw :: Tool
	local rawType = resolveToolAttributeText(tool, 'itemType', 'ItemType', 'itemtype', 'type', 'Type')
	if rawType == nil then
		return nil
	end

	local normalized = normalizeTypeToken(rawType)
	if normalized == '' then
		return nil
	end

	return normalized
end

function Magic.isMagicTool(toolRaw: any, expectedTypeRaw: any): boolean
	local itemType = Magic.resolveToolItemType(toolRaw)
	if itemType == nil then
		return false
	end

	local expectedTypeToken = normalizeTypeToken(if expectedTypeRaw == nil then DEFAULT_EXPECTED_ITEM_TYPE else expectedTypeRaw)
	if expectedTypeToken == '' then
		expectedTypeToken = normalizeTypeToken(DEFAULT_EXPECTED_ITEM_TYPE)
	end
	return itemType == expectedTypeToken
end

local function normalizeProjectile(definition: { [string]: any }, magicData: { [string]: any }): { [string]: any }?
	local projectileRaw = if typeof(magicData.projectile) == 'table' then magicData.projectile else definition.projectile
	if typeof(projectileRaw) ~= 'table' then
		return nil
	end

	local projectile = projectileRaw :: { [string]: any }
	return {
		enabled = sanitizeBoolean(projectile.enabled, true),
		speed = sanitizeNumber(projectile.speed, 120, 1, 5000),
		spread = sanitizeNumber(projectile.spread, 0, 0, 90),
		count = math.max(1, math.floor(sanitizeNumber(projectile.count, 1, 1, 50))),
		lifetime = sanitizeNumber(projectile.lifetime, 2, 0.05, 60),
		pierce = math.max(0, math.floor(sanitizeNumber(projectile.pierce, 0, 0, 100))),
	}
end

local function resolveWeaponConfig(itemIdRaw: any, expectedTypeToken: string, expectedTypeLabel: string, validateDefinitionType: boolean): MagicWeaponConfig?
	local rawItemId = sanitizeItemId(itemIdRaw)
	if rawItemId == nil then
		return nil
	end

	local canonicalItemId = resolveCanonicalItemId(rawItemId)
	if canonicalItemId == nil then
		cachedWeaponConfigs[rawItemId] = false
		return nil
	end

	local cached = cachedWeaponConfigs[canonicalItemId]
	if cached == nil then
		cached = cachedWeaponConfigs[rawItemId]
	end
	if cached ~= nil then
		if cached == false then
			return nil
		end
		local cloned = cloneWeaponConfig(cached)
		cloned.itemType = expectedTypeLabel
		return cloned
	end

	local definition = getItemDefinition(canonicalItemId)
	if definition == nil then
		cachedWeaponConfigs[canonicalItemId] = false
		cachedWeaponConfigs[rawItemId] = false
		return nil
	end

	local magicData = if typeof(definition.magic) == 'table' then definition.magic :: { [string]: any } else {}
	local stats = if typeof(definition.stats) == 'table' then definition.stats :: { [string]: any } else {}

	local definitionTypeToken = normalizeTypeToken(definition.itemType or definition.type or definition.weaponType or magicData.itemType)
	if validateDefinitionType and definitionTypeToken ~= '' and definitionTypeToken ~= expectedTypeToken then
		cachedWeaponConfigs[canonicalItemId] = false
		cachedWeaponConfigs[rawItemId] = false
		return nil
	end

	local useCase = string.lower(trim(definition.useCase))
	if useCase ~= '' and useCase ~= 'weapon' and useCase ~= 'magic' then
		cachedWeaponConfigs[canonicalItemId] = false
		cachedWeaponConfigs[rawItemId] = false
		return nil
	end

	local attackSpeedCooldown = ATTACK_SPEED_TO_COOLDOWN[string.lower(trim(stats.attackSpeed))]
	local cooldownFromAttackSpeed = if attackSpeedCooldown ~= nil then attackSpeedCooldown else DEFAULT_COOLDOWN

	local weaponConfig: MagicWeaponConfig = {
		itemId = canonicalItemId,
		itemType = expectedTypeLabel,
		displayName = sanitizeString(definition.name, canonicalItemId),
		description = sanitizeString(definition.description, ''),
		damage = sanitizeNumber(magicData.damage or stats.magicDamage or stats.dmg or definition.damage, DEFAULT_DAMAGE, 0, 500000),
		manaCost = sanitizeNumber(magicData.manaCost or magicData.mana or stats.manaCost or stats.mana, DEFAULT_MANA_COST, 0, 100000),
		cooldown = sanitizeNumber(magicData.cooldown or definition.cooldown, cooldownFromAttackSpeed, 0, 120),
		castTime = sanitizeNumber(magicData.castTime or definition.castTime, DEFAULT_CAST_TIME, 0, 60),
		range = sanitizeNumber(magicData.range or definition.range, DEFAULT_RANGE, 0.1, 5000),
		autoRepeatWhileHeld = sanitizeBoolean(magicData.autoRepeatWhileHeld, DEFAULT_AUTO_REPEAT),
		allowQueueOnCooldown = sanitizeBoolean(magicData.allowQueueOnCooldown, DEFAULT_ALLOW_QUEUE_ON_COOLDOWN),
		projectile = normalizeProjectile(definition, magicData),
		animations = if typeof(magicData.animations) == 'table' then magicData.animations else if typeof(definition.animations) == 'table' then definition.animations else nil,
		definition = definition,
	}

	cachedWeaponConfigs[canonicalItemId] = weaponConfig
	cachedWeaponConfigs[rawItemId] = weaponConfig
	return cloneWeaponConfig(weaponConfig)
end

function Magic.resolveWeaponConfig(itemIdRaw: any, expectedItemTypeRaw: any): MagicWeaponConfig?
	local expectedTypeLabel = normalizeTypeLabel(expectedItemTypeRaw, DEFAULT_EXPECTED_ITEM_TYPE)
	local expectedTypeToken = normalizeTypeToken(expectedTypeLabel)
	if expectedTypeToken == '' then
		return nil
	end
	return resolveWeaponConfig(itemIdRaw, expectedTypeToken, expectedTypeLabel, false)
end

function Magic.resolveWeaponConfigFromTool(toolRaw: any, expectedItemTypeRaw: any): MagicWeaponConfig?
	if typeof(toolRaw) ~= 'Instance' or not toolRaw:IsA('Tool') then
		return nil
	end

	local expectedTypeLabel = normalizeTypeLabel(expectedItemTypeRaw, DEFAULT_EXPECTED_ITEM_TYPE)
	local expectedTypeToken = normalizeTypeToken(expectedTypeLabel)
	if expectedTypeToken == '' then
		return nil
	end

	local itemTypeToken = Magic.resolveToolItemType(toolRaw)
	if itemTypeToken == nil or itemTypeToken ~= expectedTypeToken then
		return nil
	end

	local itemId = Magic.resolveToolItemId(toolRaw)
	if itemId == nil then
		return nil
	end

	return resolveWeaponConfig(itemId, expectedTypeToken, expectedTypeLabel, true)
end

local function getServiceMethod(service: MagicServiceAdapter, methodName: string): ((...any) -> any)?
	local method = (service :: any)[methodName]
	if typeof(method) ~= 'function' then
		return nil
	end
	return method
end

local function mergeContext(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	if extra == nil then
		return base
	end
	for key, value in extra do
		base[key] = value
	end
	return base
end

function Magic.new(configRaw: MagicConfig?): Magic
	local config = if typeof(configRaw) == 'table' then configRaw else {}
	local expectedTypeLabel = normalizeTypeLabel(config.expectedItemType, DEFAULT_EXPECTED_ITEM_TYPE)
	local expectedTypeToken = normalizeTypeToken(expectedTypeLabel)

	local self = setmetatable({
		janitor = Janitor.new(),
		toolJanitor = Janitor.new(),
		signals = {
			castRequested = Signal.new(),
			castStarted = Signal.new(),
			castCommitted = Signal.new(),
			castFinished = Signal.new(),
			castFailed = Signal.new(),
			weaponChanged = Signal.new(),
			inputHeldChanged = Signal.new(),
			enabledChanged = Signal.new(),
		},
		callbacks = if typeof(config.callbacks) == 'table' then config.callbacks else {},
		service = if typeof(config.service) == 'table' then config.service else nil,
		boundTool = nil,
		character = if typeof(config.character) == 'Instance' and config.character:IsA('Model') then config.character else nil,
		ownerPlayer = if typeof(config.ownerPlayer) == 'Instance' and config.ownerPlayer:IsA('Player') then config.ownerPlayer else nil,
		enabled = true,
		inputHeld = false,
		autoRepeatWhileHeld = sanitizeBoolean(config.autoRepeatWhileHeld, DEFAULT_AUTO_REPEAT),
		allowQueueOnCooldown = sanitizeBoolean(config.allowQueueOnCooldown, DEFAULT_ALLOW_QUEUE_ON_COOLDOWN),
		validateDefinitionItemType = sanitizeBoolean(config.validateDefinitionItemType, DEFAULT_VALIDATE_DEFINITION_ITEM_TYPE),
		expectedItemType = expectedTypeLabel,
		expectedItemTypeToken = if expectedTypeToken == '' then normalizeTypeToken(DEFAULT_EXPECTED_ITEM_TYPE) else expectedTypeToken,
		weaponConfig = nil,
		resolvedItemId = nil,
		resolvedItemType = nil,
		queued = false,
		casting = false,
		cooldownUntil = 0,
		retryToken = 0,
		castToken = 0,
		destroyed = false,
		lastError = nil,
	}, Magic)

	self.janitor:GiveChore(self.toolJanitor)
	self.janitor:GiveChore(function()
		for _, signalObject in self.signals do
			local signalObjectTyped = signalObject :: SignalObject
			signalObjectTyped:Destroy()
		end
	end)

	if config.tool ~= nil then
		self:bindTool(config.tool)
	end

	return self
end

function Magic:_invokeCallback(name: string, ...: any)
	local callback = (self.callbacks :: any)[name]
	if typeof(callback) ~= 'function' then
		return
	end
	local ok, err = pcall(callback, self, ...)
	if not ok then
		warn(("[Magic] Callback '%s' failed: %s"):format(name, tostring(err)))
	end
end

function Magic:_callServiceBoolean(methodName: string, amount: number, context: { [string]: any }): boolean?
	if self.service == nil then
		return nil
	end

	local method = getServiceMethod(self.service, methodName)
	if method == nil then
		return nil
	end

	local ok, result = pcall(method, self.service, self.ownerPlayer, amount, context)
	if not ok then
		warn(("[Magic] Service method '%s' failed: %s"):format(methodName, tostring(result)))
		return false
	end
	if result == nil then
		return nil
	end
	return result == true
end

function Magic:_serviceAllowsCast(context: { [string]: any }): boolean
	if self.service == nil then
		return true
	end

	local onRequested = getServiceMethod(self.service, 'onMagicCastRequested')
	if onRequested == nil then
		return true
	end

	local ok, result = pcall(onRequested, self.service, self, context)
	if not ok then
		warn(("[Magic] Service method 'onMagicCastRequested' failed: %s"):format(tostring(result)))
		return false
	end
	return result ~= false
end

function Magic:_serviceCanConsumeMana(amount: number, context: { [string]: any }): boolean
	if amount <= 0 or self.service == nil then
		return true
	end

	local canConsume = self:_callServiceBoolean('canConsumeMana', amount, context)
	if canConsume ~= nil then
		return canConsume
	end

	local hasMana = self:_callServiceBoolean('hasMana', amount, context)
	if hasMana ~= nil then
		return hasMana
	end

	local getManaMethod = getServiceMethod(self.service, 'getMana')
	if getManaMethod == nil then
		return true
	end

	local ok, result = pcall(getManaMethod, self.service, self.ownerPlayer, context)
	if not ok then
		warn(("[Magic] Service method 'getMana' failed: %s"):format(tostring(result)))
		return false
	end
	if typeof(result) == 'number' and result == result then
		return result >= amount
	end
	return true
end

function Magic:_serviceConsumeMana(amount: number, context: { [string]: any }): boolean
	if amount <= 0 or self.service == nil then
		return true
	end

	local consumed = self:_callServiceBoolean('consumeMana', amount, context)
	if consumed ~= nil then
		return consumed
	end

	local spent = self:_callServiceBoolean('spendMana', amount, context)
	if spent ~= nil then
		return spent
	end

	return true
end

function Magic:_notifyServiceCommitted(context: { [string]: any })
	if self.service == nil then
		return
	end

	local onCommitted = getServiceMethod(self.service, 'onMagicCastCommitted')
	if onCommitted == nil then
		return
	end

	local ok, err = pcall(onCommitted, self.service, self, context)
	if not ok then
		warn(("[Magic] Service method 'onMagicCastCommitted' failed: %s"):format(tostring(err)))
	end
end

function Magic:_emitFailed(reason: string, contextExtra: { [string]: any }?)
	self.lastError = reason
	local context = mergeContext({
		now = os.clock(),
		reason = reason,
		itemId = self.resolvedItemId,
		itemType = self.resolvedItemType,
		weaponConfig = self.weaponConfig,
	}, contextExtra)
	self.signals.castFailed:Fire(context)
	self:_invokeCallback('onCastFailed', context)
end

function Magic:_emitFinished(success: boolean, reason: string, contextExtra: { [string]: any }?)
	local context = mergeContext({
		now = os.clock(),
		success = success,
		reason = reason,
		itemId = self.resolvedItemId,
		itemType = self.resolvedItemType,
		weaponConfig = self.weaponConfig,
	}, contextExtra)
	self.signals.castFinished:Fire(context)
	self:_invokeCallback('onCastFinished', context)
end

function Magic:_scheduleQueue(waitTime: number)
	if self.destroyed then
		return
	end

	self.retryToken += 1
	local token = self.retryToken
	task.delay(math.max(0, waitTime), function()
		if self.destroyed or token ~= self.retryToken then
			return
		end
		self:_processQueue('CooldownReady')
	end)
end

function Magic:_processQueue(triggerRaw: any)
	if self.destroyed or not self.enabled or not self.queued or self.casting then
		return
	end

	local now = os.clock()
	if now < self.cooldownUntil then
		if self.allowQueueOnCooldown then
			self:_scheduleQueue(self.cooldownUntil - now)
		end
		return
	end

	self.queued = false
	self:_startCast(triggerRaw)
end

function Magic:_commitCast(token: number, baseContext: { [string]: any })
	if self.destroyed or not self.casting or self.castToken ~= token then
		return
	end

	local config = self.weaponConfig
	if config == nil then
		self.casting = false
		self:_emitFailed('WeaponConfigLost', baseContext)
		self:_emitFinished(false, 'WeaponConfigLost', baseContext)
		return
	end

	local context = mergeContext({
		now = os.clock(),
		itemId = config.itemId,
		itemType = config.itemType,
		weaponConfig = config,
		tool = self.boundTool,
		ownerPlayer = self.ownerPlayer,
		character = self.character,
		castToken = token,
	}, baseContext)

	if not self:_serviceConsumeMana(config.manaCost, context) then
		self.casting = false
		self:_emitFailed('ManaConsumeRejected', context)
		self:_emitFinished(false, 'ManaConsumeRejected', context)
		return
	end

	self.cooldownUntil = os.clock() + math.max(0, config.cooldown)
	self.casting = false

	self.signals.castCommitted:Fire(context)
	self:_invokeCallback('onCastCommitted', context)
	self:_notifyServiceCommitted(context)
	self:_emitFinished(true, 'CastCommitted', context)

	if self.autoRepeatWhileHeld and self.inputHeld then
		self:queueCast('HoldRepeat')
	elseif self.queued then
		self:_processQueue('Pending')
	end
end

function Magic:_startCast(triggerRaw: any)
	if self.destroyed or not self.enabled or self.casting then
		return
	end

	local tool = self.boundTool
	if tool == nil then
		self:_emitFailed('NoBoundTool', { trigger = triggerRaw })
		return
	end

	local config = self:refreshWeaponConfig()
	if config == nil then
		self:_emitFailed(if self.lastError ~= nil then self.lastError else 'WeaponConfigNotFound', {
			trigger = triggerRaw,
			tool = tool,
		})
		return
	end

	local context = {
		now = os.clock(),
		trigger = sanitizeString(triggerRaw, 'Cast'),
		itemId = config.itemId,
		itemType = config.itemType,
		weaponConfig = config,
		tool = tool,
		ownerPlayer = self.ownerPlayer,
		character = self.character,
	}

	if not self:_serviceAllowsCast(context) then
		self:_emitFailed('ServiceRejected', context)
		return
	end
	if not self:_serviceCanConsumeMana(config.manaCost, context) then
		self:_emitFailed('NotEnoughMana', context)
		return
	end

	self.casting = true
	self.castToken += 1
	local token = self.castToken

	context.castToken = token
	context.startedAt = os.clock()
	self.signals.castStarted:Fire(context)
	self:_invokeCallback('onCastStarted', context)

	local castTime = math.max(0, config.castTime)
	if castTime <= 0 then
		self:_commitCast(token, context)
		return
	end

	task.delay(castTime, function()
		if self.destroyed or not self.casting or self.castToken ~= token then
			return
		end
		self:_commitCast(token, context)
	end)
end

function Magic:queueCast(triggerRaw: any): boolean
	if self.destroyed or not self.enabled then
		return false
	end

	self.queued = true
	local context = {
		now = os.clock(),
		trigger = sanitizeString(triggerRaw, 'Queue'),
		itemId = self.resolvedItemId,
		itemType = self.resolvedItemType,
		weaponConfig = self.weaponConfig,
		tool = self.boundTool,
	}

	self.signals.castRequested:Fire(context)
	self:_invokeCallback('onCastRequested', context)
	self:_processQueue(context.trigger)
	return true
end

function Magic:cast(triggerRaw: any): boolean
	return self:queueCast(triggerRaw or 'Cast')
end

function Magic:tap(triggerRaw: any): boolean
	return self:queueCast(triggerRaw or 'Tap')
end

function Magic:inputBegan(triggerRaw: any): boolean
	local wasHeld = self.inputHeld
	self.inputHeld = true
	if wasHeld ~= self.inputHeld then
		self.signals.inputHeldChanged:Fire(self.inputHeld)
		self:_invokeCallback('onInputHeldChanged', self.inputHeld)
	end
	return self:queueCast(triggerRaw or 'InputBegan')
end

function Magic:inputEnded(_: any): boolean
	local wasHeld = self.inputHeld
	self.inputHeld = false
	if wasHeld ~= self.inputHeld then
		self.signals.inputHeldChanged:Fire(self.inputHeld)
		self:_invokeCallback('onInputHeldChanged', self.inputHeld)
	end
	return true
end

function Magic:setEnabled(enabledRaw: any)
	local enabled = sanitizeBoolean(enabledRaw, self.enabled)
	if enabled == self.enabled then
		return
	end

	self.enabled = enabled
	self.signals.enabledChanged:Fire(self.enabled)
	self:_invokeCallback('onEnabledChanged', self.enabled)
	if not enabled then
		self:cancel('Disabled')
	elseif self.queued then
		self:_processQueue('Enabled')
	end
end

function Magic:setService(serviceRaw: any)
	self.service = if typeof(serviceRaw) == 'table' then serviceRaw else nil
end

function Magic:setOwnerPlayer(playerRaw: any)
	self.ownerPlayer = if typeof(playerRaw) == 'Instance' and playerRaw:IsA('Player') then playerRaw else nil
end

function Magic:setCharacter(characterRaw: any)
	self.character = if typeof(characterRaw) == 'Instance' and characterRaw:IsA('Model') then characterRaw else nil
end

function Magic:setExpectedItemType(itemTypeRaw: any)
	local label = normalizeTypeLabel(itemTypeRaw, DEFAULT_EXPECTED_ITEM_TYPE)
	local token = normalizeTypeToken(label)
	if token == '' then
		return
	end

	self.expectedItemType = label
	self.expectedItemTypeToken = token
	self:refreshWeaponConfig()
end

function Magic:refreshWeaponConfig(): MagicWeaponConfig?
	local tool = self.boundTool
	if tool == nil then
		self.weaponConfig = nil
		self.resolvedItemId = nil
		self.resolvedItemType = nil
		self.lastError = 'NoBoundTool'
		return nil
	end

	local toolItemType = Magic.resolveToolItemType(tool)
	if toolItemType == nil then
		self.weaponConfig = nil
		self.resolvedItemId = nil
		self.resolvedItemType = nil
		self.lastError = 'MissingItemTypeAttribute'
		return nil
	end
	if toolItemType ~= self.expectedItemTypeToken then
		self.weaponConfig = nil
		self.resolvedItemId = nil
		self.resolvedItemType = toolItemType
		self.lastError = 'InvalidItemType'
		return nil
	end

	local itemId = Magic.resolveToolItemId(tool)
	if itemId == nil then
		self.weaponConfig = nil
		self.resolvedItemId = nil
		self.resolvedItemType = toolItemType
		self.lastError = 'MissingItemIdAttribute'
		return nil
	end

	local weaponConfig = resolveWeaponConfig(itemId, self.expectedItemTypeToken, self.expectedItemType, self.validateDefinitionItemType)
	if weaponConfig == nil then
		self.weaponConfig = nil
		self.resolvedItemId = itemId
		self.resolvedItemType = toolItemType
		self.lastError = 'NoMagicWeaponDefinition'
		return nil
	end

	local previousItemId = self.resolvedItemId
	local previousWeaponConfig = self.weaponConfig

	self.weaponConfig = weaponConfig
	self.resolvedItemId = weaponConfig.itemId
	self.resolvedItemType = toolItemType
	self.lastError = nil
	self.autoRepeatWhileHeld = weaponConfig.autoRepeatWhileHeld
	self.allowQueueOnCooldown = weaponConfig.allowQueueOnCooldown

	if previousItemId ~= self.resolvedItemId or not areWeaponConfigsEquivalent(previousWeaponConfig, weaponConfig) then
		local context = {
			now = os.clock(),
			itemId = self.resolvedItemId,
			itemType = self.resolvedItemType,
			weaponConfig = self.weaponConfig,
			tool = tool,
		}
		self.signals.weaponChanged:Fire(context)
		self:_invokeCallback('onWeaponChanged', context)
	end

	return cloneWeaponConfig(weaponConfig)
end

function Magic:bindTool(toolRaw: any): boolean
	local tool = if typeof(toolRaw) == 'Instance' and toolRaw:IsA('Tool') then toolRaw else nil
	if tool == nil then
		return false
	end

	self.toolJanitor:Clean()
	self.boundTool = tool
	if tool.Parent ~= nil and tool.Parent:IsA('Model') then
		self:setCharacter(tool.Parent)
	end

	for _, attributeName in { 'itemType', 'ItemType', 'itemtype', 'type', 'itemId', 'ItemId', 'ittemId', 'id' } do
		self.toolJanitor:GiveChore(tool:GetAttributeChangedSignal(attributeName):Connect(function()
			self:refreshWeaponConfig()
		end))
	end

	self.toolJanitor:GiveChore(tool.Equipped:Connect(function()
		if tool.Parent ~= nil and tool.Parent:IsA('Model') then
			self:setCharacter(tool.Parent)
		end
		self:refreshWeaponConfig()
	end))

	self.toolJanitor:GiveChore(tool.Activated:Connect(function()
		self:inputBegan('ToolActivated')
	end))

	self.toolJanitor:GiveChore(tool.Deactivated:Connect(function()
		self:inputEnded('ToolDeactivated')
	end))

	self.toolJanitor:GiveChore(tool.Unequipped:Connect(function()
		self:inputEnded('ToolUnequipped')
		self:cancel('ToolUnequipped')
	end))

	self.toolJanitor:GiveChore(tool.Destroying:Connect(function()
		if self.boundTool == tool then
			self:unbindTool()
		end
	end))

	self:refreshWeaponConfig()
	return true
end

function Magic:unbindTool()
	self.toolJanitor:Clean()
	self.boundTool = nil
	self.weaponConfig = nil
	self.resolvedItemId = nil
	self.resolvedItemType = nil
	self.lastError = nil
	self.queued = false
	self.retryToken += 1
end

function Magic:resolveBoundWeaponConfig(): MagicWeaponConfig?
	return self:refreshWeaponConfig()
end

function Magic:getBoundItemId(): string?
	return self.resolvedItemId
end

function Magic:getBoundItemType(): string?
	return self.resolvedItemType
end

function Magic:getLastError(): string?
	return self.lastError
end

function Magic:on(signalNameRaw: any, callback: (...any) -> ()): RBXScriptConnection?
	if typeof(signalNameRaw) ~= 'string' or typeof(callback) ~= 'function' then
		return nil
	end

	local signalObject = (self.signals :: any)[signalNameRaw]
	if signalObject == nil then
		return nil
	end
	return (signalObject :: SignalObject):Connect(callback)
end

function Magic:cancel(reasonRaw: any)
	self.queued = false
	self.retryToken += 1

	local wasCasting = self.casting
	self.casting = false
	self.castToken += 1

	local wasHeld = self.inputHeld
	self.inputHeld = false
	if wasHeld ~= self.inputHeld then
		self.signals.inputHeldChanged:Fire(self.inputHeld)
		self:_invokeCallback('onInputHeldChanged', self.inputHeld)
	end

	if wasCasting then
		self:_emitFinished(false, sanitizeString(reasonRaw, 'Cancelled'))
	end
end

function Magic:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:cancel('Destroyed')
	self:unbindTool()
	self.janitor:Destroy()
end

function Magic:Destroy()
	self:destroy()
end

return Magic
