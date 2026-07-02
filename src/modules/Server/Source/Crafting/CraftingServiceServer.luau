
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Configs = require("CoreConfigs")
local CraftingServiceUtils = require("CraftingServiceUtils")
local InventoryServiceServer = require("InventoryServiceServer")
local InventoryServiceUtils = require("InventoryServiceUtils")
local PacketPayload = require("PacketPayload")
local CraftingServicePackets = require("NetPacketsShared").CraftingService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = CraftingServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CraftingService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = CraftingServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CraftingService`)
		return
	end

	packet.listen(function(payload: any, player: Player?)
		if player == nil then
			return
		end

		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, player, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "requestCraft")
	bindPacket(self, "requestSync")
end

local PlayerDataServiceServer = require("PlayerDataServiceServer")
local PlayerServiceServer = require("PlayerServiceServer")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")

type RecipeRegistry = CraftingServiceUtils.RecipeRegistry
type CraftingServiceConfig = CraftingServiceUtils.CraftingServiceConfig
type CraftingPersistentState = CraftingServiceUtils.CraftingPersistentState
type CraftingServiceStateSnapshot = CraftingServiceUtils.CraftingServiceStateSnapshot
type InventoryProvider = CraftingServiceUtils.InventoryProvider
type CraftTransactionResult = CraftingServiceUtils.CraftTransactionResult

type PlayerDataServiceServerObject = {
	WaitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	GetValue: (self: PlayerDataServiceServerObject, player: Player, pathRaw: any, fallback: any) -> any,
	SetValue: (
		self: PlayerDataServiceServerObject,
		player: Player,
		pathRaw: any,
		value: any,
		replicateToClientRaw: any
	) -> boolean,
	SavePlayerData: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
}

type InventoryServiceServerObject = {
	GetState: (self: InventoryServiceServerObject, player: Player) -> any,
}

type WorldGenerationServiceServerObject = {
	GetBiomeTypeAtWorldPosition: (self: WorldGenerationServiceServerObject, worldPosition: Vector3) -> number?,
}

type PlayerRuntime = {
	loadToken: number,
	hasGotPersistedLoad: boolean,
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

local function CoerceFlagId(flagRaw: any): string?
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

function CraftingServiceServer.CreateRuntime(_self: CraftingServiceServer): PlayerRuntime
	return {
		loadToken = 0,
		hasGotPersistedLoad = false,
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
	local nextRuntime = self:CreateRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function CraftingServiceServer.IsRuntimeReady(_self: CraftingServiceServer, runtime: PlayerRuntime): boolean
	return runtime.hasGotPersistedLoad
end

function CraftingServiceServer.CreateStateSnapshot(
	_self: CraftingServiceServer,
	runtime: PlayerRuntime
): CraftingServiceStateSnapshot
	return {
		knownRecipeIds = CraftingServiceUtils.CloneStringSet(runtime.knownRecipeIds),
		discoveredItemIds = CraftingServiceUtils.CloneStringSet(runtime.discoveredItemIds),
		progressionFlags = CraftingServiceUtils.CloneStringSet(runtime.progressionFlags),
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
	sendPacket(player, CraftingServiceUtils.CLIENT_METHOD_APPLY_STATE, self:CreateStateSnapshot(runtime))
end

function CraftingServiceServer.PushCraftResult(
	self: CraftingServiceServer,
	player: Player,
	transactionResult: CraftTransactionResult,
	reasonRaw: any?
)
	local reason = if typeof(reasonRaw) == "string" then reasonRaw else transactionResult.reason
	sendPacket(player, CraftingServiceUtils.CLIENT_METHOD_CRAFT_RESULT, {
		success = transactionResult.success == true,
		reason = reason,
		recipeId = transactionResult.recipeId,
		quantity = transactionResult.quantity,
		updatedAt = os.clock(),
	})
end

function CraftingServiceServer.MarkRuntimeDirty(_self: CraftingServiceServer, runtime: PlayerRuntime)
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
	if not runtime.hasGotPersistedLoad then
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
	local serializedState = CraftingServiceUtils.SerializePersistentState(payload)
	local success, didSet = pcall(function()
		return playerDataService:SetValue(player, self.config.dataPath, serializedState, false)
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
		if
			CraftingServiceUtils.RecipeValidator.AreUnlockConditionsSatisfied(
				recipe,
				runtime.discoveredItemIds,
				runtime.progressionFlags
			)
		then
			runtime.knownRecipeIds[recipeId] = true
			didUnlockAny = true
		end
	end

	if didUnlockAny then
		self:MarkRuntimeDirty(runtime)
	end
	return didUnlockAny
end

function CraftingServiceServer.UnlockAllEligibleRecipes(self: CraftingServiceServer, runtime: PlayerRuntime): boolean
	return self:UnlockRecipesByIds(runtime, self.registry.recipeIdsOrdered)
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
	if not InventoryServiceUtils.IsLoadedState((inventoryState :: any).loadState) then
		return false
	end

	local didChange = false
	local discoveredRecipeCandidates: { [string]: boolean } = {}
	local inventoryCounts = CraftingServiceUtils.BuildInventoryItemCountMap(inventoryState)
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
		self:MarkRuntimeDirty(runtime)
	end

	local shouldForceUnlockScan = forceUnlockScanRaw == true
	if shouldForceUnlockScan then
		if self:UnlockAllEligibleRecipes(runtime) then
			didChange = true
		end
		return didChange
	end

	local candidateRecipeIds = mapToOrderedRecipeIds(self.registry, discoveredRecipeCandidates)
	if #candidateRecipeIds > 0 and self:UnlockRecipesByIds(runtime, candidateRecipeIds) then
		didChange = true
	end

	return didChange
end

function CraftingServiceServer.ApplyPersistedStateToRuntime(
	self: CraftingServiceServer,
	runtime: PlayerRuntime,
	persistedStateRaw: any
)
	local CoerceD = CraftingServiceUtils.CoercePersistentState(persistedStateRaw, self.registry)
	runtime.knownRecipeIds = CoerceD.knownRecipeIds
	runtime.discoveredItemIds = CoerceD.discoveredItemIds
	runtime.progressionFlags = CoerceD.progressionFlags
	for recipeId, enabled in self.registry.defaultKnownRecipeIds do
		if enabled then
			runtime.knownRecipeIds[recipeId] = true
		end
	end
	runtime.hasGotPersistedLoad = true
end

function CraftingServiceServer.LoadPlayerState(self: CraftingServiceServer, player: Player, loadToken: number)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local persistedStateRaw = nil
	local playerDataService = self.playerDataService
	if playerDataService ~= nil then
		pcall(function()
			playerDataService:WaitForData(player, self.config.dataLoadTimeoutSeconds)
		end)
		local readSuccess, readResult = pcall(function()
			return playerDataService:GetValue(player, self.config.dataPath, nil)
		end)
		if readSuccess then
			persistedStateRaw = readResult
		end
	end

	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	self:ApplyPersistedStateToRuntime(runtime, persistedStateRaw)

	local inventoryState = self.inventoryService:GetState(player)
	self:RefreshDiscoveriesFromInventory(runtime, inventoryState, true)
	self:PushState(player, runtime, true)
	self:PersistRuntime(player, runtime)
end

function CraftingServiceServer.TrackPlayer(self: CraftingServiceServer, player: Player)
	local runtime = self:GetRuntime(player)
	runtime.loadToken += 1
	runtime.hasGotPersistedLoad = false
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
		self:LoadPlayerState(player, loadToken)
	end)
end

function CraftingServiceServer.UntrackPlayer(self: CraftingServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:PersistRuntime(player, runtime)
	pcall(function()
		self.playerDataService:SavePlayerData(player)
	end)
	runtime.loadToken += 1
	self.playerRuntimes[player] = nil
end

function CraftingServiceServer.GetPlayerBiomeTokens(
	self: CraftingServiceServer,
	player: Player
): { [string]: boolean }
	local rootPosition = CraftingServiceUtils.GetPlayerRootPosition(player)
	if rootPosition == nil then
		return {}
	end
	return CraftingServiceUtils.GetBiomeTokensFromWorldService(self.worldGenerationService, rootPosition)
end

function CraftingServiceServer.RequestSync(self: CraftingServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:TrackPlayer(player)
		return
	end
	self:PushState(player, runtime, true)
end

function CraftingServiceServer.RequestCraft(
	self: CraftingServiceServer,
	player: Player,
	recipeIdRaw: any,
	quantityRaw: any
)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or not self:IsRuntimeReady(runtime) then
		self:PushCraftResult(player, {
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
		self:PushCraftResult(player, {
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

	local recipeId, quantity = CraftingServiceUtils.RecipeValidator.CoerceCraftRequest(
		recipeIdRaw,
		quantityRaw,
		self.config.maxCraftQuantityPerRequest
	)
	if recipeId == nil or quantity <= 0 then
		self:PushCraftResult(player, {
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
		self:PushCraftResult(player, {
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
		self:PushCraftResult(player, {
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
		self:PushCraftResult(player, {
			success = false,
			reason = "busy",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "busy")
		return
	end

	local stationsNearPlayer = CraftingServiceUtils.StationDetector.GetStationsNearPlayer(
		player,
		self.registry.stationTagById,
		self.config.stationValidationRadius,
		recipe.requiredStations
	)
	if not CraftingServiceUtils.RecipeValidator.AreStationsSatisfied(recipe, stationsNearPlayer) then
		self:PushCraftResult(player, {
			success = false,
			reason = "missing_station",
			recipeId = recipeId,
			quantity = quantity,
			consumed = {},
			granted = {},
		}, "missing_station")
		return
	end

	local biomeTokens = self:GetPlayerBiomeTokens(player)
	if not CraftingServiceUtils.RecipeValidator.IsBiomeSatisfied(recipe, biomeTokens) then
		self:PushCraftResult(player, {
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
		return CraftingServiceUtils.CraftTransaction.Execute(self.inventoryProvider, player, recipe, quantity)
	end)
	runtime.transactionLocked = false

	if not transactionSuccess then
		self:PushCraftResult(player, {
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
		self:PushCraftResult(player, transactionResult, transactionResult.reason)
		return
	end

	local candidateRecipeIdSet: { [string]: boolean } = {}
	for _, grantedItem in transactionResult.granted do
		if runtime.discoveredItemIds[grantedItem.itemId] ~= true then
			runtime.discoveredItemIds[grantedItem.itemId] = true
			self:MarkRuntimeDirty(runtime)
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
	if #candidateRecipeIds > 0 and self:UnlockRecipesByIds(runtime, candidateRecipeIds) then
		didUnlock = true
	end

	self:PushState(player, runtime, didUnlock)
	self:PushCraftResult(player, transactionResult, nil)
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
		if runtime.hasGotPersistedLoad and shouldWatchInventory then
			local inventoryState = self.inventoryService:GetState(player)
			local updatedAt = if typeof(inventoryState) == "table"
					and typeof((inventoryState :: any).updatedAt) == "number"
				then (inventoryState :: any).updatedAt
				else -math.huge
			if updatedAt ~= runtime.lastObservedInventoryUpdatedAt then
				runtime.lastObservedInventoryUpdatedAt = updatedAt
				if self:RefreshDiscoveriesFromInventory(runtime, inventoryState, false) then
					self:PushState(player, runtime, true)
				end
			end
		end

		if runtime.dirty and runtime.hasGotPersistedLoad then
			if now - runtime.lastPersistAt >= self.config.persistIntervalSeconds then
				self:PersistRuntime(player, runtime)
			end
		end
	end
end

function CraftingServiceServer.SetInventoryProvider(self: CraftingServiceServer, providerRaw: any)
	if typeof(providerRaw) == "table" then
		local provider = providerRaw :: { [string]: any }
		if
			typeof(provider.IsReady) == "function"
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
	self.inventoryProvider =
		CraftingServiceUtils.CraftTransaction.CreateInventoryProvider(self.inventoryService, self.playerDataService)
end

function CraftingServiceServer.SetProgressionFlag(
	self: CraftingServiceServer,
	player: Player,
	flagIdRaw: any,
	enabledRaw: any
): boolean
	local runtime = self.playerRuntimes[player]
	if runtime == nil or not runtime.hasGotPersistedLoad then
		return false
	end

	local flagId = CoerceFlagId(flagIdRaw)
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

	self:MarkRuntimeDirty(runtime)
	local candidateRecipeIds = self.registry.recipeIdsByUnlockFlag[flagId]
	if candidateRecipeIds ~= nil then
		self:UnlockRecipesByIds(runtime, candidateRecipeIds)
	end
	self:PushState(player, runtime, true)
	return true
end

function CraftingServiceServer.Init(self: CraftingServiceServer)
	self.config = CraftingServiceUtils.GetEffectiveConfig((Configs :: any).crafting)
	self.registry = CraftingServiceUtils.GetRegistry(self.config)
	self.playerRuntimes = {}
	self.inventoryWatchAccumulator = 0
	self.inventoryService = InventoryServiceServer :: InventoryServiceServerObject
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.inventoryProvider =
		CraftingServiceUtils.CraftTransaction.CreateInventoryProvider(self.inventoryService, self.playerDataService)

	bindPackets(self)

	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
			self:TrackPlayer(player)
		end
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if PlayerServiceServer:IsGameplayActiveForPlayer(player) then
			self:TrackPlayer(player)
		end
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:UntrackPlayer(player)
	end)

	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:OnHeartbeat(dt)
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
		self:PersistRuntime(player, runtime)
		self.playerRuntimes[player] = nil
	end
end
type CraftingServiceServer = typeof(CraftingServiceServer) & {
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
