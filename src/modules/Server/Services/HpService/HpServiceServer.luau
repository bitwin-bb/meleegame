--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local CmdrUtils = require(script:FindFirstAncestor("game").Shared.Cmdr.CmdrUtils)
local HpServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.HpService.HpServiceUtils)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)
local PlayerDataServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerDataService.PlayerDataServiceServer)

type HpServiceState = HpServiceUtils.HpServiceState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type PlayerRuntime = {
	state: HpServiceState,
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
	humanoid: Humanoid?,
	loadToken: number,
	pendingPersistedHealth: number?,
	pendingPersistedMaxHealth: number?,
	hasResolvedPersistedLoad: boolean,
	healthChangedBeforePersistedLoad: boolean,
	isApplyingPersistedHealth: boolean,
	suppressDamageFeedbackDepth: number,
	isDeathLocked: boolean,
}

type PlayerDataServiceServerObject = {
	getLoadState: (self: PlayerDataServiceServerObject, player: Player) -> string,
	requestSync: (self: PlayerDataServiceServerObject, player: Player) -> (),
	waitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	waitForDataPromise: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	isLoaded: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
	getHpData: (self: PlayerDataServiceServerObject, player: Player, fallback: any) -> any,
	setHpData: (self: PlayerDataServiceServerObject, player: Player, hpDataRaw: any, replicateToClientRaw: any) -> boolean,
	savePlayerData: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
}

local HpServiceServer = {}
local DEFAULT_DATA_LOAD_TIMEOUT_SECONDS = 20
local DEFAULT_DATA_LOAD_RETRY_DELAY_SECONDS = 1
local SUPPRESS_DAMAGE_FEEDBACK_ATTRIBUTE = "HpService_SuppressDamageFeedback"

local function isGodmodeEnabled(playerRaw: any): boolean
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return false
	end

	return playerRaw:GetAttribute(CmdrUtils.GODMODE_ENABLED_ATTRIBUTE) == true
end

local function isHumanoidDead(humanoid: Humanoid): boolean
	if humanoid.Health <= 0 then
		return true
	end
	return humanoid:GetState() == Enum.HumanoidStateType.Dead
end

local function applyHumanoidPresentationSettings(humanoid: Humanoid)
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.HealthDisplayDistance = 0
end

function HpServiceServer.Init(self: HpServiceServer)
	self.networker = Networker.server.new("HpService", self, {
		self.RequestSync,
	})
	self.playerRuntimes = {}
	self.heartValue = HpServiceUtils.DEFAULT_HEART_VALUE
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.dataPath = HpServiceUtils.getDefaultDataPath()
	self.dataLoadTimeoutSeconds = DEFAULT_DATA_LOAD_TIMEOUT_SECONDS
	self.dataLoadRetryDelaySeconds = DEFAULT_DATA_LOAD_RETRY_DELAY_SECONDS

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
end

function HpServiceServer.CreateRuntime(_self: HpServiceServer): PlayerRuntime
	return {
		state = HpServiceUtils.createDefaultState(),
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		humanoid = nil,
		loadToken = 0,
		pendingPersistedHealth = nil,
		pendingPersistedMaxHealth = nil,
		hasResolvedPersistedLoad = false,
		healthChangedBeforePersistedLoad = false,
		isApplyingPersistedHealth = false,
		suppressDamageFeedbackDepth = 0,
		isDeathLocked = false,
	}
end

function HpServiceServer.SetHumanoidHealthWithoutDamageFeedback(
	_self: HpServiceServer,
	runtime: PlayerRuntime,
	humanoid: Humanoid,
	nextHealth: number
)
	runtime.suppressDamageFeedbackDepth += 1
	humanoid:SetAttribute(SUPPRESS_DAMAGE_FEEDBACK_ATTRIBUTE, true)
	humanoid.Health = nextHealth

	task.defer(function()
		runtime.suppressDamageFeedbackDepth = math.max(0, runtime.suppressDamageFeedbackDepth - 1)
		if runtime.suppressDamageFeedbackDepth <= 0 then
			humanoid:SetAttribute(SUPPRESS_DAMAGE_FEEDBACK_ATTRIBUTE, false)
		end
	end)
end

function HpServiceServer.RestoreGodmodeHealth(
	self: HpServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	humanoid: Humanoid
): number
	runtime.isDeathLocked = false
	local targetHealth = math.max(1, humanoid.MaxHealth)
	if math.abs(humanoid.Health - targetHealth) > 1e-3 then
		self:setHumanoidHealthWithoutDamageFeedback(runtime, humanoid, targetHealth)
	end

	self:refreshStateFromHumanoid(player, humanoid)
	return humanoid.Health
end

function HpServiceServer.GetRuntime(self: HpServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime then
		return runtime
	end

	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function HpServiceServer.PushState(self: HpServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	self.networker:fire(player, "applyState", HpServiceUtils.cloneState(runtime.state))
end

function HpServiceServer.PersistRuntime(self: HpServiceServer, player: Player, runtime: PlayerRuntime): boolean
	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return false
	end
	if not playerDataService:isLoaded(player) then
		return false
	end

	local serializedState = HpServiceUtils.serializeStateForData(runtime.state)
	local success, didSet = pcall(function()
		return playerDataService:setHpData(player, serializedState, false)
	end)
	if not success then
		return false
	end

	return didSet == true
end

function HpServiceServer.ApplyPendingPersistedState(
	self: HpServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	humanoid: Humanoid
): boolean
	if runtime.isDeathLocked then
		return false
	end

	local pendingHealth = runtime.pendingPersistedHealth
	local pendingMaxHealth = runtime.pendingPersistedMaxHealth
	if pendingHealth == nil and pendingMaxHealth == nil then
		return false
	end

	local nextMaxHealth = math.max(
		1,
		if typeof(pendingMaxHealth) == "number" and pendingMaxHealth == pendingMaxHealth
			then pendingMaxHealth
			else humanoid.MaxHealth
	)
	local nextHealth = math.clamp(
		if typeof(pendingHealth) == "number" and pendingHealth == pendingHealth then pendingHealth else humanoid.Health,
		0,
		nextMaxHealth
	)
	runtime.pendingPersistedHealth = nil
	runtime.pendingPersistedMaxHealth = nil
	humanoid.MaxHealth = nextMaxHealth
	runtime.isApplyingPersistedHealth = true
	self:setHumanoidHealthWithoutDamageFeedback(runtime, humanoid, nextHealth)
	runtime.isApplyingPersistedHealth = false
	self:refreshStateFromHumanoid(player, humanoid)

	for _, delaySeconds in { 0.05, 0.2, 0.5, 1 } do
		task.delay(delaySeconds, function()
			if runtime.humanoid ~= humanoid then
				return
			end
			if humanoid.Parent == nil then
				return
			end
			if runtime.isDeathLocked then
				return
			end

			local clampedMaxHealth = math.max(1, nextMaxHealth)
			local clampedTarget = math.clamp(nextHealth, 0, clampedMaxHealth)
			if math.abs(humanoid.MaxHealth - clampedMaxHealth) > 1e-3 then
				humanoid.MaxHealth = clampedMaxHealth
			end
			if math.abs(humanoid.Health - clampedTarget) > 1e-3 then
				self:setHumanoidHealthWithoutDamageFeedback(runtime, humanoid, clampedTarget)
			end
			self:refreshStateFromHumanoid(player, humanoid)
		end)
	end

	return true
end

function HpServiceServer.RefreshStateFromHumanoid(self: HpServiceServer, player: Player, humanoid: Humanoid)
	local runtime = self:getRuntime(player)
	if runtime.humanoid == humanoid and runtime.isDeathLocked and humanoid.Health > 0 then
		self:setHumanoidHealthWithoutDamageFeedback(runtime, humanoid, 0)
	end

	runtime.state = HpServiceUtils.createStateFromHumanoid(humanoid, self.heartValue, runtime.state)
	if runtime.hasResolvedPersistedLoad then
		self:persistRuntime(player, runtime)
	end
	self:pushState(player)
end

function HpServiceServer.RetryLoadPersistedHealthLater(
	self: HpServiceServer,
	player: Player,
	loadToken: number
)
	task.delay(self.dataLoadRetryDelaySeconds, function()
		local runtime = self.playerRuntimes[player]
		if runtime == nil or runtime.loadToken ~= loadToken then
			return
		end
		if runtime.hasResolvedPersistedLoad then
			return
		end
		self:loadPersistedHealth(player, loadToken)
	end)
end

function HpServiceServer.LoadPersistedHealth(self: HpServiceServer, player: Player, loadToken: number)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return
	end

	pcall(function()
		playerDataService:requestSync(player)
	end)

	local waitSuccess, nextPlayerData = pcall(function()
		local waitPromise = playerDataService:waitForDataPromise(player, self.dataLoadTimeoutSeconds)
		return select(2, waitPromise:Yield())
	end)
	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end
	if not waitSuccess then
		self:retryLoadPersistedHealthLater(player, loadToken)
		return
	end
	if nextPlayerData == nil then
		local loadStateSuccess, playerDataLoadState = pcall(function()
			return playerDataService:getLoadState(player)
		end)
		if loadStateSuccess and playerDataLoadState == "Loaded" then
			runtime.hasResolvedPersistedLoad = true
			self:persistRuntime(player, runtime)
			self:pushState(player)
			return
		end
		if loadStateSuccess and playerDataLoadState == "Failed" then
			return
		end
		self:retryLoadPersistedHealthLater(player, loadToken)
		return
	end

	local readSuccess, persistedHpRaw = pcall(function()
		return playerDataService:getHpData(player, nil)
	end)
	if not readSuccess then
		runtime.hasResolvedPersistedLoad = true
		self:pushState(player)
		return
	end

	runtime.hasResolvedPersistedLoad = true
	local persistedHealth, persistedMaxHealth =
		HpServiceUtils.resolvePersistedHealthAndMaxHealth(persistedHpRaw, runtime.state.maxHealth)
	if runtime.healthChangedBeforePersistedLoad then
		self:persistRuntime(player, runtime)
		runtime.pendingPersistedHealth = nil
		runtime.pendingPersistedMaxHealth = nil
		self:pushState(player)
		return
	end
	if persistedHealth == nil then
		self:persistRuntime(player, runtime)
		self:pushState(player)
		return
	end

	runtime.pendingPersistedHealth = persistedHealth
	runtime.pendingPersistedMaxHealth = persistedMaxHealth
	runtime.state = HpServiceUtils.createState(persistedHealth, persistedMaxHealth, self.heartValue, runtime.state)
	local humanoid = runtime.humanoid
	if humanoid ~= nil and humanoid.Parent ~= nil then
		self:applyPendingPersistedState(player, runtime, humanoid)
	else
		self:pushState(player)
	end
end

function HpServiceServer.BindHumanoid(self: HpServiceServer, player: Player, humanoid: Humanoid)
	local runtime = self:getRuntime(player)
	runtime.humanoid = humanoid
	runtime.isDeathLocked = isHumanoidDead(humanoid)
	applyHumanoidPresentationSettings(humanoid)
	local didApplyPendingHealth = self:applyPendingPersistedState(player, runtime, humanoid)
	if not didApplyPendingHealth then
		self:refreshStateFromHumanoid(player, humanoid)
	end
	if isGodmodeEnabled(player) then
		self:restoreGodmodeHealth(player, runtime, humanoid)
	end

	runtime.characterJanitor:GiveChore(humanoid.HealthChanged:Connect(function()
		if runtime.humanoid ~= humanoid then
			return
		end
		if isGodmodeEnabled(player) then
			local targetHealth = math.max(1, humanoid.MaxHealth)
			if humanoid.Health + 1e-3 < targetHealth then
				self:restoreGodmodeHealth(player, runtime, humanoid)
				return
			end
		end
		if humanoid.Health <= 0 then
			runtime.isDeathLocked = true
		elseif runtime.isDeathLocked and humanoid.Health > 0 then
			self:setHumanoidHealthWithoutDamageFeedback(runtime, humanoid, 0)
			self:refreshStateFromHumanoid(player, humanoid)
			return
		end

		if not runtime.hasResolvedPersistedLoad and not runtime.isApplyingPersistedHealth then
			if math.abs(humanoid.Health - runtime.state.health) > 1e-3 then
				runtime.healthChangedBeforePersistedLoad = true
			end
		end
		self:refreshStateFromHumanoid(player, humanoid)
	end))

	runtime.characterJanitor:GiveChore(humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if runtime.humanoid ~= humanoid then
			return
		end
		if isGodmodeEnabled(player) then
			self:restoreGodmodeHealth(player, runtime, humanoid)
			return
		end
		self:refreshStateFromHumanoid(player, humanoid)
	end))

	runtime.characterJanitor:GiveChore(humanoid.Destroying:Connect(function()
		if runtime.humanoid == humanoid then
			runtime.humanoid = nil
		end
	end))

	runtime.characterJanitor:GiveChore(humanoid.Died:Connect(function()
		if runtime.humanoid ~= humanoid then
			return
		end
		runtime.isDeathLocked = true
		self:refreshStateFromHumanoid(player, humanoid)
	end))
end

function HpServiceServer.BindCharacter(self: HpServiceServer, player: Player, character: Model)
	local runtime = self:getRuntime(player)
	runtime.characterJanitor:Clean()
	runtime.humanoid = nil
	runtime.isDeathLocked = false

	local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
	if currentHumanoid then
		self:bindHumanoid(player, currentHumanoid)
	end

	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if runtime.humanoid ~= nil then
			return
		end
		if child:IsA("Humanoid") then
			self:bindHumanoid(player, child)
		end
	end))

	runtime.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if runtime.humanoid == child then
			runtime.humanoid = nil
		end
	end))
end

function HpServiceServer.TrackPlayer(self: HpServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.loadToken += 1
	runtime.state = HpServiceUtils.createDefaultState()
	runtime.playerJanitor:Clean()
	runtime.characterJanitor:Clean()
	runtime.humanoid = nil
	runtime.pendingPersistedHealth = nil
	runtime.pendingPersistedMaxHealth = nil
	runtime.hasResolvedPersistedLoad = false
	runtime.healthChangedBeforePersistedLoad = false
	runtime.isApplyingPersistedHealth = false
	runtime.suppressDamageFeedbackDepth = 0
	runtime.isDeathLocked = false

	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:bindCharacter(player, character)
	end))

	if player.Character then
		self:bindCharacter(player, player.Character)
	end
	self:pushState(player)

	local loadToken = runtime.loadToken
	task.spawn(function()
		self:loadPersistedHealth(player, loadToken)
	end)
end

function HpServiceServer.UntrackPlayer(self: HpServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if not runtime then
		return
	end
	self:persistRuntime(player, runtime)
	if self.playerDataService ~= nil then
		pcall(function()
			self.playerDataService:savePlayerData(player)
		end)
	end

	runtime.loadToken += 1
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function HpServiceServer.GetHumanoid(self: HpServiceServer, player: Player): Humanoid?
	local runtime = self:getRuntime(player)
	local cachedHumanoid = runtime.humanoid
	if cachedHumanoid and cachedHumanoid.Parent ~= nil then
		return cachedHumanoid
	end

	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		runtime.humanoid = humanoid
		applyHumanoidPresentationSettings(humanoid)
	end

	return humanoid
end

function HpServiceServer.RequestSync(self: HpServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:trackPlayer(player)
		return
	end

	if not runtime.hasResolvedPersistedLoad then
		local loadToken = runtime.loadToken
		task.spawn(function()
			self:loadPersistedHealth(player, loadToken)
		end)
	end

	self:pushState(player)
end

function HpServiceServer.GetState(self: HpServiceServer, player: Player): HpServiceState
	local runtime = self:getRuntime(player)
	return HpServiceUtils.cloneState(runtime.state)
end

function HpServiceServer.SetPlayerMaxHealth(
	self: HpServiceServer,
	player: Player,
	nextMaxHealthRaw: any,
	fillToMaxRaw: any
): number?
	local runtime = self:getRuntime(player)
	local nextMaxHealth = math.max(
		1,
		if typeof(nextMaxHealthRaw) == "number" and nextMaxHealthRaw == nextMaxHealthRaw
			then nextMaxHealthRaw
			else runtime.state.maxHealth
	)
	local fillToMax = fillToMaxRaw ~= false
	local appliedHealth = if fillToMax then nextMaxHealth else math.clamp(runtime.state.health, 0, nextMaxHealth)
	local stateHealth = if runtime.isDeathLocked then 0 else appliedHealth

	runtime.pendingPersistedMaxHealth = nextMaxHealth
	runtime.pendingPersistedHealth = appliedHealth
	if not runtime.hasResolvedPersistedLoad then
		runtime.healthChangedBeforePersistedLoad = true
	end

	runtime.state = HpServiceUtils.createState(stateHealth, nextMaxHealth, self.heartValue, runtime.state)

	local humanoid = self:getHumanoid(player)
	if humanoid ~= nil and humanoid.Parent ~= nil and not runtime.isDeathLocked then
		self:applyPendingPersistedState(player, runtime, humanoid)
		if not runtime.hasResolvedPersistedLoad then
			self:pushState(player)
		end
	else
		if runtime.hasResolvedPersistedLoad then
			self:persistRuntime(player, runtime)
		end
		self:pushState(player)
	end

	return nextMaxHealth
end

function HpServiceServer.SetPlayerHealth(self: HpServiceServer, player: Player, nextHealthRaw: any): number?
	local runtime = self:getRuntime(player)
	local humanoid = self:getHumanoid(player)
	if not humanoid then
		return nil
	end
	if runtime.isDeathLocked then
		if humanoid.Health > 0 then
			self:setHumanoidHealthWithoutDamageFeedback(runtime, humanoid, 0)
		end
		self:refreshStateFromHumanoid(player, humanoid)
		return humanoid.Health
	end

	local nextHealth = math.clamp(
		if typeof(nextHealthRaw) == "number" then nextHealthRaw else humanoid.Health,
		0,
		math.max(1, humanoid.MaxHealth)
	)
	humanoid.Health = nextHealth
	self:refreshStateFromHumanoid(player, humanoid)
	return nextHealth
end

function HpServiceServer.DamagePlayer(self: HpServiceServer, player: Player, damageRaw: any): number?
	local runtime = self:getRuntime(player)
	local humanoid = self:getHumanoid(player)
	if not humanoid then
		return nil
	end
	if isGodmodeEnabled(player) then
		return self:restoreGodmodeHealth(player, runtime, humanoid)
	end
	if runtime.isDeathLocked then
		self:refreshStateFromHumanoid(player, humanoid)
		return humanoid.Health
	end

	local amount = math.max(0, if typeof(damageRaw) == "number" then damageRaw else 0)
	humanoid:TakeDamage(amount)
	self:refreshStateFromHumanoid(player, humanoid)
	return humanoid.Health
end

function HpServiceServer.HealPlayer(self: HpServiceServer, player: Player, amountRaw: any): number?
	local runtime = self:getRuntime(player)
	local humanoid = self:getHumanoid(player)
	if not humanoid then
		return nil
	end
	if runtime.isDeathLocked then
		if humanoid.Health > 0 then
			self:setHumanoidHealthWithoutDamageFeedback(runtime, humanoid, 0)
		end
		self:refreshStateFromHumanoid(player, humanoid)
		return humanoid.Health
	end

	local amount = math.max(0, if typeof(amountRaw) == "number" then amountRaw else 0)
	local nextHealth = math.clamp(humanoid.Health + amount, 0, math.max(1, humanoid.MaxHealth))
	humanoid.Health = nextHealth
	self:refreshStateFromHumanoid(player, humanoid)
	return nextHealth
end

function HpServiceServer.Destroy(self: HpServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end

	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	for player, runtime in self.playerRuntimes do
		self:persistRuntime(player, runtime)
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
	end

	if self.networker then
		self.networker:destroy()
	end
end

HpServiceServer.init = HpServiceServer.Init
HpServiceServer.createRuntime = HpServiceServer.CreateRuntime
HpServiceServer.setHumanoidHealthWithoutDamageFeedback = HpServiceServer.SetHumanoidHealthWithoutDamageFeedback
HpServiceServer.restoreGodmodeHealth = HpServiceServer.RestoreGodmodeHealth
HpServiceServer.getRuntime = HpServiceServer.GetRuntime
HpServiceServer.pushState = HpServiceServer.PushState
HpServiceServer.persistRuntime = HpServiceServer.PersistRuntime
HpServiceServer.applyPendingPersistedState = HpServiceServer.ApplyPendingPersistedState
HpServiceServer.refreshStateFromHumanoid = HpServiceServer.RefreshStateFromHumanoid
HpServiceServer.retryLoadPersistedHealthLater = HpServiceServer.RetryLoadPersistedHealthLater
HpServiceServer.loadPersistedHealth = HpServiceServer.LoadPersistedHealth
HpServiceServer.bindHumanoid = HpServiceServer.BindHumanoid
HpServiceServer.bindCharacter = HpServiceServer.BindCharacter
HpServiceServer.trackPlayer = HpServiceServer.TrackPlayer
HpServiceServer.untrackPlayer = HpServiceServer.UntrackPlayer
HpServiceServer.getHumanoid = HpServiceServer.GetHumanoid
HpServiceServer.requestSync = HpServiceServer.RequestSync
HpServiceServer.getState = HpServiceServer.GetState
HpServiceServer.setPlayerMaxHealth = HpServiceServer.SetPlayerMaxHealth
HpServiceServer.setPlayerHealth = HpServiceServer.SetPlayerHealth
HpServiceServer.damagePlayer = HpServiceServer.DamagePlayer
HpServiceServer.healPlayer = HpServiceServer.HealPlayer
HpServiceServer.destroy = HpServiceServer.Destroy

export type HpServiceServer = typeof(HpServiceServer) & {
	networker: Networker.Server,
	playerRuntimes: { [Player]: PlayerRuntime },
	heartValue: number,
	playerDataService: PlayerDataServiceServerObject,
	dataPath: { string },
	dataLoadTimeoutSeconds: number,
	dataLoadRetryDelaySeconds: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return HpServiceServer :: HpServiceServer

