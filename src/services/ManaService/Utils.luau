--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local ManaServiceUtils = {}

export type ManaServiceState = {
	mana: number,
	maxMana: number,
	regenPerSecond: number,
	normalizedMana: number,
	delta: number,
	lastSpend: number,
	lastGain: number,
	isLoaded: boolean,
	updatedAt: number,
}

local DEFAULT_MAX_MANA = 20
local DEFAULT_REGEN_PER_SECOND = 8
local DEFAULT_DATA_PATH = { "mana" }

ManaServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
ManaServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
ManaServiceUtils.DEFAULT_MAX_MANA = DEFAULT_MAX_MANA
ManaServiceUtils.DEFAULT_REGEN_PER_SECOND = DEFAULT_REGEN_PER_SECOND
ManaServiceUtils.DEFAULT_DATA_PATH = DEFAULT_DATA_PATH

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(valueRaw)
		if parsed ~= nil and parsed == parsed then
			value = parsed
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

local function sanitizeLoadedFlag(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

function ManaServiceUtils.createState(
	manaRaw: any,
	maxManaRaw: any,
	regenPerSecondRaw: any,
	isLoadedRaw: any,
	fallbackRaw: ManaServiceState?
): ManaServiceState
	local fallback = fallbackRaw
	local fallbackMaxMana = if fallback ~= nil then fallback.maxMana else DEFAULT_MAX_MANA
	local maxMana = sanitizeNumber(maxManaRaw, fallbackMaxMana, 1, 100000)
	local fallbackMana = if fallback ~= nil then fallback.mana else maxMana
	local mana = sanitizeNumber(manaRaw, fallbackMana, 0, maxMana)
	local fallbackRegenPerSecond = if fallback ~= nil then fallback.regenPerSecond else DEFAULT_REGEN_PER_SECOND
	local regenPerSecond = sanitizeNumber(regenPerSecondRaw, fallbackRegenPerSecond, 0, 10000)
	local previousMana = if fallback ~= nil then fallback.mana else mana
	local delta = mana - previousMana
	local isLoaded = sanitizeLoadedFlag(isLoadedRaw, if fallback ~= nil then fallback.isLoaded else false)

	return {
		mana = mana,
		maxMana = maxMana,
		regenPerSecond = regenPerSecond,
		normalizedMana = math.clamp(mana / maxMana, 0, 1),
		delta = delta,
		lastSpend = math.max(0, -delta),
		lastGain = math.max(0, delta),
		isLoaded = isLoaded,
		updatedAt = os.clock(),
	}
end

function ManaServiceUtils.createDefaultState(): ManaServiceState
	return ManaServiceUtils.createState(DEFAULT_MAX_MANA, DEFAULT_MAX_MANA, DEFAULT_REGEN_PER_SECOND, false, nil)
end

function ManaServiceUtils.sanitizeState(stateRaw: any, fallbackRaw: ManaServiceState?): ManaServiceState
	local source = if typeof(stateRaw) == "table" then (stateRaw :: { [string]: any }) else {}
	local fallback = if fallbackRaw ~= nil then fallbackRaw else ManaServiceUtils.createDefaultState()
	local nextState = ManaServiceUtils.createState(
		source.mana,
		source.maxMana,
		source.regenPerSecond,
		source.isLoaded,
		fallback
	)
	local updatedAtRaw = source.updatedAt
	if typeof(updatedAtRaw) == "number" and updatedAtRaw == updatedAtRaw then
		nextState.updatedAt = updatedAtRaw
	end
	return nextState
end

function ManaServiceUtils.cloneState(state: ManaServiceState): ManaServiceState
	return Sift.Dictionary.copy(state) :: ManaServiceState
end

function ManaServiceUtils.clonePath(pathRaw: any): { string }
	local source = if typeof(pathRaw) == "table" then pathRaw else DEFAULT_DATA_PATH
	local output = Sift.Array.map(source, function(segmentRaw: any): string?
		if typeof(segmentRaw) == "string" and segmentRaw ~= "" then
			return segmentRaw
		end
		return nil
	end)
	if #output <= 0 then
		return { "mana" }
	end
	return output
end

function ManaServiceUtils.getDefaultDataPath(): { string }
	return ManaServiceUtils.clonePath(DEFAULT_DATA_PATH)
end

function ManaServiceUtils.serializeStateForData(stateRaw: any): { [string]: any }
	local state = if typeof(stateRaw) == "table"
		then ManaServiceUtils.sanitizeState(stateRaw, ManaServiceUtils.createDefaultState())
		else ManaServiceUtils.createDefaultState()

	return {
		mana = state.mana,
		maxMana = state.maxMana,
		regenPerSecond = state.regenPerSecond,
		updatedAt = os.time(),
	}
end

function ManaServiceUtils.createStateFromData(
	persistedRaw: any,
	fallbackRaw: ManaServiceState?,
	isLoadedRaw: any
): ManaServiceState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else ManaServiceUtils.createDefaultState()

	if typeof(persistedRaw) == "number" and persistedRaw == persistedRaw then
		return ManaServiceUtils.createState(
			persistedRaw,
			fallback.maxMana,
			fallback.regenPerSecond,
			isLoadedRaw,
			fallback
		)
	end

	if typeof(persistedRaw) ~= "table" then
		return ManaServiceUtils.createState(
			fallback.mana,
			fallback.maxMana,
			fallback.regenPerSecond,
			isLoadedRaw,
			fallback
		)
	end

	local source = persistedRaw :: { [string]: any }
	local manaRaw = source.mana or source.current
	local maxManaRaw = source.maxMana or source.max or source.maximum
	local regenRaw = source.regenPerSecond or source.manaRegen or source.regen or source.recovery
	return ManaServiceUtils.createState(manaRaw, maxManaRaw, regenRaw, isLoadedRaw, fallback)
end

return ManaServiceUtils
