--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryServiceUtils)
local CraftingTree = require(script.Parent.CraftingTree)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local CraftingServiceUtils = {}

export type ItemAmount = {
	itemId: string,
	amount: number,
	itemIds: { string }?,
}

export type UnlockConditions = {
	requiredItems: { string }?,
	requiredFlags: { string }?,
}

export type RecipeDefinition = {
	id: string,
	displayName: string,
	category: string,
	ingredients: { ItemAmount },
	results: { ItemAmount },
	requiredStations: { string },
	requiredBiome: string?,
	unlockConditions: UnlockConditions?,
	sortOrder: number,
	isHidden: boolean,
	orderIndex: number,
}

export type StationDefinition = {
	id: string,
	displayName: string,
	tag: string,
}

export type RecipeGroup = {
	id: string,
	displayName: string,
	sortOrder: number,
	recipeIds: { string },
}

export type RecipeRegistry = {
	version: number,
	recipes: { RecipeDefinition },
	recipeIdsOrdered: { string },
	recipesById: { [string]: RecipeDefinition },
	recipeIdsByStation: { [string]: { string } },
	noStationRecipeIds: { string },
	recipeIdsByCategory: { [string]: { string } },
	recipeIdsByUnlockItem: { [string]: { string } },
	recipeIdsByUnlockFlag: { [string]: { string } },
	unlockRelevantItemIds: { string },
	unlockRelevantItemIdSet: { [string]: boolean },
	stationDefinitions: { [string]: StationDefinition },
	stationTagById: { [string]: string },
	groups: { [string]: RecipeGroup },
	groupIdsOrdered: { string },
	groupIdByRecipeId: { [string]: string },
	defaultKnownRecipeIds: { [string]: boolean },
}

export type CraftingServiceConfig = {
	stationScanRadius: number,
	stationValidationRadius: number,
	stationScanRateHz: number,
	biomeScanRateHz: number,
	clientRequestThrottleSeconds: number,
	serverRequestRateLimitSeconds: number,
	bulkCraftIntervalSeconds: number,
	inventoryWatchIntervalSeconds: number,
	statePushIntervalSeconds: number,
	persistIntervalSeconds: number,
	dataLoadTimeoutSeconds: number,
	maxCraftQuantityPerRequest: number,
	dataPath: { string },
	stationTagPrefix: string,
	stationTagById: { [string]: string },
}

export type CraftingPersistentState = {
	knownRecipeIds: { [string]: boolean },
	discoveredItemIds: { [string]: boolean },
	progressionFlags: { [string]: boolean },
	updatedAt: number,
}

export type CraftingServiceStateSnapshot = {
	knownRecipeIds: { [string]: boolean },
	discoveredItemIds: { [string]: boolean },
	progressionFlags: { [string]: boolean },
	updatedAt: number,
}

export type RecipePreviewIngredient = {
	itemId: string,
	required: number,
	available: number,
	isSufficient: boolean,
}

export type RecipePreviewResult = {
	itemId: string,
	amount: number,
}

export type RecipePreview = {
	recipeId: string,
	quantity: number,
	maxCraftableQuantity: number,
	canCraft: boolean,
	isKnown: boolean,
	ingredients: { RecipePreviewIngredient },
	results: { RecipePreviewResult },
	missingStations: { string },
	missingBiome: string?,
}

export type InventoryProvider = {
	IsReady: (self: InventoryProvider, player: Player) -> boolean,
	CountItem: (self: InventoryProvider, player: Player, itemId: string) -> number,
	HasItems: (self: InventoryProvider, player: Player, requirements: { ItemAmount }) -> boolean,
	ConsumeItems: (self: InventoryProvider, player: Player, requirements: { ItemAmount }) -> (boolean, { ItemAmount }, string?),
	GrantItems: (self: InventoryProvider, player: Player, grantItems: { ItemAmount }) -> (boolean, { ItemAmount }, string?),
	RestoreItems: (self: InventoryProvider, player: Player, restoreItems: { ItemAmount }) -> boolean,
	RevokeItems: (self: InventoryProvider, player: Player, revokeItems: { ItemAmount }) -> boolean,
}

export type CraftTransactionResult = {
	success: boolean,
	reason: string?,
	recipeId: string,
	quantity: number,
	consumed: { ItemAmount },
	granted: { ItemAmount },
}

export type ClientStationDetector = {
	start: (self: ClientStationDetector) -> (),
	stop: (self: ClientStationDetector) -> (),
	forceScan: (self: ClientStationDetector) -> (),
	getActiveStations: (self: ClientStationDetector) -> { [string]: boolean },
	destroy: (self: ClientStationDetector) -> (),
}

CraftingServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
CraftingServiceUtils.NETWORK_METHOD_REQUEST_CRAFT = "requestCraft"
CraftingServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
CraftingServiceUtils.CLIENT_METHOD_CRAFT_RESULT = "onCraftResult"

local DEFAULT_STATION_SCAN_RADIUS = 26
local DEFAULT_STATION_VALIDATION_RADIUS = 26
local DEFAULT_STATION_SCAN_RATE_HZ = 8
local DEFAULT_BIOME_SCAN_RATE_HZ = 6
local DEFAULT_CLIENT_REQUEST_THROTTLE_SECONDS = 0.12
local DEFAULT_SERVER_REQUEST_RATE_LIMIT_SECONDS = 0.08
local DEFAULT_BULK_CRAFT_INTERVAL_SECONDS = 0.2
local DEFAULT_INVENTORY_WATCH_INTERVAL_SECONDS = 0.2
local DEFAULT_STATE_PUSH_INTERVAL_SECONDS = 0.1
local DEFAULT_PERSIST_INTERVAL_SECONDS = 3
local DEFAULT_DATA_LOAD_TIMEOUT_SECONDS = 20
local DEFAULT_MAX_CRAFT_QUANTITY_PER_REQUEST = 99
local DEFAULT_DATA_PATH = { "crafting" }
local DEFAULT_STATION_TAG_PREFIX = "Station_"
local BIOME_TYPE_NORMAL = 1
local BIOME_TYPE_CORRUPTION = 2
local BIOME_ID_FOREST = 1
local BIOME_ID_JUNGLE = 4

local BIOME_TOKEN_ALIASES: { [string]: string } = {
	corrupt = "corruption",
	overworld = "forest",
}
local COIN_ITEM_ID_TO_KEY: { [string]: string } = {
	CopperCoin = "copper",
	SilverCoin = "silver",
	GoldCoin = "gold",
	PlatinumCoin = "platinum",
}
local COIN_ITEM_MAX_AMOUNT = 999
local COIN_KEY_TO_COPPER_VALUE: { [string]: number } = {
	copper = 1,
	silver = 100,
	gold = 10_000,
	platinum = 1_000_000,
}
local COIN_KEYS_ORDER_DESCENDING = { "platinum", "gold", "silver", "copper" }

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeString(valueRaw: any, fallback: string?): string?
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

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = math.floor(valueRaw)
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(trim(valueRaw))
		if parsed ~= nil and parsed == parsed then
			value = math.floor(parsed)
		end
	end
	return math.clamp(value, minimum, maximum)
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(trim(valueRaw))
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end
	return math.clamp(value, minimum, maximum)
end

local function cloneStringSet(setRaw: any): { [string]: boolean }
	local output: { [string]: boolean } = {}
	if typeof(setRaw) ~= "table" then
		return output
	end

	for key, value in setRaw do
		if typeof(key) == "number" and typeof(value) == "string" then
			output[value] = true
		elseif typeof(key) == "string" and value == true then
			output[key] = true
		end
	end

	return output
end

local function cloneStringArray(arrayRaw: any): { string }
	local output: { string } = {}
	if typeof(arrayRaw) ~= "table" then
		return output
	end
	for _, valueRaw in arrayRaw do
		local value = sanitizeString(valueRaw, nil)
		if value ~= nil then
			table.insert(output, value)
		end
	end
	return output
end

local function clonePath(pathRaw: any, fallback: { string }): { string }
	local source = if typeof(pathRaw) == "table" then pathRaw else fallback
	local output = {}
	for _, segmentRaw in source do
		local segment = sanitizeString(segmentRaw, nil)
		if segment ~= nil then
			table.insert(output, segment)
		end
	end
	if #output <= 0 then
		return Sift.Dictionary.copy(fallback)
	end
	return output
end

local function serializeStringSet(setMap: { [string]: boolean }): { string }
	local output = {}
	for key, enabled in setMap do
		if enabled == true then
			table.insert(output, key)
		end
	end
	table.sort(output)
	return output
end

local function stringSetEquals(lhs: { [string]: boolean }, rhs: { [string]: boolean }): boolean
	for key, lhsValue in lhs do
		if lhsValue ~= rhs[key] then
			return false
		end
	end
	for key, rhsValue in rhs do
		if rhsValue ~= lhs[key] then
			return false
		end
	end
	return true
end

local function stringArrayEquals(lhs: { string }, rhs: { string }): boolean
	if #lhs ~= #rhs then
		return false
	end
	for index = 1, #lhs do
		if lhs[index] ~= rhs[index] then
			return false
		end
	end
	return true
end

local function deepFreezeInternal(value: any, seen: { [any]: boolean })
	if typeof(value) ~= "table" then
		return
	end
	if seen[value] == true then
		return
	end
	seen[value] = true

	for _, nestedValue in value do
		if typeof(nestedValue) == "table" then
			deepFreezeInternal(nestedValue, seen)
		end
	end

	if not table.isfrozen(value) then
		table.freeze(value)
	end
end

local function deepFreeze<T>(value: T): T
	deepFreezeInternal(value, {})
	return value
end

local function appendUniqueString(target: { string }, value: string)
	for _, existing in target do
		if existing == value then
			return
		end
	end
	table.insert(target, value)
end

local function appendMergedItemAmount(
	target: { ItemAmount },
	itemId: string,
	amountRaw: any,
	itemIdsRaw: { string }?
)
	local amount = sanitizeInteger(amountRaw, 0, 0, 1_000_000)
	if amount <= 0 then
		return
	end
	local itemIds = if itemIdsRaw ~= nil and #itemIdsRaw > 0 then cloneStringArray(itemIdsRaw) else nil
	for _, existing in target do
		local existingItemIds = if existing.itemIds ~= nil and #existing.itemIds > 0 then existing.itemIds else nil
		if existing.itemId == itemId and stringArrayEquals(existingItemIds or {}, itemIds or {}) then
			existing.amount += amount
			return
		end
	end
	table.insert(target, {
		itemId = itemId,
		amount = amount,
		itemIds = itemIds,
	})
end

local function resolveRequirementItemIds(requirementRaw: ItemAmount): { string }
	local itemIds = if requirementRaw.itemIds ~= nil then cloneStringArray(requirementRaw.itemIds) else {}
	if #itemIds <= 0 then
		itemIds = { requirementRaw.itemId }
	end

	local hasPrimary = false
	for _, candidateItemId in itemIds do
		if candidateItemId == requirementRaw.itemId then
			hasPrimary = true
			break
		end
	end
	if not hasPrimary then
		table.insert(itemIds, 1, requirementRaw.itemId)
	end

	return itemIds
end

local function countInventoryItemsForRequirement(
	inventoryItemCountsRaw: { [string]: number },
	requirementRaw: ItemAmount
): number
	local total = 0
	for _, candidateItemId in resolveRequirementItemIds(requirementRaw) do
		total += math.max(0, math.floor(inventoryItemCountsRaw[candidateItemId] or 0))
	end
	return total
end

local function createDefaultCoinAmounts(): { [string]: number }
	return {
		copper = 0,
		silver = 0,
		gold = 0,
		platinum = 0,
	}
end

local function coinsToTotalCopper(amountsRaw: { [string]: number }): number
	local totalCopper = 0
	for coinKey, coinValue in COIN_KEY_TO_COPPER_VALUE do
		local amount = sanitizeInteger(amountsRaw[coinKey], 0, 0, 1_000_000_000)
		totalCopper += amount * coinValue
	end
	return totalCopper
end

local function totalCopperToCoinAmounts(totalCopperRaw: any): { [string]: number }
	local remaining = sanitizeInteger(totalCopperRaw, 0, 0, 1_000_000_000)
	local amounts = createDefaultCoinAmounts()
	for _, coinKey in COIN_KEYS_ORDER_DESCENDING do
		local coinValue = COIN_KEY_TO_COPPER_VALUE[coinKey]
		local coinCount = math.floor(remaining / coinValue)
		remaining -= coinCount * coinValue
		amounts[coinKey] = coinCount
	end
	return amounts
end

local function resolveCoinAmountsFromData(coinsDataRaw: any): ({ [string]: number }, boolean)
	if typeof(coinsDataRaw) ~= "table" then
		return createDefaultCoinAmounts(), false
	end

	local source = coinsDataRaw :: { [string]: any }
	local amounts = createDefaultCoinAmounts()
	local hasExplicitAmounts = false
	for coinKey in COIN_KEY_TO_COPPER_VALUE do
		local amount = sanitizeInteger(source[coinKey], 0, 0, 1_000_000_000)
		amounts[coinKey] = amount
		if amount > 0 then
			hasExplicitAmounts = true
		end
	end

	if hasExplicitAmounts then
		return amounts, true
	end

	local totalCopperRaw = source.totalCopper
	if typeof(totalCopperRaw) == "number" and totalCopperRaw == totalCopperRaw then
		return totalCopperToCoinAmounts(totalCopperRaw), false
	end

	return amounts, false
end

local function resolveStationDefinitionsFromTree(treeRaw: any): { [string]: StationDefinition }
	local output: { [string]: StationDefinition } = {}
	local tree = if typeof(treeRaw) == "table" then treeRaw else {}
	local stationsRaw = if typeof((tree :: any).stations) == "table" then (tree :: any).stations else {}

	for key, stationRaw in stationsRaw do
		if typeof(stationRaw) ~= "table" then
			continue
		end

		local stationSource = stationRaw :: { [string]: any }
		local stationId = sanitizeString(stationSource.id, if typeof(key) == "string" then key else nil)
		if stationId == nil then
			continue
		end

		local displayName = sanitizeString(stationSource.displayName, stationId) or stationId
		local tag = sanitizeString(stationSource.tag, nil) or (DEFAULT_STATION_TAG_PREFIX .. stationId)
		output[stationId] = {
			id = stationId,
			displayName = displayName,
			tag = tag,
		}
	end

	return output
end

function CraftingServiceUtils.CloneStringSet(setRaw: any): { [string]: boolean }
	return cloneStringSet(setRaw)
end

function CraftingServiceUtils.CloneStringArray(arrayRaw: any): { string }
	return cloneStringArray(arrayRaw)
end

function CraftingServiceUtils.StringSetEquals(lhs: { [string]: boolean }, rhs: { [string]: boolean }): boolean
	return stringSetEquals(lhs, rhs)
end

function CraftingServiceUtils.StringArrayEquals(lhs: { string }, rhs: { string }): boolean
	return stringArrayEquals(lhs, rhs)
end

function CraftingServiceUtils.deepFreeze<T>(value: T): T
	return deepFreeze(value)
end

function CraftingServiceUtils.GetDefaultDataPath(): { string }
	return Sift.Dictionary.copy(DEFAULT_DATA_PATH)
end

function CraftingServiceUtils.ResolveConfig(configRaw: any): CraftingServiceConfig
	local source = if typeof(configRaw) == "table" then (configRaw :: { [string]: any }) else {}
	local stationTagPrefix = sanitizeString(source.stationTagPrefix, DEFAULT_STATION_TAG_PREFIX) or DEFAULT_STATION_TAG_PREFIX

	local stationDefinitions = resolveStationDefinitionsFromTree(CraftingTree)
	local stationTagById: { [string]: string } = {}
	for stationId, stationDefinition in stationDefinitions do
		stationTagById[stationId] = stationDefinition.tag
	end

	local stationTagOverrides = if typeof(source.stationTagById) == "table"
		then (source.stationTagById :: { [string]: any })
		else {}

	for stationIdRaw, tagRaw in stationTagOverrides do
		local stationId = sanitizeString(stationIdRaw, nil)
		local tag = sanitizeString(tagRaw, nil)
		if stationId ~= nil and tag ~= nil then
			stationTagById[stationId] = tag
		end
	end

	for stationId, stationDefinition in stationDefinitions do
		if stationTagById[stationId] == nil then
			stationTagById[stationId] = stationTagPrefix .. stationDefinition.id
		end
	end

	return {
		stationScanRadius = sanitizeNumber(source.stationScanRadius, DEFAULT_STATION_SCAN_RADIUS, 2, 500),
		stationValidationRadius = sanitizeNumber(source.stationValidationRadius, DEFAULT_STATION_VALIDATION_RADIUS, 2, 500),
		stationScanRateHz = sanitizeNumber(source.stationScanRateHz, DEFAULT_STATION_SCAN_RATE_HZ, 1, 30),
		biomeScanRateHz = sanitizeNumber(source.biomeScanRateHz, DEFAULT_BIOME_SCAN_RATE_HZ, 1, 30),
		clientRequestThrottleSeconds = sanitizeNumber(
			source.clientRequestThrottleSeconds,
			DEFAULT_CLIENT_REQUEST_THROTTLE_SECONDS,
			0.02,
			2
		),
		serverRequestRateLimitSeconds = sanitizeNumber(
			source.serverRequestRateLimitSeconds,
			DEFAULT_SERVER_REQUEST_RATE_LIMIT_SECONDS,
			0.02,
			2
		),
		bulkCraftIntervalSeconds = sanitizeNumber(
			source.bulkCraftIntervalSeconds,
			DEFAULT_BULK_CRAFT_INTERVAL_SECONDS,
			0.03,
			5
		),
		inventoryWatchIntervalSeconds = sanitizeNumber(
			source.inventoryWatchIntervalSeconds,
			DEFAULT_INVENTORY_WATCH_INTERVAL_SECONDS,
			0.05,
			5
		),
		statePushIntervalSeconds = sanitizeNumber(
			source.statePushIntervalSeconds,
			DEFAULT_STATE_PUSH_INTERVAL_SECONDS,
			0.05,
			5
		),
		persistIntervalSeconds = sanitizeNumber(source.persistIntervalSeconds, DEFAULT_PERSIST_INTERVAL_SECONDS, 0.2, 30),
		dataLoadTimeoutSeconds = sanitizeNumber(source.dataLoadTimeoutSeconds, DEFAULT_DATA_LOAD_TIMEOUT_SECONDS, 2, 120),
		maxCraftQuantityPerRequest = sanitizeInteger(
			source.maxCraftQuantityPerRequest,
			DEFAULT_MAX_CRAFT_QUANTITY_PER_REQUEST,
			1,
			999
		),
		dataPath = clonePath(source.dataPath, DEFAULT_DATA_PATH),
		stationTagPrefix = stationTagPrefix,
		stationTagById = stationTagById,
	}
end

function CraftingServiceUtils.ResolveEffectiveConfig(configRaw: any?): CraftingServiceConfig
	local globalConfig = if configRaw ~= nil
		then configRaw
		else if typeof(Configs) == "table" then (Configs :: any).crafting else nil
	return CraftingServiceUtils.ResolveConfig(globalConfig)
end

function CraftingServiceUtils.NormalizeBiomeToken(tokenRaw: any): string?
	local token = sanitizeString(tokenRaw, nil)
	if token == nil then
		return nil
	end

	local lowered = string.lower(token)
	return BIOME_TOKEN_ALIASES[lowered] or lowered
end

function CraftingServiceUtils.ResolveBiomeTokens(biomeTypeRaw: any, biomeIdRaw: any): { [string]: boolean }
	local tokens: { [string]: boolean } = {}
	local biomeType = if typeof(biomeTypeRaw) == "number" and biomeTypeRaw == biomeTypeRaw
		then math.floor(biomeTypeRaw)
		else nil
	local biomeId = if typeof(biomeIdRaw) == "number" and biomeIdRaw == biomeIdRaw then math.floor(biomeIdRaw) else nil

	if biomeType ~= nil then
		tokens[("biometype_%d"):format(biomeType)] = true
		if biomeType == BIOME_TYPE_NORMAL then
			tokens.normal = true
			tokens.forest = true
			tokens.overworld = true
		elseif biomeType == BIOME_TYPE_CORRUPTION then
			tokens.corruption = true
		end
	end

	if biomeId ~= nil then
		tokens[("biomeid_%d"):format(biomeId)] = true
		if biomeId == BIOME_ID_FOREST then
			tokens.forest = true
		elseif biomeId == BIOME_ID_JUNGLE then
			tokens.jungle = true
		end
	end

	return tokens
end

local function resolveWorldServiceBiomeType(worldServiceRaw: any, worldPosition: Vector3): number?
	if typeof(worldServiceRaw) ~= "table" then
		return nil
	end

	local getBiomeTypeAtWorldPositionMethod = (worldServiceRaw :: any).getBiomeTypeAtWorldPosition
	if typeof(getBiomeTypeAtWorldPositionMethod) == "function" then
		local ok, result = pcall(function()
			return (worldServiceRaw :: any):getBiomeTypeAtWorldPosition(worldPosition)
		end)
		if ok and typeof(result) == "number" and result == result then
			return math.floor(result)
		end
	end

	local getWorldMethod = (worldServiceRaw :: any).getWorld
	if typeof(getWorldMethod) == "function" then
		local okWorld, worldOrError = pcall(function()
			return (worldServiceRaw :: any):getWorld()
		end)
		if okWorld and typeof(worldOrError) == "table" then
			local world = worldOrError
			local worldMethod = (world :: any).getBiomeTypeAtWorldPosition
			if typeof(worldMethod) == "function" then
				local okBiome, biomeTypeOrError = pcall(function()
					return (world :: any):getBiomeTypeAtWorldPosition(worldPosition)
				end)
				if okBiome and typeof(biomeTypeOrError) == "number" and biomeTypeOrError == biomeTypeOrError then
					return math.floor(biomeTypeOrError)
				end
			end
		end
	end

	return nil
end

local function resolveWorldServiceBiomeId(worldServiceRaw: any, worldPosition: Vector3): number?
	if typeof(worldServiceRaw) ~= "table" then
		return nil
	end

	local getBiomeIdAtWorldPositionMethod = (worldServiceRaw :: any).getBiomeIdAtWorldPosition
	if typeof(getBiomeIdAtWorldPositionMethod) == "function" then
		local ok, result = pcall(function()
			return (worldServiceRaw :: any):getBiomeIdAtWorldPosition(worldPosition)
		end)
		if ok and typeof(result) == "number" and result == result then
			return math.floor(result)
		end
	end

	local getWorldMethod = (worldServiceRaw :: any).getWorld
	if typeof(getWorldMethod) == "function" then
		local okWorld, worldOrError = pcall(function()
			return (worldServiceRaw :: any):getWorld()
		end)
		if okWorld and typeof(worldOrError) == "table" then
			local world = worldOrError
			local worldMethod = (world :: any).getBiomeIdAtWorldPosition
			if typeof(worldMethod) == "function" then
				local okBiome, biomeIdOrError = pcall(function()
					return (world :: any):getBiomeIdAtWorldPosition(worldPosition)
				end)
				if okBiome and typeof(biomeIdOrError) == "number" and biomeIdOrError == biomeIdOrError then
					return math.floor(biomeIdOrError)
				end
			end
		end
	end

	return nil
end

function CraftingServiceUtils.ResolveBiomeTokensFromWorldService(
	worldServiceRaw: any,
	worldPositionRaw: any
): { [string]: boolean }
	if typeof(worldPositionRaw) ~= "Vector3" then
		return {}
	end

	local biomeType = resolveWorldServiceBiomeType(worldServiceRaw, worldPositionRaw)
	local biomeId = resolveWorldServiceBiomeId(worldServiceRaw, worldPositionRaw)
	return CraftingServiceUtils.ResolveBiomeTokens(biomeType, biomeId)
end

function CraftingServiceUtils.ResolvePlayerRootPosition(playerRaw: any): Vector3?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local character = playerRaw.Character
	if character == nil then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart.Position
	end
	if character.PrimaryPart ~= nil then
		return character.PrimaryPart.Position
	end

	local fallbackPart = character:FindFirstChildWhichIsA("BasePart")
	if fallbackPart ~= nil then
		return fallbackPart.Position
	end
	return nil
end

function CraftingServiceUtils.ScaleItemAmounts(itemAmountsRaw: { ItemAmount }, multiplierRaw: any): { ItemAmount }
	local output: { ItemAmount } = {}
	local multiplier = sanitizeInteger(multiplierRaw, 1, 1, 9999)
	for _, itemAmount in itemAmountsRaw do
		appendMergedItemAmount(output, itemAmount.itemId, itemAmount.amount * multiplier, itemAmount.itemIds)
	end
	return output
end

function CraftingServiceUtils.CloneItemAmounts(itemAmountsRaw: { ItemAmount }): { ItemAmount }
	local output: { ItemAmount } = {}
	for _, itemAmount in itemAmountsRaw do
		table.insert(output, {
			itemId = itemAmount.itemId,
			amount = itemAmount.amount,
			itemIds = if itemAmount.itemIds ~= nil then cloneStringArray(itemAmount.itemIds) else nil,
		})
	end
	return output
end

function CraftingServiceUtils.BuildInventoryItemCountMap(inventoryStateRaw: any, coinsDataRaw: any?): { [string]: number }
	local output: { [string]: number } = {}
	if typeof(inventoryStateRaw) ~= "table" then
		inventoryStateRaw = nil
	end
	local slotsRaw = if inventoryStateRaw ~= nil then (inventoryStateRaw :: any).slots else nil
	if typeof(slotsRaw) == "table" then
		for _, slotRaw in slotsRaw do
			if typeof(slotRaw) ~= "table" then
				continue
			end
			local stackRaw = (slotRaw :: any).stack
			if typeof(stackRaw) ~= "table" then
				continue
			end
			local itemId = sanitizeString((stackRaw :: any).itemId, nil)
			local amount = sanitizeInteger((stackRaw :: any).amount, 0, 0, 1_000_000)
			if itemId == nil or amount <= 0 then
				continue
			end
			output[itemId] = (output[itemId] or 0) + amount
		end
	end

	local coinsRaw = coinsDataRaw
	if typeof(coinsRaw) == "table" then
		local resolvedCoinAmounts = resolveCoinAmountsFromData(coinsRaw)
		for coinItemId, coinKey in COIN_ITEM_ID_TO_KEY do
			local amount = sanitizeInteger(resolvedCoinAmounts[coinKey], 0, 0, COIN_ITEM_MAX_AMOUNT)
			if amount > 0 then
				output[coinItemId] = (output[coinItemId] or 0) + amount
			end
		end
	end

	return output
end

local function resolveCoinCapacityForResult(
	itemIdRaw: any,
	inventoryItemCountsRaw: { [string]: number },
	amountPerCraftRaw: any
): number?
	local itemId = sanitizeString(itemIdRaw, nil)
	if itemId == nil or COIN_ITEM_ID_TO_KEY[itemId] == nil then
		return nil
	end

	local amountPerCraft = sanitizeInteger(amountPerCraftRaw, 0, 0, 1_000_000)
	if amountPerCraft <= 0 then
		return 0
	end

	local currentAmount = math.max(0, math.floor(inventoryItemCountsRaw[itemId] or 0))
	local remainingCapacity = math.max(0, COIN_ITEM_MAX_AMOUNT - currentAmount)
	return math.floor(remainingCapacity / amountPerCraft)
end

local RecipeIndexer = {}
CraftingServiceUtils.RecipeIndexer = RecipeIndexer

local function sanitizeStringList(valueRaw: any): { string }
	local output = {}
	local seen: { [string]: boolean } = {}
	if typeof(valueRaw) ~= "table" then
		return output
	end
	for _, entryRaw in valueRaw do
		local value = sanitizeString(entryRaw, nil)
		if value ~= nil and not seen[value] then
			seen[value] = true
			table.insert(output, value)
		end
	end
	return output
end

local function sanitizeItemAmountList(valueRaw: any): { ItemAmount }
	local output: { ItemAmount } = {}
	if typeof(valueRaw) ~= "table" then
		return output
	end

	for _, entryRaw in valueRaw do
		if typeof(entryRaw) ~= "table" then
			continue
		end
		local entry = entryRaw :: { [string]: any }
		local itemIds = sanitizeStringList(entry.itemIds)
		local itemId = sanitizeString(entry.itemId, if #itemIds > 0 then itemIds[1] else nil)
		local amount = sanitizeInteger(entry.amount, 0, 0, 1_000_000)
		if itemId == nil or amount <= 0 then
			continue
		end
		appendMergedItemAmount(output, itemId, amount, itemIds)
	end

	return output
end

local function sanitizeUnlockConditions(valueRaw: any): UnlockConditions?
	if typeof(valueRaw) ~= "table" then
		return nil
	end

	local source = valueRaw :: { [string]: any }
	local requiredItems = sanitizeStringList(source.requiredItems)
	if #requiredItems <= 0 and typeof(source.requiredItems) == "table" then
		for _, entryRaw in source.requiredItems do
			if typeof(entryRaw) ~= "table" then
				continue
			end
			local itemId = sanitizeString((entryRaw :: any).itemId, nil)
			if itemId ~= nil then
				appendUniqueString(requiredItems, itemId)
			end
		end
	end

	local requiredFlags = sanitizeStringList(
		if source.requiredFlags ~= nil then source.requiredFlags else source.progressionFlags
	)

	if #requiredItems <= 0 and #requiredFlags <= 0 then
		return nil
	end

	return {
		requiredItems = if #requiredItems > 0 then requiredItems else nil,
		requiredFlags = if #requiredFlags > 0 then requiredFlags else nil,
	}
end

local function sanitizeRecipeDefinition(recipeRaw: any, fallbackId: string): RecipeDefinition?
	if typeof(recipeRaw) ~= "table" then
		return nil
	end

	local source = recipeRaw :: { [string]: any }
	local id = sanitizeString(source.id, fallbackId)
	if id == nil then
		return nil
	end

	local ingredients = sanitizeItemAmountList(source.ingredients)
	local results = sanitizeItemAmountList(source.results)
	if #ingredients <= 0 or #results <= 0 then
		return nil
	end

	return {
		id = id,
		displayName = sanitizeString(source.displayName, id) or id,
		category = sanitizeString(source.category, "Misc") or "Misc",
		ingredients = ingredients,
		results = results,
		requiredStations = sanitizeStringList(source.requiredStations),
		requiredBiome = sanitizeString(source.requiredBiome, nil),
		unlockConditions = sanitizeUnlockConditions(source.unlockConditions),
		sortOrder = sanitizeInteger(source.sortOrder, 1000, -1_000_000, 1_000_000),
		isHidden = sanitizeBoolean(source.isHidden, false),
		orderIndex = 0,
	}
end

local function sortRecipeIdsByRegistryOrder(recipeIds: { string }, recipesById: { [string]: RecipeDefinition })
	table.sort(recipeIds, function(lhsId: string, rhsId: string)
		local lhs = recipesById[lhsId]
		local rhs = recipesById[rhsId]
		if lhs == nil and rhs == nil then
			return lhsId < rhsId
		end
		if lhs == nil then
			return false
		end
		if rhs == nil then
			return true
		end
		if lhs.orderIndex ~= rhs.orderIndex then
			return lhs.orderIndex < rhs.orderIndex
		end
		return lhs.id < rhs.id
	end)
end

local function sanitizeRecipeGroup(groupRaw: any, fallbackId: string, recipesById: { [string]: RecipeDefinition }): RecipeGroup?
	if typeof(groupRaw) ~= "table" then
		return nil
	end
	local source = groupRaw :: { [string]: any }
	local id = sanitizeString(source.id, fallbackId)
	if id == nil then
		return nil
	end

	local recipeIds = sanitizeStringList(source.recipeIds)
	local filteredRecipeIds = {}
	for _, recipeId in recipeIds do
		if recipesById[recipeId] ~= nil then
			table.insert(filteredRecipeIds, recipeId)
		end
	end
	if #filteredRecipeIds <= 0 then
		return nil
	end

	sortRecipeIdsByRegistryOrder(filteredRecipeIds, recipesById)

	return {
		id = id,
		displayName = sanitizeString(source.displayName, id) or id,
		sortOrder = sanitizeInteger(source.sortOrder, 1000, -1_000_000, 1_000_000),
		recipeIds = filteredRecipeIds,
	}
end

function RecipeIndexer.BuildRegistry(treeRaw: any, configRaw: any): RecipeRegistry
	local tree = if typeof(treeRaw) == "table" then (treeRaw :: { [string]: any }) else {}
	local config = CraftingServiceUtils.ResolveConfig(configRaw)
	local stationDefinitionsFromTree = resolveStationDefinitionsFromTree(tree)
	local stationDefinitions: { [string]: StationDefinition } = {}
	local stationTagById: { [string]: string } = {}

	for stationId, stationDefinition in stationDefinitionsFromTree do
		local resolvedTag = config.stationTagById[stationId] or stationDefinition.tag
		stationDefinitions[stationId] = deepFreeze({
			id = stationDefinition.id,
			displayName = stationDefinition.displayName,
			tag = resolvedTag,
		})
		stationTagById[stationId] = resolvedTag
	end

	for stationId, stationTag in config.stationTagById do
		if stationDefinitions[stationId] == nil then
			stationDefinitions[stationId] = deepFreeze({
				id = stationId,
				displayName = stationId,
				tag = stationTag,
			})
		end
		stationTagById[stationId] = stationTag
	end

	local rawRecipes = if typeof(tree.recipes) == "table" then tree.recipes else {}
	local mutableRecipes: { RecipeDefinition } = {}
	local recipesById: { [string]: RecipeDefinition } = {}
	for index, recipeRaw in rawRecipes do
		local fallbackId = ("recipe_%d"):format(index)
		local recipe = sanitizeRecipeDefinition(recipeRaw, fallbackId)
		if recipe == nil then
			continue
		end
		if recipesById[recipe.id] ~= nil then
			continue
		end
		table.insert(mutableRecipes, recipe)
		recipesById[recipe.id] = recipe
	end

	table.sort(mutableRecipes, function(lhs: RecipeDefinition, rhs: RecipeDefinition)
		if lhs.sortOrder ~= rhs.sortOrder then
			return lhs.sortOrder < rhs.sortOrder
		end
		if lhs.category ~= rhs.category then
			return lhs.category < rhs.category
		end
		if lhs.displayName ~= rhs.displayName then
			return lhs.displayName < rhs.displayName
		end
		return lhs.id < rhs.id
	end)

	for orderIndex, recipe in mutableRecipes do
		recipe.orderIndex = orderIndex
		deepFreeze(recipe)
		recipesById[recipe.id] = recipe
	end

	local recipeIdsOrdered: { string } = {}
	local recipeIdsByStation: { [string]: { string } } = {}
	local noStationRecipeIds: { string } = {}
	local recipeIdsByCategory: { [string]: { string } } = {}
	local recipeIdsByUnlockItem: { [string]: { string } } = {}
	local recipeIdsByUnlockFlag: { [string]: { string } } = {}
	local unlockRelevantItemIdSet: { [string]: boolean } = {}
	local defaultKnownRecipeIds: { [string]: boolean } = {}

	for _, recipe in mutableRecipes do
		table.insert(recipeIdsOrdered, recipe.id)

		local byCategory = recipeIdsByCategory[recipe.category]
		if byCategory == nil then
			byCategory = {}
			recipeIdsByCategory[recipe.category] = byCategory
		end
		table.insert(byCategory, recipe.id)

		if #recipe.requiredStations <= 0 then
			table.insert(noStationRecipeIds, recipe.id)
		else
			for _, stationId in recipe.requiredStations do
				local byStation = recipeIdsByStation[stationId]
				if byStation == nil then
					byStation = {}
					recipeIdsByStation[stationId] = byStation
				end
				table.insert(byStation, recipe.id)
			end
		end

		local unlockConditions = recipe.unlockConditions
		if unlockConditions ~= nil then
			local requiredItems = unlockConditions.requiredItems
			if requiredItems ~= nil then
				for _, itemId in requiredItems do
					local byItem = recipeIdsByUnlockItem[itemId]
					if byItem == nil then
						byItem = {}
						recipeIdsByUnlockItem[itemId] = byItem
					end
					table.insert(byItem, recipe.id)
					unlockRelevantItemIdSet[itemId] = true
				end
			end

			local requiredFlags = unlockConditions.requiredFlags
			if requiredFlags ~= nil then
				for _, flagId in requiredFlags do
					local byFlag = recipeIdsByUnlockFlag[flagId]
					if byFlag == nil then
						byFlag = {}
						recipeIdsByUnlockFlag[flagId] = byFlag
					end
					table.insert(byFlag, recipe.id)
				end
			end
		end

		if recipe.isHidden ~= true and recipe.unlockConditions == nil then
			defaultKnownRecipeIds[recipe.id] = true
		end
	end

	for _, recipeIds in recipeIdsByStation do
		sortRecipeIdsByRegistryOrder(recipeIds, recipesById)
		deepFreeze(recipeIds)
	end
	for _, recipeIds in recipeIdsByCategory do
		sortRecipeIdsByRegistryOrder(recipeIds, recipesById)
		deepFreeze(recipeIds)
	end
	for _, recipeIds in recipeIdsByUnlockItem do
		sortRecipeIdsByRegistryOrder(recipeIds, recipesById)
		deepFreeze(recipeIds)
	end
	for _, recipeIds in recipeIdsByUnlockFlag do
		sortRecipeIdsByRegistryOrder(recipeIds, recipesById)
		deepFreeze(recipeIds)
	end
	sortRecipeIdsByRegistryOrder(noStationRecipeIds, recipesById)

	local groups: { [string]: RecipeGroup } = {}
	local groupIdsOrdered: { string } = {}
	local groupIdByRecipeId: { [string]: string } = {}
	local groupsRaw = if typeof(tree.groups) == "table" then tree.groups else {}

	for groupKey, groupRaw in groupsRaw do
		local fallbackId = if typeof(groupKey) == "string" then groupKey else "group"
		local group = sanitizeRecipeGroup(groupRaw, fallbackId, recipesById)
		if group == nil then
			continue
		end
		groups[group.id] = group
		table.insert(groupIdsOrdered, group.id)
	end

	table.sort(groupIdsOrdered, function(lhsId: string, rhsId: string)
		local lhs = groups[lhsId]
		local rhs = groups[rhsId]
		if lhs == nil and rhs == nil then
			return lhsId < rhsId
		end
		if lhs == nil then
			return false
		end
		if rhs == nil then
			return true
		end
		if lhs.sortOrder ~= rhs.sortOrder then
			return lhs.sortOrder < rhs.sortOrder
		end
		if lhs.displayName ~= rhs.displayName then
			return lhs.displayName < rhs.displayName
		end
		return lhs.id < rhs.id
	end)

	for _, groupId in groupIdsOrdered do
		local group = groups[groupId]
		if group ~= nil then
			for _, recipeId in group.recipeIds do
				if groupIdByRecipeId[recipeId] == nil then
					groupIdByRecipeId[recipeId] = group.id
				end
			end
			deepFreeze(group)
		end
	end

	local unlockRelevantItemIds = serializeStringSet(unlockRelevantItemIdSet)

	local registry: RecipeRegistry = {
		version = sanitizeInteger(tree.version, 1, 1, 1_000_000),
		recipes = mutableRecipes,
		recipeIdsOrdered = recipeIdsOrdered,
		recipesById = recipesById,
		recipeIdsByStation = recipeIdsByStation,
		noStationRecipeIds = noStationRecipeIds,
		recipeIdsByCategory = recipeIdsByCategory,
		recipeIdsByUnlockItem = recipeIdsByUnlockItem,
		recipeIdsByUnlockFlag = recipeIdsByUnlockFlag,
		unlockRelevantItemIds = unlockRelevantItemIds,
		unlockRelevantItemIdSet = unlockRelevantItemIdSet,
		stationDefinitions = stationDefinitions,
		stationTagById = stationTagById,
		groups = groups,
		groupIdsOrdered = groupIdsOrdered,
		groupIdByRecipeId = groupIdByRecipeId,
		defaultKnownRecipeIds = defaultKnownRecipeIds,
	}

	return deepFreeze(registry)
end

local cachedRegistry: RecipeRegistry? = nil
local cachedRegistryKey: string? = nil

local function buildRegistryCacheKey(config: CraftingServiceConfig): string
	local segments = {
		("scanRadius=%s"):format(tostring(config.stationScanRadius)),
		("validationRadius=%s"):format(tostring(config.stationValidationRadius)),
	}
	local stationIds = {}
	for stationId in config.stationTagById do
		table.insert(stationIds, stationId)
	end
	table.sort(stationIds)
	for _, stationId in stationIds do
		table.insert(segments, ("%s=%s"):format(stationId, config.stationTagById[stationId]))
	end
	return table.concat(segments, ";")
end

function CraftingServiceUtils.GetRegistry(configRaw: any?): RecipeRegistry
	local config = CraftingServiceUtils.ResolveEffectiveConfig(configRaw)
	local key = buildRegistryCacheKey(config)
	if cachedRegistry ~= nil and cachedRegistryKey == key then
		return cachedRegistry :: RecipeRegistry
	end

	local registry = RecipeIndexer.BuildRegistry(CraftingTree, config)
	cachedRegistry = registry
	cachedRegistryKey = key
	return registry
end

local RecipeValidator = {}
CraftingServiceUtils.RecipeValidator = RecipeValidator

function RecipeValidator.SanitizeCraftRequest(
	recipeIdRaw: any,
	quantityRaw: any,
	maxQuantityRaw: any
): (string?, number)
	local recipeId = sanitizeString(recipeIdRaw, nil)
	if recipeId == nil then
		return nil, 0
	end
	local maxQuantity = sanitizeInteger(maxQuantityRaw, DEFAULT_MAX_CRAFT_QUANTITY_PER_REQUEST, 1, 999)
	local quantity = sanitizeInteger(quantityRaw, 1, 1, maxQuantity)
	return recipeId, quantity
end

function RecipeValidator.IsRecipeKnown(knownRecipeIdsRaw: any, recipeIdRaw: any): boolean
	local recipeId = sanitizeString(recipeIdRaw, nil)
	if recipeId == nil then
		return false
	end
	if typeof(knownRecipeIdsRaw) ~= "table" then
		return false
	end
	return (knownRecipeIdsRaw :: { [string]: boolean })[recipeId] == true
end

function RecipeValidator.GetMissingStations(
	recipeRaw: RecipeDefinition,
	activeStationsRaw: { [string]: boolean }
): { string }
	local output = {}
	for _, stationId in recipeRaw.requiredStations do
		if activeStationsRaw[stationId] ~= true then
			table.insert(output, stationId)
		end
	end
	return output
end

function RecipeValidator.AreStationsSatisfied(
	recipeRaw: RecipeDefinition,
	activeStationsRaw: { [string]: boolean }
): boolean
	return #RecipeValidator.GetMissingStations(recipeRaw, activeStationsRaw) <= 0
end

function RecipeValidator.AreUnlockConditionsSatisfied(
	recipeRaw: RecipeDefinition,
	discoveredItemIdsRaw: { [string]: boolean },
	progressionFlagsRaw: { [string]: boolean }
): boolean
	local unlockConditions = recipeRaw.unlockConditions
	if unlockConditions == nil then
		return true
	end

	local requiredItems = unlockConditions.requiredItems
	if requiredItems ~= nil then
		for _, itemId in requiredItems do
			if discoveredItemIdsRaw[itemId] ~= true then
				return false
			end
		end
	end

	local requiredFlags = unlockConditions.requiredFlags
	if requiredFlags ~= nil then
		for _, flagId in requiredFlags do
			if progressionFlagsRaw[flagId] ~= true then
				return false
			end
		end
	end

	return true
end

local function normalizeRequiredBiomeToTokens(requiredBiomeRaw: any): { string }
	if typeof(requiredBiomeRaw) == "number" and requiredBiomeRaw == requiredBiomeRaw then
		local numberValue = math.floor(requiredBiomeRaw)
		return {
			("biometype_%d"):format(numberValue),
			("biomeid_%d"):format(numberValue),
		}
	end

	local requiredBiome = CraftingServiceUtils.NormalizeBiomeToken(requiredBiomeRaw)
	if requiredBiome == nil then
		return {}
	end
	return { requiredBiome }
end

function RecipeValidator.IsBiomeSatisfied(recipeRaw: RecipeDefinition, biomeTokensRaw: { [string]: boolean }): boolean
	local requiredBiomeTokens = normalizeRequiredBiomeToTokens(recipeRaw.requiredBiome)
	if #requiredBiomeTokens <= 0 then
		return true
	end
	for _, requiredToken in requiredBiomeTokens do
		if biomeTokensRaw[requiredToken] == true then
			return true
		end
	end
	return false
end

function CraftingServiceUtils.CreateDefaultPersistentState(): CraftingPersistentState
	return {
		knownRecipeIds = {},
		discoveredItemIds = {},
		progressionFlags = {},
		updatedAt = os.time(),
	}
end

function CraftingServiceUtils.SanitizePersistentState(
	valueRaw: any,
	registryRaw: RecipeRegistry?
): CraftingPersistentState
	local source = if typeof(valueRaw) == "table" then (valueRaw :: { [string]: any }) else {}
	local knownRecipeIds = cloneStringSet(source.knownRecipeIds)
	local discoveredItemIds = cloneStringSet(source.discoveredItemIds)
	local progressionFlags = cloneStringSet(source.progressionFlags)
	local registry = registryRaw

	if registry ~= nil then
		for recipeId in knownRecipeIds do
			if registry.recipesById[recipeId] == nil then
				knownRecipeIds[recipeId] = nil
			end
		end
	end

	local updatedAt = if typeof(source.updatedAt) == "number" and source.updatedAt == source.updatedAt
		then source.updatedAt
		else os.time()

	return {
		knownRecipeIds = knownRecipeIds,
		discoveredItemIds = discoveredItemIds,
		progressionFlags = progressionFlags,
		updatedAt = updatedAt,
	}
end

function CraftingServiceUtils.SerializePersistentState(
	valueRaw: CraftingPersistentState
): { [string]: any }
	return {
		knownRecipeIds = serializeStringSet(valueRaw.knownRecipeIds),
		discoveredItemIds = serializeStringSet(valueRaw.discoveredItemIds),
		progressionFlags = serializeStringSet(valueRaw.progressionFlags),
		updatedAt = os.time(),
	}
end

function CraftingServiceUtils.CreateDefaultServiceStateSnapshot(
	registryRaw: RecipeRegistry?
): CraftingServiceStateSnapshot
	local knownRecipeIds = {}
	if registryRaw ~= nil then
		for recipeId, enabled in registryRaw.defaultKnownRecipeIds do
			if enabled then
				knownRecipeIds[recipeId] = true
			end
		end
	end
	return {
		knownRecipeIds = knownRecipeIds,
		discoveredItemIds = {},
		progressionFlags = {},
		updatedAt = os.clock(),
	}
end

function CraftingServiceUtils.SanitizeServiceStateSnapshot(
	valueRaw: any,
	fallbackRaw: CraftingServiceStateSnapshot?
): CraftingServiceStateSnapshot
	local fallback = if fallbackRaw ~= nil then fallbackRaw else CraftingServiceUtils.CreateDefaultServiceStateSnapshot(nil)
	local source = if typeof(valueRaw) == "table" then (valueRaw :: { [string]: any }) else {}
	return {
		knownRecipeIds = cloneStringSet(if source.knownRecipeIds ~= nil then source.knownRecipeIds else fallback.knownRecipeIds),
		discoveredItemIds = cloneStringSet(
			if source.discoveredItemIds ~= nil then source.discoveredItemIds else fallback.discoveredItemIds
		),
		progressionFlags = cloneStringSet(
			if source.progressionFlags ~= nil then source.progressionFlags else fallback.progressionFlags
		),
		updatedAt = if typeof(source.updatedAt) == "number" and source.updatedAt == source.updatedAt
			then source.updatedAt
			else fallback.updatedAt,
	}
end

function CraftingServiceUtils.BuildAvailableRecipeIds(
	registry: RecipeRegistry,
	knownRecipeIdsRaw: { [string]: boolean },
	activeStationsRaw: { [string]: boolean },
	biomeTokensRaw: { [string]: boolean }?
): { string }
	local candidateRecipeIdSet: { [string]: boolean } = {}

	for _, recipeId in registry.noStationRecipeIds do
		candidateRecipeIdSet[recipeId] = true
	end
	for stationId, isActive in activeStationsRaw do
		if isActive ~= true then
			continue
		end
		local recipeIds = registry.recipeIdsByStation[stationId]
		if recipeIds == nil then
			continue
		end
		for _, recipeId in recipeIds do
			candidateRecipeIdSet[recipeId] = true
		end
	end

	local availableRecipeIds = {}
	local biomeTokens = if biomeTokensRaw ~= nil then biomeTokensRaw else {}
	for recipeId in candidateRecipeIdSet do
		local recipe = registry.recipesById[recipeId]
		if recipe == nil then
			continue
		end
		if knownRecipeIdsRaw[recipeId] ~= true then
			continue
		end
		if not RecipeValidator.AreStationsSatisfied(recipe, activeStationsRaw) then
			continue
		end
		if not RecipeValidator.IsBiomeSatisfied(recipe, biomeTokens) then
			continue
		end
		table.insert(availableRecipeIds, recipeId)
	end

	sortRecipeIdsByRegistryOrder(availableRecipeIds, registry.recipesById)
	return availableRecipeIds
end

function CraftingServiceUtils.ComputeMaxCraftableQuantity(
	recipeRaw: RecipeDefinition,
	inventoryItemCountsRaw: { [string]: number }
): number
	if #recipeRaw.ingredients <= 0 then
		return 0
	end

	local maxCraftable = math.huge
	for _, ingredient in recipeRaw.ingredients do
		if ingredient.amount <= 0 then
			return 0
		end
		local available = countInventoryItemsForRequirement(inventoryItemCountsRaw, ingredient)
		local craftableForIngredient = math.floor(available / ingredient.amount)
		if craftableForIngredient < maxCraftable then
			maxCraftable = craftableForIngredient
		end
	end

	for _, result in recipeRaw.results do
		local craftableForCapacity = resolveCoinCapacityForResult(
			result.itemId,
			inventoryItemCountsRaw,
			result.amount
		)
		if craftableForCapacity ~= nil and craftableForCapacity < maxCraftable then
			maxCraftable = craftableForCapacity
		end
	end

	if maxCraftable == math.huge then
		return 0
	end
	return math.max(0, maxCraftable)
end

function CraftingServiceUtils.BuildRecipePreview(
	recipeRaw: RecipeDefinition,
	inventoryItemCountsRaw: { [string]: number },
	quantityRaw: any,
	activeStationsRaw: { [string]: boolean },
	biomeTokensRaw: { [string]: boolean },
	knownRecipeIdsRaw: { [string]: boolean }?
): RecipePreview
	local quantity = sanitizeInteger(quantityRaw, 1, 1, 999)
	local ingredients = {}
	local results = {}
	local hasAllIngredients = true

	for _, ingredient in recipeRaw.ingredients do
		local required = ingredient.amount * quantity
		local available = countInventoryItemsForRequirement(inventoryItemCountsRaw, ingredient)
		local isSufficient = available >= required
		if not isSufficient then
			hasAllIngredients = false
		end
		table.insert(ingredients, {
			itemId = ingredient.itemId,
			required = required,
			available = available,
			isSufficient = isSufficient,
		})
	end

	for _, result in recipeRaw.results do
		table.insert(results, {
			itemId = result.itemId,
			amount = result.amount * quantity,
		})
	end

	local missingStations = RecipeValidator.GetMissingStations(recipeRaw, activeStationsRaw)
	local biomeSatisfied = RecipeValidator.IsBiomeSatisfied(recipeRaw, biomeTokensRaw)
	local knownRecipeIds = if knownRecipeIdsRaw ~= nil then knownRecipeIdsRaw else {}
	local isKnown = knownRecipeIdsRaw == nil or knownRecipeIds[recipeRaw.id] == true
	local maxCraftableQuantity = CraftingServiceUtils.ComputeMaxCraftableQuantity(recipeRaw, inventoryItemCountsRaw)

	return {
		recipeId = recipeRaw.id,
		quantity = quantity,
		maxCraftableQuantity = maxCraftableQuantity,
		canCraft = isKnown and biomeSatisfied and #missingStations <= 0 and hasAllIngredients and maxCraftableQuantity >= quantity,
		isKnown = isKnown,
		ingredients = ingredients,
		results = results,
		missingStations = missingStations,
		missingBiome = if biomeSatisfied then nil else recipeRaw.requiredBiome,
	}
end

function CraftingServiceUtils.FilterRecipeIds(
	registryRaw: RecipeRegistry,
	recipeIdsRaw: { string },
	categoryRaw: any,
	searchTextRaw: any
): { string }
	local category = sanitizeString(categoryRaw, nil)
	local searchText = sanitizeString(searchTextRaw, nil)
	local searchToken = if searchText ~= nil then string.lower(searchText) else nil
	local output = {}

	for _, recipeId in recipeIdsRaw do
		local recipe = registryRaw.recipesById[recipeId]
		if recipe == nil then
			continue
		end

		if category ~= nil and category ~= "" and recipe.category ~= category then
			continue
		end

		if searchToken ~= nil and searchToken ~= "" then
			local displayName = string.lower(recipe.displayName)
			local idToken = string.lower(recipe.id)
			if not string.find(displayName, searchToken, 1, true) and not string.find(idToken, searchToken, 1, true) then
				continue
			end
		end

		table.insert(output, recipeId)
	end

	return output
end

function CraftingServiceUtils.BuildCategoryList(registryRaw: RecipeRegistry, recipeIdsRaw: { string }): { string }
	local categoryOrder = {}
	local seen = {}
	for _, recipeId in recipeIdsRaw do
		local recipe = registryRaw.recipesById[recipeId]
		if recipe == nil then
			continue
		end
		local category = recipe.category
		if seen[category] then
			continue
		end
		seen[category] = true
		table.insert(categoryOrder, category)
	end

	table.sort(categoryOrder, function(lhs: string, rhs: string)
		local lhsRecipes = registryRaw.recipeIdsByCategory[lhs]
		local rhsRecipes = registryRaw.recipeIdsByCategory[rhs]
		local lhsSortOrder = if lhsRecipes ~= nil and #lhsRecipes > 0
			then (registryRaw.recipesById[lhsRecipes[1]] :: RecipeDefinition).sortOrder
			else 1_000_000
		local rhsSortOrder = if rhsRecipes ~= nil and #rhsRecipes > 0
			then (registryRaw.recipesById[rhsRecipes[1]] :: RecipeDefinition).sortOrder
			else 1_000_000
		if lhsSortOrder ~= rhsSortOrder then
			return lhsSortOrder < rhsSortOrder
		end
		return lhs < rhs
	end)

	return categoryOrder
end

local StationDetector = {}
CraftingServiceUtils.StationDetector = StationDetector

function StationDetector.ResolveInstancePosition(instanceRaw: any): Vector3?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	if instanceRaw:IsA("BasePart") then
		return instanceRaw.Position
	end

	if instanceRaw:IsA("Attachment") then
		local ok, worldPosition = pcall(function()
			return (instanceRaw :: Attachment).WorldPosition
		end)
		if ok and typeof(worldPosition) == "Vector3" then
			return worldPosition
		end
	end

	if instanceRaw:IsA("Model") then
		if instanceRaw.PrimaryPart ~= nil then
			return instanceRaw.PrimaryPart.Position
		end
		local rootPart = instanceRaw:FindFirstChild("HumanoidRootPart")
		if rootPart ~= nil and rootPart:IsA("BasePart") then
			return rootPart.Position
		end
		local descendantPart = instanceRaw:FindFirstChildWhichIsA("BasePart", true)
		if descendantPart ~= nil then
			return descendantPart.Position
		end
	end

	local descendant = instanceRaw:FindFirstChildWhichIsA("BasePart", true)
	if descendant ~= nil then
		return descendant.Position
	end

	return nil
end

local function resolveStationIdScanList(
	stationTagById: { [string]: string },
	requiredStationIdsRaw: { string }?
): { string }
	local stationIds = {}
	local seen = {}

	if requiredStationIdsRaw ~= nil and #requiredStationIdsRaw > 0 then
		for _, stationId in requiredStationIdsRaw do
			if seen[stationId] then
				continue
			end
			seen[stationId] = true
			table.insert(stationIds, stationId)
		end
		return stationIds
	end

	for stationId in stationTagById do
		table.insert(stationIds, stationId)
	end
	table.sort(stationIds)
	return stationIds
end

function StationDetector.GetStationsNearPosition(
	worldPositionRaw: any,
	stationTagByIdRaw: { [string]: string },
	radiusRaw: any,
	requiredStationIdsRaw: { string }?
): { [string]: boolean }
	if typeof(worldPositionRaw) ~= "Vector3" then
		return {}
	end

	local radius = sanitizeNumber(radiusRaw, DEFAULT_STATION_VALIDATION_RADIUS, 1, 1000)
	local radiusSquared = radius * radius
	local activeStations: { [string]: boolean } = {}
	local stationIds = resolveStationIdScanList(stationTagByIdRaw, requiredStationIdsRaw)

	for _, stationId in stationIds do
		local stationTag = stationTagByIdRaw[stationId]
		if stationTag == nil then
			continue
		end

		local taggedStations = TagBinder.getTagged(stationTag, CollectionService)
		for _, stationInstance in taggedStations do
			local stationPosition = StationDetector.ResolveInstancePosition(stationInstance)
			if stationPosition == nil then
				continue
			end
			local offset = stationPosition - worldPositionRaw
			if offset:Dot(offset) <= radiusSquared then
				activeStations[stationId] = true
				break
			end
		end
	end

	return activeStations
end

function StationDetector.GetStationsNearPlayer(
	playerRaw: any,
	stationTagByIdRaw: { [string]: string },
	radiusRaw: any,
	requiredStationIdsRaw: { string }?
): { [string]: boolean }
	local playerPosition = CraftingServiceUtils.ResolvePlayerRootPosition(playerRaw)
	if playerPosition == nil then
		return {}
	end
	return StationDetector.GetStationsNearPosition(playerPosition, stationTagByIdRaw, radiusRaw, requiredStationIdsRaw)
end

type ClientStationDetectorRuntime = {
	localPlayer: Player,
	stationTagById: { [string]: string },
	stationIds: { string },
	radius: number,
	scanIntervalSeconds: number,
	accumulator: number,
	activeStations: { [string]: boolean },
	onStationsChanged: ((activeStations: { [string]: boolean }, rootPosition: Vector3?) -> ())?,
	heartbeatConnection: RBXScriptConnection?,
	characterAddedConnection: RBXScriptConnection?,
	running: boolean,
}

function StationDetector.NewClientDetector(optionsRaw: any): ClientStationDetector
	local options = if typeof(optionsRaw) == "table" then (optionsRaw :: { [string]: any }) else {}
	local localPlayer = if typeof(options.localPlayer) == "Instance" and options.localPlayer:IsA("Player")
		then options.localPlayer
		else Players.LocalPlayer

	local stationTagById: { [string]: string } = {}
	if typeof(options.stationTagById) == "table" then
		for stationIdRaw, tagRaw in options.stationTagById do
			local stationId = sanitizeString(stationIdRaw, nil)
			local tag = sanitizeString(tagRaw, nil)
			if stationId ~= nil and tag ~= nil then
				stationTagById[stationId] = tag
			end
		end
	end

	local stationIds = resolveStationIdScanList(stationTagById, cloneStringArray(options.stationIds))
	local runtime: ClientStationDetectorRuntime = {
		localPlayer = localPlayer,
		stationTagById = stationTagById,
		stationIds = stationIds,
		radius = sanitizeNumber(options.radius, DEFAULT_STATION_SCAN_RADIUS, 1, 1000),
		scanIntervalSeconds = sanitizeNumber(options.scanIntervalSeconds, 1 / DEFAULT_STATION_SCAN_RATE_HZ, 1 / 60, 3),
		accumulator = 0,
		activeStations = {},
		onStationsChanged = if typeof(options.onStationsChanged) == "function"
			then options.onStationsChanged
			else nil,
		heartbeatConnection = nil,
		characterAddedConnection = nil,
		running = false,
	}

	local detector = {} :: any

	function detector:ForceScan()
		local rootPosition = CraftingServiceUtils.ResolvePlayerRootPosition(runtime.localPlayer)
		local nextStations = if rootPosition ~= nil
			then StationDetector.GetStationsNearPosition(
				rootPosition,
				runtime.stationTagById,
				runtime.radius,
				runtime.stationIds
			)
			else {}

		if stringSetEquals(runtime.activeStations, nextStations) then
			return
		end
		runtime.activeStations = nextStations

		local onChanged = runtime.onStationsChanged
		if onChanged ~= nil then
			onChanged(cloneStringSet(nextStations), rootPosition)
		end
	end

	function detector:GetActiveStations(): { [string]: boolean }
		return cloneStringSet(runtime.activeStations)
	end

	function detector:Start()
		if runtime.running then
			return
		end
		runtime.running = true
		runtime.accumulator = runtime.scanIntervalSeconds
		self:forceScan()

		runtime.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
			runtime.accumulator += dt
			if runtime.accumulator < runtime.scanIntervalSeconds then
				return
			end
			runtime.accumulator = 0
			self:forceScan()
		end)

		runtime.characterAddedConnection = runtime.localPlayer.CharacterAdded:Connect(function()
			runtime.accumulator = runtime.scanIntervalSeconds
			self:forceScan()
		end)
	end

	function detector:Stop()
		runtime.running = false
		if runtime.heartbeatConnection ~= nil then
			runtime.heartbeatConnection:Disconnect()
			runtime.heartbeatConnection = nil
		end
		if runtime.characterAddedConnection ~= nil then
			runtime.characterAddedConnection:Disconnect()
			runtime.characterAddedConnection = nil
		end
	end

	function detector:Destroy()
		self:stop()
		runtime.activeStations = {}
	end

	detector.forceScan = detector.ForceScan
	detector.getActiveStations = detector.GetActiveStations
	detector.start = detector.Start
	detector.stop = detector.Stop
	detector.destroy = detector.Destroy

	return detector :: ClientStationDetector
end

local CraftTransaction = {}
CraftingServiceUtils.CraftTransaction = CraftTransaction

local function normalizeTransactionMutationResult(resultRaw: any, fieldName: string): number
	if typeof(resultRaw) ~= "table" then
		return 0
	end
	local value = (resultRaw :: any)[fieldName]
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.max(0, math.floor(value))
end

function CraftTransaction.CreateInventoryProvider(inventoryServiceRaw: any, playerDataServiceRaw: any?): InventoryProvider
	local inventoryService = inventoryServiceRaw
	local playerDataService = playerDataServiceRaw
	local provider = {} :: any

	local function resolveCoinKey(itemIdRaw: any): string?
		local itemId = sanitizeString(itemIdRaw, nil)
		if itemId == nil then
			return nil
		end
		return COIN_ITEM_ID_TO_KEY[itemId]
	end

	local function getCoinBalance(player: Player, itemIdRaw: any): number
		local coinKey = resolveCoinKey(itemIdRaw)
		if coinKey == nil then
			return 0
		end
		if typeof(playerDataService) ~= "table" then
			return 0
		end
		local getCoinsDataMethod = (playerDataService :: any).getCoinsData
		if typeof(getCoinsDataMethod) ~= "function" then
			return 0
		end
		local ok, coinsData = pcall(function()
			return (playerDataService :: any):getCoinsData(player, nil)
		end)
		if not ok or typeof(coinsData) ~= "table" then
			return 0
		end
		local resolvedCoinAmounts = resolveCoinAmountsFromData(coinsData)
		return sanitizeInteger(resolvedCoinAmounts[coinKey], 0, 0, COIN_ITEM_MAX_AMOUNT)
	end

	local function getCoinWallet(player: Player): { [string]: number }?
		if typeof(playerDataService) ~= "table" then
			return nil
		end
		local getCoinsDataMethod = (playerDataService :: any).getCoinsData
		if typeof(getCoinsDataMethod) ~= "function" then
			return nil
		end
		local ok, coinsData = pcall(function()
			return (playerDataService :: any):getCoinsData(player, nil)
		end)
		if not ok then
			return nil
		end
		local resolvedCoinAmounts = resolveCoinAmountsFromData(coinsData)
		return {
			copper = sanitizeInteger(resolvedCoinAmounts.copper, 0, 0, COIN_ITEM_MAX_AMOUNT),
			silver = sanitizeInteger(resolvedCoinAmounts.silver, 0, 0, COIN_ITEM_MAX_AMOUNT),
			gold = sanitizeInteger(resolvedCoinAmounts.gold, 0, 0, COIN_ITEM_MAX_AMOUNT),
			platinum = sanitizeInteger(resolvedCoinAmounts.platinum, 0, 0, COIN_ITEM_MAX_AMOUNT),
		}
	end

	local function incrementCoinBalance(player: Player, itemIdRaw: any, amountRaw: any): number?
		local coinKey = resolveCoinKey(itemIdRaw)
		if coinKey == nil then
			return nil
		end
		if typeof(playerDataService) ~= "table" then
			return nil
		end
		local setCoinsDataMethod = (playerDataService :: any).setCoinsData
		if typeof(setCoinsDataMethod) ~= "function" then
			return nil
		end
		local currentWallet = getCoinWallet(player)
		if currentWallet == nil then
			return nil
		end
		local amount = if typeof(amountRaw) == "number" and amountRaw == amountRaw then math.floor(amountRaw) else 0
		local nextValue = sanitizeInteger(currentWallet[coinKey], 0, 0, COIN_ITEM_MAX_AMOUNT) + amount
		if nextValue < 0 or nextValue > COIN_ITEM_MAX_AMOUNT then
			return nextValue
		end
		currentWallet[coinKey] = nextValue
		local didSet = false
		local ok = pcall(function()
			didSet = (playerDataService :: any):setCoinsData(player, currentWallet, true) == true
		end)
		if not ok or not didSet then
			return nil
		end
		return nextValue
	end

	function provider:IsReady(player: Player): boolean
		if typeof(inventoryService) ~= "table" then
			return false
		end
		local getStateMethod = (inventoryService :: any).getState
		if typeof(getStateMethod) ~= "function" then
			return false
		end

		local ok, stateOrError = pcall(function()
			return (inventoryService :: any):getState(player)
		end)
		if not ok then
			return false
		end
		if typeof(stateOrError) ~= "table" then
			return false
		end
		return InventoryServiceUtils.isLoadedState((stateOrError :: any).loadState)
	end

	function provider:CountItem(player: Player, itemId: string): number
		local coinBalance = getCoinBalance(player, itemId)
		if coinBalance > 0 or resolveCoinKey(itemId) ~= nil then
			return coinBalance
		end
		if typeof(inventoryService) ~= "table" then
			return 0
		end
		local countMethod = (inventoryService :: any).countItem
		if typeof(countMethod) ~= "function" then
			return 0
		end
		local ok, countOrError = pcall(function()
			return (inventoryService :: any):countItem(player, itemId, nil, false)
		end)
		if not ok or typeof(countOrError) ~= "number" or countOrError ~= countOrError then
			return 0
		end
		return math.max(0, math.floor(countOrError))
	end

	local function countRequirementItems(player: Player, requirement: ItemAmount): number
		local total = 0
		for _, candidateItemId in resolveRequirementItemIds(requirement) do
			total += provider:CountItem(player, candidateItemId)
		end
		return total
	end

	function provider:HasItems(player: Player, requirements: { ItemAmount }): boolean
		for _, requirement in requirements do
			if countRequirementItems(player, requirement) < requirement.amount then
				return false
			end
		end
		return true
	end

	function provider:ConsumeItems(player: Player, requirements: { ItemAmount }): (boolean, { ItemAmount }, string?)
		local consumed: { ItemAmount } = {}
		if typeof(inventoryService) ~= "table" then
			return false, consumed, "inventory_unavailable"
		end
		local removeMethod = (inventoryService :: any).removeItem
		if typeof(removeMethod) ~= "function" then
			return false, consumed, "inventory_unavailable"
		end

		for _, requirement in requirements do
			local coinKey = resolveCoinKey(requirement.itemId)
			if coinKey ~= nil then
				if self:CountItem(player, requirement.itemId) < requirement.amount then
					return false, consumed, "insufficient_ingredients"
				end
				local nextValue = incrementCoinBalance(player, requirement.itemId, -requirement.amount)
				if nextValue == nil or nextValue < 0 then
					if nextValue ~= nil and nextValue < 0 then
						incrementCoinBalance(player, requirement.itemId, requirement.amount)
					end
					return false, consumed, "consume_failed"
				end
				appendMergedItemAmount(consumed, requirement.itemId, requirement.amount)
				continue
			end
			local remaining = requirement.amount
			if countRequirementItems(player, requirement) < remaining then
				return false, consumed, "insufficient_ingredients"
			end
			for _, candidateItemId in resolveRequirementItemIds(requirement) do
				if remaining <= 0 then
					break
				end

				local available = self:CountItem(player, candidateItemId)
				if available <= 0 then
					continue
				end

				local toRemove = math.min(remaining, available)
				local ok, resultOrError = pcall(function()
					return (inventoryService :: any):removeItem(player, candidateItemId, toRemove)
				end)
				if not ok then
					return false, consumed, "consume_failed"
				end

				local removed = normalizeTransactionMutationResult(resultOrError, "removed")
				if removed > 0 then
					appendMergedItemAmount(consumed, candidateItemId, removed)
					remaining -= removed
				end
			end
			if remaining > 0 then
				return false, consumed, "insufficient_ingredients"
			end
		end

		return true, consumed, nil
	end

	function provider:GrantItems(player: Player, grantItems: { ItemAmount }): (boolean, { ItemAmount }, string?)
		local granted: { ItemAmount } = {}
		if typeof(inventoryService) ~= "table" then
			return false, granted, "inventory_unavailable"
		end
		local addMethod = (inventoryService :: any).addItem
		if typeof(addMethod) ~= "function" then
			return false, granted, "inventory_unavailable"
		end

		for _, grantItem in grantItems do
			if resolveCoinKey(grantItem.itemId) ~= nil then
				local currentAmount = getCoinBalance(player, grantItem.itemId)
				if currentAmount + grantItem.amount > COIN_ITEM_MAX_AMOUNT then
					return false, granted, "inventory_full"
				end
				local nextValue = incrementCoinBalance(player, grantItem.itemId, grantItem.amount)
				if nextValue == nil then
					return false, granted, "grant_failed"
				end
				appendMergedItemAmount(granted, grantItem.itemId, grantItem.amount)
				continue
			end

			local ok, resultOrError = pcall(function()
				return (inventoryService :: any):addItem(player, grantItem.itemId, grantItem.amount, {
					stackIdPrefix = "craft",
				})
			end)
			if not ok then
				return false, granted, "grant_failed"
			end

			local added = normalizeTransactionMutationResult(resultOrError, "added")
			if added > 0 then
				appendMergedItemAmount(granted, grantItem.itemId, added)
			end
			if added < grantItem.amount then
				return false, granted, "inventory_full"
			end
		end

		return true, granted, nil
	end

	function provider:RestoreItems(player: Player, restoreItems: { ItemAmount }): boolean
		if #restoreItems <= 0 then
			return true
		end
		if typeof(inventoryService) ~= "table" then
			return false
		end
		local addMethod = (inventoryService :: any).addItem
		if typeof(addMethod) ~= "function" then
			return false
		end

		local restoredEverything = true
		for _, restoreItem in restoreItems do
			if resolveCoinKey(restoreItem.itemId) ~= nil then
				local currentAmount = getCoinBalance(player, restoreItem.itemId)
				if currentAmount + restoreItem.amount > COIN_ITEM_MAX_AMOUNT then
					restoredEverything = false
					continue
				end
				local nextValue = incrementCoinBalance(player, restoreItem.itemId, restoreItem.amount)
				if nextValue == nil then
					restoredEverything = false
				end
				continue
			end

			local ok, resultOrError = pcall(function()
				return (inventoryService :: any):addItem(player, restoreItem.itemId, restoreItem.amount, {
					stackIdPrefix = "craftRollback",
				})
			end)
			local added = if ok then normalizeTransactionMutationResult(resultOrError, "added") else 0
			if (not ok) or added < restoreItem.amount then
				restoredEverything = false
			end
		end

		return restoredEverything
	end

	function provider:RevokeItems(player: Player, revokeItems: { ItemAmount }): boolean
		if #revokeItems <= 0 then
			return true
		end
		if typeof(inventoryService) ~= "table" then
			return false
		end
		local removeMethod = (inventoryService :: any).removeItem
		if typeof(removeMethod) ~= "function" then
			return false
		end

		local revokedEverything = true
		for _, revokeItem in revokeItems do
			if resolveCoinKey(revokeItem.itemId) ~= nil then
				if self:CountItem(player, revokeItem.itemId) < revokeItem.amount then
					revokedEverything = false
				else
					local nextValue = incrementCoinBalance(player, revokeItem.itemId, -revokeItem.amount)
					if nextValue == nil or nextValue < 0 then
						if nextValue ~= nil and nextValue < 0 then
							incrementCoinBalance(player, revokeItem.itemId, revokeItem.amount)
						end
						revokedEverything = false
					end
				end
				continue
			end

			local ok, resultOrError = pcall(function()
				return (inventoryService :: any):removeItem(player, revokeItem.itemId, revokeItem.amount)
			end)
			local removed = if ok then normalizeTransactionMutationResult(resultOrError, "removed") else 0
			if (not ok) or removed < revokeItem.amount then
				revokedEverything = false
			end
		end

		return revokedEverything
	end

	return provider :: InventoryProvider
end

function CraftTransaction.Execute(
	providerRaw: InventoryProvider,
	player: Player,
	recipeRaw: RecipeDefinition,
	quantityRaw: any
): CraftTransactionResult
	local quantity = sanitizeInteger(quantityRaw, 1, 1, 999)
	local scaledIngredients = CraftingServiceUtils.ScaleItemAmounts(recipeRaw.ingredients, quantity)
	local scaledResults = CraftingServiceUtils.ScaleItemAmounts(recipeRaw.results, quantity)

	local failedResult = function(reason: string, consumedRaw: { ItemAmount }?, grantedRaw: { ItemAmount }?): CraftTransactionResult
		return {
			success = false,
			reason = reason,
			recipeId = recipeRaw.id,
			quantity = quantity,
			consumed = if consumedRaw ~= nil then consumedRaw else {},
			granted = if grantedRaw ~= nil then grantedRaw else {},
		}
	end

	if not providerRaw:IsReady(player) then
		return failedResult("inventory_not_ready")
	end
	if not providerRaw:HasItems(player, scaledIngredients) then
		return failedResult("insufficient_ingredients")
	end

	local didConsume, consumedItems, consumeReason = providerRaw:ConsumeItems(player, scaledIngredients)
	if not didConsume then
		providerRaw:RestoreItems(player, consumedItems)
		return failedResult(consumeReason or "consume_failed", consumedItems)
	end

	local didGrant, grantedItems, grantReason = providerRaw:GrantItems(player, scaledResults)
	if not didGrant then
		local revokedGrantedItems = providerRaw:RevokeItems(player, grantedItems)
		if revokedGrantedItems then
			providerRaw:RestoreItems(player, consumedItems)
		end
		return failedResult(if revokedGrantedItems then (grantReason or "grant_failed") else "grant_rollback_failed", consumedItems, grantedItems)
	end

	return {
		success = true,
		reason = nil,
		recipeId = recipeRaw.id,
		quantity = quantity,
		consumed = consumedItems,
		granted = grantedItems,
	}
end

CraftingServiceUtils.cloneStringSet = CraftingServiceUtils.CloneStringSet
CraftingServiceUtils.cloneStringArray = CraftingServiceUtils.CloneStringArray
CraftingServiceUtils.stringSetEquals = CraftingServiceUtils.StringSetEquals
CraftingServiceUtils.stringArrayEquals = CraftingServiceUtils.StringArrayEquals
CraftingServiceUtils.getDefaultDataPath = CraftingServiceUtils.GetDefaultDataPath
CraftingServiceUtils.resolveConfig = CraftingServiceUtils.ResolveConfig
CraftingServiceUtils.resolveEffectiveConfig = CraftingServiceUtils.ResolveEffectiveConfig
CraftingServiceUtils.normalizeBiomeToken = CraftingServiceUtils.NormalizeBiomeToken
CraftingServiceUtils.resolveBiomeTokens = CraftingServiceUtils.ResolveBiomeTokens
CraftingServiceUtils.resolveBiomeTokensFromWorldService = CraftingServiceUtils.ResolveBiomeTokensFromWorldService
CraftingServiceUtils.resolvePlayerRootPosition = CraftingServiceUtils.ResolvePlayerRootPosition
CraftingServiceUtils.scaleItemAmounts = CraftingServiceUtils.ScaleItemAmounts
CraftingServiceUtils.cloneItemAmounts = CraftingServiceUtils.CloneItemAmounts
CraftingServiceUtils.buildInventoryItemCountMap = CraftingServiceUtils.BuildInventoryItemCountMap
RecipeIndexer.buildRegistry = RecipeIndexer.BuildRegistry
CraftingServiceUtils.getRegistry = CraftingServiceUtils.GetRegistry
RecipeValidator.sanitizeCraftRequest = RecipeValidator.SanitizeCraftRequest
RecipeValidator.isRecipeKnown = RecipeValidator.IsRecipeKnown
RecipeValidator.getMissingStations = RecipeValidator.GetMissingStations
RecipeValidator.areStationsSatisfied = RecipeValidator.AreStationsSatisfied
RecipeValidator.areUnlockConditionsSatisfied = RecipeValidator.AreUnlockConditionsSatisfied
RecipeValidator.isBiomeSatisfied = RecipeValidator.IsBiomeSatisfied
CraftingServiceUtils.createDefaultPersistentState = CraftingServiceUtils.CreateDefaultPersistentState
CraftingServiceUtils.sanitizePersistentState = CraftingServiceUtils.SanitizePersistentState
CraftingServiceUtils.serializePersistentState = CraftingServiceUtils.SerializePersistentState
CraftingServiceUtils.createDefaultServiceStateSnapshot = CraftingServiceUtils.CreateDefaultServiceStateSnapshot
CraftingServiceUtils.sanitizeServiceStateSnapshot = CraftingServiceUtils.SanitizeServiceStateSnapshot
CraftingServiceUtils.buildAvailableRecipeIds = CraftingServiceUtils.BuildAvailableRecipeIds
CraftingServiceUtils.computeMaxCraftableQuantity = CraftingServiceUtils.ComputeMaxCraftableQuantity
CraftingServiceUtils.buildRecipePreview = CraftingServiceUtils.BuildRecipePreview
CraftingServiceUtils.filterRecipeIds = CraftingServiceUtils.FilterRecipeIds
CraftingServiceUtils.buildCategoryList = CraftingServiceUtils.BuildCategoryList
StationDetector.resolveInstancePosition = StationDetector.ResolveInstancePosition
StationDetector.getStationsNearPosition = StationDetector.GetStationsNearPosition
StationDetector.getStationsNearPlayer = StationDetector.GetStationsNearPlayer
StationDetector.newClientDetector = StationDetector.NewClientDetector
CraftTransaction.createInventoryProvider = CraftTransaction.CreateInventoryProvider
CraftTransaction.execute = CraftTransaction.Execute

return CraftingServiceUtils
