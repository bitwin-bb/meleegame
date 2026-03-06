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

function PlayerDataServiceUtils.cloneDeep(value: any): any
	return cloneDeepInternal(value, {})
end

function PlayerDataServiceUtils.clonePath(pathRaw: any, fallbackPathRaw: any): { DataPathSegment }
	return clonePath(pathRaw, if fallbackPathRaw ~= nil then fallbackPathRaw else DEFAULT_HP_DATA_PATH)
end

function PlayerDataServiceUtils.getDefaultHpDataPath(): { DataPathSegment }
	return clonePath(DEFAULT_HP_DATA_PATH, DEFAULT_HP_DATA_PATH)
end

function PlayerDataServiceUtils.getDefaultCoinsDataPath(): { DataPathSegment }
	return clonePath(DEFAULT_COINS_DATA_PATH, DEFAULT_COINS_DATA_PATH)
end

function PlayerDataServiceUtils.createDefaultData(templateRaw: any): PlayerData
	local template = if typeof(templateRaw) == "table" then templateRaw else {}
	return cloneDeepInternal(template, {})
end

function PlayerDataServiceUtils.reconcileData(dataRaw: any, templateRaw: any): PlayerData
	local data = if typeof(dataRaw) == "table" then dataRaw else {}
	local template = if typeof(templateRaw) == "table" then templateRaw else {}
	reconcileDataInternal(data, template)
	return data
end

function PlayerDataServiceUtils.sanitizeLoadState(loadStateRaw: any, fallback: LoadState?): LoadState
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

function PlayerDataServiceUtils.isLoadedState(loadStateRaw: any): boolean
	return PlayerDataServiceUtils.sanitizeLoadState(loadStateRaw) == LOAD_STATE_LOADED
end

function PlayerDataServiceUtils.createDefaultState(): PlayerDataServiceState
	return {
		data = {},
		loadState = LOAD_STATE_UNLOADED,
		updatedAt = os.clock(),
	}
end

function PlayerDataServiceUtils.createState(
	dataRaw: any,
	loadStateRaw: any,
	fallbackState: PlayerDataServiceState?
): PlayerDataServiceState
	local fallback = if fallbackState then fallbackState else PlayerDataServiceUtils.createDefaultState()
	local sourceData = if typeof(dataRaw) == "table" then dataRaw else fallback.data
	return {
		data = cloneDeepInternal(sourceData, {}),
		loadState = PlayerDataServiceUtils.sanitizeLoadState(loadStateRaw, fallback.loadState),
		updatedAt = os.clock(),
	}
end

function PlayerDataServiceUtils.cloneState(state: PlayerDataServiceState): PlayerDataServiceState
	return {
		data = cloneDeepInternal(state.data, {}),
		loadState = state.loadState,
		updatedAt = state.updatedAt,
	}
end

function PlayerDataServiceUtils.normalizePath(pathRaw: any): { DataPathSegment }?
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

function PlayerDataServiceUtils.getValueAtPath(dataRaw: any, pathRaw: any, fallback: any): any
	local path = PlayerDataServiceUtils.normalizePath(pathRaw)
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

function PlayerDataServiceUtils.setValueAtPath(dataRaw: any, pathRaw: any, value: any): boolean
	if typeof(dataRaw) ~= "table" then
		return false
	end

	local path = PlayerDataServiceUtils.normalizePath(pathRaw)
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

function PlayerDataServiceUtils.removeValueAtPath(dataRaw: any, pathRaw: any): boolean
	if typeof(dataRaw) ~= "table" then
		return false
	end

	local path = PlayerDataServiceUtils.normalizePath(pathRaw)
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

function PlayerDataServiceUtils.incrementValueAtPath(
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
	local currentRaw = PlayerDataServiceUtils.getValueAtPath(dataRaw, pathRaw, fallbackValue)
	local current = if typeof(currentRaw) == "number" and currentRaw == currentRaw then currentRaw else fallbackValue
	local nextValue = current + amount

	if not PlayerDataServiceUtils.setValueAtPath(dataRaw, pathRaw, nextValue) then
		return nil
	end

	return nextValue
end

function PlayerDataServiceUtils.mergeData(targetRaw: any, incomingRaw: any): boolean
	if typeof(targetRaw) ~= "table" then
		return false
	end
	if typeof(incomingRaw) ~= "table" then
		return false
	end

	mergeDataInternal(targetRaw, incomingRaw)
	return true
end

function PlayerDataServiceUtils.getProfileKey(playerOrUserIdRaw: any): string?
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

return PlayerDataServiceUtils
