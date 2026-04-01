--!strict
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataTemplate = require(ReplicatedStorage.Shared.Modules.Core.DataTemplate)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local PlayerDataServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceUtils)

type InventoryState = InventoryServiceUtils.InventoryState

type PlayerDataServiceServerObject = {
	getValue: (self: PlayerDataServiceServerObject, player: Player, pathRaw: any, fallback: any) -> any,
	getLoadState: (self: PlayerDataServiceServerObject, player: Player) -> string,
	getProfile: (self: PlayerDataServiceServerObject, player: Player) -> any,
	isLoaded: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
	requestSync: (self: PlayerDataServiceServerObject, player: Player) -> (),
	waitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	setValue: (
		self: PlayerDataServiceServerObject,
		player: Player,
		pathRaw: any,
		value: any,
		replicateToClientRaw: any
	) -> boolean,
}

export type LoadResult = {
	success: boolean,
	inventoryData: any,
	source: string,
	reason: string,
}

type InventoryProfileConfig = {
	dataPath: { string }?,
	defaultInventoryData: { [string]: any }?,
	primaryTimeoutSeconds: number?,
	fallbackTimeoutSeconds: number?,
}

type InventoryProfile = typeof(setmetatable(
	{} :: {
		playerDataService: PlayerDataServiceServerObject?,
		dataPath: { string },
		defaultInventoryData: { [string]: any },
		primaryTimeoutSeconds: number,
		fallbackTimeoutSeconds: number,
		fallbackDataStore: any,
	},
	{} :: { __index: any }
))

local InventoryProfile = {}
InventoryProfile.__index = InventoryProfile

local function sanitizeTimeout(timeoutRaw: any, fallback: number): number
	if typeof(timeoutRaw) ~= "number" or timeoutRaw ~= timeoutRaw then
		return fallback
	end
	return math.max(0, timeoutRaw)
end

local function runProtectedWithTimeout(timeoutSeconds: number, callback: () -> (any, any?)): (string, boolean, any, any)
	local bindable = Instance.new("BindableEvent")
	local settled = false

	local function settle(status: string, success: boolean, result: any, extra: any)
		if settled then
			return
		end
		settled = true
		bindable:Fire(status, success, result, extra)
	end

	task.spawn(function()
		local success, result, extra = pcall(callback)
		settle("completed", success, result, extra)
	end)

	task.delay(math.max(0, timeoutSeconds), function()
		settle("timed_out", false, nil, nil)
	end)

	local status, success, result, extra = bindable.Event:Wait()
	bindable:Destroy()
	return status, success, result, extra
end

local function resolveDefaultInventoryDataTemplate(): { [string]: any }
	local templateRoot = if typeof(DataTemplate) == "table" then DataTemplate else {}
	local playerDataTemplate = if typeof((templateRoot :: any).playerData) == "table"
		then (templateRoot :: any).playerData
		else {}
	local inventoryTemplate = PlayerDataServiceUtils.getValueAtPath(
		playerDataTemplate,
		InventoryServiceUtils.getDefaultDataPath(),
		nil
	)
	if typeof(inventoryTemplate) == "table" then
		return PlayerDataServiceUtils.cloneDeep(inventoryTemplate)
	end

	return InventoryServiceUtils.serializeStateForData(
		InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
	)
end

local function validatePersistedInventoryData(inventoryRaw: any): (boolean, string)
	if inventoryRaw == nil then
		return true, "inventory_missing"
	end
	if typeof(inventoryRaw) ~= "table" then
		return false, "inventory_not_table"
	end

	local inventory = inventoryRaw :: { [string]: any }
	local capacity = inventory.capacity
	if capacity ~= nil and (typeof(capacity) ~= "number" or capacity ~= capacity) then
		return false, "capacity_not_number"
	end

	local selectedSlot = inventory.selectedSlot
	if selectedSlot ~= nil and (typeof(selectedSlot) ~= "number" or selectedSlot ~= selectedSlot) then
		return false, "selected_slot_not_number"
	end

	local slots = inventory.slots
	if slots == nil then
		slots = inventory.items
	end
	if slots ~= nil and typeof(slots) ~= "table" then
		return false, "slots_not_table"
	end

	return true, "inventory_valid"
end

function InventoryProfile.new(
	playerDataService: PlayerDataServiceServerObject?,
	configRaw: InventoryProfileConfig?
): InventoryProfile
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local dataPath = InventoryServiceUtils.getDefaultDataPath()
	if typeof(config.dataPath) == "table" then
		dataPath = InventoryServiceUtils.clonePath(config.dataPath)
	end

	local getDataStoreSuccess, fallbackDataStore = pcall(function()
		return DataStoreService:GetDataStore(PlayerDataServiceUtils.DEFAULT_PROFILE_STORE_NAME)
	end)

	local self = setmetatable({
		playerDataService = playerDataService,
		dataPath = dataPath,
		defaultInventoryData = if typeof(config.defaultInventoryData) == "table"
			then PlayerDataServiceUtils.cloneDeep(config.defaultInventoryData)
			else resolveDefaultInventoryDataTemplate(),
		primaryTimeoutSeconds = sanitizeTimeout(config.primaryTimeoutSeconds, 3),
		fallbackTimeoutSeconds = sanitizeTimeout(config.fallbackTimeoutSeconds, 4),
		fallbackDataStore = if getDataStoreSuccess then fallbackDataStore else nil,
	}, InventoryProfile)

	return self
end

function InventoryProfile.cloneDefaultInventoryData(self: InventoryProfile): { [string]: any }
	return PlayerDataServiceUtils.cloneDeep(self.defaultInventoryData)
end

function InventoryProfile.hasAuthoritativeProfile(self: InventoryProfile, player: Player): boolean
	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return false
	end

	local success, profile = pcall(function()
		return playerDataService:getProfile(player)
	end)
	return success and profile ~= nil
end

function InventoryProfile.loadFromPrimary(
	self: InventoryProfile,
	player: Player,
	timeoutSecondsRaw: any
): LoadResult
	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return {
			success = false,
			inventoryData = nil,
			source = "player-data-service",
			reason = "player_data_service_missing",
		}
	end

	local timeoutSeconds = sanitizeTimeout(timeoutSecondsRaw, self.primaryTimeoutSeconds)
	local requestSyncSuccess = pcall(function()
		playerDataService:requestSync(player)
	end)
	if not requestSyncSuccess then
		return {
			success = false,
			inventoryData = nil,
			source = "player-data-service",
			reason = "request_sync_error",
		}
	end

	local completionStatus, callSuccess, resultKind, resultDetail =
		runProtectedWithTimeout(timeoutSeconds, function()
			local hasActiveProfile = self:hasAuthoritativeProfile(player)
			if hasActiveProfile and playerDataService:isLoaded(player) then
				return "loaded", playerDataService:getValue(player, self.dataPath, nil)
			end

			local waitedData = playerDataService:waitForData(player, timeoutSeconds)
			if waitedData ~= nil and typeof(waitedData) ~= "table" then
				return "not_loaded", "player_data_not_table"
			end

			local loadState = playerDataService:getLoadState(player)
			hasActiveProfile = self:hasAuthoritativeProfile(player)
			if waitedData == nil and loadState ~= "Loaded" then
				return "not_loaded", loadState
			end
			if loadState == "Loaded" and not hasActiveProfile then
				return "not_loaded", "loaded_without_profile"
			end

			return "loaded", playerDataService:getValue(player, self.dataPath, nil)
		end)

	if completionStatus == "timed_out" then
		return {
			success = false,
			inventoryData = nil,
			source = "player-data-service",
			reason = "timeout",
		}
	end
	if not callSuccess then
		return {
			success = false,
			inventoryData = nil,
			source = "player-data-service",
			reason = "error:" .. tostring(resultKind),
		}
	end
	if resultKind ~= "loaded" then
		return {
			success = false,
			inventoryData = nil,
			source = "player-data-service",
			reason = "dependency_" .. tostring(resultDetail),
		}
	end

	local isValid, validationReason = validatePersistedInventoryData(resultDetail)
	if not isValid then
		return {
			success = false,
			inventoryData = nil,
			source = "player-data-service",
			reason = validationReason,
		}
	end

	return {
		success = true,
		inventoryData = if resultDetail ~= nil then PlayerDataServiceUtils.cloneDeep(resultDetail) else self:cloneDefaultInventoryData(),
		source = "player-data-service",
		reason = validationReason,
	}
end

function InventoryProfile.loadFromFallback(
	self: InventoryProfile,
	player: Player,
	timeoutSecondsRaw: any
): LoadResult
	local profileKey = PlayerDataServiceUtils.getProfileKey(player)
	if profileKey == nil then
		return {
			success = false,
			inventoryData = nil,
			source = "default",
			reason = "profile_key_invalid",
		}
	end

	if self.fallbackDataStore == nil then
		return {
			success = false,
			inventoryData = nil,
			source = "default",
			reason = "datastore_unavailable",
		}
	end

	local timeoutSeconds = sanitizeTimeout(timeoutSecondsRaw, self.fallbackTimeoutSeconds)
	local completionStatus, callSuccess, rawProfileData =
		runProtectedWithTimeout(timeoutSeconds, function()
			return self.fallbackDataStore:GetAsync(profileKey)
		end)

	if completionStatus == "timed_out" then
		return {
			success = false,
			inventoryData = nil,
			source = "default",
			reason = "timeout",
		}
	end
	if not callSuccess then
		return {
			success = false,
			inventoryData = nil,
			source = "default",
			reason = "error:" .. tostring(rawProfileData),
		}
	end
	if rawProfileData == nil then
		return {
			success = true,
			inventoryData = self:cloneDefaultInventoryData(),
			source = "default",
			reason = "profile_missing",
		}
	end
	if typeof(rawProfileData) ~= "table" then
		return {
			success = false,
			inventoryData = nil,
			source = "default",
			reason = "raw_profile_not_table",
		}
	end

	local rawProfileTable = rawProfileData :: { [string]: any }
	local persistedDataRoot = rawProfileData
	if rawProfileTable.Data ~= nil then
		if typeof(rawProfileTable.Data) ~= "table" then
			return {
				success = false,
				inventoryData = nil,
				source = "default",
				reason = "profile_data_not_table",
			}
		end
		persistedDataRoot = rawProfileTable.Data
	end
	if typeof(persistedDataRoot) ~= "table" then
		return {
			success = false,
			inventoryData = nil,
			source = "default",
			reason = "profile_data_not_table",
		}
	end

	local rawInventory = PlayerDataServiceUtils.getValueAtPath(persistedDataRoot, self.dataPath, nil)
	local isValid, validationReason = validatePersistedInventoryData(rawInventory)
	if not isValid then
		return {
			success = false,
			inventoryData = nil,
			source = "default",
			reason = validationReason,
		}
	end

	return {
		success = true,
		inventoryData = if rawInventory ~= nil then PlayerDataServiceUtils.cloneDeep(rawInventory) else self:cloneDefaultInventoryData(),
		source = if rawInventory ~= nil then "datastore" else "default",
		reason = if rawInventory ~= nil then "datastore_inventory" else "inventory_missing",
	}
end

function InventoryProfile.resolvePersistedInventory(
	self: InventoryProfile,
	player: Player,
	primaryTimeoutSecondsRaw: any,
	fallbackTimeoutSecondsRaw: any
): LoadResult
	local primaryResult = self:loadFromPrimary(player, primaryTimeoutSecondsRaw)
	if primaryResult.success then
		return primaryResult
	end

	local fallbackResult = self:loadFromFallback(player, fallbackTimeoutSecondsRaw)
	if fallbackResult.success then
		return fallbackResult
	end

	return {
		success = false,
		inventoryData = self:cloneDefaultInventoryData(),
		source = fallbackResult.source,
		reason = fallbackResult.reason,
	}
end

function InventoryProfile.saveState(
	self: InventoryProfile,
	player: Player,
	stateRaw: any
): boolean
	if typeof(stateRaw) ~= "table" then
		return false
	end
	if not InventoryServiceUtils.isLoadedState((stateRaw :: any).loadState) then
		return false
	end

	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return false
	end
	if not self:hasAuthoritativeProfile(player) then
		return false
	end

	local serializedState = InventoryServiceUtils.serializeStateForData(stateRaw)
	local success, didSet = pcall(function()
		return playerDataService:setValue(player, self.dataPath, serializedState, false)
	end)
	if not success then
		return false
	end
	return didSet == true
end

return InventoryProfile
