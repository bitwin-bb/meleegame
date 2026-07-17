local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ServiceBag = require("ServiceBag")
local Configs = require("CoreConfigs")
local CraftingServiceUtils = require("CraftingServiceUtils")
local InventoryServiceClient = require("InventoryServiceClient")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local CraftingServicePackets = require("NetPacketsShared").CraftingService

local function sendPacket(methodName: string, ...: any)
	local packet = CraftingServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CraftingService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = CraftingServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CraftingService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyState")
	bindPacket(self, "onCraftResult")
	bindPacket(self, "requestCraft")
	bindPacket(self, "requestSync")
end

local PlayerDataServiceClient = require("PlayerDataServiceClient")
local Signal = require("Signal")
local SnackbarNotifications = require("FeatureSnackbarNotifications")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

type RecipeRegistry = CraftingServiceUtils.RecipeRegistry
type CraftingServiceConfig = CraftingServiceUtils.CraftingServiceConfig
type CraftingServiceStateSnapshot = CraftingServiceUtils.CraftingServiceStateSnapshot
type RecipePreview = CraftingServiceUtils.RecipePreview
type ClientStationDetector = CraftingServiceUtils.ClientStationDetector

type SignalObject = Signal.Signal<...any>

type JanitorClass = any

type CachedRecipeList = {
	filterRevision: number,
	inventoryRevision: number,
	recipes: { any },
}

local CraftingServiceClient = {}
CraftingServiceClient.ServiceName = "CraftingServiceClient"

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function cloneCountMap(countsRaw: { [string]: number }): { [string]: number }
	return table.clone(countsRaw)
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

local function cloneRecipeEntries(entriesRaw: { any }): { any }
	local output: { any } = {}
	for _, entry in entriesRaw do
		table.insert(output, entry)
	end
	return output
end

local function buildRecipeListCacheKey(categoryRaw: any, searchRaw: any): string
	local category = trim(categoryRaw)
	local search = string.lower(trim(searchRaw))
	return `{category}::{search}`
end

function CraftingServiceClient.CreateInitialKnownRecipeIds(
	_self: CraftingServiceClient,
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

function CraftingServiceClient.GetLocalBiomeTokens(self: CraftingServiceClient): { [string]: boolean }
	local rootPosition = CraftingServiceUtils.GetPlayerRootPosition(self.localPlayer)
	if rootPosition == nil then
		return {}
	end
	return CraftingServiceUtils.GetBiomeTokensFromWorldService(WorldGenerationServiceClient, rootPosition)
end

function CraftingServiceClient.InvalidateCachedLists(self: CraftingServiceClient)
	table.clear(self.cachedRecipeLists)
end

function CraftingServiceClient.EmitStateChanged(self: CraftingServiceClient)
	self.stateChanged:Fire(self:GetState())
end

function CraftingServiceClient.RefreshAvailableRecipeIds(self: CraftingServiceClient, forceRaw: any?): boolean
	local nextAvailableRecipeIds = CraftingServiceUtils.BuildAvailableRecipeIds(
		self.registry,
		self.serverState.knownRecipeIds,
		self.activeStations,
		self.currentBiomeTokens
	)

	local didChange = forceRaw == true
	if not didChange then
		didChange = not CraftingServiceUtils.StringArrayEquals(self.availableRecipeIds, nextAvailableRecipeIds)
	end
	if not didChange then
		return false
	end

	self.availableRecipeIds = nextAvailableRecipeIds
	self.availableCategories = CraftingServiceUtils.BuildCategoryList(self.registry, nextAvailableRecipeIds)
	self.filterRevision += 1
	self:InvalidateCachedLists()
	return true
end

function CraftingServiceClient.SetActiveStations(
	self: CraftingServiceClient,
	nextStationsRaw: { [string]: boolean }
): boolean
	local nextStations = CraftingServiceUtils.CloneStringSet(nextStationsRaw)
	if CraftingServiceUtils.StringSetEquals(self.activeStations, nextStations) then
		return false
	end
	self.activeStations = nextStations
	self:RefreshAvailableRecipeIds(true)
	self:EmitStateChanged()
	return true
end

function CraftingServiceClient.RefreshBiomeTokens(self: CraftingServiceClient): boolean
	local nextBiomeTokens = self:GetLocalBiomeTokens()
	if CraftingServiceUtils.StringSetEquals(self.currentBiomeTokens, nextBiomeTokens) then
		return false
	end
	self.currentBiomeTokens = nextBiomeTokens
	self:RefreshAvailableRecipeIds(true)
	self:EmitStateChanged()
	return true
end

function CraftingServiceClient.ApplyInventoryState(
	self: CraftingServiceClient,
	stateRaw: any,
	coinsDataRaw: any?
): boolean
	local nextCounts = CraftingServiceUtils.BuildInventoryItemCountMap(stateRaw, coinsDataRaw)
	if countMapEquals(self.inventoryItemCounts, nextCounts) then
		return false
	end
	self.inventoryItemCounts = nextCounts
	self.inventoryRevision += 1
	self:InvalidateCachedLists()
	self:EmitStateChanged()
	return true
end

function CraftingServiceClient.HandleStationsChanged(
	self: CraftingServiceClient,
	nextStations: { [string]: boolean },
	rootPosition: Vector3?
)
	self:SetActiveStations(nextStations)
	if rootPosition ~= nil then
		self:RefreshBiomeTokens()
	end
end

function CraftingServiceClient.ApplyState(self: CraftingServiceClient, stateRaw: any)
	local fallback = self.serverState
	local nextState = CraftingServiceUtils.CoerceServiceStateSnapshot(stateRaw, fallback)
	if
		CraftingServiceUtils.StringSetEquals(self.serverState.knownRecipeIds, nextState.knownRecipeIds)
		and CraftingServiceUtils.StringSetEquals(self.serverState.discoveredItemIds, nextState.discoveredItemIds)
		and CraftingServiceUtils.StringSetEquals(self.serverState.progressionFlags, nextState.progressionFlags)
	then
		self.serverState = nextState
		return
	end

	self.serverState = nextState
	self:RefreshAvailableRecipeIds(true)
	self:EmitStateChanged()
end

function CraftingServiceClient.OnCraftResult(self: CraftingServiceClient, resultRaw: any)
	local source = if typeof(resultRaw) == "table" then resultRaw :: { [string]: any } else {} :: any
	local result = {
		success = source.success == true,
		reason = if typeof(source.reason) == "string" then source.reason else nil,
		recipeId = if typeof(source.recipeId) == "string" then source.recipeId else nil,
		quantity = if typeof(source.quantity) == "number" and source.quantity == source.quantity
			then math.max(0, math.floor(source.quantity))
			else 0,
		updatedAt = os.clock(),
	}
	self.lastCraftResult = result
	if result.success ~= true or self.bulkCraftToken == nil then
		SnackbarNotifications.ShowCraftResult(result, self)
	end
	self:EmitStateChanged()
end

function CraftingServiceClient.RequestSync(_self: CraftingServiceClient)
	sendPacket(CraftingServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function CraftingServiceClient.RequestCraft(self: CraftingServiceClient, recipeIdRaw: any, quantityRaw: any): boolean
	local recipeId, quantity = CraftingServiceUtils.RecipeValidator.CoerceCraftRequest(
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
	sendPacket(CraftingServiceUtils.NETWORK_METHOD_REQUEST_CRAFT, recipeId, quantity)
	return true
end

function CraftingServiceClient.StopBulkCraft(self: CraftingServiceClient): boolean
	if self.bulkCraftToken == nil then
		return false
	end
	self.bulkCraftToken = nil
	self:EmitStateChanged()
	return true
end

function CraftingServiceClient.StartBulkCraft(self: CraftingServiceClient, recipeIdRaw: any, quantityRaw: any): boolean
	local recipeId, quantity = CraftingServiceUtils.RecipeValidator.CoerceCraftRequest(
		recipeIdRaw,
		quantityRaw,
		self.config.maxCraftQuantityPerRequest
	)
	if recipeId == nil or quantity <= 0 then
		return false
	end

	self:StopBulkCraft()
	local token = {}
	self.bulkCraftToken = token
	self:EmitStateChanged()

	task.spawn(function()
		while self.bulkCraftToken == token do
			local preview = self:GetRecipePreview(recipeId, quantity)
			if preview == nil or preview.canCraft ~= true then
				break
			end

			self:RequestCraft(recipeId, quantity)
			task.wait(self.config.bulkCraftIntervalSeconds)
		end

		if self.bulkCraftToken == token then
			self.bulkCraftToken = nil
			self:EmitStateChanged()
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

	return CraftingServiceUtils.BuildRecipePreview(
		recipe,
		self.inventoryItemCounts,
		quantityRaw,
		self.activeStations,
		self.currentBiomeTokens,
		self.serverState.knownRecipeIds
	)
end

function CraftingServiceClient.GetRecipes(self: CraftingServiceClient, optionsRaw: any?): { any }
	local options = if typeof(optionsRaw) == "table" then optionsRaw :: { [string]: any } else {} :: any
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

	local filteredRecipeIds = CraftingServiceUtils.FilterRecipeIds(
		self.registry,
		self.availableRecipeIds,
		if category ~= "" then category else nil,
		if searchText ~= "" then searchText else nil
	)

	local entries: { any } = {}
	for _, recipeId in filteredRecipeIds do
		local recipe = self.registry.recipesById[recipeId]
		if recipe == nil then
			continue
		end
		local preview = self:GetRecipePreview(recipeId, 1)
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

function CraftingServiceClient.GetRecipesByCategory(
	self: CraftingServiceClient,
	searchTextRaw: any?
): { [string]: { any } }
	local searchText = trim(searchTextRaw)
	local byCategory: { [string]: { any } } = {}
	local entries = self:GetRecipes({
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
	return CraftingServiceUtils.CloneStringArray(self.availableCategories)
end

function CraftingServiceClient.SetSearchQuery(self: CraftingServiceClient, queryRaw: any): boolean
	local nextQuery = trim(queryRaw)
	if self.searchQuery == nextQuery then
		return false
	end
	self.searchQuery = nextQuery
	self:EmitStateChanged()
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
	self:EmitStateChanged()
	return true
end

function CraftingServiceClient.GetState(self: CraftingServiceClient): { [string]: any }
	return {
		knownRecipeIds = CraftingServiceUtils.CloneStringSet(self.serverState.knownRecipeIds),
		discoveredItemIds = CraftingServiceUtils.CloneStringSet(self.serverState.discoveredItemIds),
		progressionFlags = CraftingServiceUtils.CloneStringSet(self.serverState.progressionFlags),
		activeStations = CraftingServiceUtils.CloneStringSet(self.activeStations),
		currentBiomeTokens = CraftingServiceUtils.CloneStringSet(self.currentBiomeTokens),
		inventoryItemCounts = cloneCountMap(self.inventoryItemCounts),
		availableRecipeIds = CraftingServiceUtils.CloneStringArray(self.availableRecipeIds),
		availableCategories = CraftingServiceUtils.CloneStringArray(self.availableCategories),
		searchQuery = self.searchQuery,
		categoryFilter = self.categoryFilter,
		lastCraftResult = self.lastCraftResult,
		isBulkCrafting = self.bulkCraftToken ~= nil,
		updatedAt = os.clock(),
	}
end

function CraftingServiceClient.Init(self: CraftingServiceClient, serviceBag: ServiceBag.ServiceBag?)
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	self.localPlayer = Players.LocalPlayer
	self.config = CraftingServiceUtils.GetEffectiveConfig((Configs :: any).crafting)
	self.registry = CraftingServiceUtils.GetRegistry(self.config)
	bindPackets(self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.serverState = CraftingServiceUtils.CreateDefaultServiceStateSnapshot(self.registry)
	self.serverState.knownRecipeIds = self:CreateInitialKnownRecipeIds(self.registry)
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

	local stationDetector = CraftingServiceUtils.StationDetector.NewClientDetector({
		localPlayer = self.localPlayer,
		stationTagById = self.registry.stationTagById,
		stationIds = nil,
		radius = self.config.stationScanRadius,
		scanIntervalSeconds = 1 / self.config.stationScanRateHz,
		onStationsChanged = function(nextStations: { [string]: boolean }, rootPosition: Vector3?)
			self:HandleStationsChanged(nextStations, rootPosition)
		end,
	})
	self.stationDetector = stationDetector
	self.stationDetector:Start()

	local initialInventoryState = InventoryServiceClient:GetState()
	local initialCoinsData = PlayerDataServiceClient:GetCoinsData(nil)
	self:ApplyInventoryState(initialInventoryState, initialCoinsData)
	self.currentBiomeTokens = self:GetLocalBiomeTokens()
	self:RefreshAvailableRecipeIds(true)

	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: any)
			self:ApplyInventoryState(nextState, PlayerDataServiceClient:GetCoinsData(nil))
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
			self:ApplyInventoryState(InventoryServiceClient:GetState(), coinsData)
		end))
	end

	self.janitor:GiveChore(RunService.Heartbeat:Connect(function(dt: number)
		local nextAccumulator = (self.biomeScanAccumulator :: number) + dt
		self.biomeScanAccumulator = nextAccumulator
		if nextAccumulator < (self.biomeScanIntervalSeconds :: number) then
			return
		end
		self.biomeScanAccumulator = 0
		self:RefreshBiomeTokens()
	end))

	self.janitor:GiveChore(function()
		if self.stationDetector ~= nil then
			self.stationDetector:Destroy()
		end
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:RequestSync()
	self:EmitStateChanged()
end

function CraftingServiceClient.Destroy(self: CraftingServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
	self._serviceBag = nil
end
type CraftingServiceClient = typeof(CraftingServiceClient) & {
	_serviceBag: ServiceBag.ServiceBag?,
	localPlayer: Player,
	config: CraftingServiceConfig,
	registry: RecipeRegistry,
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
