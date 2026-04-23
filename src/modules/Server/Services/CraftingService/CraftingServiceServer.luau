--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CraftingServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.CraftingService.CraftingServiceUtils)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryService.InventoryServiceUtils)
local InventoryServiceServer = require(script:FindFirstAncestor("game").Server.Services.InventoryService.InventoryServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)
local PlayerDataServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerDataService.PlayerDataServiceServer)
local WorldGenerationServiceServer = require(script:FindFirstAncestor("game").Server.Services.WorldGenerationService.WorldGenerationServiceServer)

type RecipeRegistry = CraftingServiceUtils.RecipeRegistry
type CraftingServiceConfig = CraftingServiceUtils.CraftingServiceConfig
type CraftingPersistentState = CraftingServiceUtils.CraftingPersistentState
type CraftingServiceStateSnapshot = CraftingServiceUtils.CraftingServiceStateSnapshot
type InventoryProvider = CraftingServiceUtils.InventoryProvider
type CraftTransactionResult = CraftingServiceUtils.CraftTransactionResult

type PlayerDataServiceServerObject = {
	waitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	getValue: (self: PlayerDataServiceServerObject, player: Player, pathRaw: any, fallback: any) -> any,
	setValue: (
		self: PlayerDataServiceServerObject,
		player: Player,
		pathRaw: any,
		value: any,
		replicateToClientRaw: any
	) -> boolean,
	savePlayerData: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
}

type InventoryServiceServerObject = {
	getState: (self: InventoryServiceServerObject, player: Player) -> any,
}

type WorldGenerationServiceServerObject = {
	getBiomeTypeAtWorldPosition: (self: WorldGenerationServiceServerObject, worldPosition: Vector3) -> number?,
}

type PlayerRuntime = {
	loadToken: number,
	hasResolvedPersistedLoad: boolean,
	knownRecipeIds: { [string]: boolean },
	discoveredItemIds: { [string]: boolean },
	progressionFlags: { [string]: boolean },
	dirty: boolean,
	lastPersistAt: number,
	lastStatePushAt: number,
	lastCraftRequestAt: number,
	lastObservedInventoryUpdatedAt: number,
	transactionLocked: boolean,
}

local CraftingServiceServer = {}

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeFlagId(flagRaw: any): string?
	local flagId = trim(flagRaw)
	if flagId == "" then
		return nil
	end
	return flagId
end

local function mapToOrderedRecipeIds(registry: RecipeRegistry, recipeIdSet: { [string]: boolean }): { string }
	local orderedRecipeIds = {}
	for _, recipeId in registry.recipeIdsOrdered do
		if recipeIdSet[recipeId] == true then
			table.insert(orderedRecipeIds, recipeId)
		end
	end
	return orderedRecipeIds
end

function CraftingServiceServer.CreateRuntime(self: CraftingServiceServer): PlayerRuntime
	return {
		loadToken = 0,
		hasResolvedPersistedLoad = false,
		knownRecipeIds = {},
		discoveredItemIds = {},
		progressionFlags = {},
		dirty = false,
		lastPersistAt = 0,
		lastStatePushAt = -math.huge,
		lastCraftRequestAt = -math.huge,
		lastObservedInventoryUpdatedAt = -math.huge,
		transactionLocked = false,
	}
end

function CraftingServiceServer.GetRuntime(self: CraftingServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end
	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function CraftingServiceServer.IsRuntimeReady(self: CraftingServiceServer, runtime: PlayerRuntime): boolean
	return runtime.hasResolvedPersistedLoad
end

function CraftingServiceServer.CreateStateSnapshot(
	self: CraftingServiceServer,
	runtime: PlayerRuntime
): CraftingServiceStateSnapshot
	return {
		knownRecipeIds = CraftingServiceUtils.cloneStringSet(runtime.knownRecipeIds),
		discoveredItemIds = CraftingServiceUtils.cloneStringSet(runtime.discoveredItemIds),
		progressionFlags = CraftingServiceUtils.cloneStringSet(runtime.progressionFlags),
		updatedAt = os.clock(),
	}
end

function CraftingServiceServer.PushState(
	self: CraftingServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	forceRaw: any?
)
	local force = forceRaw == true
	local now = os.clock()
	if not force and now - runtime.lastStatePushAt < self.config.statePushIntervalSeconds then
		return
	end

	runtime.lastStatePushAt = now
	self.networker:fire(
		player,
		CraftingServiceUtils.CLIENT_METHOD_APPLY_STATE,
		self:createStateSnapshot(runtime)
	)
end

function CraftingServiceServer.PushCraftResult(
	self: CraftingServiceServer,
	player: Player,
	transactionResult: CraftTransactionResult,
	reasonRaw: any?
)
	local reason = if typeof(reasonRaw) == "string" then reasonRaw else transactionResult.reason
	self.networker:fire(player, CraftingServiceUtils.CLIENT_METHOD_CRAFT_RESULT, {
		success = transactionResult.success == true,
		reason = reason,
		recipeId = transactionResult.recipeId,
		quantity = transactionResult.quantity,
		updatedAt = os.clock(),
	})
end

function CraftingServiceServer.MarkRuntimeDirty(self: CraftingServiceServer, runtime: PlayerRuntime)
	runtime.dirty = true
end

function CraftingServiceServer.PersistRuntime(
	self: CraftingServiceServer,
	player: Player,
	runtime: PlayerRuntime
): boolean
	if not runtime.dirty then
		return false
	end
	if not runtime.hasResolvedPersistedLoad then
		return false
	end

	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return false
	end

	local payload: CraftingPersistentState = {
		knownRecipeIds = runtime.knownRecipeIds,
		discoveredItemIds = runtime.discoveredItemIds,
		progressionFlags = runtime.progressionFlags,
		updatedAt = os.time(),
	}
	local serializedState = CraftingServiceUtils.serializePersistentState(payload)
	local success, didSet = pcall(function()
		return playerDataService:setValue(player, self.config.dataPath, serializedState, false)
	end)
	if not success or didSet ~= true then
		return false
	end

	runtime.dirty = false
	runtime.lastPersistAt = os.clock()
	return true
end

function CraftingServiceServer.UnlockRecipesByIds(
	self: CraftingServiceServer,
	runtime: PlayerRuntime,
	recipeIdsRaw: { string }
): boolean
	local didUnlockAny = false
	for _, recipeId in recipeIdsRaw do
		if runtime.knownRecipeIds[recipeId] == true then
			continue
		end
		local recipe = self.registry.recipesById[recipeId]
		if recipe == nil then
			continue
		end
		if CraftingServiceUtils.RecipeValidator.areUnlockConditionsSatisfied(
			recipe,
			runtime.discoveredItemIds,
			runtime.progressionFlags
		) then
			runtime.knownRecipeIds[recipeId] = true
			didUnlockAny = true
		end
	end

	if didUnlockAny then
		self:markRuntimeDirty(runtime)
	end
	return didUnlockAny
end

function CraftingServiceServer.UnlockAllEligibleRecipes(
	self: CraftingServiceServer,
	runtime: PlayerRuntime
): boolean
	return self:unlockRecipesByIds(runtime, self.registry.recipeIdsOrdered)
end

function CraftingServiceServer.RefreshDiscoveriesFromInventory(
	self: CraftingServiceServer,
	runtime: PlayerRuntime,
	inventoryStateRaw: any,
	forceUnlockScanRaw: any?
): boolean
	local inventoryState = if typeof(inventoryStateRaw) == "table" then inventoryStateRaw else nil
	if inventoryState == nil then
		return false
	end
	if not InventoryServiceUtils.isLoadedState((inventoryState :: any).loadState) then
		return false
	end

	local didChange = false
	local discoveredRecipeCandidates: { [string]: boolean } = {}
	local inventoryCounts = CraftingServiceUtils.buildInventoryItemCountMap(inventoryState)
	for itemId, amount in inventoryCounts do
		if amount <= 0 then
			continue
		end
		if runtime.discoveredItemIds[itemId] ~= true then
			runtime.discoveredItemIds[itemId] = true
			didChange = true
		end

		local candidateRecipeIds = self.registry.recipeIdsByUnlockItem[itemId]
		if candidateRecipeIds ~= nil then
			for _, recipeId in candidateRecipeIds do
				discoveredRecipeCandidates[recipeId] = true
			end
		end
	end

	if didChange then
		self:markRuntimeDirty(runtime)
	end

	local shouldForceUnlockScan = forceUnlockScanRaw == true
	if shouldForceUnlockScan then
		if self:unlockAllEligibleRecipes(runtime) then
			didChange = true
		end
		return didChange
	end

	local candidateRecipeIds = mapToOrderedRecipeIds(self.registry, discoveredRecipeCandidates)
	if #candidateRecipeIds > 0 and self:unlockRecipesByIds(runtime, candidateRecipeIds) then
		didChange = true
	end

	return didChange
end

function CraftingServiceServer.ApplyPersistedStateToRuntime(
	self: CraftingServiceServer,
	runtime: PlayerRuntime,
	persistedStateRaw: any
)
	local sanitized = CraftingServiceUtils.sanitizePersistentState(persistedStateRaw, self.registry)
	runtime.knownRecipeIds = sanitized.knownRecipeIds
	runtime.discoveredItemIds = sanitized.discoveredItemIds
	runtime.progressionFlags = sanitized.progressionFlags
	for recipeId, enabled in self.registry.defaultKnownRecipeIds do
		if enabled then
			runtime.knownRecipeIds[recipeId] = true
		end
	end
	runtime.hasResolvedPersistedLoad = true
end

function CraftingServiceServer.LoadPlayerState(
	self: CraftingServiceServer,
	player: Player,
	loadToken: number
)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local persistedStateRaw = nil
	local playerDataService = self.playerDataService
	if playerDataService ~= nil then
		pcall(function()
			playerDataService:waitForData(player, self.config.dataLoadTimeoutSeconds)
		end)
		local readSuccess, readResult = pcall(function()
			return playerDataService:getValue(player, self.config.dataPath, nil)
		end)
		if readSuccess then
			persistedStateRaw = readResult
		end
	end

	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	self:applyPersistedStateToRuntime(runtime, persistedStateRaw)

	local inventoryState = self.inventoryService:getState(player)
	self:refreshDiscoveriesFromInventory(runtime, inventoryState, true)
	self:pushState(player, runtime, true)
	self:persistRuntime(player, runtime)
end

function CraftingServiceServer.TrackPlayer(self: CraftingServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.loadToken += 1
	runtime.hasResolvedPersistedLoad = false
	runtime.knownRecipeIds = {}
	runtime.discoveredItemIds = {}
	runtime.progressionFlags = {}
	runtime.dirty = false
	runtime.lastPersistAt = 0
	runtime.lastStatePushAt = -math.huge
	runtime.lastCraftRequestAt = -math.huge
	runtime.lastObservedInventoryUpdatedAt = -math.huge
	runtime.transactionLocked = false

	local loadToken = runtime.loadToken
	task.spawn(function()
		self:loadPlayerState(player, loadToken)
	end)
end

function CraftingServiceServer.UntrackPlayer(self: CraftingServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:persistRuntime(player, runtime)
	pcall(function()
		self.playerDataService:savePlayerData(player)
	end)
	runtime.loadToken += 1
	self.playerRuntimes[player] = nil
end

function CraftingServiceServer.ResolvePlayerBiomeTokens(self: CraftingServiceServer, player: Player): { [string]: boolean }
	local rootPosition = CraftingServiceUtils.resolvePlayerRootPosition(player)
	if rootPosition == nil then
		return {}
	end
	return CraftingServiceUtils.resolveBiomeTokensFromWorldService(self.worldGenerationService, rootPosition)
end

function CraftingServiceServer.RequestSync(self: CraftingServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:trackPlayer(player)
		return
	end
	self:pushState(player, runtime, true)
end

function CraftingServiceServer.RequestCraft(
	self: CraftingServiceServer,
	player: Player,
	recipeIdRaw: any,
	quantityRaw: any
)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or not self:isRuntimeReady(runtime) then
		self:pushCraftResult(player, {
			success = false,
			reason = "not_ready",
			recipeId = "",
			quantity = 0,
			consumed = {},
			granted = {},
		}, "not_ready")
		return
	end

	local now = os.clock()
	if now - runtime.lastCraftRequestAt < self.config.serverRequestRateLimitSeconds then
		self:pushCraftResult(player, {
			success = false,
			reason = "rate_limited",
			recipeId = "",
			quantity = 0,
			consumed = {},
			granted = {},
		}, "rate_limited")
		return
	end
	runtime.lastCraftRequestAt = now

	local recipeId, quantity =
		CraftingServiceUtils.RecipeValidator.sanitizeCraftRequest(recipeIdRaw, quantityRaw, self.config.maxCraftQuantityPerRequest)
	if recipeId == nil or quantity <= 0 then
		self:pushCraftResult(player, {
			success = false,
			reason = "invalid_request",
			recipeId = "",
			quantity = 0,
			consumed = {},
			granted = {},
		}, "invalid_request")
		return
	end

	local recipe = self.registry.recipesById[recipeId]
	if recipe == nil then
		self:pushCraftResult(player, {
			success = false,
			reason = "invalid_recipe",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "invalid_recipe")
		return
	end
	if runtime.knownRecipeIds[recipeId] ~= true then
		self:pushCraftResult(player, {
			success = false,
			reason = "recipe_locked",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "recipe_locked")
		return
	end

	if runtime.transactionLocked then
		self:pushCraftResult(player, {
			success = false,
			reason = "busy",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "busy")
		return
	end

	local stationsNearPlayer = CraftingServiceUtils.StationDetector.getStationsNearPlayer(
		player,
		self.registry.stationTagById,
		self.config.stationValidationRadius,
		recipe.requiredStations
	)
	if not CraftingServiceUtils.RecipeValidator.areStationsSatisfied(recipe, stationsNearPlayer) then
		self:pushCraftResult(player, {
			success = false,
			reason = "missing_station",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "missing_station")
		return
	end

	local biomeTokens = self:resolvePlayerBiomeTokens(player)
	if not CraftingServiceUtils.RecipeValidator.isBiomeSatisfied(recipe, biomeTokens) then
		self:pushCraftResult(player, {
			success = false,
			reason = "wrong_biome",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "wrong_biome")
		return
	end

	runtime.transactionLocked = true
	local transactionSuccess, transactionResultOrError = pcall(function()
		return CraftingServiceUtils.CraftTransaction.execute(self.inventoryProvider, player, recipe, quantity)
	end)
	runtime.transactionLocked = false

	if not transactionSuccess then
		self:pushCraftResult(player, {
			success = false,
			reason = "transaction_error",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "transaction_error")
		return
	end

	local transactionResult = transactionResultOrError :: CraftTransactionResult

	if not transactionResult.success then
		self:pushCraftResult(player, transactionResult, transactionResult.reason)
		return
	end

	local candidateRecipeIdSet: { [string]: boolean } = {}
	for _, grantedItem in transactionResult.granted do
		if runtime.discoveredItemIds[grantedItem.itemId] ~= true then
			runtime.discoveredItemIds[grantedItem.itemId] = true
			self:markRuntimeDirty(runtime)
		end
		local candidates = self.registry.recipeIdsByUnlockItem[grantedItem.itemId]
		if candidates ~= nil then
			for _, candidateRecipeId in candidates do
				candidateRecipeIdSet[candidateRecipeId] = true
			end
		end
	end

	local didUnlock = false
	local candidateRecipeIds = mapToOrderedRecipeIds(self.registry, candidateRecipeIdSet)
	if #candidateRecipeIds > 0 and self:unlockRecipesByIds(runtime, candidateRecipeIds) then
		didUnlock = true
	end

	self:pushState(player, runtime, didUnlock)
	self:pushCraftResult(player, transactionResult, nil)
end

function CraftingServiceServer.OnHeartbeat(self: CraftingServiceServer, dtRaw: any)
	local dt = if typeof(dtRaw) == "number" and dtRaw == dtRaw then math.max(0, dtRaw) else 0
	if dt <= 0 then
		return
	end

	self.inventoryWatchAccumulator += dt
	local shouldWatchInventory = self.inventoryWatchAccumulator >= self.config.inventoryWatchIntervalSeconds
	if shouldWatchInventory then
		self.inventoryWatchAccumulator = 0
	end

	local now = os.clock()
	for player, runtime in self.playerRuntimes do
		if runtime.hasResolvedPersistedLoad and shouldWatchInventory then
			local inventoryState = self.inventoryService:getState(player)
			local updatedAt = if typeof(inventoryState) == "table" and typeof((inventoryState :: any).updatedAt) == "number"
				then (inventoryState :: any).updatedAt
				else -math.huge
			if updatedAt ~= runtime.lastObservedInventoryUpdatedAt then
				runtime.lastObservedInventoryUpdatedAt = updatedAt
				if self:refreshDiscoveriesFromInventory(runtime, inventoryState, false) then
					self:pushState(player, runtime, true)
				end
			end
		end

		if runtime.dirty and runtime.hasResolvedPersistedLoad then
			if now - runtime.lastPersistAt >= self.config.persistIntervalSeconds then
				self:persistRuntime(player, runtime)
			end
		end
	end
end

function CraftingServiceServer.SetInventoryProvider(self: CraftingServiceServer, providerRaw: any)
	if typeof(providerRaw) == "table" then
		local provider = providerRaw :: { [string]: any }
		if typeof(provider.IsReady) == "function"
			and typeof(provider.CountItem) == "function"
			and typeof(provider.HasItems) == "function"
			and typeof(provider.ConsumeItems) == "function"
			and typeof(provider.GrantItems) == "function"
			and typeof(provider.RestoreItems) == "function"
			and typeof(provider.RevokeItems) == "function"
		then
			self.inventoryProvider = providerRaw
			return
		end
	end
	self.inventoryProvider = CraftingServiceUtils.CraftTransaction.createInventoryProvider(
		self.inventoryService,
		self.playerDataService
	)
end

function CraftingServiceServer.SetProgressionFlag(
	self: CraftingServiceServer,
	player: Player,
	flagIdRaw: any,
	enabledRaw: any
): boolean
	local runtime = self.playerRuntimes[player]
	if runtime == nil or not runtime.hasResolvedPersistedLoad then
		return false
	end

	local flagId = sanitizeFlagId(flagIdRaw)
	if flagId == nil then
		return false
	end

	local enabled = enabledRaw == true
	if enabled then
		if runtime.progressionFlags[flagId] == true then
			return false
		end
		runtime.progressionFlags[flagId] = true
	else
		if runtime.progressionFlags[flagId] == nil then
			return false
		end
		runtime.progressionFlags[flagId] = nil
	end

	self:markRuntimeDirty(runtime)
	local candidateRecipeIds = self.registry.recipeIdsByUnlockFlag[flagId]
	if candidateRecipeIds ~= nil then
		self:unlockRecipesByIds(runtime, candidateRecipeIds)
	end
	self:pushState(player, runtime, true)
	return true
end

function CraftingServiceServer.Init(self: CraftingServiceServer)
	self.config = CraftingServiceUtils.resolveEffectiveConfig((Configs :: any).crafting)
	self.registry = CraftingServiceUtils.getRegistry(self.config)
	self.playerRuntimes = {}
	self.inventoryWatchAccumulator = 0
	self.inventoryService = InventoryServiceServer :: InventoryServiceServerObject
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.inventoryProvider = CraftingServiceUtils.CraftTransaction.createInventoryProvider(
		self.inventoryService,
		self.playerDataService
	)

	self.networker = Networker.server.new("CraftingService", self, {
		self.RequestSync,
		self.RequestCraft,
	})

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

function CraftingServiceServer.Destroy(self: CraftingServiceServer)
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

	for player, runtime in self.playerRuntimes do
		self:persistRuntime(player, runtime)
		self.playerRuntimes[player] = nil
	end

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

CraftingServiceServer.createRuntime = CraftingServiceServer.CreateRuntime
CraftingServiceServer.getRuntime = CraftingServiceServer.GetRuntime
CraftingServiceServer.isRuntimeReady = CraftingServiceServer.IsRuntimeReady
CraftingServiceServer.createStateSnapshot = CraftingServiceServer.CreateStateSnapshot
CraftingServiceServer.pushState = CraftingServiceServer.PushState
CraftingServiceServer.pushCraftResult = CraftingServiceServer.PushCraftResult
CraftingServiceServer.markRuntimeDirty = CraftingServiceServer.MarkRuntimeDirty
CraftingServiceServer.persistRuntime = CraftingServiceServer.PersistRuntime
CraftingServiceServer.unlockRecipesByIds = CraftingServiceServer.UnlockRecipesByIds
CraftingServiceServer.unlockAllEligibleRecipes = CraftingServiceServer.UnlockAllEligibleRecipes
CraftingServiceServer.refreshDiscoveriesFromInventory = CraftingServiceServer.RefreshDiscoveriesFromInventory
CraftingServiceServer.applyPersistedStateToRuntime = CraftingServiceServer.ApplyPersistedStateToRuntime
CraftingServiceServer.loadPlayerState = CraftingServiceServer.LoadPlayerState
CraftingServiceServer.trackPlayer = CraftingServiceServer.TrackPlayer
CraftingServiceServer.untrackPlayer = CraftingServiceServer.UntrackPlayer
CraftingServiceServer.resolvePlayerBiomeTokens = CraftingServiceServer.ResolvePlayerBiomeTokens
CraftingServiceServer.requestSync = CraftingServiceServer.RequestSync
CraftingServiceServer.requestCraft = CraftingServiceServer.RequestCraft
CraftingServiceServer.onHeartbeat = CraftingServiceServer.OnHeartbeat
CraftingServiceServer.setInventoryProvider = CraftingServiceServer.SetInventoryProvider
CraftingServiceServer.setProgressionFlag = CraftingServiceServer.SetProgressionFlag
CraftingServiceServer.init = CraftingServiceServer.Init
CraftingServiceServer.destroy = CraftingServiceServer.Destroy

type CraftingServiceServer = typeof(CraftingServiceServer) & {
	networker: Networker.Server,
	config: CraftingServiceConfig,
	registry: RecipeRegistry,
	playerRuntimes: { [Player]: PlayerRuntime },
	inventoryWatchAccumulator: number,
	inventoryService: InventoryServiceServerObject,
	inventoryProvider: InventoryProvider,
	playerDataService: PlayerDataServiceServerObject,
	worldGenerationService: WorldGenerationServiceServerObject,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return CraftingServiceServer :: CraftingServiceServer

