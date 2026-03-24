--!strict
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Networker = require(ReplicatedStorage.Packages.Networker)
local Commands = require(ReplicatedStorage.Shared.Services.DevPromptService.Commands)
local DevPromptServiceUtils = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceUtils)
local Role = require(ReplicatedStorage.Shared.Services.DevPromptService.Role)
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local HpServiceServer = require(ServerScriptService.Services.HpService.HpServiceServer)
local InventoryServiceServer = require(ServerScriptService.Services.InventoryService.InventoryServiceServer)
local ManaServiceServer = require(ServerScriptService.Services.ManaService.ManaServiceServer)
local PlayerServiceServer = require(ServerScriptService.Services.PlayerService.PlayerServiceServer)
local BossServiceServer = require(ServerScriptService.Services.BossService.BossServiceServer)
local NpcServiceServer = require(ServerScriptService.Services.NpcService.NpcServiceServer)
local MagicServiceServer = require(ServerScriptService.Services.MagicService.MagicServiceServer)
local WeatherServiceServer = require(ServerScriptService.Services.WeatherService.WeatherServiceServer)
local WeatherServiceUtils = require(ReplicatedStorage.Shared.Services.WeatherService.WeatherServiceUtils)

type CommandResult = Commands.CommandResult
type ConsoleEntry = DevPromptServiceUtils.ConsoleEntry
type DevPromptState = DevPromptServiceUtils.DevPromptState
type PlayerRoleSnapshot = Role.PlayerRoleSnapshot
type RoleId = Role.RoleId
type RoleOverrides = Role.RoleOverrides
type RoleResolveContext = Role.RoleResolveContext
type WeatherType = WeatherServiceUtils.WeatherType
type WeatherServiceState = WeatherServiceUtils.WeatherServiceState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type PlayerRuntime = {
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
}

local DevPromptServiceServer = {}

local DEFAULT_ADMIN_MIN_GROUP_RANK = 254
local DEFAULT_MODERATOR_MIN_GROUP_RANK = 200
local DEV_COMMAND_MAX_HEALTH = 500
local DEV_COMMAND_MAX_MANA = 200
local DEV_COMMAND_DEFAULT_FLY_SPEED = DevPromptServiceUtils.DEFAULT_FLY_SPEED
local DEV_COMMAND_MIN_FLY_SPEED = DevPromptServiceUtils.MIN_FLY_SPEED
local DEV_COMMAND_MAX_FLY_SPEED = DevPromptServiceUtils.MAX_FLY_SPEED

local GREEN_SLIME_VARIANTS = {
	slime = true,
	green = true,
	greenslime = true,
}

local EYE_OF_CTHULHU_VARIANTS = {
	eye = true,
	eyeofcthulhu = true,
	eoc = true,
}

local function normalizeToken(valueRaw: any): string
	local text = DevPromptServiceUtils.trim(valueRaw)
	if text == "" then
		return ""
	end
	return string.lower(string.gsub(text, "[%s_%-%.]", ""))
end

local function resolveCharacterHumanoid(characterRaw: any): Humanoid?
	if typeof(characterRaw) ~= "Instance" or not characterRaw:IsA("Model") then
		return nil
	end
	local character = characterRaw :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		return humanoid
	end
	return nil
end

local function resolveCharacterRootPart(characterRaw: any): BasePart?
	if typeof(characterRaw) ~= "Instance" or not characterRaw:IsA("Model") then
		return nil
	end
	local character = characterRaw :: Model
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end
	return nil
end

local function cloneRoleSnapshot(snapshot: PlayerRoleSnapshot): PlayerRoleSnapshot
	return DevPromptServiceUtils.clonePlayerRoleSnapshot(snapshot)
end

local function createPlayerRuntime(): PlayerRuntime
	return {
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
	}
end

function DevPromptServiceServer.resolveOwnerInfo(self: DevPromptServiceServer)
	self.ownerUserId = nil
	self.ownerName = ""
	self.creatorGroupId = nil

	if game.CreatorType == Enum.CreatorType.User then
		self.ownerUserId = DevPromptServiceUtils.sanitizeUserId(game.CreatorId)
	elseif game.CreatorType == Enum.CreatorType.Group then
		self.creatorGroupId = DevPromptServiceUtils.sanitizeUserId(game.CreatorId)
		if self.creatorGroupId ~= nil then
			local ok, groupInfoOrError = pcall(function()
				return GroupService:GetGroupInfoAsync(self.creatorGroupId :: number)
			end)
			if ok and typeof(groupInfoOrError) == "table" then
				local ownerInfo = (groupInfoOrError :: any).Owner
				if typeof(ownerInfo) == "table" then
					self.ownerUserId = DevPromptServiceUtils.sanitizeUserId((ownerInfo :: any).Id)
					self.ownerName = DevPromptServiceUtils.trim((ownerInfo :: any).Name)
				end
			end
		end
	end

	if self.ownerUserId ~= nil and self.ownerName == "" then
		local ok, nameOrError = pcall(function()
			return Players:GetNameFromUserIdAsync(self.ownerUserId :: number)
		end)
		if ok and typeof(nameOrError) == "string" then
			self.ownerName = nameOrError
		end
	end
end

function DevPromptServiceServer.getRoleResolveContext(self: DevPromptServiceServer): RoleResolveContext
	return {
		ownerUserId = self.ownerUserId,
		creatorGroupId = self.creatorGroupId,
		roleOverrides = self.roleOverrides,
		adminMinGroupRank = self.adminMinGroupRank,
		moderatorMinGroupRank = self.moderatorMinGroupRank,
	}
end

function DevPromptServiceServer.getOrCreatePlayerRuntime(self: DevPromptServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end

	local nextRuntime = createPlayerRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function DevPromptServiceServer.attachGodmodeToHumanoid(
	self: DevPromptServiceServer,
	player: Player,
	humanoid: Humanoid,
	runtime: PlayerRuntime
)
	local function refill()
		if self.godmodeUsers[player.UserId] ~= true then
			return
		end
		if humanoid.Parent == nil then
			return
		end
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = humanoid.MaxHealth
		end
	end

	task.defer(refill)
	runtime.characterJanitor:GiveChore(humanoid.HealthChanged:Connect(function()
		task.defer(refill)
	end))
	runtime.characterJanitor:GiveChore(humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		task.defer(refill)
	end))
end

function DevPromptServiceServer.bindCharacter(self: DevPromptServiceServer, player: Player, character: Model)
	local runtime = self:getOrCreatePlayerRuntime(player)
	runtime.characterJanitor:Clean()

	local function bindHumanoid(humanoid: Humanoid)
		if self.godmodeUsers[player.UserId] == true then
			self:attachGodmodeToHumanoid(player, humanoid, runtime)
		end
	end

	local humanoid = resolveCharacterHumanoid(character)
	if humanoid ~= nil then
		bindHumanoid(humanoid)
	end

	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			bindHumanoid(child)
		end
	end))

	if self.flySpeeds[player.UserId] ~= nil and PlayerServiceServer ~= nil then
		pcall(function()
			PlayerServiceServer:setMovementLocked(player, false, true)
		end)
	end
end

function DevPromptServiceServer.refreshPlayerRole(self: DevPromptServiceServer, player: Player)
	local roleId = Role.resolveRoleIdForPlayer(player, self:getRoleResolveContext())
	local snapshot = Role.createSnapshot(roleId, player.UserId, player.Name, player.DisplayName)
	snapshot.canUseCommands = self:isOwnerPlayer(player)
	self.playerRoles[player] = snapshot

	player:SetAttribute(DevPromptServiceUtils.ROLE_ATTRIBUTE, snapshot.roleId)
	player:SetAttribute(DevPromptServiceUtils.CAN_USE_COMMANDS_ATTRIBUTE, self:isOwnerPlayer(player))
	player:SetAttribute(DevPromptServiceUtils.GODMODE_ATTRIBUTE, self.godmodeUsers[player.UserId] == true)
	local flySpeed = self.flySpeeds[player.UserId]
	local flyEnabled = flySpeed ~= nil
	player:SetAttribute(DevPromptServiceUtils.FLY_ATTRIBUTE, flyEnabled)
	player:SetAttribute(DevPromptServiceUtils.FLY_SPEED_ATTRIBUTE, if flyEnabled then flySpeed else nil)
end

function DevPromptServiceServer.refreshAllPlayerRoles(self: DevPromptServiceServer)
	for _, player in Players:GetPlayers() do
		self:refreshPlayerRole(player)
	end
end

function DevPromptServiceServer.bindPlayer(self: DevPromptServiceServer, player: Player)
	local runtime = self:getOrCreatePlayerRuntime(player)
	runtime.playerJanitor:Clean()

	self:refreshPlayerRole(player)
	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:bindCharacter(player, character)
	end))
	if player.Character ~= nil then
		self:bindCharacter(player, player.Character)
	end
end

function DevPromptServiceServer.unbindPlayer(self: DevPromptServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
	end
	self.playerRoles[player] = nil
end

function DevPromptServiceServer.getPlayerRoleSnapshot(self: DevPromptServiceServer, player: Player): PlayerRoleSnapshot?
	local snapshot = self.playerRoles[player]
	if snapshot == nil then
		return nil
	end
	return cloneRoleSnapshot(snapshot)
end

function DevPromptServiceServer.getSortedPlayerRoleSnapshots(self: DevPromptServiceServer): { PlayerRoleSnapshot }
	local snapshots = {}
	for _, snapshot in self.playerRoles do
		snapshots[#snapshots + 1] = cloneRoleSnapshot(snapshot)
	end
	table.sort(snapshots, function(a, b)
		if a.priority == b.priority then
			return a.userName < b.userName
		end
		return a.priority > b.priority
	end)
	return snapshots
end

function DevPromptServiceServer.createPlayerRolesPayload(self: DevPromptServiceServer): { [string]: PlayerRoleSnapshot }
	local payload = {}
	for _, snapshot in self.playerRoles do
		payload[tostring(snapshot.userId)] = cloneRoleSnapshot(snapshot)
	end
	return payload
end

function DevPromptServiceServer.createStateSnapshot(self: DevPromptServiceServer, player: Player): DevPromptState
	local snapshot = self.playerRoles[player]
	local localRoleId = if snapshot ~= nil then snapshot.roleId else "Member"
	return DevPromptServiceUtils.sanitizeState({
		ownerUserId = self.ownerUserId,
		ownerName = self.ownerName,
		localRoleId = localRoleId,
		canUseCommands = self:isOwnerPlayer(player),
		playerRoles = self:createPlayerRolesPayload(),
		commandPrefix = self.commandPrefix,
		maxEntries = self.maxEntries,
		entries = {},
		isOpen = false,
	}, DevPromptServiceUtils.createDefaultState())
end

function DevPromptServiceServer.pushState(self: DevPromptServiceServer, player: Player)
	self.networker:fire(player, DevPromptServiceUtils.CLIENT_METHOD_APPLY_STATE, self:createStateSnapshot(player))
end

function DevPromptServiceServer.broadcastState(self: DevPromptServiceServer)
	for _, player in Players:GetPlayers() do
		self:pushState(player)
	end
end

function DevPromptServiceServer.sendEntries(
	self: DevPromptServiceServer,
	player: Player,
	entriesRaw: { ConsoleEntry },
	clearBeforeRaw: any
)
	local clearBefore = clearBeforeRaw == true
	local entries = DevPromptServiceUtils.cloneEntries(entriesRaw)
	if #entries <= 0 and not clearBefore then
		return
	end
	self.networker:fire(player, DevPromptServiceUtils.CLIENT_METHOD_RECEIVE_ENTRIES, entries, clearBefore)
end

function DevPromptServiceServer.requestSync(self: DevPromptServiceServer, player: Player)
	self:pushState(player)
end

function DevPromptServiceServer.getUnauthorizedCommandMessage(self: DevPromptServiceServer): string
	if self.ownerUserId == nil then
		return "Developer commands are disabled because the owner could not be resolved."
	end
	if self.ownerName ~= "" then
		return ("Only the resolved owner (%s) can use developer commands."):format(self.ownerName)
	end
	return ("Only the resolved owner (%d) can use developer commands."):format(self.ownerUserId)
end

function DevPromptServiceServer.isOwnerPlayer(self: DevPromptServiceServer, player: Player): boolean
	if self.ownerUserId == nil then
		return false
	end
	return player.UserId == self.ownerUserId
end

function DevPromptServiceServer.canPlayerUseCommands(self: DevPromptServiceServer, player: Player): boolean
	return self:isOwnerPlayer(player)
end

function DevPromptServiceServer.resolvePlayerQuery(
	_self: DevPromptServiceServer,
	queryRaw: any,
	defaultPlayerRaw: Player?
): (Player?, string?)
	local defaultPlayer = if typeof(defaultPlayerRaw) == "Instance" and defaultPlayerRaw:IsA("Player")
		then defaultPlayerRaw
		else nil
	local query = DevPromptServiceUtils.trim(queryRaw)
	if query == "" then
		if defaultPlayer ~= nil then
			return defaultPlayer, nil
		end
		return nil, "A player name is required."
	end

	local normalizedQuery = string.lower(query)
	if normalizedQuery == "me" or normalizedQuery == "self" then
		if defaultPlayer ~= nil then
			return defaultPlayer, nil
		end
	end

	local exactMatch: Player? = nil
	local partialMatches = {}
	for _, player in Players:GetPlayers() do
		local playerName = string.lower(player.Name)
		local displayName = string.lower(player.DisplayName)
		if playerName == normalizedQuery or displayName == normalizedQuery then
			exactMatch = player
			break
		end
		if string.sub(playerName, 1, #normalizedQuery) == normalizedQuery
			or string.sub(displayName, 1, #normalizedQuery) == normalizedQuery then
			partialMatches[#partialMatches + 1] = player
		end
	end

	if exactMatch ~= nil then
		return exactMatch, nil
	end
	if #partialMatches == 1 then
		return partialMatches[1], nil
	end
	if #partialMatches > 1 then
		return nil, ("Player query \"%s\" matched multiple players."):format(query)
	end

	return nil, ("Player \"%s\" was not found."):format(query)
end

function DevPromptServiceServer.healPlayerTarget(
	_self: DevPromptServiceServer,
	targetPlayer: Player,
	amountRaw: any
): (boolean, number)
	local amount = if typeof(amountRaw) == "number" and amountRaw == amountRaw then amountRaw else 999999
	local resultingHealth = HpServiceServer:healPlayer(targetPlayer, amount)
	if resultingHealth == nil then
		return false, 0
	end
	return true, resultingHealth
end

function DevPromptServiceServer.setPlayerMaxHealthTarget(
	_self: DevPromptServiceServer,
	targetPlayer: Player,
	amountRaw: any
): (boolean, number, number)
	local requestedAmount = if typeof(amountRaw) == "number" and amountRaw == amountRaw then amountRaw else 0
	local nextMaxHealth = math.clamp(math.floor(requestedAmount), 1, DEV_COMMAND_MAX_HEALTH)
	local appliedMaxHealth = HpServiceServer:setPlayerMaxHealth(targetPlayer, nextMaxHealth, true)
	if appliedMaxHealth == nil then
		return false, 0, 0
	end

	local state = HpServiceServer:getState(targetPlayer)
	return true, state.health, state.maxHealth
end

function DevPromptServiceServer.setPlayerMaxManaTarget(
	_self: DevPromptServiceServer,
	targetPlayer: Player,
	amountRaw: any
): (boolean, number, number)
	local requestedAmount = if typeof(amountRaw) == "number" and amountRaw == amountRaw then amountRaw else 0
	local nextMaxMana = math.clamp(math.floor(requestedAmount), 1, DEV_COMMAND_MAX_MANA)
	local appliedMaxMana = ManaServiceServer:setMaxMana(targetPlayer, nextMaxMana)
	if appliedMaxMana == nil then
		return false, 0, 0
	end

	local appliedMana = ManaServiceServer:setMana(targetPlayer, appliedMaxMana)
	if appliedMana == nil then
		return false, 0, 0
	end

	local state = ManaServiceServer:getState(targetPlayer)
	return true, state.mana, state.maxMana
end

function DevPromptServiceServer.giveItemToPlayer(
	_self: DevPromptServiceServer,
	targetPlayer: Player,
	itemIdRaw: any,
	amountRaw: any
): (boolean, string, number, number, string?)
	local canonicalItemId = ItemRegistry.resolveCanonicalItemId(itemIdRaw)
	local requestedAmount = math.clamp(
		if typeof(amountRaw) == "number" and amountRaw == amountRaw then math.floor(amountRaw) else 1,
		1,
		9999
	)
	if canonicalItemId == nil then
		return false, tostring(itemIdRaw), 0, requestedAmount, "unknown_item"
	end

	local result = InventoryServiceServer:addItem(targetPlayer, canonicalItemId, requestedAmount, {
		stackIdPrefix = "devprompt",
	})
	if result.added <= 0 then
		return false, canonicalItemId, 0, requestedAmount, "inventory_full"
	end
	return true, canonicalItemId, result.added, result.requested, nil
end

function DevPromptServiceServer.getWeatherStateSnapshot(_self: DevPromptServiceServer): WeatherServiceState?
	local weatherService = WeatherServiceServer :: any
	if typeof(weatherService) ~= "table" or typeof(weatherService.getState) ~= "function" then
		return nil
	end

	local ok, stateOrError = pcall(function()
		return weatherService:getState()
	end)
	if not ok or typeof(stateOrError) ~= "table" then
		return nil
	end

	return stateOrError :: WeatherServiceState
end

function DevPromptServiceServer.isWeatherServiceEnabled(_self: DevPromptServiceServer): boolean
	local weatherService = WeatherServiceServer :: any
	if typeof(weatherService) ~= "table" then
		return false
	end

	local config = weatherService.config
	if typeof(config) ~= "table" then
		return false
	end

	return (config :: any).enabled == true
end

function DevPromptServiceServer.setWeatherState(
	self: DevPromptServiceServer,
	weatherTypeRaw: any,
	transitionSecondsRaw: any?
): (boolean, WeatherType?, number, string?)
	local weatherService = WeatherServiceServer :: any
	if typeof(weatherService) ~= "table" or typeof(weatherService.setWeather) ~= "function" then
		return false, nil, 0, "service_unavailable"
	end
	if not self:isWeatherServiceEnabled() then
		return false, nil, 0, "service_disabled"
	end

	local config = if typeof(weatherService.config) == "table" then weatherService.config else {}
	local transitionSeconds =
		WeatherServiceUtils.sanitizeNumber(transitionSecondsRaw, (config :: any).weatherTransitionSeconds or 0, 0, 60)

	local ok, weatherTypeOrError = pcall(function()
		return weatherService:setWeather(weatherTypeRaw, transitionSeconds, true)
	end)
	if not ok then
		return false, nil, transitionSeconds, "service_error"
	end

	local state = self:getWeatherStateSnapshot()
	local appliedWeatherType = if state ~= nil
		then state.weatherType
		else WeatherServiceUtils.sanitizeWeatherType(weatherTypeOrError, "Clear")
	local appliedTransition = if state ~= nil then state.weatherTransitionSeconds else transitionSeconds
	return true, appliedWeatherType, appliedTransition, nil
end

function DevPromptServiceServer.setDaylightCycleEnabled(
	self: DevPromptServiceServer,
	enabledRaw: any
): (boolean, boolean, number, string?)
	local weatherService = WeatherServiceServer :: any
	if typeof(weatherService) ~= "table" or typeof(weatherService.setDayNightCycleEnabled) ~= "function" then
		return false, false, 0, "service_unavailable"
	end
	if not self:isWeatherServiceEnabled() then
		return false, false, 0, "service_disabled"
	end

	local ok, enabledOrError = pcall(function()
		return weatherService:setDayNightCycleEnabled(enabledRaw, true)
	end)
	if not ok then
		return false, false, 0, "service_error"
	end

	local state = self:getWeatherStateSnapshot()
	local appliedEnabled = if state ~= nil
		then state.dayNightCycleEnabled
		else WeatherServiceUtils.sanitizeBoolean(enabledOrError, false)
	local clockTime = if state ~= nil then state.clockTime else 0
	return true, appliedEnabled, clockTime, nil
end

function DevPromptServiceServer.setDaylightClockTime(
	self: DevPromptServiceServer,
	clockTimeRaw: any
): (boolean, number, string?)
	local weatherService = WeatherServiceServer :: any
	if typeof(weatherService) ~= "table" or typeof(weatherService.setClockTime) ~= "function" then
		return false, 0, "service_unavailable"
	end
	if not self:isWeatherServiceEnabled() then
		return false, 0, "service_disabled"
	end

	local ok, clockTimeOrError = pcall(function()
		return weatherService:setClockTime(clockTimeRaw, true)
	end)
	if not ok then
		return false, 0, "service_error"
	end

	local state = self:getWeatherStateSnapshot()
	local clockTime = if state ~= nil then state.clockTime else WeatherServiceUtils.sanitizeNumber(clockTimeOrError, 12, 0, 24)
	return true, clockTime, nil
end

function DevPromptServiceServer.clearAllEntities(_self: DevPromptServiceServer): (number, number, number)
	local removedNpcCount = 0
	local removedBossCount = 0
	local removedProjectileCount = 0

	local npcService = NpcServiceServer :: any
	if typeof(npcService) == "table" and typeof(npcService.removeRuntime) == "function" then
		local runtimeIds = {}
		if typeof(npcService.runtimes) == "table" then
			for runtimeId in npcService.runtimes do
				if typeof(runtimeId) == "string" and runtimeId ~= "" then
					runtimeIds[#runtimeIds + 1] = runtimeId
				end
			end
		end

		table.sort(runtimeIds)
		for _, runtimeId in runtimeIds do
			if typeof(npcService.runtimes) == "table" and npcService.runtimes[runtimeId] ~= nil then
				local ok = pcall(function()
					npcService:removeRuntime(runtimeId, "devClearEntities")
				end)
				if ok then
					removedNpcCount += 1
				end
			end
		end
	end

	local bossService = BossServiceServer :: any
	if typeof(bossService) == "table" and typeof(bossService.removeController) == "function" then
		bossService.pendingNaturalSpawn = nil

		local runtimeIds = {}
		local seenRuntimeIds = {}
		local state = bossService.state
		local orderedIds = if typeof(state) == "table" then (state :: any).orderedIds else nil
		if typeof(orderedIds) == "table" then
			for _, runtimeId in orderedIds do
				if typeof(runtimeId) == "string" and runtimeId ~= "" and not seenRuntimeIds[runtimeId] then
					seenRuntimeIds[runtimeId] = true
					runtimeIds[#runtimeIds + 1] = runtimeId
				end
			end
		end
		if typeof(bossService.controllersById) == "table" then
			for runtimeId in bossService.controllersById do
				if typeof(runtimeId) == "string" and runtimeId ~= "" and not seenRuntimeIds[runtimeId] then
					seenRuntimeIds[runtimeId] = true
					runtimeIds[#runtimeIds + 1] = runtimeId
				end
			end
		end

		table.sort(runtimeIds)
		for _, runtimeId in runtimeIds do
			if typeof(bossService.controllersById) == "table" and bossService.controllersById[runtimeId] ~= nil then
				local ok = pcall(function()
					bossService:removeController(runtimeId, "devClearEntities")
				end)
				if ok then
					removedBossCount += 1
				end
			end
		end
	end

	local magicService = MagicServiceServer :: any
	if typeof(magicService) == "table"
		and typeof(magicService.activeProjectiles) == "table"
		and typeof(magicService.releaseProjectile) == "function" then
		local projectileIds = {}
		for projectileId in magicService.activeProjectiles do
			if typeof(projectileId) == "number" and projectileId == projectileId then
				projectileIds[#projectileIds + 1] = projectileId
			end
		end

		table.sort(projectileIds)
		for _, projectileId in projectileIds do
			local projectile = magicService.activeProjectiles[projectileId]
			if projectile ~= nil then
				magicService.activeProjectiles[projectileId] = nil
				local ok = pcall(function()
					magicService:releaseProjectile(projectile)
				end)
				if ok then
					removedProjectileCount += 1
				end
			end
		end
	end

	return removedNpcCount, removedBossCount, removedProjectileCount
end

function DevPromptServiceServer.spawnEntityForPlayer(
	_self: DevPromptServiceServer,
	player: Player,
	entityTokenRaw: any,
	amountRaw: any,
	optionsRaw: any?
): (boolean, number, string?)
	local normalized = normalizeToken(entityTokenRaw)
	local spawnSlime = GREEN_SLIME_VARIANTS[normalized] == true
	local spawnEyeOfCthulhu = EYE_OF_CTHULHU_VARIANTS[normalized] == true
	if not spawnSlime and not spawnEyeOfCthulhu then
		return false, 0, "unsupported_entity"
	end

	local character = player.Character
	local rootPart = resolveCharacterRootPart(character)
	if rootPart == nil then
		return false, 0, "missing_character_root"
	end

	local amount = math.clamp(
		if typeof(amountRaw) == "number" and amountRaw == amountRaw then math.floor(amountRaw) else 1,
		1,
		if spawnEyeOfCthulhu then 5 else 20
	)
	local spawnedCount = 0
	local lastFailureReason = nil :: string?
	local basePosition = if spawnEyeOfCthulhu
		then rootPart.Position + rootPart.CFrame.LookVector * 18 + Vector3.new(0, 20, 0)
		else rootPart.Position + rootPart.CFrame.LookVector * 10 + Vector3.new(0, 3, 0)
	local rightVector = rootPart.CFrame.RightVector

	for index = 1, amount do
		local offset = (index - 1) - ((amount - 1) * 0.5)
		local lateralSpacing = if spawnEyeOfCthulhu then 10 else 4
		local spawnPosition = basePosition + rightVector * (offset * lateralSpacing)
		local spawnCFrame = CFrame.new(spawnPosition)
		local runtime: any = nil
		if spawnEyeOfCthulhu then
			local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
			local spawnOk, controllerOrError, bossReason = pcall(function()
				return BossServiceServer:spawnBoss({
					bossId = "EyeOfCthulhu",
					targetPlayer = player,
					spawnSource = "DebugCommand",
					encounterChannel = BossServiceServer:createUniqueDebugEncounterChannel("EyeOfCthulhu", player, index),
					planeX = rootPart.Position.X,
					simulationSpeed = if typeof((options :: any).simulationSpeed) == "number"
						then (options :: any).simulationSpeed
						else nil,
					aggressiveness = if typeof((options :: any).aggressiveness) == "number"
						then (options :: any).aggressiveness
						else nil,
				})
			end)
			if spawnOk then
				runtime = controllerOrError
				if runtime == nil and typeof(bossReason) == "string" and bossReason ~= "" then
					lastFailureReason = bossReason
				end
			else
				local spawnErrorText = DevPromptServiceUtils.trim(tostring(controllerOrError))
				lastFailureReason = if spawnErrorText ~= ""
					then ("boss_spawn_error: %s"):format(spawnErrorText)
					else "boss_spawn_error"
				warn(("[DevPromptService] Boss spawn failed for %s (%d): %s"):format(
					player.Name,
					player.UserId,
					tostring(controllerOrError)
				))
			end
		else
			local spawnConfig = NpcServiceServer:createDefaultSpawnConfigAt(spawnCFrame)
			if spawnConfig == nil then
				continue
			end
			runtime = NpcServiceServer:spawnSlime(spawnConfig)
		end
		if runtime ~= nil then
			spawnedCount += 1
		end
	end

	if spawnedCount <= 0 then
		return false, 0, if lastFailureReason ~= nil then lastFailureReason else "no_valid_spawn_position"
	end
	return true, spawnedCount, nil
end

function DevPromptServiceServer.setGodmode(self: DevPromptServiceServer, player: Player, enabledRaw: any): boolean
	local current = self.godmodeUsers[player.UserId] == true
	local nextEnabled = if typeof(enabledRaw) == "boolean" then enabledRaw else not current

	if nextEnabled then
		self.godmodeUsers[player.UserId] = true
	else
		self.godmodeUsers[player.UserId] = nil
	end

	player:SetAttribute(DevPromptServiceUtils.GODMODE_ATTRIBUTE, nextEnabled)
	if player.Character ~= nil then
		self:bindCharacter(player, player.Character)
	end
	return nextEnabled
end

function DevPromptServiceServer.setFlyEnabled(
	self: DevPromptServiceServer,
	player: Player,
	enabledRaw: any,
	speedRaw: any?
): (boolean, number)
	local currentSpeed = self.flySpeeds[player.UserId]
	local currentEnabled = currentSpeed ~= nil
	local nextEnabled = if typeof(enabledRaw) == "boolean" then enabledRaw else not currentEnabled

	local nextSpeed = DEV_COMMAND_DEFAULT_FLY_SPEED
	if currentSpeed ~= nil then
		nextSpeed = currentSpeed
	end
	if typeof(speedRaw) == "number" and speedRaw == speedRaw then
		nextSpeed = math.clamp(speedRaw, DEV_COMMAND_MIN_FLY_SPEED, DEV_COMMAND_MAX_FLY_SPEED)
	end

	if nextEnabled then
		self.flySpeeds[player.UserId] = nextSpeed
		player:SetAttribute(DevPromptServiceUtils.FLY_ATTRIBUTE, true)
		player:SetAttribute(DevPromptServiceUtils.FLY_SPEED_ATTRIBUTE, nextSpeed)
		if PlayerServiceServer ~= nil then
			pcall(function()
				PlayerServiceServer:setMovementLocked(player, false, true)
			end)
		end
	else
		self.flySpeeds[player.UserId] = nil
		player:SetAttribute(DevPromptServiceUtils.FLY_ATTRIBUTE, false)
		player:SetAttribute(DevPromptServiceUtils.FLY_SPEED_ATTRIBUTE, nil)
	end

	return nextEnabled, nextSpeed
end

function DevPromptServiceServer.submitCommand(self: DevPromptServiceServer, player: Player, commandTextRaw: any)
	local commandText = DevPromptServiceUtils.trim(commandTextRaw)
	if commandText == "" then
		return
	end

	local snapshot = self.playerRoles[player]
	local roleId = if snapshot ~= nil then snapshot.roleId else "Member"
	local response = nil :: CommandResult?
	if self:canPlayerUseCommands(player) then
		response = Commands.execute(self, player, commandText)
	else
		response = {
			ok = false,
			clearBefore = false,
			echoInput = true,
			entries = {
				DevPromptServiceUtils.createConsoleEntry("error", self:getUnauthorizedCommandMessage(), {
					timestamp = os.clock(),
				}),
			},
		}
	end

	local outgoingEntries = {}
	if response.echoInput ~= false then
		outgoingEntries[#outgoingEntries + 1] = DevPromptServiceUtils.createConsoleEntry("command", commandText, {
			userId = player.UserId,
			userName = player.Name,
			roleId = roleId,
			timestamp = os.clock(),
		})
	end
	for _, entry in response.entries do
		outgoingEntries[#outgoingEntries + 1] = DevPromptServiceUtils.cloneConsoleEntry(entry)
	end

	self:sendEntries(player, outgoingEntries, response.clearBefore)
end

function DevPromptServiceServer.init(self: DevPromptServiceServer)
	self.playerRoles = {}
	self.playerRuntimes = {}
	self.godmodeUsers = {}
	self.flySpeeds = {}
	self.roleOverrides = Role.getDefaultRoleOverrides()
	self.commandPrefix = DevPromptServiceUtils.DEFAULT_COMMAND_PREFIX
	self.maxEntries = DevPromptServiceUtils.DEFAULT_MAX_ENTRIES
	self.adminMinGroupRank = DEFAULT_ADMIN_MIN_GROUP_RANK
	self.moderatorMinGroupRank = DEFAULT_MODERATOR_MIN_GROUP_RANK

	self:resolveOwnerInfo()

	self.networker = Networker.server.new("DevPromptService", self, {
		self.requestSync,
		self.submitCommand,
	})

	for _, player in Players:GetPlayers() do
		self:bindPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:bindPlayer(player)
		self:broadcastState()
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:unbindPlayer(player)
		self:broadcastState()
	end)

	self:broadcastState()
end

function DevPromptServiceServer.destroy(self: DevPromptServiceServer)
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	for player in self.playerRuntimes do
		self:unbindPlayer(player)
	end

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

type DevPromptServiceServer = typeof(DevPromptServiceServer) & {
	networker: Networker.Server,
	playerRoles: { [Player]: PlayerRoleSnapshot },
	playerRuntimes: { [Player]: PlayerRuntime },
	godmodeUsers: { [number]: boolean },
	flySpeeds: { [number]: number },
	roleOverrides: RoleOverrides,
	commandPrefix: string,
	maxEntries: number,
	adminMinGroupRank: number,
	moderatorMinGroupRank: number,
	ownerUserId: number?,
	ownerName: string,
	creatorGroupId: number?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return DevPromptServiceServer :: DevPromptServiceServer
