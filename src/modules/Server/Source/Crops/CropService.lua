local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ObservableSet = require("ObservableSet")
local Rx = require("Rx")
local ServiceBag = require("ServiceBag")
local Set = require("Set")
local Signal = require("Signal")
local Table = require("Table")

local Players = game:GetService("Players")

local BuildServiceServer = require("BuildServiceServer")
local BuildServiceUtils = require("BuildServiceUtils")
local CelestialCycleServer = require("CelestialCycleServer")
local Configs = require("CoreConfigs")
local CoreRuntime = require("CoreRuntime")
local CropDefinitions = require("CropDefinitions")
local CropRules = require("CropRules")
local CropStateStore = require("CropStateStore")
local CropTreeBuilder = require("CropTreeBuilder")
local CropTypes = require("CropTypes")
local InventoryServiceServer = require("InventoryServiceServer")
local LiquidServiceUtils = require("LiquidServiceUtils")
local LootServiceServer = require("LootServiceServer")
local NetPacketsServer = require("NetPacketsServer")
local PacketPayload = require("PacketPayload")
local PlayerServiceServer = require("PlayerServiceServer")
local Rand = require("Rand")
local SpawnChance = require("SpawnChance")
local TickScheduler = require("TickScheduler")
local WeatherServiceServer = require("WeatherServiceServer")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")
local WorldMutationQueue = require("WorldMutationQueue")

local CropPackets = NetPacketsServer.CropService
local NETWORK = CropTypes.Network
local DELTA_OPERATION = CropTypes.DeltaOperation
local KIND = CropTypes.Kind
local AIR_TILE_ID = BuildServiceUtils.AIR_TILE_ID

local DAYLIGHT_BY_PART = {
	Dawn = 0.62,
	Day = 1,
	Dusk = 0.48,
	Night = 0.1,
}

local DEFAULT_SPREAD_OFFSETS = {
	{ x = -1, y = 0 },
	{ x = 1, y = 0 },
	{ x = 0, y = -1 },
	{ x = 0, y = 1 },
}

local CropService = {}
CropService.ServiceName = "CropService"

local activeService: any? = nil
local packetsBound = false

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function coerceInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function coerceNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function contains(listRaw: any, value: any): boolean
	if typeof(listRaw) ~= "table" then
		return false
	end
	if (listRaw :: any)[value] == true then
		return true
	end
	for _, candidate in listRaw do
		if candidate == value then
			return true
		end
	end
	return false
end

local function coerceConfig(): any
	local fallback = CropDefinitions.GetSystemConfig()
	local source = if typeof(Configs) == "table" and typeof((Configs :: any).crops) == "table"
		then (Configs :: any).crops
		else {} :: any
	return {
		randomUpdateInterval = coerceNumber(source.randomUpdateInterval, fallback.randomUpdateInterval, 0.05, 60),
		samplesPerChunk = coerceInteger(source.samplesPerChunk, fallback.samplesPerChunk, 1, 1024),
		maxChunksPerTick = coerceInteger(source.maxChunksPerTick, fallback.maxChunksPerTick, 1, 1024),
		maxRandomUpdatesPerTick = coerceInteger(
			source.maxRandomUpdatesPerTick,
			fallback.maxRandomUpdatesPerTick,
			1,
			65536
		),
		maxTerrainMutationsPerFlush = coerceInteger(
			source.maxTerrainMutationsPerFlush,
			fallback.maxTerrainMutationsPerFlush,
			1,
			65536
		),
		deltaBatchMax = coerceInteger(source.deltaBatchMax, fallback.deltaBatchMax, 1, 4096),
		lightScanHeight = coerceInteger(source.lightScanHeight, fallback.lightScanHeight, 1, 128),
		waterScanRadius = coerceInteger(source.waterScanRadius, fallback.waterScanRadius, 0, 16),
		requestInterval = coerceNumber(source.requestInterval, fallback.requestInterval, 0.03, 5),
	}
end

local function sendPacket(player: Player, methodName: string, payload: any)
	local packet = CropPackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CropService`)
		return
	end
	packet.sendTo(PacketPayload.Pack(payload), player)
end

local function bindRequest(methodName: string)
	local packet = CropPackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CropService`)
		return
	end

	packet.listen(function(payloadRaw: any, player: Player?)
		local service = activeService
		if service == nil or player == nil then
			return
		end
		local count, arguments = PacketPayload.Unpack(payloadRaw)
		if count < 1 or typeof(arguments[1]) ~= "table" then
			return
		end

		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = service[handlerName]
		if typeof(handler) == "function" then
			handler(service, player, arguments[1])
		end
	end)
end

local function bindPackets()
	if packetsBound then
		return
	end
	packetsBound = true
	bindRequest(NETWORK.RequestPlant)
	bindRequest(NETWORK.RequestHarvest)
	bindRequest(NETWORK.RequestSync)
end

local function defaultGrassUpdate(
	service: any,
	_definition: any,
	_state: any?,
	tileX: number,
	tileY: number,
	seed: number
)
	return service:TrySpread(tileX, tileY, seed)
end

local function defaultTreeUpdate(
	service: any,
	_definition: any,
	state: any?,
	tileX: number,
	tileY: number,
	seed: number
)
	if state == nil or state.segment ~= nil then
		return false, "not_sapling"
	end
	return service:TryGrow(tileX, tileY, seed)
end

local function defaultPlantUpdate(
	service: any,
	definition: any,
	state: any?,
	tileX: number,
	tileY: number,
	seed: number
)
	if state == nil then
		return false, "missing_crop"
	end
	local grew = select(1, service:TryGrow(tileX, tileY, seed))
	if grew then
		return true, "grew"
	end
	if definition.spread ~= nil then
		return service:TrySpread(tileX, tileY, Rand.Fork(seed, "spread"))
	end
	return false, "no_update"
end

local function getDefaultUpdateHandler(definition: any): any
	if definition.kind == KIND.Grass then
		return defaultGrassUpdate
	end
	if definition.kind == KIND.Tree then
		return defaultTreeUpdate
	end
	return defaultPlantUpdate
end

function CropService.Init(self: any, serviceBag: any)
	assert(ServiceBag.isServiceBag(serviceBag), "No serviceBag")
	assert(self._serviceBag == nil, "Already initialized")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._config = coerceConfig()
	self._definitionsById = {}
	self._definitionIdsByAlias = {}
	self._updateHandlersById = {}
	self._tileUpdateDefinitions = {}
	self._pendingDeltasByKey = {}
	self._pendingDeltaOrder = {}
	self._pendingTerrainTileIds = {}
	self._playerInterest = {}
	self._lastRequestAtByPlayer = {}
	self._revision = 0
	self._updateStep = 0
	self._chunkCursor = 1
	self._harvestSequence = 0
	self._world = nil
	self._worldMaid = nil
	self._environmentSnapshot = nil
	self._activeChunks = self._maid:Add(ObservableSet.new())
	self._store = CropStateStore.New(32)
	self._terrainMutationQueue = WorldMutationQueue.New({
		chunkSize = 32,
		flushInterval = self._config.randomUpdateInterval,
		maxMutationsPerFlush = self._config.maxTerrainMutationsPerFlush,
	})
	self.cropChanged = self._maid:Add(Signal.new())
	self._cropChangedObservable = Rx.fromSignal(self.cropChanged):Pipe({
		Rx.share(),
	})

	local definitions = CropDefinitions.GetAll()
	local ids = Table.keys(definitions)
	table.sort(ids)
	for _, id in ids do
		self:RegisterCrop(definitions[id])
	end

	activeService = self
	bindPackets()
end

function CropService.Start(self: any)
	assert(self._serviceBag ~= nil, "Not initialized")
	self:BindWorld(WorldGenerationServiceServer:GetWorld())

	local runtime = CoreRuntime.GetServerRuntime()
	local scheduler = runtime:GetTickScheduler()
	self._updateToken = scheduler:ScheduleEvery(
		function()
			self:StepRandomUpdates()
		end,
		self._config.randomUpdateInterval,
		{
			group = "service.crops.server",
			priority = TickScheduler.Priority.LOW,
			catchUp = false,
		}
	)
	self._maid:GiveTask(function()
		if self._updateToken ~= nil then
			self._updateToken:Cancel()
			self._updateToken = nil
		end
	end)
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player: Player)
		self._playerInterest[player] = nil
		self._lastRequestAtByPlayer[player] = nil
	end))
end

function CropService.RegisterCrop(self: any, definitionRaw: any, updateHandlerRaw: any?): (boolean, string)
	if typeof(definitionRaw) ~= "table" then
		return false, "invalid_definition"
	end
	local definition = Table.deepCopy(definitionRaw)
	local cropId = CropTypes.CoerceCropId(definition.id)
	if cropId == nil or typeof(definition.kind) ~= "string" then
		return false, "invalid_definition"
	end
	if typeof(definition.stages) ~= "table" or #definition.stages <= 0 then
		return false, "missing_growth_stages"
	end

	definition.id = cropId
	local normalized = string.lower(cropId)
	self._definitionsById[cropId] = definition
	self._definitionIdsByAlias[normalized] = cropId
	self._updateHandlersById[cropId] = if typeof(updateHandlerRaw) == "function"
		then updateHandlerRaw
		else getDefaultUpdateHandler(definition)

	if typeof(definition.randomUpdateTileIds) == "table" then
		for _, tileIdRaw in definition.randomUpdateTileIds do
			local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
			if tileId ~= nil then
				self._tileUpdateDefinitions[tileId] = cropId
			end
		end
	end
	return true, "ok"
end

function CropService.GetDefinition(self: any, cropIdRaw: any): any?
	local cropId = CropTypes.CoerceCropId(cropIdRaw)
	if cropId == nil then
		return nil
	end
	local canonicalId = self._definitionIdsByAlias[string.lower(cropId)] or cropId
	return self._definitionsById[canonicalId]
end

function CropService.ObserveCropChanged(self: any): any
	return self._cropChangedObservable
end

function CropService.ObserveActiveChunkCount(self: any): any
	return self._activeChunks:ObserveCount()
end

function CropService.GetActiveChunkKeys(self: any): { string }
	local keys = self._activeChunks:GetList()
	table.sort(keys)
	return keys
end

function CropService.GetCropAt(self: any, tileXRaw: any, tileYRaw: any): any?
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return nil
	end
	return self._store:Get(tileX, tileY)
end

function CropService._clearActiveChunks(self: any)
	for _, chunkKey in self._activeChunks:GetList() do
		self._activeChunks:Remove(chunkKey)
	end
end

function CropService.BindWorld(self: any, worldRaw: any)
	if worldRaw == nil or worldRaw == self._world then
		return
	end

	local replacingWorld = self._world ~= nil
	self._world = worldRaw
	self:_clearActiveChunks()
	table.clear(self._playerInterest)
	if replacingWorld then
		self._store:Clear()
		table.clear(self._pendingDeltasByKey)
		table.clear(self._pendingDeltaOrder)
		table.clear(self._pendingTerrainTileIds)
		self._revision += 1
	end

	local chunkSize = coerceInteger((worldRaw :: any).chunkSize, 32, 1, 1024)
	self._store:Destroy()
	self._store = CropStateStore.New(chunkSize)
	self._terrainMutationQueue:Destroy()
	self._terrainMutationQueue = WorldMutationQueue.New({
		chunkSize = chunkSize,
		flushInterval = self._config.randomUpdateInterval,
		maxMutationsPerFlush = self._config.maxTerrainMutationsPerFlush,
	})

	local worldMaid = Maid.new()
	self._worldMaid = worldMaid
	self._maid._worldMaid = worldMaid

	worldMaid:GiveTask(Rx.merge({
		worldRaw:ObserveChunkCollisionReady():Pipe({
			Rx.map(function(event: any)
				return { kind = "ready", event = event }
			end),
		}),
		worldRaw:ObserveChunkCollisionUnloaded():Pipe({
			Rx.map(function(event: any)
				return { kind = "unloaded", event = event }
			end),
		}),
	}):Subscribe(function(message: any)
		local event = message.event
		if typeof(event) ~= "table" or typeof(event.chunkKey) ~= "string" then
			return
		end
		if message.kind == "ready" then
			self._activeChunks:Add(event.chunkKey)
		else
			self._activeChunks:Remove(event.chunkKey)
		end
	end))
	worldMaid:GiveTask(worldRaw:ObservePlayerInterest():Subscribe(function(event: any)
		self:OnPlayerInterestChanged(event)
	end))

	for _, player in worldRaw:GetTrackedPlayers() do
		local interestKeys = worldRaw:GetPlayerInterestKeys(player)
		self._playerInterest[player] = Set.copy(interestKeys)
		for chunkKey in interestKeys do
			if worldRaw:IsChunkCollisionReadyByKey(chunkKey) then
				self._activeChunks:Add(chunkKey)
			end
		end
	end

	if replacingWorld then
		for _, player in Players:GetPlayers() do
			self:PushState(player)
		end
	end
end

function CropService.OnPlayerInterestChanged(self: any, eventRaw: any)
	if typeof(eventRaw) ~= "table" then
		return
	end
	local player = (eventRaw :: any).player
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local nextInterest = if typeof((eventRaw :: any).interestKeys) == "table"
		then Set.copy((eventRaw :: any).interestKeys)
		else {}
	local previousInterest = self._playerInterest[player] or {}
	self._playerInterest[player] = nextInterest

	for chunkKey in Set.difference(nextInterest, previousInterest) do
		if self._world:IsChunkCollisionReadyByKey(chunkKey) then
			self._activeChunks:Add(chunkKey)
			self:PushChunkSnapshot(player, chunkKey)
		end
	end
	for chunkKey in Set.difference(previousInterest, nextInterest) do
		sendPacket(player, NETWORK.OnChunkUnloaded, {
			chunkKey = chunkKey,
			revision = self._revision,
		})
	end
end

function CropService._getTileId(self: any, tileX: number, tileY: number): number
	local key = CropTypes.GetTileKey(tileX, tileY)
	local pending = self._pendingTerrainTileIds[key]
	if pending ~= nil then
		return pending
	end
	local tileId = select(1, self._world:GetTileAt(tileX, tileY))
	return if isFiniteNumber(tileId) then math.floor(tileId) else AIR_TILE_ID
end

function CropService._isTileOpen(self: any, tileX: number, tileY: number, ignoredKeyRaw: any?): boolean
	if self:_getTileId(tileX, tileY) ~= AIR_TILE_ID then
		return false
	end
	local key = CropTypes.GetTileKey(tileX, tileY)
	if key == ignoredKeyRaw then
		return true
	end
	return self._store:GetByKey(key) == nil
end

function CropService._countOpen(
	self: any,
	tileX: number,
	tileY: number,
	directionX: number,
	directionY: number,
	limit: number
): number
	local count = 0
	for distance = 1, limit do
		if not self:_isTileOpen(tileX + directionX * distance, tileY + directionY * distance, nil) then
			break
		end
		count += 1
	end
	return count
end

function CropService._getWaterLevel(self: any, tileX: number, tileY: number): number
	local maximumFill = 0
	local radius = self._config.waterScanRadius
	for offsetX = -radius, radius do
		for offsetY = -radius, radius do
			local packedCell = self._world:GetLiquidCellAt(tileX + offsetX, tileY + offsetY)
			local liquidType, fill = LiquidServiceUtils.LiquidCell.Unpack(packedCell)
			if liquidType == LiquidServiceUtils.LIQUID_TYPE.WATER then
				maximumFill = math.max(maximumFill, fill)
			end
		end
	end
	return maximumFill / LiquidServiceUtils.MAX_FILL
end

function CropService._getEnvironmentState(self: any): any
	if self._environmentSnapshot ~= nil then
		return self._environmentSnapshot
	end
	return {
		celestial = CelestialCycleServer:GetState(),
		weather = WeatherServiceServer:GetState(),
	}
end

function CropService.ResolveEnvironment(self: any, definitionRaw: any, tileX: number, tileY: number): any
	local definition = if typeof(definitionRaw) == "table" then definitionRaw else {} :: any
	local placement = if typeof(definition.placement) == "table" then definition.placement else {} :: any
	local soilOffsetY = if isFiniteNumber(placement.soilOffsetY) then math.floor(placement.soilOffsetY) else -1
	local soilY = if placement.mode == CropTypes.PlacementMode.ReplaceSoil then tileY else tileY + soilOffsetY
	local environmentState = self:_getEnvironmentState()
	local celestial = if typeof(environmentState.celestial) == "table" then environmentState.celestial else {} :: any
	local weather = if typeof(environmentState.weather) == "table" then environmentState.weather else {} :: any
	local dayPart = if typeof(celestial.dayPart) == "string" then celestial.dayPart else "Day"
	local daylight = DAYLIGHT_BY_PART[dayPart] or 0
	local openAbove = self:_countOpen(tileX, tileY, 0, 1, self._config.lightScanHeight)
	local skyExposure = openAbove / self._config.lightScanHeight

	return {
		targetTileId = self:_getTileId(tileX, tileY),
		soilTileId = self:_getTileId(tileX, soilY),
		biomeId = self._world:GetBiomeIdAt(tileX, tileY),
		biomeType = self._world:GetBiomeTypeAt(tileX, tileY),
		clockTime = if isFiniteNumber(celestial.clockTime)
			then celestial.clockTime
			else if isFiniteNumber(weather.clockTime) then weather.clockTime else 12,
		dayPart = dayPart,
		weatherType = if typeof(weather.weatherType) == "string" then weather.weatherType else "Clear",
		light = math.clamp(daylight * skyExposure, 0, 1),
		water = self:_getWaterLevel(tileX, tileY),
		rain = if isFiniteNumber(weather.rainIntensity) then math.clamp(weather.rainIntensity, 0, 1) else 0,
		targetOpen = self:_isTileOpen(tileX, tileY, nil),
		openAbove = openAbove,
		openLeft = self:_countOpen(tileX, tileY, -1, 0, 16),
		openRight = self:_countOpen(tileX, tileY, 1, 0, 16),
	}
end

function CropService._queueDelta(self: any, deltaRaw: any, lookupPrefix: string)
	self._revision += 1
	local delta = table.clone(deltaRaw)
	delta.revision = self._revision
	local lookupKey = `{lookupPrefix}:{delta.key}`
	if self._pendingDeltasByKey[lookupKey] == nil then
		self._pendingDeltaOrder[#self._pendingDeltaOrder + 1] = lookupKey
	end
	self._pendingDeltasByKey[lookupKey] = delta
	self.cropChanged:Fire(CropTypes.CloneDelta(delta))
end

function CropService._setCropState(self: any, stateRaw: any, reasonRaw: any?): boolean
	local state = CropTypes.CloneState(stateRaw)
	if state == nil then
		return false
	end
	local changed = self._store:Set(state)
	if not changed then
		return false
	end
	local key = CropTypes.GetTileKey(state.tileX, state.tileY)
	self:_queueDelta({
		op = DELTA_OPERATION.Set,
		key = key,
		chunkKey = CropTypes.GetChunkKey(state.tileX, state.tileY, self._world.chunkSize),
		tileX = state.tileX,
		tileY = state.tileY,
		crop = state,
		reason = if typeof(reasonRaw) == "string" then reasonRaw else "crop_changed",
	}, "crop")
	return true
end

function CropService._removeCropByKey(self: any, key: string, reasonRaw: any?): any?
	local state = self._store:RemoveByKey(key)
	if state == nil then
		return nil
	end
	self:_queueDelta({
		op = DELTA_OPERATION.Remove,
		key = key,
		chunkKey = CropTypes.GetChunkKey(state.tileX, state.tileY, self._world.chunkSize),
		tileX = state.tileX,
		tileY = state.tileY,
		reason = if typeof(reasonRaw) == "string" then reasonRaw else "crop_removed",
	}, "crop")
	return state
end

function CropService._removeCropRoot(self: any, rootKey: string, reasonRaw: any?): { any }
	local states = self._store:GetRootStates(rootKey)
	for _, state in states do
		self:_removeCropByKey(CropTypes.GetTileKey(state.tileX, state.tileY), reasonRaw)
	end
	return states
end

function CropService.QueueTerrainMutation(
	self: any,
	tileX: number,
	tileY: number,
	tileId: number,
	reasonRaw: any?
): boolean
	local key = CropTypes.GetTileKey(tileX, tileY)
	local previousTileId = self:_getTileId(tileX, tileY)
	self._pendingTerrainTileIds[key] = tileId
	return self._terrainMutationQueue:Enqueue({
		x = tileX,
		y = tileY,
		z = 0,
		tileId = tileId,
		previousTileId = previousTileId,
		metadata = {
			reason = if typeof(reasonRaw) == "string" then reasonRaw else "crop",
		},
	})
end

function CropService.FlushTerrainMutations(self: any): number
	local changedCount = 0
	while self._terrainMutationQueue:GetPendingCount() > 0 do
		local batch = self._terrainMutationQueue:Flush(self._config.maxTerrainMutationsPerFlush)
		if batch == nil then
			break
		end
		for _, chunkBatch in batch.chunks do
			for _, mutation in chunkBatch.mutations do
				local key = CropTypes.GetTileKey(mutation.x, mutation.y)
				self._pendingTerrainTileIds[key] = nil
				local reason = if typeof(mutation.metadata) == "table"
						and typeof(mutation.metadata.reason) == "string"
					then mutation.metadata.reason
					else "crop"
				local changed, _, nextTileId =
					BuildServiceServer:SetTileAtAuthoritative(mutation.x, mutation.y, mutation.tileId, reason)
				if changed then
					changedCount += 1
					self:_queueDelta({
						op = DELTA_OPERATION.Terrain,
						key = key,
						chunkKey = CropTypes.GetChunkKey(mutation.x, mutation.y, self._world.chunkSize),
						tileX = mutation.x,
						tileY = mutation.y,
						tileId = nextTileId,
						reason = reason,
					}, "terrain")
				end
			end
		end
	end
	return changedCount
end

function CropService._canPlayerInteract(self: any, player: Player, tileX: number, tileY: number): (boolean, string)
	local gameplayCheck = (PlayerServiceServer :: any).IsGameplayActiveForPlayer
	if typeof(gameplayCheck) == "function" then
		local ok, active = pcall(gameplayCheck, PlayerServiceServer, player)
		if not ok or active ~= true then
			return false, "gameplay_inactive"
		end
	end
	if not BuildServiceServer:IsWithinInteractionRange(player, tileX, tileY) then
		return false, "out_of_range"
	end
	local chunkKey = CropTypes.GetChunkKey(tileX, tileY, self._world.chunkSize)
	if not self._world:IsChunkCollisionReadyByKey(chunkKey) then
		return false, "chunk_not_ready"
	end
	return true, "ok"
end

function CropService._consumeSeed(_self: any, player: Player?, definition: any): (boolean, string)
	if player == nil then
		return true, "ok"
	end
	if typeof(definition.seedItemId) ~= "string" or definition.seedItemId == "" then
		return false, "not_player_plantable"
	end
	local result = InventoryServiceServer:RemoveItem(player, definition.seedItemId, 1, {})
	if result.removed ~= 1 then
		return false, "missing_seed"
	end
	return true, "ok"
end

function CropService._refundSeed(_self: any, player: Player?, definition: any)
	if player == nil or typeof(definition.seedItemId) ~= "string" then
		return
	end
	InventoryServiceServer:AddItem(player, definition.seedItemId, 1, {})
end

function CropService.Plant(
	self: any,
	player: Player?,
	cropIdRaw: any,
	tileXRaw: any,
	tileYRaw: any,
	optionsRaw: any?
): (boolean, string, any?)
	local definition = self:GetDefinition(cropIdRaw)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if definition == nil or tileX == nil or tileY == nil then
		return false, "invalid_crop_or_coordinate", nil
	end
	if player ~= nil then
		local allowed, reason = self:_canPlayerInteract(player, tileX, tileY)
		if not allowed then
			return false, reason, nil
		end
	end

	local environment = self:ResolveEnvironment(definition, tileX, tileY)
	local canPlant, plantReason = CropRules.CanPlant(definition, environment)
	if not canPlant then
		return false, plantReason, nil
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {} :: any
	if options.bypassInventory ~= true then
		local consumed, consumeReason = self:_consumeSeed(player, definition)
		if not consumed then
			return false, consumeReason, nil
		end
	end

	if definition.placement.mode == CropTypes.PlacementMode.ReplaceSoil then
		local resultTileId = BuildServiceUtils.CoerceTileId(definition.placement.resultTileId)
		if resultTileId == nil then
			self:_refundSeed(player, definition)
			return false, "invalid_result_tile", nil
		end
		self:QueueTerrainMutation(tileX, tileY, resultTileId, "crop_plant")
		self:FlushTerrainMutations()
		if self:_getTileId(tileX, tileY) ~= resultTileId then
			self:_refundSeed(player, definition)
			return false, "terrain_changed", nil
		end
		self:FlushReplication()
		return true, "ok", nil
	end

	local state = {
		cropId = definition.id,
		tileX = tileX,
		tileY = tileY,
		stage = 0,
		variant = coerceInteger(options.variant, 0, 0, 65535),
		ownerUserId = if player ~= nil then player.UserId else nil,
	}
	if not self:_setCropState(state, "crop_plant") then
		self:_refundSeed(player, definition)
		return false, "state_changed", nil
	end
	self:FlushReplication()
	return true, "ok", self:GetCropAt(tileX, tileY)
end

function CropService._validateTreeClearance(self: any, definition: any, state: any, environment: any): (boolean, string)
	local tree = definition.tree
	if typeof(tree) ~= "table" then
		return false, "missing_tree_settings"
	end
	if not contains(tree.soilTileIds, environment.soilTileId) then
		return false, "invalid_soil"
	end

	local rootKey = state.rootKey or CropTypes.GetTileKey(state.tileX, state.tileY)
	local bounds = CropTreeBuilder.GetClearanceBounds(definition)
	if bounds == nil then
		return false, "missing_tree_settings"
	end
	for offsetX = bounds.minX, bounds.maxX do
		for offsetY = bounds.minY, bounds.maxY do
			local tileX = state.tileX + offsetX
			local tileY = state.tileY + offsetY
			if tileX == state.tileX and tileY == state.tileY then
				continue
			end
			if not self:_isTileOpen(tileX, tileY, rootKey) then
				return false, "tree_clearance_blocked"
			end
		end
	end

	local blockerRadius = coerceInteger(tree.nearbyBlockerRadius, 3, 0, 32)
	for offsetX = -blockerRadius, blockerRadius do
		for offsetY = -1, bounds.maxY do
			local nearby = self._store:Get(state.tileX + offsetX, state.tileY + offsetY)
			if nearby ~= nil and nearby.rootKey ~= rootKey then
				local nearbyDefinition = self:GetDefinition(nearby.cropId)
				if nearbyDefinition ~= nil and nearbyDefinition.kind == KIND.Tree then
					return false, "nearby_tree_blocker"
				end
			end
		end
		local treeHit = BuildServiceServer:GetTreeHitAt(state.tileX + offsetX, state.tileY)
		if treeHit ~= nil then
			return false, "nearby_tree_blocker"
		end
	end
	return true, "ok"
end

function CropService._tryGrowTree(self: any, definition: any, state: any, seed: number): (boolean, string)
	local environment = self:ResolveEnvironment(definition, state.tileX, state.tileY)
	local requirementsPassed, requirementsReason =
		CropRules.CheckRequirements(definition.growthRequirements, environment)
	if not requirementsPassed then
		return false, requirementsReason
	end
	local clearancePassed, clearanceReason = self:_validateTreeClearance(definition, state, environment)
	if not clearancePassed then
		return false, clearanceReason
	end

	local roll = SpawnChance.Roll(definition.tree.growthChance, seed)
	if not roll.spawned then
		return false, "growth_roll_failed"
	end
	local segments = CropTreeBuilder.Generate(definition, state, roll.seed or seed)
	if #segments <= 0 then
		return false, "tree_generation_failed"
	end
	local rootKey = state.rootKey or CropTypes.GetTileKey(state.tileX, state.tileY)
	for _, segment in segments do
		local key = CropTypes.GetTileKey(segment.tileX, segment.tileY)
		if key ~= rootKey and not self:_isTileOpen(segment.tileX, segment.tileY, rootKey) then
			return false, "tree_generation_blocked"
		end
	end
	for _, segment in segments do
		self:_setCropState(segment, "tree_grown")
	end
	return true, "ok"
end

function CropService.TryGrow(self: any, tileXRaw: any, tileYRaw: any, seedRaw: any?): (boolean, string)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return false, "invalid_coordinate"
	end
	local state = self._store:Get(tileX, tileY)
	if state == nil then
		return false, "missing_crop"
	end
	local definition = self:GetDefinition(state.cropId)
	if definition == nil then
		return false, "missing_definition"
	end
	local seed = if isFiniteNumber(seedRaw)
		then Rand.Uint32(seedRaw)
		else Rand.HashCoordinates(self._world.seed or 1, tileX, tileY, self._updateStep)
	if definition.kind == KIND.Tree then
		return self:_tryGrowTree(definition, state, seed)
	end

	local environment = self:ResolveEnvironment(definition, tileX, tileY)
	local canGrow, reason = CropRules.CanGrow(definition, state, environment)
	if not canGrow then
		return false, reason
	end
	local stageDefinition = CropRules.GetStage(definition, state.stage)
	local growthChance = if stageDefinition ~= nil and isFiniteNumber(stageDefinition.growthChance)
		then stageDefinition.growthChance
		else 1
	local roll = SpawnChance.Roll(growthChance, seed)
	if not roll.spawned then
		return false, "growth_roll_failed"
	end
	state.stage = math.min(state.stage + 1, CropRules.GetFinalStage(definition))
	self:_setCropState(state, "crop_grown")
	return true, "ok"
end

function CropService._tryGrassDecoration(
	self: any,
	definition: any,
	tileX: number,
	tileY: number,
	seed: number
): boolean
	local spread = definition.spread
	if typeof(spread) ~= "table" or not isFiniteNumber(spread.decorativeChance) then
		return false
	end
	local roll = SpawnChance.Roll(spread.decorativeChance, seed)
	if not roll.spawned or typeof(spread.decorativeCropIds) ~= "table" or #spread.decorativeCropIds <= 0 then
		return false
	end
	local nextSeed, index = Rand.Integer(roll.seed or seed, 1, #spread.decorativeCropIds)
	local decorativeId = spread.decorativeCropIds[index]
	local decorative = self:GetDefinition(decorativeId)
	local targetX = tileX
	local targetY = tileY + 1
	if decorative == nil or not self:_isTileOpen(targetX, targetY, nil) then
		return false
	end
	local environment = self:ResolveEnvironment(decorative, targetX, targetY)
	local canPlant = select(1, CropRules.CanPlant(decorative, environment))
	if not canPlant then
		return false
	end
	return self:_setCropState({
		cropId = decorative.id,
		tileX = targetX,
		tileY = targetY,
		stage = 0,
		variant = nextSeed % 4,
	}, "grass_decoration")
end

function CropService._countNearbyCrop(self: any, cropId: string, tileX: number, tileY: number, radius: number): number
	local count = 0
	for offsetX = -radius, radius do
		for offsetY = -radius, radius do
			local state = self._store:Get(tileX + offsetX, tileY + offsetY)
			if state ~= nil and state.cropId == cropId then
				count += 1
			end
		end
	end
	return count
end

function CropService.TrySpread(self: any, tileXRaw: any, tileYRaw: any, seedRaw: any?): (boolean, string)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return false, "invalid_coordinate"
	end
	local state = self._store:Get(tileX, tileY)
	local definition
	if state ~= nil then
		definition = self:GetDefinition(state.cropId)
	else
		local tileId = self:_getTileId(tileX, tileY)
		definition = self:GetDefinition(self._tileUpdateDefinitions[tileId])
	end
	if definition == nil or typeof(definition.spread) ~= "table" then
		return false, "cannot_spread"
	end
	local seed = if isFiniteNumber(seedRaw)
		then Rand.Uint32(seedRaw)
		else Rand.HashCoordinates(self._world.seed or 1, tileX, tileY, self._updateStep)
	local sourceEnvironment = self:ResolveEnvironment(definition, tileX, tileY)
	local canSpread, spreadReason = CropRules.CanSpread(definition, state, sourceEnvironment)
	if not canSpread then
		return false, spreadReason
	end

	local decorated = false
	if definition.kind == KIND.Grass then
		decorated = self:_tryGrassDecoration(definition, tileX, tileY, Rand.Fork(seed, "decoration"))
	end
	local spreadRoll = SpawnChance.Roll(definition.spread.chance, seed)
	if not spreadRoll.spawned then
		return decorated, if decorated then "decorated" else "spread_roll_failed"
	end

	local offsets = if typeof(definition.spread.offsets) == "table" and #definition.spread.offsets > 0
		then definition.spread.offsets
		else DEFAULT_SPREAD_OFFSETS
	local nextSeed, offsetIndex = Rand.Integer(spreadRoll.seed or seed, 1, #offsets)
	local offset = offsets[offsetIndex]
	if typeof(offset) ~= "table" or not isFiniteNumber(offset.x) or not isFiniteNumber(offset.y) then
		return decorated, "invalid_spread_offset"
	end
	local targetX = tileX + math.floor(offset.x)
	local targetY = tileY + math.floor(offset.y)

	if definition.kind == KIND.Grass then
		local targetTileId = self:_getTileId(targetX, targetY)
		if not contains(definition.spread.targetTileIds, targetTileId) then
			return decorated, "invalid_spread_target"
		end
		if definition.spread.requireOpenAbove == true and not self:_isTileOpen(targetX, targetY + 1, nil) then
			return decorated, "spread_target_blocked"
		end
		local resultTileId = BuildServiceUtils.CoerceTileId(definition.spread.resultTileId)
		if resultTileId == nil then
			return decorated, "invalid_result_tile"
		end
		self:QueueTerrainMutation(targetX, targetY, resultTileId, "grass_spread")
		return true, "ok"
	end

	local resultCropId = CropTypes.CoerceCropId(definition.spread.resultCropId) or definition.id
	local resultDefinition = self:GetDefinition(resultCropId)
	if resultDefinition == nil or not self:_isTileOpen(targetX, targetY, nil) then
		return false, "spread_target_blocked"
	end
	local nearbyRadius = coerceInteger(definition.spread.nearbyRadius, 2, 0, 16)
	local maxNearby = coerceInteger(definition.spread.maxNearby, 8, 1, 256)
	if self:_countNearbyCrop(resultDefinition.id, targetX, targetY, nearbyRadius) >= maxNearby then
		return false, "spread_density_reached"
	end
	local environment = self:ResolveEnvironment(resultDefinition, targetX, targetY)
	local canPlant, plantReason = CropRules.CanPlant(resultDefinition, environment)
	if not canPlant then
		return false, plantReason
	end
	self:_setCropState({
		cropId = resultDefinition.id,
		tileX = targetX,
		tileY = targetY,
		stage = 0,
		variant = nextSeed % 4,
	}, "crop_spread")
	return true, "ok"
end

function CropService.RandomUpdate(self: any, tileXRaw: any, tileYRaw: any, seedRaw: any?): (boolean, string)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return false, "invalid_coordinate"
	end
	local state = self._store:Get(tileX, tileY)
	local definition
	if state ~= nil then
		definition = self:GetDefinition(state.cropId)
	else
		definition = self:GetDefinition(self._tileUpdateDefinitions[self:_getTileId(tileX, tileY)])
	end
	if definition == nil then
		return false, "no_update_handler"
	end
	local handler = self._updateHandlersById[definition.id]
	if typeof(handler) ~= "function" then
		return false, "no_update_handler"
	end
	local seed = if isFiniteNumber(seedRaw)
		then Rand.Uint32(seedRaw)
		else Rand.HashCoordinates(self._world.seed or 1, tileX, tileY, self._updateStep)
	return handler(self, definition, state, tileX, tileY, seed)
end

function CropService.StepRandomUpdates(self: any): number
	local latestWorld = WorldGenerationServiceServer:GetWorld()
	if latestWorld ~= self._world then
		self:BindWorld(latestWorld)
	end
	if self._world == nil then
		return 0
	end

	local chunkKeys = self:GetActiveChunkKeys()
	if #chunkKeys <= 0 then
		return 0
	end
	self._updateStep += 1
	self._environmentSnapshot = {
		celestial = CelestialCycleServer:GetState(),
		weather = WeatherServiceServer:GetState(),
	}

	local startIndex = math.clamp(self._chunkCursor, 1, #chunkKeys)
	local chunksProcessed = 0
	local updatesProcessed = 0
	local worldSeed = Rand.Seed(self._world.seed or 1)
	while chunksProcessed < math.min(#chunkKeys, self._config.maxChunksPerTick) do
		local chunkIndex = ((startIndex - 1 + chunksProcessed) % #chunkKeys) + 1
		local chunkKey = chunkKeys[chunkIndex]
		chunksProcessed += 1
		if not self._world:IsChunkCollisionReadyByKey(chunkKey) then
			self._activeChunks:Remove(chunkKey)
			continue
		end

		local chunkX, chunkY = BuildServiceUtils.UnpackChunkKey(chunkKey)
		if chunkX == nil or chunkY == nil then
			continue
		end
		for sampleIndex = 1, self._config.samplesPerChunk do
			if updatesProcessed >= self._config.maxRandomUpdatesPerTick then
				break
			end
			local seed = Rand.HashCoordinates(worldSeed, chunkX, chunkY, self._updateStep * 4099 + sampleIndex)
			local localX
			seed, localX = Rand.Integer(seed, 0, self._world.chunkSize - 1)
			local localY
			seed, localY = Rand.Integer(seed, 0, self._world.chunkSize - 1)
			local tileX = chunkX * self._world.chunkSize + localX
			local tileY = chunkY * self._world.chunkSize + localY
			if tileY >= self._world.minTileY and tileY <= self._world.maxTileY then
				self:RandomUpdate(tileX, tileY, seed)
				updatesProcessed += 1
			end
		end
		if updatesProcessed >= self._config.maxRandomUpdatesPerTick then
			break
		end
	end

	self._chunkCursor = ((startIndex - 1 + chunksProcessed) % #chunkKeys) + 1
	self:FlushTerrainMutations()
	self:FlushReplication()
	self._environmentSnapshot = nil
	return updatesProcessed
end

function CropService._rollHarvestDrops(self: any, definition: any, state: any): { any }
	self._harvestSequence += 1
	local seed = Rand.HashCoordinates(Rand.Seed(self._world.seed or 1), state.tileX, state.tileY, self._harvestSequence)
	local drops = {}
	for _, dropRaw in definition.harvestDrops or {} do
		if typeof(dropRaw) ~= "table" or typeof(dropRaw.itemId) ~= "string" then
			continue
		end
		local roll = SpawnChance.Roll(if isFiniteNumber(dropRaw.chance) then dropRaw.chance else 1, seed)
		seed = roll.seed or seed
		if not roll.spawned then
			continue
		end
		local minimum = coerceInteger(dropRaw.minAmount, 1, 0, 9999)
		local maximum = coerceInteger(dropRaw.maxAmount, minimum, minimum, 9999)
		local amount
		seed, amount = Rand.Integer(seed, minimum, maximum)
		if amount > 0 then
			drops[#drops + 1] = {
				itemId = dropRaw.itemId,
				amount = amount,
			}
		end
	end
	return drops
end

function CropService._awardDrops(self: any, player: Player?, state: any, drops: { any })
	if player == nil then
		return
	end
	local origin = BuildServiceUtils.TileToWorldCenter(
		state.tileX,
		state.tileY,
		self._world.worldOrigin,
		self._world.tileSize,
		self._world.basePlaneX
	)
	for _, drop in drops do
		local result = InventoryServiceServer:AddItem(player, drop.itemId, drop.amount, {})
		if result.leftover <= 0 then
			continue
		end
		pcall(function()
			LootServiceServer:SpawnLootRuntime(drop.itemId, result.leftover, origin, {
				sourceType = "CropHarvest",
				ownerUserId = player.UserId,
				ownerLockSeconds = 0.45,
			})
		end)
	end
end

function CropService.Harvest(
	self: any,
	player: Player?,
	tileXRaw: any,
	tileYRaw: any,
	_optionsRaw: any?
): (boolean, string, { any })
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return false, "invalid_coordinate", {}
	end
	if player ~= nil then
		local allowed, reason = self:_canPlayerInteract(player, tileX, tileY)
		if not allowed then
			return false, reason, {}
		end
	end

	local selectedState = self._store:Get(tileX, tileY)
	if selectedState == nil then
		return false, "missing_crop", {}
	end
	local rootKey = selectedState.rootKey or CropTypes.GetTileKey(tileX, tileY)
	local state = self._store:GetByKey(rootKey) or selectedState
	local definition = self:GetDefinition(state.cropId)
	if definition == nil then
		return false, "missing_definition", {}
	end
	local environment = self:ResolveEnvironment(definition, state.tileX, state.tileY)
	local canHarvest, reason = CropRules.CanHarvest(definition, state, environment)
	if not canHarvest then
		return false, reason, {}
	end

	local drops = self:_rollHarvestDrops(definition, state)
	self:_removeCropRoot(rootKey, "crop_harvested")
	self:_awardDrops(player, state, drops)
	self:FlushReplication()
	return true, "ok", drops
end

function CropService._acceptRequest(self: any, player: Player): boolean
	local now = os.clock()
	local lastAt = self._lastRequestAtByPlayer[player] or -math.huge
	if now - lastAt < self._config.requestInterval then
		return false
	end
	self._lastRequestAtByPlayer[player] = now
	return true
end

function CropService.RequestPlant(self: any, player: Player, payloadRaw: any)
	if not self:_acceptRequest(player) then
		return
	end
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {} :: any
	local success, reason, state = self:Plant(player, payload.cropId, payload.tileX, payload.tileY, nil)
	sendPacket(player, NETWORK.OnActionResult, {
		action = "plant",
		requestId = payload.requestId,
		success = success,
		reason = reason,
		crop = state,
		tileX = payload.tileX,
		tileY = payload.tileY,
	})
end

function CropService.RequestHarvest(self: any, player: Player, payloadRaw: any)
	if not self:_acceptRequest(player) then
		return
	end
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {} :: any
	local success, reason, drops = self:Harvest(player, payload.tileX, payload.tileY, nil)
	sendPacket(player, NETWORK.OnActionResult, {
		action = "harvest",
		requestId = payload.requestId,
		success = success,
		reason = reason,
		drops = drops,
		tileX = payload.tileX,
		tileY = payload.tileY,
	})
end

function CropService.CreatePlayerSnapshot(self: any, player: Player): any
	local interest = if self._world ~= nil then self._world:GetPlayerInterestKeys(player) else {}
	local crops = {}
	local chunkKeys = Table.keys(interest)
	table.sort(chunkKeys)
	for _, chunkKey in chunkKeys do
		for _, state in self._store:GetChunkStates(chunkKey) do
			crops[#crops + 1] = state
		end
	end
	return {
		revision = self._revision,
		crops = crops,
	}
end

function CropService.PushState(self: any, player: Player)
	if self._world == nil then
		return
	end
	local interest = self._world:GetPlayerInterestKeys(player)
	self._playerInterest[player] = Set.copy(interest)
	sendPacket(player, NETWORK.ApplyState, self:CreatePlayerSnapshot(player))
end

function CropService.PushChunkSnapshot(self: any, player: Player, chunkKey: string)
	sendPacket(player, NETWORK.OnChunkSnapshot, {
		chunkKey = chunkKey,
		revision = self._revision,
		crops = self._store:GetChunkStates(chunkKey),
	})
end

function CropService.RequestSync(self: any, player: Player, _payloadRaw: any)
	self:PushState(player)
end

function CropService.FlushReplication(self: any): number
	if #self._pendingDeltaOrder <= 0 or self._world == nil then
		return 0
	end

	local deltas = {}
	for _, lookupKey in self._pendingDeltaOrder do
		local delta = CropTypes.CloneDelta(self._pendingDeltasByKey[lookupKey])
		if delta ~= nil then
			deltas[#deltas + 1] = delta
		end
	end
	local perPlayer = {}
	for _, delta in deltas do
		for _, player in self._world:GetPlayersInterestedInChunk(delta.chunkKey) do
			local playerDeltas = perPlayer[player]
			if playerDeltas == nil then
				playerDeltas = {}
				perPlayer[player] = playerDeltas
			end
			playerDeltas[#playerDeltas + 1] = delta
		end
	end

	local packetCount = 0
	for player, playerDeltas in perPlayer do
		local startIndex = 1
		while startIndex <= #playerDeltas do
			local stopIndex = math.min(#playerDeltas, startIndex + self._config.deltaBatchMax - 1)
			local batch = table.create(stopIndex - startIndex + 1)
			for index = startIndex, stopIndex do
				batch[#batch + 1] = playerDeltas[index]
			end
			sendPacket(player, NETWORK.OnCropDeltas, {
				revision = self._revision,
				deltas = batch,
			})
			packetCount += 1
			startIndex = stopIndex + 1
		end
	end

	table.clear(self._pendingDeltasByKey)
	table.clear(self._pendingDeltaOrder)
	return packetCount
end

function CropService.Destroy(self: any)
	if activeService == self then
		activeService = nil
	end
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	if self._store ~= nil then
		self._store:Destroy()
	end
	if self._terrainMutationQueue ~= nil then
		self._terrainMutationQueue:Destroy()
	end
	self._serviceBag = nil
	self._world = nil
end

return CropService
