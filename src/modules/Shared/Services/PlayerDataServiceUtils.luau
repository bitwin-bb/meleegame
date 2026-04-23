--!strict
local PlayerDataServiceUtils = {}

export type LoadState = "Unloaded" | "Loading" | "Loaded" | "Failed"
export type DataPathSegment = string | number
export type DataPath = string | { DataPathSegment }
export type PlayerData = { [any]: any }
export type PlayerDataServiceState = {
	data: PlayerData,
	loadState: LoadState,
	updatedAt: number,
	isLoading: boolean,
	hasResolvedInitialLoad: boolean,
	loadToken: number,
	lastFailureReason: string?,
	loadElapsedSeconds: number,
}

local DEFAULT_PROFILE_STORE_NAME = "PlayerData"
local PROFILE_KEY_PREFIX = "Player_"
local DEFAULT_HP_DATA_PATH = { "hp" }
local DEFAULT_COINS_DATA_PATH = { "coins" }

local LOAD_STATE_UNLOADED: LoadState = "Unloaded"
local LOAD_STATE_LOADING: LoadState = "Loading"
local LOAD_STATE_LOADED: LoadState = "Loaded"
local LOAD_STATE_FAILED: LoadState = "Failed"

PlayerDataServiceUtils.DEFAULT_PROFILE_STORE_NAME = DEFAULT_PROFILE_STORE_NAME
PlayerDataServiceUtils.PROFILE_KEY_PREFIX = PROFILE_KEY_PREFIX
PlayerDataServiceUtils.DEFAULT_HP_DATA_PATH = DEFAULT_HP_DATA_PATH
PlayerDataServiceUtils.DEFAULT_COINS_DATA_PATH = DEFAULT_COINS_DATA_PATH
PlayerDataServiceUtils.LOAD_STATE_UNLOADED = LOAD_STATE_UNLOADED
PlayerDataServiceUtils.LOAD_STATE_LOADING = LOAD_STATE_LOADING
PlayerDataServiceUtils.LOAD_STATE_LOADED = LOAD_STATE_LOADED
PlayerDataServiceUtils.LOAD_STATE_FAILED = LOAD_STATE_FAILED

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") or ""
end

local function sanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function sanitizeWholeNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.max(0, math.floor(valueRaw))
end

local function sanitizeNonNegativeNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.max(0, valueRaw)
end

local function sanitizeOptionalString(valueRaw: any): string?
	if typeof(valueRaw) ~= "string" then
		return nil
	end
	local trimmedValue = trim(valueRaw)
	if trimmedValue == "" then
		return nil
	end
	return trimmedValue
end

local function clonePath(pathRaw: any, fallbackPathRaw: any): { DataPathSegment }
	local source = if typeof(pathRaw) == "table" then pathRaw else fallbackPathRaw
	local output = {}
	for _, segmentRaw in source do
		local segmentType = typeof(segmentRaw)
		if segmentType == "string" then
			local segment = trim(segmentRaw :: string)
			if segment ~= "" then
				table.insert(output, segment)
			end
		elseif segmentType == "number" then
			local numeric = segmentRaw :: number
			if numeric == numeric then
				table.insert(output, math.floor(numeric))
			end
		end
	end

	if #output == 0 then
		return clonePath(DEFAULT_HP_DATA_PATH, DEFAULT_HP_DATA_PATH)
	end
	return output
end

local function cloneDeepInternal(value: any, seen: { [any]: any }): any
	if typeof(value) ~= "table" then
		return value
	end

	local existingClone = seen[value]
	if existingClone ~= nil then
		return existingClone
	end

	local cloned = {}
	seen[value] = cloned
	for key, nestedValue in value do
		local clonedKey = cloneDeepInternal(key, seen)
		cloned[clonedKey] = cloneDeepInternal(nestedValue, seen)
	end

	return cloned
end

local function reconcileDataInternal(target: { [any]: any }, template: { [any]: any })
	for key, templateValue in template do
		local currentValue = target[key]
		if currentValue == nil then
			target[key] = cloneDeepInternal(templateValue, {})
		elseif typeof(currentValue) == "table" and typeof(templateValue) == "table" then
			reconcileDataInternal(currentValue, templateValue)
		end
	end
end

local function mergeDataInternal(target: { [any]: any }, incoming: { [any]: any })
	for key, incomingValue in incoming do
		if typeof(incomingValue) == "table" then
			local currentValue = target[key]
			if typeof(currentValue) == "table" then
				mergeDataInternal(currentValue, incomingValue)
			else
				target[key] = cloneDeepInternal(incomingValue, {})
			end
		else
			target[key] = incomingValue
		end
	end
end

local function normalizeStringPath(path: string): { DataPathSegment }?
	local normalizedPath = {}
	local trimmedPath = trim(path)
	if trimmedPath == "" then
		return nil
	end

	for token in string.gmatch(trimmedPath, "[^%.]+") do
		local segment = trim(token)
		if segment == "" then
			return nil
		end

		local asIntegerString = string.match(segment, "^%-?%d+$")
		local asNumber = if asIntegerString then tonumber(asIntegerString) else nil
		if asNumber ~= nil then
			table.insert(normalizedPath, asNumber)
		else
			table.insert(normalizedPath, segment)
		end
	end

	if #normalizedPath == 0 then
		return nil
	end

	return normalizedPath
end

function PlayerDataServiceUtils.CloneDeep(value: any): any
	return cloneDeepInternal(value, {})
end

function PlayerDataServiceUtils.ClonePath(pathRaw: any, fallbackPathRaw: any): { DataPathSegment }
	return clonePath(pathRaw, if fallbackPathRaw ~= nil then fallbackPathRaw else DEFAULT_HP_DATA_PATH)
end

function PlayerDataServiceUtils.GetDefaultHpDataPath(): { DataPathSegment }
	return clonePath(DEFAULT_HP_DATA_PATH, DEFAULT_HP_DATA_PATH)
end

function PlayerDataServiceUtils.GetDefaultCoinsDataPath(): { DataPathSegment }
	return clonePath(DEFAULT_COINS_DATA_PATH, DEFAULT_COINS_DATA_PATH)
end

function PlayerDataServiceUtils.CreateDefaultData(templateRaw: any): PlayerData
	local template = if typeof(templateRaw) == "table" then templateRaw else {}
	return cloneDeepInternal(template, {})
end

function PlayerDataServiceUtils.ReconcileData(dataRaw: any, templateRaw: any): PlayerData
	local data = if typeof(dataRaw) == "table" then dataRaw else {}
	local template = if typeof(templateRaw) == "table" then templateRaw else {}
	reconcileDataInternal(data, template)
	return data
end

function PlayerDataServiceUtils.SanitizeLoadState(loadStateRaw: any, fallback: LoadState?): LoadState
	if loadStateRaw == LOAD_STATE_UNLOADED then
		return LOAD_STATE_UNLOADED
	end
	if loadStateRaw == LOAD_STATE_LOADING then
		return LOAD_STATE_LOADING
	end
	if loadStateRaw == LOAD_STATE_LOADED then
		return LOAD_STATE_LOADED
	end
	if loadStateRaw == LOAD_STATE_FAILED then
		return LOAD_STATE_FAILED
	end
	return fallback or LOAD_STATE_UNLOADED
end

function PlayerDataServiceUtils.IsLoadedState(loadStateRaw: any): boolean
	return PlayerDataServiceUtils.SanitizeLoadState(loadStateRaw) == LOAD_STATE_LOADED
end

function PlayerDataServiceUtils.IsTerminalLoadState(loadStateRaw: any): boolean
	local loadState = PlayerDataServiceUtils.SanitizeLoadState(loadStateRaw)
	return loadState == LOAD_STATE_LOADED or loadState == LOAD_STATE_FAILED
end

function PlayerDataServiceUtils.HasResolvedState(stateRaw: any): boolean
	if typeof(stateRaw) ~= "table" then
		return false
	end

	local state = stateRaw :: { [string]: any }
	if sanitizeBoolean(state.hasResolvedInitialLoad, false) then
		return true
	end
	return PlayerDataServiceUtils.IsTerminalLoadState(state.loadState)
end

function PlayerDataServiceUtils.CreateDefaultState(): PlayerDataServiceState
	return {
		data = {},
		loadState = LOAD_STATE_UNLOADED,
		updatedAt = os.clock(),
		isLoading = false,
		hasResolvedInitialLoad = false,
		loadToken = 0,
		lastFailureReason = nil,
		loadElapsedSeconds = 0,
	}
end

function PlayerDataServiceUtils.CreateState(
	dataRaw: any,
	loadStateRaw: any,
	fallbackState: PlayerDataServiceState?,
	metadataRaw: any?
): PlayerDataServiceState
	local fallback = if fallbackState then fallbackState else PlayerDataServiceUtils.CreateDefaultState()
	local sourceData = if typeof(dataRaw) == "table" then dataRaw else fallback.data
	local metadata = if typeof(metadataRaw) == "table" then metadataRaw :: { [string]: any } else {}
	local loadState = PlayerDataServiceUtils.SanitizeLoadState(loadStateRaw, fallback.loadState)
	local hasResolvedInitialLoad = if metadata.hasResolvedInitialLoad ~= nil
		then sanitizeBoolean(metadata.hasResolvedInitialLoad, PlayerDataServiceUtils.IsTerminalLoadState(loadState))
		else PlayerDataServiceUtils.IsTerminalLoadState(loadState)
	local isLoading = if metadata.isLoading ~= nil
		then sanitizeBoolean(metadata.isLoading, loadState == LOAD_STATE_LOADING)
		else loadState == LOAD_STATE_LOADING
	local lastFailureReason = if loadState == LOAD_STATE_FAILED
		then sanitizeOptionalString(metadata.lastFailureReason) or fallback.lastFailureReason
		else nil
	return {
		data = cloneDeepInternal(sourceData, {}),
		loadState = loadState,
		updatedAt = os.clock(),
		isLoading = isLoading,
		hasResolvedInitialLoad = hasResolvedInitialLoad,
		loadToken = sanitizeWholeNumber(metadata.loadToken, fallback.loadToken),
		lastFailureReason = lastFailureReason,
		loadElapsedSeconds = if metadata.loadElapsedSeconds ~= nil
			then sanitizeNonNegativeNumber(metadata.loadElapsedSeconds, fallback.loadElapsedSeconds)
			else fallback.loadElapsedSeconds,
	}
end

function PlayerDataServiceUtils.CloneState(state: PlayerDataServiceState): PlayerDataServiceState
	return {
		data = cloneDeepInternal(state.data, {}),
		loadState = state.loadState,
		updatedAt = state.updatedAt,
		isLoading = state.isLoading,
		hasResolvedInitialLoad = state.hasResolvedInitialLoad,
		loadToken = state.loadToken,
		lastFailureReason = state.lastFailureReason,
		loadElapsedSeconds = state.loadElapsedSeconds,
	}
end

function PlayerDataServiceUtils.NormalizePath(pathRaw: any): { DataPathSegment }?
	if typeof(pathRaw) == "string" then
		return normalizeStringPath(pathRaw)
	end

	if typeof(pathRaw) ~= "table" then
		return nil
	end

	local normalizedPath = {}
	for _, segment in pathRaw do
		local segmentType = typeof(segment)
		if segmentType == "string" then
			local trimmed = trim(segment :: string)
			if trimmed == "" then
				return nil
			end
			table.insert(normalizedPath, trimmed)
		elseif segmentType == "number" then
			local numeric = segment :: number
			if numeric ~= numeric then
				return nil
			end
			table.insert(normalizedPath, math.floor(numeric))
		else
			return nil
		end
	end

	if #normalizedPath == 0 then
		return nil
	end

	return normalizedPath
end

function PlayerDataServiceUtils.GetValueAtPath(dataRaw: any, pathRaw: any, fallback: any): any
	local path = PlayerDataServiceUtils.NormalizePath(pathRaw)
	if path == nil then
		return fallback
	end
	if typeof(dataRaw) ~= "table" then
		return fallback
	end

	local cursor: any = dataRaw
	for _, segment in path do
		if typeof(cursor) ~= "table" then
			return fallback
		end
		local nextValue = (cursor :: { [any]: any })[segment]
		if nextValue == nil then
			return fallback
		end
		cursor = nextValue
	end

	return cursor
end

function PlayerDataServiceUtils.SetValueAtPath(dataRaw: any, pathRaw: any, value: any): boolean
	if typeof(dataRaw) ~= "table" then
		return false
	end

	local path = PlayerDataServiceUtils.NormalizePath(pathRaw)
	if path == nil then
		return false
	end

	local cursor = dataRaw :: { [any]: any }
	for index = 1, #path - 1 do
		local segment = path[index]
		local nextValue = cursor[segment]
		if typeof(nextValue) ~= "table" then
			nextValue = {}
			cursor[segment] = nextValue
		end
		cursor = nextValue
	end

	cursor[path[#path]] = value
	return true
end

function PlayerDataServiceUtils.RemoveValueAtPath(dataRaw: any, pathRaw: any): boolean
	if typeof(dataRaw) ~= "table" then
		return false
	end

	local path = PlayerDataServiceUtils.NormalizePath(pathRaw)
	if path == nil then
		return false
	end

	local cursor = dataRaw :: { [any]: any }
	for index = 1, #path - 1 do
		local segment = path[index]
		local nextValue = cursor[segment]
		if typeof(nextValue) ~= "table" then
			return false
		end
		cursor = nextValue
	end

	local leafSegment = path[#path]
	if cursor[leafSegment] == nil then
		return false
	end

	cursor[leafSegment] = nil
	return true
end

function PlayerDataServiceUtils.IncrementValueAtPath(
	dataRaw: any,
	pathRaw: any,
	amountRaw: any,
	fallbackValueRaw: any
): number?
	if typeof(dataRaw) ~= "table" then
		return nil
	end

	local amount = if typeof(amountRaw) == "number" and amountRaw == amountRaw then amountRaw else 0
	local fallbackValue = if typeof(fallbackValueRaw) == "number" and fallbackValueRaw == fallbackValueRaw
		then fallbackValueRaw
		else 0
	local currentRaw = PlayerDataServiceUtils.GetValueAtPath(dataRaw, pathRaw, fallbackValue)
	local current = if typeof(currentRaw) == "number" and currentRaw == currentRaw then currentRaw else fallbackValue
	local nextValue = current + amount

	if not PlayerDataServiceUtils.SetValueAtPath(dataRaw, pathRaw, nextValue) then
		return nil
	end

	return nextValue
end

function PlayerDataServiceUtils.MergeData(targetRaw: any, incomingRaw: any): boolean
	if typeof(targetRaw) ~= "table" then
		return false
	end
	if typeof(incomingRaw) ~= "table" then
		return false
	end

	mergeDataInternal(targetRaw, incomingRaw)
	return true
end

function PlayerDataServiceUtils.GetProfileKey(playerOrUserIdRaw: any): string?
	local userId: number?
	if typeof(playerOrUserIdRaw) == "number" then
		userId = playerOrUserIdRaw
	elseif typeof(playerOrUserIdRaw) == "Instance" and (playerOrUserIdRaw :: Instance):IsA("Player") then
		userId = (playerOrUserIdRaw :: Player).UserId
	end

	if userId == nil then
		return nil
	end
	if userId ~= userId then
		return nil
	end
	if userId <= 0 then
		return nil
	end

	return PROFILE_KEY_PREFIX .. tostring(math.floor(userId))
end

PlayerDataServiceUtils.cloneDeep = PlayerDataServiceUtils.CloneDeep
PlayerDataServiceUtils.clonePath = PlayerDataServiceUtils.ClonePath
PlayerDataServiceUtils.getDefaultHpDataPath = PlayerDataServiceUtils.GetDefaultHpDataPath
PlayerDataServiceUtils.getDefaultCoinsDataPath = PlayerDataServiceUtils.GetDefaultCoinsDataPath
PlayerDataServiceUtils.createDefaultData = PlayerDataServiceUtils.CreateDefaultData
PlayerDataServiceUtils.reconcileData = PlayerDataServiceUtils.ReconcileData
PlayerDataServiceUtils.sanitizeLoadState = PlayerDataServiceUtils.SanitizeLoadState
PlayerDataServiceUtils.isLoadedState = PlayerDataServiceUtils.IsLoadedState
PlayerDataServiceUtils.isTerminalLoadState = PlayerDataServiceUtils.IsTerminalLoadState
PlayerDataServiceUtils.hasResolvedState = PlayerDataServiceUtils.HasResolvedState
PlayerDataServiceUtils.createDefaultState = PlayerDataServiceUtils.CreateDefaultState
PlayerDataServiceUtils.createState = PlayerDataServiceUtils.CreateState
PlayerDataServiceUtils.cloneState = PlayerDataServiceUtils.CloneState
PlayerDataServiceUtils.normalizePath = PlayerDataServiceUtils.NormalizePath
PlayerDataServiceUtils.getValueAtPath = PlayerDataServiceUtils.GetValueAtPath
PlayerDataServiceUtils.setValueAtPath = PlayerDataServiceUtils.SetValueAtPath
PlayerDataServiceUtils.removeValueAtPath = PlayerDataServiceUtils.RemoveValueAtPath
PlayerDataServiceUtils.incrementValueAtPath = PlayerDataServiceUtils.IncrementValueAtPath
PlayerDataServiceUtils.mergeData = PlayerDataServiceUtils.MergeData
PlayerDataServiceUtils.getProfileKey = PlayerDataServiceUtils.GetProfileKey

return PlayerDataServiceUtils
