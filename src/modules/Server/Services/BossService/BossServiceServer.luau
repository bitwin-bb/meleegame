--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossService.BossServiceUtils)
local EyeOfCthulhuController = require(script:FindFirstAncestor("game").Shared.Classes.Boss.EyeOfCthulhu)
local EyeOfCthulhuConfig = require(script:FindFirstAncestor("game").Shared.Classes.Boss.EyeOfCthulhu.Config)
local HpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpService.HpServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)
local WeatherServiceServer = require(script:FindFirstAncestor("game").Server.Services.WeatherService.WeatherServiceServer)
local WorldGenerationServiceServer =
	require(script:FindFirstAncestor("game").Server.Services.WorldGenerationService.WorldGenerationServiceServer)

type BossId = BossServiceUtils.BossId
type BossSnapshot = BossServiceUtils.BossSnapshot
type BossServiceState = BossServiceUtils.BossServiceState
type BossRegistryEntry = BossServiceUtils.BossRegistryEntry
type BossSpawnRequest = BossServiceUtils.BossSpawnRequest

type BossObject = any

type HpServiceServerObject = {
	damagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
}

type WeatherServiceServerObject = {
	getState: (self: WeatherServiceServerObject) -> { clockTime: number },
}

type WorldGenerationServiceServerObject = {
	getWorld: (self: WorldGenerationServiceServerObject) -> any,
}

type PendingNaturalSpawn = {
	bossId: BossId,
	targetPlayer: Player,
	encounterChannel: string,
	delayRemaining: number,
	announcement: string,
}

local BossServiceServer = {}

local CONTROLLER_CONSTRUCTORS = {
	EyeOfCthulhu = function(
		service: BossServiceServer,
		definition: BossRegistryEntry,
		spawnRequest: BossSpawnRequest
	): BossObject
		return EyeOfCthulhuController.new(service, definition, spawnRequest)
	end,
}

local DEFAULT_STATE_PUSH_INTERVAL = BossServiceUtils.DEFAULT_STATE_PUSH_INTERVAL
local DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL = BossServiceUtils.DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL
local DEFAULT_BOX_QUERY_MAX_PARTS = 96

local function resolveBossSettingsSource(): { [string]: any }
	if typeof(Configs) ~= "table" then
		return {}
	end

	local bossSettings = (Configs :: any).bossSettings
	if typeof(bossSettings) ~= "table" then
		return {}
	end

	return bossSettings :: { [string]: any }
end

local function resolveEyeConfigSource(): { [string]: any }?
	local bossSettings = resolveBossSettingsSource()
	local eyeConfig = (bossSettings :: any).eyeOfCthulhu
	if typeof(eyeConfig) == "table" then
		return eyeConfig
	end
	return nil
end

local function disconnect(connectionRaw: any)
	if connectionRaw == nil then
		return
	end
	pcall(function()
		connectionRaw:Disconnect()
	end)
end

local function trim(valueRaw: any): string
	return BossServiceUtils.trim(valueRaw)
end

local function resolveBossId(boss: BossObject): string
	if typeof(boss) == "table" and typeof(boss.id) == "string" then
		return boss.id
	end
	return ""
end

local function destroyBossSafely(bossRaw: any)
	if typeof(bossRaw) ~= "table" then
		return
	end

	local destroy = (bossRaw :: any).destroy
	if typeof(destroy) ~= "function" then
		return
	end

	pcall(function()
		destroy(bossRaw)
	end)
end

function BossServiceServer.GetNow(self: BossServiceServer): number
	return os.clock()
end

function BossServiceServer.GetClockTime(self: BossServiceServer): number
	local weatherService = self.weatherService
	if weatherService == nil then
		return 12
	end

	local ok, stateOrError = pcall(function()
		return weatherService:getState()
	end)
	if not ok or typeof(stateOrError) ~= "table" then
		return 12
	end

	return BossServiceUtils.sanitizeNumber((stateOrError :: any).clockTime, 12, 0, 24)
end

function BossServiceServer.IsNightTime(self: BossServiceServer): boolean
	return BossServiceUtils.isNightClockTime(self:getClockTime())
end

function BossServiceServer.GetWorld(self: BossServiceServer): any?
	local worldGenerationService = self.worldGenerationService
	if worldGenerationService == nil then
		return nil
	end

	local ok, worldOrError = pcall(function()
		return worldGenerationService:getWorld()
	end)
	if not ok then
		return nil
	end

	if worldOrError ~= self.world then
		self.world = worldOrError
	end
	return self.world
end

function BossServiceServer.GetSurfaceYAtWorldPosition(self: BossServiceServer, worldPosition: Vector3): number?
	local world = self:getWorld()
	if typeof(world) ~= "table" then
		return nil
	end

	local worldOrigin = if typeof((world :: any).worldOrigin) == "Vector3" then (world :: any).worldOrigin else Vector3.zero
	local tileSize = if typeof((world :: any).tileSize) == "number" and (world :: any).tileSize > 0
		then (world :: any).tileSize
		else 2
	local biomeGenerator = (world :: any).biomeGenerator
	if typeof(biomeGenerator) ~= "table" or typeof((biomeGenerator :: any).getColumnProfile) ~= "function" then
		return nil
	end

	local tileX = math.floor((worldPosition.Z - worldOrigin.Z) / tileSize)
	local ok, columnOrError = pcall(function()
		return (biomeGenerator :: any):getColumnProfile(tileX)
	end)
	if not ok or typeof(columnOrError) ~= "table" then
		return nil
	end

	local surfaceTileY = (columnOrError :: any).surfaceY
	if typeof(surfaceTileY) ~= "number" or surfaceTileY ~= surfaceTileY then
		return nil
	end

	return worldOrigin.Y + surfaceTileY * tileSize
end

function BossServiceServer.IsPlayerAboveSurface(self: BossServiceServer, playerRaw: any): boolean
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return false
	end

	local rootPart = BossServiceUtils.resolveCharacterRootPart(playerRaw)
	if rootPart == nil then
		return false
	end

	local surfaceY = self:getSurfaceYAtWorldPosition(rootPart.Position)
	if surfaceY == nil then
		return true
	end

	return rootPart.Position.Y >= surfaceY
end

function BossServiceServer.DamagePlayer(
	self: BossServiceServer,
	playerRaw: any,
	damageRaw: any,
	_controllerRaw: any?
): number?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local hpService = self.hpService
	if hpService == nil then
		return nil
	end

	local damage = BossServiceUtils.sanitizeNumber(damageRaw, 0, 0, 10 ^ 6)
	if damage <= 0 then
		return nil
	end

	return hpService:damagePlayer(playerRaw, damage)
end

function BossServiceServer.EnsureOrderedId(self: BossServiceServer, runtimeId: string)
	for _, existingId in self.state.orderedIds do
		if existingId == runtimeId then
			return
		end
	end

	table.insert(self.state.orderedIds, runtimeId)
end

function BossServiceServer.RemoveOrderedId(self: BossServiceServer, runtimeId: string)
	local nextOrderedIds = {}
	for _, existingId in self.state.orderedIds do
		if existingId ~= runtimeId then
			table.insert(nextOrderedIds, existingId)
		end
	end
	self.state.orderedIds = nextOrderedIds
end

function BossServiceServer.CreateSnapshot(self: BossServiceServer, boss: BossObject): BossSnapshot
	local existingSnapshot = self.state.byId[resolveBossId(boss)]
	local snapshot = BossServiceUtils.sanitizeSnapshot({
		id = boss.id,
		bossId = boss.bossId,
		displayName = boss.displayName,
		encounterChannel = boss.encounterChannel,
		state = boss.state,
		phase = boss.phase,
		hp = boss.hp,
		maxHp = boss.maxHp,
		isAlive = boss.isAlive,
		position = boss.position,
		velocity = boss.velocity,
		facing = boss.facing,
		stateTime = boss.stateTime,
		chargeIndex = boss.chargeIndex,
		targetUserId = boss.targetUserId,
		updatedAt = self:getNow(),
		lastReason = boss.lastReason,
		presentation = boss.presentation,
		motion = boss.motion,
	}, existingSnapshot)

	if snapshot == nil then
		error("[BossService] Failed to build snapshot")
	end

	return snapshot
end

function BossServiceServer.UpsertControllerState(self: BossServiceServer, boss: BossObject): BossSnapshot
	local snapshot = self:createSnapshot(boss)
	self.state.byId[snapshot.id] = snapshot
	self:ensureOrderedId(snapshot.id)
	self.state.updatedAt = self:getNow()
	boss.snapshotDirty = false
	boss.lastSnapshotAt = self.state.updatedAt
	return snapshot
end

function BossServiceServer.CreateStateSnapshot(self: BossServiceServer): BossServiceState
	return BossServiceUtils.cloneState(self.state)
end

function BossServiceServer.Broadcast(self: BossServiceServer, methodName: string, ...: any)
	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self.networker:fire(player, methodName, ...)
		end
	end
end

function BossServiceServer.PushState(self: BossServiceServer, playerRaw: any?)
	local snapshot = self:createStateSnapshot()
	if playerRaw ~= nil then
		if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then
			self.networker:fire(playerRaw, BossServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
		end
		return
	end

	self:broadcast(BossServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
end

function BossServiceServer.RequestSync(self: BossServiceServer, player: Player)
	self:pushState(player)
end

function BossServiceServer.ResolveSpawnRequest(
	self: BossServiceServer,
	requestRaw: any
): (BossSpawnRequest?, BossRegistryEntry?, string?)
	local request = BossServiceUtils.sanitizeSpawnRequest(requestRaw, nil)
	if request == nil then
		return nil, nil, "invalid_request"
	end

	local definition = BossServiceUtils.getRegistryEntryById(request.bossId)
	if definition == nil then
		return nil, nil, "unknown_boss"
	end

	request.encounterChannel = if typeof(request.encounterChannel) == "string" and request.encounterChannel ~= ""
		then request.encounterChannel
		else definition.encounterChannel
	return request, definition, nil
end

function BossServiceServer.IsEncounterChannelBusy(self: BossServiceServer, encounterChannelRaw: any): boolean
	local encounterChannel = trim(encounterChannelRaw)
	if encounterChannel == "" then
		return false
	end

	return self.controllersByChannel[encounterChannel] ~= nil
end

function BossServiceServer.ResolveControllerConstructor(
	self: BossServiceServer,
	definition: BossRegistryEntry
): ((BossServiceServer, BossRegistryEntry, BossSpawnRequest) -> BossObject)?
	local constructor = CONTROLLER_CONSTRUCTORS[definition.controllerId]
	if typeof(constructor) == "function" then
		return constructor
	end
	return nil
end

function BossServiceServer.RefreshControllerModelBinding(self: BossServiceServer, boss: BossObject)
	local runtimeId = resolveBossId(boss)
	if runtimeId == "" then
		return
	end

	local currentModel = boss.model
	local boundModel = self.boundModelsById[runtimeId]
	if boundModel == currentModel then
		return
	end

	disconnect(self.modelDestroyConnectionsById[runtimeId])
	self.modelDestroyConnectionsById[runtimeId] = nil
	self.boundModelsById[runtimeId] = currentModel

	if currentModel == nil then
		return
	end

	self.modelDestroyConnectionsById[runtimeId] = currentModel.Destroying:Connect(function()
		if boss.model ~= currentModel then
			return
		end
		boss:requestRemoval("ModelDestroyed")
	end)
end

function BossServiceServer.TrackController(self: BossServiceServer, boss: BossObject)
	self.controllersById[boss.id] = boss
	self.controllersByChannel[boss.encounterChannel] = boss
	self:refreshControllerModelBinding(boss)
end

function BossServiceServer.UntrackController(self: BossServiceServer, boss: BossObject)
	local runtimeId = resolveBossId(boss)
	if runtimeId == "" then
		return
	end

	self.controllersById[runtimeId] = nil
	if self.controllersByChannel[boss.encounterChannel] == boss then
		self.controllersByChannel[boss.encounterChannel] = nil
	end

	disconnect(self.modelDestroyConnectionsById[runtimeId])
	self.modelDestroyConnectionsById[runtimeId] = nil
	self.boundModelsById[runtimeId] = nil
end

function BossServiceServer.SyncControllerSnapshot(
	self: BossServiceServer,
	boss: BossObject,
	forceRaw: any?
): BossSnapshot?
	local force = forceRaw == true
	local now = self:getNow()
	if not force then
		if boss.snapshotDirty ~= true then
			return nil
		end
		if now - boss.lastSnapshotAt < self.statePushInterval then
			return nil
		end
	end

	local snapshot = self:upsertControllerState(boss)
	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_UPDATED, snapshot)
	return snapshot
end

function BossServiceServer.RemoveController(self: BossServiceServer, runtimeIdRaw: any, reasonRaw: any?)
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return
	end

	local boss = self.controllersById[runtimeId]
	if boss == nil then
		return
	end

	self:untrackController(boss)
	self.state.byId[runtimeId] = nil
	self:removeOrderedId(runtimeId)
	self.state.updatedAt = self:getNow()

	local reason = trim(reasonRaw)
	if reason ~= "" then
		boss.lastReason = reason
	end

	boss:destroy()
	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_REMOVED, runtimeId)
end

function BossServiceServer.SpawnBoss(self: BossServiceServer, requestRaw: any): (BossObject?, string?)
	local request, definition, requestError = self:resolveSpawnRequest(requestRaw)
	if request == nil or definition == nil then
		return nil, requestError
	end

	if definition.singletonPerChannel and self:isEncounterChannelBusy(request.encounterChannel) then
		return nil, "encounter_channel_busy"
	end

	if definition.nightOnlySummon and request.spawnSource ~= "DebugCommand" and not self:isNightTime() then
		return nil, "night_only"
	end

	local constructor = self:resolveControllerConstructor(definition)
	if constructor == nil then
		return nil, "missing_controller_constructor"
	end

	local constructOk, bossOrError = pcall(function()
		return constructor(self, definition, request)
	end)
	if not constructOk then
		return nil, "controller_construction_error"
	end

	local boss = bossOrError
	if boss == nil then
		return nil, "controller_construction_failed"
	end

	local spawnOk, spawnError = pcall(function()
		boss:spawn()
	end)
	if not spawnOk then
		destroyBossSafely(boss)
		return nil, "controller_spawn_failed"
	end

	self:trackController(boss)
	self:refreshControllerModelBinding(boss)

	local afterSpawn = (boss :: any).afterSpawn
	if typeof(afterSpawn) == "function" then
		local afterSpawnOk, afterSpawnError = pcall(function()
			afterSpawn(boss)
		end)
		if not afterSpawnOk then
			self:untrackController(boss)
			destroyBossSafely(boss)
			return nil, "controller_after_spawn_failed"
		end
	end

	local snapshot = self:upsertControllerState(boss)
	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_BOSS_ADDED, snapshot)
	return boss, nil
end

function BossServiceServer.ResolveEncounterTarget(self: BossServiceServer, boss: BossObject): Player?
	local currentTarget = boss.targetPlayer
	if currentTarget ~= nil and BossServiceUtils.isPlayerAlive(currentTarget) then
		return currentTarget
	end

	local bossPosition = boss.position
	local nearestPlayer = nil :: Player?
	local nearestDistance = math.huge
	for _, player in Players:GetPlayers() do
		if not BossServiceUtils.isPlayerAlive(player) then
			continue
		end
		local rootPart = BossServiceUtils.resolveCharacterRootPart(player)
		if rootPart == nil then
			continue
		end

		local distance = (BossServiceUtils.projectPositionToPlaneX(rootPart.Position, boss.planeX) - bossPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearestPlayer = player
		end
	end

	return nearestPlayer
end

function BossServiceServer.ResolveControllerFromInstance(self: BossServiceServer, instanceRaw: any): BossObject?
	local runtimeId = BossServiceUtils.resolveRuntimeIdFromInstance(instanceRaw)
	if runtimeId == nil then
		return nil
	end

	return self.controllersById[runtimeId]
end

function BossServiceServer.DamageBossFromHitPart(
	self: BossServiceServer,
	hitPartRaw: any,
	damageRaw: any,
	sourceRaw: any?,
	damageContextRaw: any?
): number
	local boss = self:resolveControllerFromInstance(hitPartRaw)
	if boss == nil then
		return 0
	end

	local appliedDamage = boss:takeDamage(damageRaw, sourceRaw, damageContextRaw)
	if appliedDamage > 0 then
		self:syncControllerSnapshot(boss, true)
	end
	return appliedDamage
end

function BossServiceServer.DamageBossesInBox(
	self: BossServiceServer,
	queryCFrameRaw: any,
	querySizeRaw: any,
	damageRaw: any,
	sourceRaw: any?,
	damageContextRaw: any?
): number
	if typeof(queryCFrameRaw) ~= "CFrame" or typeof(querySizeRaw) ~= "Vector3" then
		return 0
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.MaxParts = DEFAULT_BOX_QUERY_MAX_PARTS

	local ok, partsOrError = pcall(function()
		return Workspace:GetPartBoundsInBox(queryCFrameRaw, querySizeRaw, overlapParams)
	end)
	if not ok or typeof(partsOrError) ~= "table" then
		return 0
	end

	local totalAppliedDamage = 0
	local seenIds = {}
	for _, part in partsOrError do
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
			continue
		end

		local runtimeId = BossServiceUtils.resolveRuntimeIdFromInstance(part)
		if runtimeId == nil or seenIds[runtimeId] == true then
			continue
		end
		seenIds[runtimeId] = true

		local boss = self.controllersById[runtimeId]
		if boss == nil then
			continue
		end

		local appliedDamage = boss:takeDamage(damageRaw, sourceRaw, damageContextRaw)
		if appliedDamage > 0 then
			totalAppliedDamage += appliedDamage
			self:syncControllerSnapshot(boss, true)
		end
	end

	return totalAppliedDamage
end

function BossServiceServer.CreateUniqueDebugEncounterChannel(
	self: BossServiceServer,
	bossId: BossId,
	player: Player,
	indexRaw: any
): string
	local index = math.max(1, math.floor(BossServiceUtils.sanitizeNumber(indexRaw, 1, 1, 10 ^ 6)))
	return ("debug.%s.%d.%d.%d"):format(
		BossServiceUtils.normalizeToken(bossId),
		player.UserId,
		math.floor(self:getNow() * 1000 + 0.5),
		index
	)
end

function BossServiceServer.BroadcastAnnouncement(self: BossServiceServer, textRaw: any, bossIdRaw: any?)
	local text = trim(textRaw)
	if text == "" then
		return
	end

	self:broadcast(BossServiceUtils.CLIENT_METHOD_ON_ANNOUNCEMENT, {
		text = text,
		bossId = bossIdRaw,
		updatedAt = self:getNow(),
	})
end

function BossServiceServer.ResolveNaturalSpawnTargetPlayer(self: BossServiceServer): Player?
	local alivePlayers = {}
	for _, player in Players:GetPlayers() do
		if BossServiceUtils.isPlayerAlive(player) then
			table.insert(alivePlayers, player)
		end
	end

	if #alivePlayers <= 0 then
		return nil
	end

	return alivePlayers[self.random:NextInteger(1, #alivePlayers)]
end

function BossServiceServer.ScheduleNaturalSpawn(self: BossServiceServer, definition: BossRegistryEntry)
	if self.pendingNaturalSpawn ~= nil then
		return
	end

	local targetPlayer = self:resolveNaturalSpawnTargetPlayer()
	if targetPlayer == nil then
		return
	end

	local defaultConfig = self.defaultConfigByBossId[definition.id]
	if typeof(defaultConfig) ~= "table" or defaultConfig.naturalSpawnEnabled ~= true then
		return
	end

	local spawnChance = BossServiceUtils.sanitizeNumber(defaultConfig.naturalSpawnChancePerNight, 0, 0, 1)
	if spawnChance <= 0 then
		return
	end
	if self.random:NextNumber() > spawnChance then
		return
	end

	local announcement = if definition.naturalSpawnAnnouncement ~= nil
		then definition.naturalSpawnAnnouncement
		else ("A %s is approaching..."):format(definition.displayName)
	self.pendingNaturalSpawn = {
		bossId = definition.id,
		targetPlayer = targetPlayer,
		encounterChannel = definition.encounterChannel,
		delayRemaining = BossServiceUtils.sanitizeNumber(defaultConfig.naturalSpawnAnnouncementDelay, 2, 0, 30),
		announcement = announcement,
	}
	self:broadcastAnnouncement(announcement, definition.id)
end

function BossServiceServer.StepNaturalSpawns(self: BossServiceServer, dt: number, previousClockTime: number, currentClockTime: number)
	if BossServiceUtils.didClockPass(previousClockTime, currentClockTime, BossServiceUtils.NIGHT_START_CLOCK_TIME) then
		for _, definition in BossServiceUtils.getRegistryEntries() do
			if definition.supportsNaturalSpawn and not self:isEncounterChannelBusy(definition.encounterChannel) then
				self:scheduleNaturalSpawn(definition)
			end
		end
	end

	local pending = self.pendingNaturalSpawn
	if pending == nil then
		return
	end

	if not self:isNightTime() then
		self.pendingNaturalSpawn = nil
		return
	end

	if not BossServiceUtils.isPlayerAlive(pending.targetPlayer) then
		self.pendingNaturalSpawn = nil
		return
	end

	pending.delayRemaining -= dt
	if pending.delayRemaining > 0 then
		return
	end

	if not self:isPlayerAboveSurface(pending.targetPlayer) then
		return
	end

	local controller, reason = self:spawnBoss({
		bossId = pending.bossId,
		targetPlayer = pending.targetPlayer,
		spawnSource = "NaturalSpawn",
		encounterChannel = pending.encounterChannel,
	})

	if controller ~= nil or reason ~= "encounter_channel_busy" then
		self.pendingNaturalSpawn = nil
	end
end

function BossServiceServer.SummonBossForPlayer(
	self: BossServiceServer,
	playerRaw: any,
	bossTokenRaw: any,
	optionsRaw: any?
): (BossObject?, string?)
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil, "invalid_player"
	end

	local definition = BossServiceUtils.getRegistryEntryByToken(bossTokenRaw)
	if definition == nil then
		return nil, "unknown_boss"
	end

	if definition.nightOnlySummon and not self:isNightTime() then
		return nil, "night_only"
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	return self:spawnBoss({
		bossId = definition.id,
		targetPlayer = playerRaw,
		spawnSource = "ManualSummon",
		simulationSpeed = (options :: any).simulationSpeed,
		aggressiveness = (options :: any).aggressiveness,
		expertBehaviorEnabled = (options :: any).expertBehaviorEnabled,
	})
end

function BossServiceServer.RequestManualSummon(self: BossServiceServer, player: Player, bossTokenRaw: any, optionsRaw: any?)
	if self.allowClientManualSummon ~= true then
		return
	end

	self:summonBossForPlayer(player, bossTokenRaw, optionsRaw)
end

function BossServiceServer.GetState(self: BossServiceServer): BossServiceState
	return self:createStateSnapshot()
end

function BossServiceServer.OnHeartbeat(self: BossServiceServer, dtRaw: any)
	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end

	local previousClockTime = self.previousClockTime
	local currentClockTime = self:getClockTime()
	self.naturalSpawnAccumulator += dt
	if self.naturalSpawnAccumulator >= self.naturalSpawnCheckInterval then
		self.naturalSpawnAccumulator = 0
		self:stepNaturalSpawns(dt, previousClockTime, currentClockTime)
	end
	self.previousClockTime = currentClockTime

	local orderedIds = Sift.Dictionary.copy(self.state.orderedIds)
	for _, runtimeId in orderedIds do
		local boss = self.controllersById[runtimeId]
		if boss == nil then
			continue
		end

		if boss.removeRequested == true then
			self:removeController(runtimeId, boss.removeReason)
			continue
		end

		local simulationSpeed = 1
		local getSimulationSpeed = (boss :: any).getSimulationSpeed
		if typeof(getSimulationSpeed) == "function" then
			simulationSpeed = BossServiceUtils.sanitizeNumber(getSimulationSpeed(boss), 1, 0.05, 5)
		end

		boss:step(dt * simulationSpeed)
		self:refreshControllerModelBinding(boss)

		if boss.removeRequested == true then
			self:removeController(runtimeId, boss.removeReason)
			continue
		end

		self:syncControllerSnapshot(boss, false)
	end
end

function BossServiceServer.TrackPlayer(self: BossServiceServer, player: Player)
	self:pushState(player)
end

function BossServiceServer.UntrackPlayer(self: BossServiceServer, _player: Player)
	return
end

function BossServiceServer.Init(self: BossServiceServer)
	self.networker = Networker.server.new("BossService", self, {
		self.RequestSync,
		self.RequestManualSummon,
	})
	self.hpService = HpServiceServer :: HpServiceServerObject
	self.weatherService = WeatherServiceServer :: WeatherServiceServerObject
	self.worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.controllersById = {}
	self.controllersByChannel = {}
	self.boundModelsById = {}
	self.modelDestroyConnectionsById = {}
	self.state = BossServiceUtils.createDefaultState()
	self.statePushInterval = DEFAULT_STATE_PUSH_INTERVAL
	self.naturalSpawnCheckInterval = DEFAULT_NATURAL_SPAWN_CHECK_INTERVAL
	self.naturalSpawnAccumulator = 0
	self.random = Random.new()
	self.world = nil
	self.pendingNaturalSpawn = nil
	self.allowClientManualSummon = false
	self.defaultConfigByBossId = {
		EyeOfCthulhu = EyeOfCthulhuConfig.resolve(resolveEyeConfigSource()),
	}
	self.previousClockTime = self:getClockTime()

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

function BossServiceServer.Destroy(self: BossServiceServer)
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

	local runtimeIds = Sift.Dictionary.copy(self.state.orderedIds)
	for _, runtimeId in runtimeIds do
		self:removeController(runtimeId, "service_destroy")
	end

	for runtimeId, connection in self.modelDestroyConnectionsById do
		disconnect(connection)
		self.modelDestroyConnectionsById[runtimeId] = nil
	end

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

BossServiceServer.getNow = BossServiceServer.GetNow
BossServiceServer.getClockTime = BossServiceServer.GetClockTime
BossServiceServer.isNightTime = BossServiceServer.IsNightTime
BossServiceServer.getWorld = BossServiceServer.GetWorld
BossServiceServer.getSurfaceYAtWorldPosition = BossServiceServer.GetSurfaceYAtWorldPosition
BossServiceServer.isPlayerAboveSurface = BossServiceServer.IsPlayerAboveSurface
BossServiceServer.damagePlayer = BossServiceServer.DamagePlayer
BossServiceServer.ensureOrderedId = BossServiceServer.EnsureOrderedId
BossServiceServer.removeOrderedId = BossServiceServer.RemoveOrderedId
BossServiceServer.createSnapshot = BossServiceServer.CreateSnapshot
BossServiceServer.upsertControllerState = BossServiceServer.UpsertControllerState
BossServiceServer.createStateSnapshot = BossServiceServer.CreateStateSnapshot
BossServiceServer.broadcast = BossServiceServer.Broadcast
BossServiceServer.pushState = BossServiceServer.PushState
BossServiceServer.requestSync = BossServiceServer.RequestSync
BossServiceServer.resolveSpawnRequest = BossServiceServer.ResolveSpawnRequest
BossServiceServer.isEncounterChannelBusy = BossServiceServer.IsEncounterChannelBusy
BossServiceServer.resolveControllerConstructor = BossServiceServer.ResolveControllerConstructor
BossServiceServer.refreshControllerModelBinding = BossServiceServer.RefreshControllerModelBinding
BossServiceServer.trackController = BossServiceServer.TrackController
BossServiceServer.untrackController = BossServiceServer.UntrackController
BossServiceServer.syncControllerSnapshot = BossServiceServer.SyncControllerSnapshot
BossServiceServer.removeController = BossServiceServer.RemoveController
BossServiceServer.spawnBoss = BossServiceServer.SpawnBoss
BossServiceServer.resolveEncounterTarget = BossServiceServer.ResolveEncounterTarget
BossServiceServer.resolveControllerFromInstance = BossServiceServer.ResolveControllerFromInstance
BossServiceServer.damageBossFromHitPart = BossServiceServer.DamageBossFromHitPart
BossServiceServer.damageBossesInBox = BossServiceServer.DamageBossesInBox
BossServiceServer.createUniqueDebugEncounterChannel = BossServiceServer.CreateUniqueDebugEncounterChannel
BossServiceServer.broadcastAnnouncement = BossServiceServer.BroadcastAnnouncement
BossServiceServer.resolveNaturalSpawnTargetPlayer = BossServiceServer.ResolveNaturalSpawnTargetPlayer
BossServiceServer.scheduleNaturalSpawn = BossServiceServer.ScheduleNaturalSpawn
BossServiceServer.stepNaturalSpawns = BossServiceServer.StepNaturalSpawns
BossServiceServer.summonBossForPlayer = BossServiceServer.SummonBossForPlayer
BossServiceServer.requestManualSummon = BossServiceServer.RequestManualSummon
BossServiceServer.getState = BossServiceServer.GetState
BossServiceServer.onHeartbeat = BossServiceServer.OnHeartbeat
BossServiceServer.trackPlayer = BossServiceServer.TrackPlayer
BossServiceServer.untrackPlayer = BossServiceServer.UntrackPlayer
BossServiceServer.init = BossServiceServer.Init
BossServiceServer.destroy = BossServiceServer.Destroy

type BossServiceServer = typeof(BossServiceServer) & {
	networker: Networker.Server,
	hpService: HpServiceServerObject,
	weatherService: WeatherServiceServerObject,
	worldGenerationService: WorldGenerationServiceServerObject,
	controllersById: { [string]: BossObject },
	controllersByChannel: { [string]: BossObject },
	boundModelsById: { [string]: Model? },
	modelDestroyConnectionsById: { [string]: RBXScriptConnection? },
	state: BossServiceState,
	statePushInterval: number,
	naturalSpawnCheckInterval: number,
	naturalSpawnAccumulator: number,
	random: Random,
	world: any?,
	pendingNaturalSpawn: PendingNaturalSpawn?,
	allowClientManualSummon: boolean,
	defaultConfigByBossId: { [BossId]: { [string]: any } },
	previousClockTime: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return BossServiceServer :: BossServiceServer
