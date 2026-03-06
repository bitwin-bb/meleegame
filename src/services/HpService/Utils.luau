--!strict
local HpServiceUtils = {}

export type HeartState = {
	index: number,
	health: number,
	maxHealth: number,
	fillAlpha: number,
	transparency: number,
	isFull: boolean,
	isEmpty: boolean,
}

export type HpServiceState = {
	health: number,
	maxHealth: number,
	heartValue: number,
	heartCount: number,
	hearts: { HeartState },
	isAlive: boolean,
	delta: number,
	lastDamage: number,
	lastHeal: number,
	updatedAt: number,
}

local DEFAULT_HEART_VALUE = 20
local DEFAULT_MAX_HEALTH = 100
local DEFAULT_DATA_PATH = { "hp" }

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end

	local nextValue = value
	if minimum ~= nil and nextValue < minimum then
		nextValue = minimum
	end
	if maximum ~= nil and nextValue > maximum then
		nextValue = maximum
	end
	return nextValue
end

local function createHeartState(index: number, healthInHeart: number, maxHealthInHeart: number): HeartState
	local clampedMaxHealth = math.max(1, maxHealthInHeart)
	local clampedHealth = math.clamp(healthInHeart, 0, clampedMaxHealth)
	local fillAlpha = if clampedMaxHealth > 0 then clampedHealth / clampedMaxHealth else 0
	local transparency = 1 - fillAlpha

	return {
		index = index,
		health = clampedHealth,
		maxHealth = clampedMaxHealth,
		fillAlpha = fillAlpha,
		transparency = transparency,
		isFull = clampedHealth >= clampedMaxHealth,
		isEmpty = clampedHealth <= 0,
	}
end

function HpServiceUtils.buildHearts(healthRaw: any, maxHealthRaw: any, heartValueRaw: any): { HeartState }
	local heartValue = sanitizeNumber(heartValueRaw, DEFAULT_HEART_VALUE, 1, nil)
	local maxHealth = sanitizeNumber(maxHealthRaw, DEFAULT_MAX_HEALTH, 1, nil)
	local health = sanitizeNumber(healthRaw, maxHealth, 0, maxHealth)

	local heartCount = math.max(1, math.ceil(maxHealth / heartValue))
	local hearts: { HeartState } = table.create(heartCount)

	for heartIndex = 1, heartCount do
		local heartStart = (heartIndex - 1) * heartValue
		local maxHealthInHeart = math.clamp(maxHealth - heartStart, 0, heartValue)
		local heartHealth = math.clamp(health - heartStart, 0, maxHealthInHeart)
		hearts[heartIndex] = createHeartState(heartIndex, heartHealth, maxHealthInHeart)
	end

	return hearts
end

function HpServiceUtils.createState(
	healthRaw: any,
	maxHealthRaw: any,
	heartValueRaw: any,
	fallback: HpServiceState?
): HpServiceState
	local fallbackMaxHealth = if fallback then fallback.maxHealth else DEFAULT_MAX_HEALTH
	local maxHealth = sanitizeNumber(maxHealthRaw, fallbackMaxHealth, 1, nil)
	local fallbackHealth = if fallback then fallback.health else maxHealth
	local health = sanitizeNumber(healthRaw, fallbackHealth, 0, maxHealth)
	local fallbackHeartValue = if fallback then fallback.heartValue else DEFAULT_HEART_VALUE
	local heartValue = sanitizeNumber(heartValueRaw, fallbackHeartValue, 1, nil)
	local previousHealth = if fallback then fallback.health else health
	local delta = health - previousHealth

	local hearts = HpServiceUtils.buildHearts(health, maxHealth, heartValue)
	return {
		health = health,
		maxHealth = maxHealth,
		heartValue = heartValue,
		heartCount = #hearts,
		hearts = hearts,
		isAlive = health > 0,
		delta = delta,
		lastDamage = math.max(0, -delta),
		lastHeal = math.max(0, delta),
		updatedAt = os.clock(),
	}
end

function HpServiceUtils.createDefaultState(): HpServiceState
	return HpServiceUtils.createState(DEFAULT_MAX_HEALTH, DEFAULT_MAX_HEALTH, DEFAULT_HEART_VALUE, nil)
end

function HpServiceUtils.createStateFromHumanoid(
	humanoid: Humanoid,
	heartValueRaw: any,
	fallback: HpServiceState?
): HpServiceState
	return HpServiceUtils.createState(humanoid.Health, humanoid.MaxHealth, heartValueRaw, fallback)
end

function HpServiceUtils.sanitizeState(stateRaw: any, fallback: HpServiceState?): HpServiceState
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	local fallbackState = if fallback then fallback else HpServiceUtils.createDefaultState()
	local nextState =
		HpServiceUtils.createState((source :: any).health, (source :: any).maxHealth, (source :: any).heartValue, fallbackState)

	local sourceUpdatedAt = (source :: any).updatedAt
	if typeof(sourceUpdatedAt) == "number" and sourceUpdatedAt == sourceUpdatedAt then
		nextState.updatedAt = sourceUpdatedAt
	end

	local sourceDelta = (source :: any).delta
	if typeof(sourceDelta) == "number" and sourceDelta == sourceDelta then
		nextState.delta = sourceDelta
	end

	local sourceLastDamage = (source :: any).lastDamage
	if typeof(sourceLastDamage) == "number" and sourceLastDamage == sourceLastDamage then
		nextState.lastDamage = math.max(0, sourceLastDamage)
	end

	local sourceLastHeal = (source :: any).lastHeal
	if typeof(sourceLastHeal) == "number" and sourceLastHeal == sourceLastHeal then
		nextState.lastHeal = math.max(0, sourceLastHeal)
	end

	return nextState
end

function HpServiceUtils.cloneState(state: HpServiceState): HpServiceState
	local clonedHearts: { HeartState } = table.create(#state.hearts)
	for index, heart in state.hearts do
		clonedHearts[index] = {
			index = heart.index,
			health = heart.health,
			maxHealth = heart.maxHealth,
			fillAlpha = heart.fillAlpha,
			transparency = heart.transparency,
			isFull = heart.isFull,
			isEmpty = heart.isEmpty,
		}
	end

	return {
		health = state.health,
		maxHealth = state.maxHealth,
		heartValue = state.heartValue,
		heartCount = state.heartCount,
		hearts = clonedHearts,
		isAlive = state.isAlive,
		delta = state.delta,
		lastDamage = state.lastDamage,
		lastHeal = state.lastHeal,
		updatedAt = state.updatedAt,
	}
end

function HpServiceUtils.clonePath(pathRaw: any): { string }
	local source = if typeof(pathRaw) == "table" then pathRaw else DEFAULT_DATA_PATH
	local output = {}
	for _, segmentRaw in source do
		if typeof(segmentRaw) == "string" and segmentRaw ~= "" then
			table.insert(output, segmentRaw)
		end
	end
	if #output == 0 then
		return { "hp" }
	end
	return output
end

function HpServiceUtils.getDefaultDataPath(): { string }
	return HpServiceUtils.clonePath(DEFAULT_DATA_PATH)
end

function HpServiceUtils.serializeStateForData(stateRaw: any): { [string]: any }
	local state = if typeof(stateRaw) == "table"
		then HpServiceUtils.sanitizeState(stateRaw, HpServiceUtils.createDefaultState())
		else HpServiceUtils.createDefaultState()

	return {
		health = state.health,
		maxHealth = state.maxHealth,
		updatedAt = os.time(),
	}
end

function HpServiceUtils.resolvePersistedHealth(healthDataRaw: any): number?
	if typeof(healthDataRaw) == "number" and healthDataRaw == healthDataRaw then
		return math.max(0, healthDataRaw)
	end

	if typeof(healthDataRaw) ~= "table" then
		return nil
	end

	local source = healthDataRaw :: { [string]: any }
	local healthRaw = source.health
	if typeof(healthRaw) ~= "number" or healthRaw ~= healthRaw then
		return nil
	end

	return math.max(0, healthRaw)
end

function HpServiceUtils.resolvePersistedHealthAndMaxHealth(
	healthDataRaw: any,
	fallbackMaxHealthRaw: any
): (number?, number)
	local fallbackMaxHealth =
		if typeof(fallbackMaxHealthRaw) == "number" and fallbackMaxHealthRaw == fallbackMaxHealthRaw
			then math.max(1, fallbackMaxHealthRaw)
			else DEFAULT_MAX_HEALTH

	if typeof(healthDataRaw) == "number" and healthDataRaw == healthDataRaw then
		return math.max(0, healthDataRaw), fallbackMaxHealth
	end

	if typeof(healthDataRaw) ~= "table" then
		return nil, fallbackMaxHealth
	end

	local source = healthDataRaw :: { [string]: any }
	local healthRaw = source.health
	if typeof(healthRaw) ~= "number" or healthRaw ~= healthRaw then
		return nil, fallbackMaxHealth
	end

	local maxHealthRaw = source.maxHealth
	local maxHealth =
		if typeof(maxHealthRaw) == "number" and maxHealthRaw == maxHealthRaw
			then math.max(1, maxHealthRaw)
			else fallbackMaxHealth

	return math.max(0, healthRaw), maxHealth
end

HpServiceUtils.DEFAULT_HEART_VALUE = DEFAULT_HEART_VALUE
HpServiceUtils.DEFAULT_MAX_HEALTH = DEFAULT_MAX_HEALTH
HpServiceUtils.DEFAULT_DATA_PATH = DEFAULT_DATA_PATH

return HpServiceUtils
