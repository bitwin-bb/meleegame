--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CraftingServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.CraftingService.CraftingServiceUtils)
local SnackbarNotifications = require(script:FindFirstAncestor("game").Client.SnackbarNotifications)
local InventoryServiceClient = require(script:FindFirstAncestor("game").Client.Services.InventoryService.InventoryServiceClient)
local PlayerDataServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerDataService.PlayerDataServiceClient)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationService.WorldGenerationServiceClient)

type RecipeRegistry = CraftingServiceUtils.RecipeRegistry
type CraftingServiceConfig = CraftingServiceUtils.CraftingServiceConfig
type CraftingServiceStateSnapshot = CraftingServiceUtils.CraftingServiceStateSnapshot
type RecipePreview = CraftingServiceUtils.RecipePreview
type ClientStationDetector = CraftingServiceUtils.ClientStationDetector

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: { [string]: any }) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, payload: { [string]: any }) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type CachedRecipeList = {
	filterRevision: number,
	inventoryRevision: number,
	recipes: { [string]: any },
}

local CraftingServiceClient = {}

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function cloneCountMap(countsRaw: { [string]: number }): { [string]: number }
	local output: { [string]: number } = {}
	for key, value in countsRaw do
		output[key] = value
	end
	return output
end

local function countMapEquals(lhs: { [string]: number }, rhs: { [string]: number }): boolean
	for key, lhsValue in lhs do
		if rhs[key] ~= lhsValue then
			return false
		end
	end
	for key, rhsValue in rhs do
		if lhs[key] ~= rhsValue then
			return false
		end
	end
	return true
end

local function cloneRecipeEntries(entriesRaw: { [string]: any }): { [string]: any }
	local output = {}
	for _, entry in entriesRaw do
		table.insert(output, entry)
	end
	return output
end

local function buildRecipeListCacheKey(categoryRaw: any, searchRaw: any): string
	local category = trim(categoryRaw)
	local search = string.lower(trim(searchRaw))
	return (`{category}::{search}`)
end

function CraftingServiceClient.CreateInitialKnownRecipeIds(
	self: CraftingServiceClient,
	registry: RecipeRegistry
): { [string]: boolean }
	local knownRecipeIds: { [string]: boolean } = {}
	for recipeId, enabled in registry.defaultKnownRecipeIds do
		if enabled then
			knownRecipeIds[recipeId] = true
		end
	end
	return knownRecipeIds
end

function CraftingServiceClient.ResolveLocalBiomeTokens(self: CraftingServiceClient): { [string]: boolean }
	local rootPosition = CraftingServiceUtils.resolvePlayerRootPosition(self.localPlayer)
	if rootPosition == nil then
		return {}
	end
	return CraftingServiceUtils.resolveBiomeTokensFromWorldService(WorldGenerationServiceClient, rootPosition)
end

function CraftingServiceClient.InvalidateCachedLists(self: CraftingServiceClient)
	table.clear(self.cachedRecipeLists)
end

function CraftingServiceClient.EmitStateChanged(self: CraftingServiceClient)
	self.stateChanged:Fire(self:getState())
end

function CraftingServiceClient.RefreshAvailableRecipeIds(self: CraftingServiceClient, forceRaw: any?): boolean
	local nextAvailableRecipeIds = CraftingServiceUtils.buildAvailableRecipeIds(
		self.registry,
		self.serverState.knownRecipeIds,
		self.activeStations,
		self.currentBiomeTokens
	)

	local didChange = forceRaw == true
	if not didChange then
		didChange = not CraftingServiceUtils.stringArrayEquals(self.availableRecipeIds, nextAvailableRecipeIds)
	end
	if not didChange then
		return false
	end

	self.availableRecipeIds = nextAvailableRecipeIds
	self.availableCategories = CraftingServiceUtils.buildCategoryList(self.registry, nextAvailableRecipeIds)
	self.filterRevision += 1
	self:invalidateCachedLists()
	return true
end

function CraftingServiceClient.SetActiveStations(self: CraftingServiceClient, nextStationsRaw: { [string]: boolean }): boolean
	local nextStations = CraftingServiceUtils.cloneStringSet(nextStationsRaw)
	if CraftingServiceUtils.stringSetEquals(self.activeStations, nextStations) then
		return false
	end
	self.activeStations = nextStations
	self:refreshAvailableRecipeIds(true)
	self:emitStateChanged()
	return true
end

function CraftingServiceClient.RefreshBiomeTokens(self: CraftingServiceClient): boolean
	local nextBiomeTokens = self:resolveLocalBiomeTokens()
	if CraftingServiceUtils.stringSetEquals(self.currentBiomeTokens, nextBiomeTokens) then
		return false
	end
	self.currentBiomeTokens = nextBiomeTokens
	self:refreshAvailableRecipeIds(true)
	self:emitStateChanged()
	return true
end

function CraftingServiceClient.ApplyInventoryState(self: CraftingServiceClient, stateRaw: any, coinsDataRaw: any?): boolean
	local nextCounts = CraftingServiceUtils.buildInventoryItemCountMap(stateRaw, coinsDataRaw)
	if countMapEquals(self.inventoryItemCounts, nextCounts) then
		return false
	end
	self.inventoryItemCounts = nextCounts
	self.inventoryRevision += 1
	self:invalidateCachedLists()
	self:emitStateChanged()
	return true
end

function CraftingServiceClient.HandleStationsChanged(
	self: CraftingServiceClient,
	nextStations: { [string]: boolean },
	rootPosition: Vector3?
)
	self:setActiveStations(nextStations)
	if rootPosition ~= nil then
		self:refreshBiomeTokens()
	end
end

function CraftingServiceClient.ApplyState(self: CraftingServiceClient, stateRaw: any)
	local fallback = self.serverState
	local nextState = CraftingServiceUtils.sanitizeServiceStateSnapshot(stateRaw, fallback)
	if CraftingServiceUtils.stringSetEquals(self.serverState.knownRecipeIds, nextState.knownRecipeIds)
		and CraftingServiceUtils.stringSetEquals(self.serverState.discoveredItemIds, nextState.discoveredItemIds)
		and CraftingServiceUtils.stringSetEquals(self.serverState.progressionFlags, nextState.progressionFlags)
	then
		self.serverState = nextState
		return
	end

	self.serverState = nextState
	self:refreshAvailableRecipeIds(true)
	self:emitStateChanged()
end

function CraftingServiceClient.OnCraftResult(self: CraftingServiceClient, resultRaw: any)
	local source = if typeof(resultRaw) == "table" then (resultRaw :: { [string]: any }) else {}
	self.lastCraftResult = {
		success = source.success == true,
		reason = if typeof(source.reason) == "string" then source.reason else nil,
		recipeId = if typeof(source.recipeId) == "string" then source.recipeId else nil,
		quantity = if typeof(source.quantity) == "number" and source.quantity == source.quantity
			then math.max(0, math.floor(source.quantity))
			else 0,
		updatedAt = os.clock(),
	}
	if self.lastCraftResult.success ~= true or self.bulkCraftToken == nil then
		SnackbarNotifications.showCraftResult(self.lastCraftResult, self)
	end
	self:emitStateChanged()
end

function CraftingServiceClient.RequestSync(self: CraftingServiceClient)
	self.networker:fire(CraftingServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function CraftingServiceClient.RequestCraft(
	self: CraftingServiceClient,
	recipeIdRaw: any,
	quantityRaw: any
): boolean
	local recipeId, quantity = CraftingServiceUtils.RecipeValidator.sanitizeCraftRequest(
		recipeIdRaw,
		quantityRaw,
		self.config.maxCraftQuantityPerRequest
	)
	if recipeId == nil or quantity <= 0 then
		return false
	end

	local now = os.clock()
	if now - self.lastCraftRequestAt < self.config.clientRequestThrottleSeconds then
		return false
	end

	self.lastCraftRequestAt = now
	self.networker:fire(CraftingServiceUtils.NETWORK_METHOD_REQUEST_CRAFT, recipeId, quantity)
	return true
end

function CraftingServiceClient.StopBulkCraft(self: CraftingServiceClient): boolean
	if self.bulkCraftToken == nil then
		return false
	end
	self.bulkCraftToken = nil
	self:emitStateChanged()
	return true
end

function CraftingServiceClient.StartBulkCraft(
	self: CraftingServiceClient,
	recipeIdRaw: any,
	quantityRaw: any
): boolean
	local recipeId, quantity = CraftingServiceUtils.RecipeValidator.sanitizeCraftRequest(
		recipeIdRaw,
		quantityRaw,
		self.config.maxCraftQuantityPerRequest
	)
	if recipeId == nil or quantity <= 0 then
		return false
	end

	self:stopBulkCraft()
	local token = {}
	self.bulkCraftToken = token
	self:emitStateChanged()

	task.spawn(function()
		while self.bulkCraftToken == token do
			local preview = self:getRecipePreview(recipeId, quantity)
			if preview == nil or preview.canCraft ~= true then
				break
			end

			self:requestCraft(recipeId, quantity)
			task.wait(self.config.bulkCraftIntervalSeconds)
		end

		if self.bulkCraftToken == token then
			self.bulkCraftToken = nil
			self:emitStateChanged()
		end
	end)

	return true
end

function CraftingServiceClient.GetRecipePreview(
	self: CraftingServiceClient,
	recipeIdRaw: any,
	quantityRaw: any
): RecipePreview?
	local recipeId = trim(recipeIdRaw)
	if recipeId == "" then
		return nil
	end
	local recipe = self.registry.recipesById[recipeId]
	if recipe == nil then
		return nil
	end

	return CraftingServiceUtils.buildRecipePreview(
		recipe,
		self.inventoryItemCounts,
		quantityRaw,
		self.activeStations,
		self.currentBiomeTokens,
		self.serverState.knownRecipeIds
	)
end

function CraftingServiceClient.GetRecipes(self: CraftingServiceClient, optionsRaw: any?): { [string]: any }
	local options = if typeof(optionsRaw) == "table" then (optionsRaw :: { [string]: any }) else {}
	local category = trim(options.category)
	local searchText = trim(options.searchText)
	if category == "" then
		category = self.categoryFilter
	end
	if searchText == "" then
		searchText = self.searchQuery
	end
	local cacheKey = buildRecipeListCacheKey(category, searchText)
	local cached = self.cachedRecipeLists[cacheKey]
	if cached ~= nil then
		if cached.filterRevision == self.filterRevision and cached.inventoryRevision == self.inventoryRevision then
			return cloneRecipeEntries(cached.recipes)
		end
	end

	local filteredRecipeIds = CraftingServiceUtils.filterRecipeIds(
		self.registry,
		self.availableRecipeIds,
		if category ~= "" then category else nil,
		if searchText ~= "" then searchText else nil
	)

	local entries = {}
	for _, recipeId in filteredRecipeIds do
		local recipe = self.registry.recipesById[recipeId]
		if recipe == nil then
			continue
		end
		local preview = self:getRecipePreview(recipeId, 1)
		table.insert(entries, {
			recipeId = recipe.id,
			displayName = recipe.displayName,
			category = recipe.category,
			resultItemId = if #recipe.results > 0 then recipe.results[1].itemId else nil,
			groupId = self.registry.groupIdByRecipeId[recipe.id],
			sortOrder = recipe.sortOrder,
			isHidden = recipe.isHidden,
			canCraft = if preview ~= nil then preview.canCraft else false,
			maxCraftableQuantity = if preview ~= nil then preview.maxCraftableQuantity else 0,
			preview = preview,
		})
	end

	self.cachedRecipeLists[cacheKey] = {
		filterRevision = self.filterRevision,
		inventoryRevision = self.inventoryRevision,
		recipes = entries,
	}

	return cloneRecipeEntries(entries)
end

function CraftingServiceClient.GetRecipesByCategory(self: CraftingServiceClient, searchTextRaw: any?): { [string]: { [string]: any } }
	local searchText = trim(searchTextRaw)
	local byCategory: { [string]: { [string]: any } } = {}
	local entries = self:getRecipes({
		searchText = searchText,
	})
	for _, entry in entries do
		local category = if typeof(entry.category) == "string" then entry.category else "Misc"
		local list = byCategory[category]
		if list == nil then
			list = {}
			byCategory[category] = list
		end
		table.insert(list, entry)
	end
	return byCategory
end

function CraftingServiceClient.GetCategoryTabs(self: CraftingServiceClient): { string }
	return CraftingServiceUtils.cloneStringArray(self.availableCategories)
end

function CraftingServiceClient.SetSearchQuery(self: CraftingServiceClient, queryRaw: any): boolean
	local nextQuery = trim(queryRaw)
	if self.searchQuery == nextQuery then
		return false
	end
	self.searchQuery = nextQuery
	self:emitStateChanged()
	return true
end

function CraftingServiceClient.SetCategoryFilter(self: CraftingServiceClient, categoryRaw: any): boolean
	local nextCategory = trim(categoryRaw)
	if nextCategory == "" then
		nextCategory = ""
	end
	if self.categoryFilter == nextCategory then
		return false
	end
	self.categoryFilter = nextCategory
	self:emitStateChanged()
	return true
end

function CraftingServiceClient.GetState(self: CraftingServiceClient): { [string]: any }
	return {
		knownRecipeIds = CraftingServiceUtils.cloneStringSet(self.serverState.knownRecipeIds),
		discoveredItemIds = CraftingServiceUtils.cloneStringSet(self.serverState.discoveredItemIds),
		progressionFlags = CraftingServiceUtils.cloneStringSet(self.serverState.progressionFlags),
		activeStations = CraftingServiceUtils.cloneStringSet(self.activeStations),
		currentBiomeTokens = CraftingServiceUtils.cloneStringSet(self.currentBiomeTokens),
		inventoryItemCounts = cloneCountMap(self.inventoryItemCounts),
		availableRecipeIds = CraftingServiceUtils.cloneStringArray(self.availableRecipeIds),
		availableCategories = CraftingServiceUtils.cloneStringArray(self.availableCategories),
		searchQuery = self.searchQuery,
		categoryFilter = self.categoryFilter,
		lastCraftResult = self.lastCraftResult,
		isBulkCrafting = self.bulkCraftToken ~= nil,
		updatedAt = os.clock(),
	}
end

function CraftingServiceClient.Init(self: CraftingServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.config = CraftingServiceUtils.resolveEffectiveConfig((Configs :: any).crafting)
	self.registry = CraftingServiceUtils.getRegistry(self.config)
	self.networker = Networker.client.new("CraftingService", self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.serverState = CraftingServiceUtils.createDefaultServiceStateSnapshot(self.registry)
	self.serverState.knownRecipeIds = self:createInitialKnownRecipeIds(self.registry)
	self.activeStations = {}
	self.currentBiomeTokens = {}
	self.inventoryItemCounts = {}
	self.availableRecipeIds = {}
	self.availableCategories = {}
	self.cachedRecipeLists = {}
	self.filterRevision = 0
	self.inventoryRevision = 0
	self.searchQuery = ""
	self.categoryFilter = ""
	self.lastCraftResult = nil
	self.lastCraftRequestAt = -math.huge
	self.bulkCraftToken = nil
	self.biomeScanAccumulator = 1 / self.config.biomeScanRateHz
	self.biomeScanIntervalSeconds = 1 / self.config.biomeScanRateHz

	local stationDetector = CraftingServiceUtils.StationDetector.newClientDetector({
		localPlayer = self.localPlayer,
		stationTagById = self.registry.stationTagById,
		stationIds = nil,
		radius = self.config.stationScanRadius,
		scanIntervalSeconds = 1 / self.config.stationScanRateHz,
		onStationsChanged = function(nextStations: { [string]: boolean }, rootPosition: Vector3?)
			self:handleStationsChanged(nextStations, rootPosition)
		end,
	})
	self.stationDetector = stationDetector
	self.stationDetector:start()

	local initialInventoryState = InventoryServiceClient:getState()
	local initialCoinsData = PlayerDataServiceClient:getCoinsData(nil)
	self:applyInventoryState(initialInventoryState, initialCoinsData)
	self.currentBiomeTokens = self:resolveLocalBiomeTokens()
	self:refreshAvailableRecipeIds(true)

	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: any)
			self:applyInventoryState(nextState, PlayerDataServiceClient:getCoinsData(nil))
		end))
	end

	if PlayerDataServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(PlayerDataServiceClient.stateChanged:Connect(function(nextState: any)
			local coinsData = nil
			if typeof(nextState) == "table" then
				local data = (nextState :: any).data
				if typeof(data) == "table" then
					coinsData = (data :: any).coins
				end
			end
			self:applyInventoryState(InventoryServiceClient:getState(), coinsData)
		end))
	end

	self.janitor:GiveChore(RunService.Heartbeat:Connect(function(dt: number)
		self.biomeScanAccumulator += dt
		if self.biomeScanAccumulator < self.biomeScanIntervalSeconds then
			return
		end
		self.biomeScanAccumulator = 0
		self:refreshBiomeTokens()
	end))

	self.janitor:GiveChore(function()
		if self.stationDetector ~= nil then
			self.stationDetector:destroy()
		end
	end)
	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:requestSync()
	self:emitStateChanged()
end

function CraftingServiceClient.Destroy(self: CraftingServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

CraftingServiceClient.createInitialKnownRecipeIds = CraftingServiceClient.CreateInitialKnownRecipeIds
CraftingServiceClient.resolveLocalBiomeTokens = CraftingServiceClient.ResolveLocalBiomeTokens
CraftingServiceClient.invalidateCachedLists = CraftingServiceClient.InvalidateCachedLists
CraftingServiceClient.emitStateChanged = CraftingServiceClient.EmitStateChanged
CraftingServiceClient.refreshAvailableRecipeIds = CraftingServiceClient.RefreshAvailableRecipeIds
CraftingServiceClient.setActiveStations = CraftingServiceClient.SetActiveStations
CraftingServiceClient.refreshBiomeTokens = CraftingServiceClient.RefreshBiomeTokens
CraftingServiceClient.applyInventoryState = CraftingServiceClient.ApplyInventoryState
CraftingServiceClient.handleStationsChanged = CraftingServiceClient.HandleStationsChanged
CraftingServiceClient.applyState = CraftingServiceClient.ApplyState
CraftingServiceClient.onCraftResult = CraftingServiceClient.OnCraftResult
CraftingServiceClient.requestSync = CraftingServiceClient.RequestSync
CraftingServiceClient.requestCraft = CraftingServiceClient.RequestCraft
CraftingServiceClient.stopBulkCraft = CraftingServiceClient.StopBulkCraft
CraftingServiceClient.startBulkCraft = CraftingServiceClient.StartBulkCraft
CraftingServiceClient.getRecipePreview = CraftingServiceClient.GetRecipePreview
CraftingServiceClient.getRecipes = CraftingServiceClient.GetRecipes
CraftingServiceClient.getRecipesByCategory = CraftingServiceClient.GetRecipesByCategory
CraftingServiceClient.getCategoryTabs = CraftingServiceClient.GetCategoryTabs
CraftingServiceClient.setSearchQuery = CraftingServiceClient.SetSearchQuery
CraftingServiceClient.setCategoryFilter = CraftingServiceClient.SetCategoryFilter
CraftingServiceClient.getState = CraftingServiceClient.GetState
CraftingServiceClient.init = CraftingServiceClient.Init
CraftingServiceClient.destroy = CraftingServiceClient.Destroy

type CraftingServiceClient = typeof(CraftingServiceClient) & {
	localPlayer: Player,
	config: CraftingServiceConfig,
	registry: RecipeRegistry,
	networker: Networker.Client,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	serverState: CraftingServiceStateSnapshot,
	activeStations: { [string]: boolean },
	currentBiomeTokens: { [string]: boolean },
	inventoryItemCounts: { [string]: number },
	availableRecipeIds: { string },
	availableCategories: { string },
	cachedRecipeLists: { [string]: CachedRecipeList },
	filterRevision: number,
	inventoryRevision: number,
	searchQuery: string,
	categoryFilter: string,
	lastCraftResult: { [string]: any }?,
	lastCraftRequestAt: number,
	bulkCraftToken: any?,
	biomeScanAccumulator: number,
	biomeScanIntervalSeconds: number,
	stationDetector: ClientStationDetector,
}

return CraftingServiceClient :: CraftingServiceClient

