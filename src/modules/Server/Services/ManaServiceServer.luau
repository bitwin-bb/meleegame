--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local ManaServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.ManaServiceUtils)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerServiceServer)
local PlayerDataServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerDataServiceServer)

type ManaServiceState = ManaServiceUtils.ManaServiceState

type PlayerRuntime = {
	state: ManaServiceState,
	loadToken: number,
	hasResolvedPersistedLoad: boolean,
	stateChangedBeforePersistedLoad: boolean,
	dirty: boolean,
	lastPersistAt: number,
	lastStatePushAt: number,
}

type PlayerDataServiceServerObject = {
	waitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	isLoaded: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
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

local ManaServiceServer = {}

local STATE_PUSH_INTERVAL = 0.1
local PERSIST_INTERVAL_SECONDS = 2
local DATA_LOAD_TIMEOUT_SECONDS = 20
local REGEN_PUSH_EPSILON = 0.01

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(valueRaw)
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

function ManaServiceServer.CreateRuntime(self: ManaServiceServer): PlayerRuntime
	return {
		state = ManaServiceUtils.createDefaultState(),
		loadToken = 0,
		hasResolvedPersistedLoad = false,
		stateChangedBeforePersistedLoad = false,
		dirty = false,
		lastPersistAt = 0,
		lastStatePushAt = 0,
	}
end

function ManaServiceServer.GetRuntime(self: ManaServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end

	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function ManaServiceServer.PushState(
	self: ManaServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	forceRaw: any
)
	local force = forceRaw == true
	local now = os.clock()
	if not force and now - runtime.lastStatePushAt < STATE_PUSH_INTERVAL then
		return
	end

	runtime.lastStatePushAt = now
	self.networker:fire(player, ManaServiceUtils.CLIENT_METHOD_APPLY_STATE, ManaServiceUtils.cloneState(runtime.state))
end

function ManaServiceServer.PersistRuntime(self: ManaServiceServer, player: Player, runtime: PlayerRuntime): boolean
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
	if not playerDataService:isLoaded(player) then
		return false
	end

	local payload = ManaServiceUtils.serializeStateForData(runtime.state)
	local success, didSet = pcall(function()
		return playerDataService:setValue(player, self.dataPath, payload, false)
	end)
	if not success then
		return false
	end
	if didSet ~= true then
		return false
	end

	runtime.dirty = false
	runtime.lastPersistAt = os.clock()
	return true
end

function ManaServiceServer.ApplyState(
	self: ManaServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	nextManaRaw: any,
	nextMaxManaRaw: any,
	nextRegenRaw: any,
	markDirtyRaw: any,
	forcePushRaw: any
)
	local nextState = ManaServiceUtils.createState(
		nextManaRaw,
		nextMaxManaRaw,
		nextRegenRaw,
		runtime.hasResolvedPersistedLoad,
		runtime.state
	)
	runtime.state = nextState

	if markDirtyRaw == true then
		runtime.dirty = true
		if not runtime.hasResolvedPersistedLoad then
			runtime.stateChangedBeforePersistedLoad = true
		end
	end

	self:pushState(player, runtime, forcePushRaw)
end

function ManaServiceServer.LoadPersistedState(self: ManaServiceServer, player: Player, loadToken: number)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local playerDataService = self.playerDataService
	if playerDataService ~= nil then
		pcall(function()
			playerDataService:waitForData(player, self.dataLoadTimeoutSeconds)
		end)
	end

	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local persistedRaw = nil
	if playerDataService ~= nil then
		local readSuccess, readResult = pcall(function()
			return playerDataService:getValue(player, self.dataPath, nil)
		end)
		if readSuccess then
			persistedRaw = readResult
		else
		end
	end

	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	runtime.hasResolvedPersistedLoad = true
	if runtime.stateChangedBeforePersistedLoad then
		runtime.state = ManaServiceUtils.createState(
			runtime.state.mana,
			runtime.state.maxMana,
			runtime.state.regenPerSecond,
			true,
			runtime.state
		)
		self:pushState(player, runtime, true)
		if runtime.dirty then
			self:persistRuntime(player, runtime)
		end
		return
	end

	if persistedRaw ~= nil then
		runtime.state = ManaServiceUtils.createStateFromData(persistedRaw, runtime.state, true)
	else
		runtime.state = ManaServiceUtils.createState(
			runtime.state.mana,
			runtime.state.maxMana,
			runtime.state.regenPerSecond,
			true,
			runtime.state
		)
		runtime.dirty = true
	end

	self:pushState(player, runtime, true)
	if runtime.dirty then
		self:persistRuntime(player, runtime)
	end
end

function ManaServiceServer.StepRegen(self: ManaServiceServer, dt: number)
	for player, runtime in self.playerRuntimes do
		local state = runtime.state
		if state.regenPerSecond > 0 and state.mana < state.maxMana then
			local nextMana = math.clamp(state.mana + state.regenPerSecond * dt, 0, state.maxMana)
			if math.abs(nextMana - state.mana) >= REGEN_PUSH_EPSILON then
				self:applyState(
					player,
					runtime,
					nextMana,
					state.maxMana,
					state.regenPerSecond,
					true,
					false
				)
			end
		end

		if runtime.dirty and runtime.hasResolvedPersistedLoad then
			if os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
				self:persistRuntime(player, runtime)
			end
		end
	end
end

function ManaServiceServer.TrackPlayer(self: ManaServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.loadToken += 1
	runtime.state = ManaServiceUtils.createDefaultState()
	runtime.hasResolvedPersistedLoad = false
	runtime.stateChangedBeforePersistedLoad = false
	runtime.dirty = false
	runtime.lastPersistAt = 0
	runtime.lastStatePushAt = 0
	self:pushState(player, runtime, true)

	local loadToken = runtime.loadToken
	task.spawn(function()
		self:loadPersistedState(player, loadToken)
	end)
end

function ManaServiceServer.UntrackPlayer(self: ManaServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:persistRuntime(player, runtime)
	if self.playerDataService ~= nil then
		pcall(function()
			self.playerDataService:savePlayerData(player)
		end)
	end

	runtime.loadToken += 1
	self.playerRuntimes[player] = nil
end

function ManaServiceServer.RequestSync(self: ManaServiceServer, player: Player)
	if self.playerRuntimes[player] == nil then
		self:trackPlayer(player)
		return
	end
	local runtime = self:getRuntime(player)
	self:pushState(player, runtime, true)
end

function ManaServiceServer.GetState(self: ManaServiceServer, player: Player): ManaServiceState
	local runtime = self:getRuntime(player)
	return ManaServiceUtils.cloneState(runtime.state)
end

function ManaServiceServer.IsReady(self: ManaServiceServer, player: Player): boolean
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end
	return runtime.hasResolvedPersistedLoad
end

function ManaServiceServer.GetMana(self: ManaServiceServer, player: Player?): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end
	return runtime.state.mana
end

function ManaServiceServer.GetMaxMana(self: ManaServiceServer, player: Player?): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end
	return runtime.state.maxMana
end

function ManaServiceServer.GetRegenPerSecond(self: ManaServiceServer, player: Player?): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end
	return runtime.state.regenPerSecond
end

function ManaServiceServer.CanConsumeMana(self: ManaServiceServer, player: Player?, amountRaw: any, _contextRaw: any): boolean
	if player == nil then
		return false
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end

	local amount = sanitizeNumber(amountRaw, 0, 0, 1_000_000)
	if amount <= 0 then
		return true
	end
	return runtime.state.mana + 1e-6 >= amount
end

function ManaServiceServer.ConsumeMana(self: ManaServiceServer, player: Player?, amountRaw: any, _contextRaw: any): boolean
	if player == nil then
		return false
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end

	local amount = sanitizeNumber(amountRaw, 0, 0, 1_000_000)
	if amount <= 0 then
		return true
	end
	if runtime.state.mana + 1e-6 < amount then
		return false
	end

	self:applyState(
		player,
		runtime,
		runtime.state.mana - amount,
		runtime.state.maxMana,
		runtime.state.regenPerSecond,
		true,
		false
	)
	if runtime.hasResolvedPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:persistRuntime(player, runtime)
	end
	return true
end

function ManaServiceServer.AddMana(self: ManaServiceServer, player: Player?, amountRaw: any, _contextRaw: any): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end

	local amount = sanitizeNumber(amountRaw, 0, 0, 1_000_000)
	if amount <= 0 then
		return runtime.state.mana
	end

	local nextMana = math.clamp(runtime.state.mana + amount, 0, runtime.state.maxMana)
	if math.abs(nextMana - runtime.state.mana) <= 1e-6 then
		return runtime.state.mana
	end

	self:applyState(
		player,
		runtime,
		nextMana,
		runtime.state.maxMana,
		runtime.state.regenPerSecond,
		true,
		false
	)
	if runtime.hasResolvedPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:persistRuntime(player, runtime)
	end
	return runtime.state.mana
end

function ManaServiceServer.SetMana(self: ManaServiceServer, player: Player?, manaRaw: any, _contextRaw: any): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end

	local nextMana = sanitizeNumber(manaRaw, runtime.state.mana, 0, runtime.state.maxMana)
	if math.abs(nextMana - runtime.state.mana) <= 1e-6 then
		return runtime.state.mana
	end

	self:applyState(
		player,
		runtime,
		nextMana,
		runtime.state.maxMana,
		runtime.state.regenPerSecond,
		true,
		false
	)
	if runtime.hasResolvedPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:persistRuntime(player, runtime)
	end
	return runtime.state.mana
end

function ManaServiceServer.SetMaxMana(self: ManaServiceServer, player: Player?, maxManaRaw: any, _contextRaw: any): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end

	local nextMaxMana = sanitizeNumber(maxManaRaw, runtime.state.maxMana, 1, 100000)
	local nextMana = math.clamp(runtime.state.mana, 0, nextMaxMana)
	if math.abs(nextMaxMana - runtime.state.maxMana) <= 1e-6 and math.abs(nextMana - runtime.state.mana) <= 1e-6 then
		return runtime.state.maxMana
	end

	self:applyState(
		player,
		runtime,
		nextMana,
		nextMaxMana,
		runtime.state.regenPerSecond,
		true,
		false
	)
	if runtime.hasResolvedPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:persistRuntime(player, runtime)
	end
	return runtime.state.maxMana
end

function ManaServiceServer.SetRegenPerSecond(self: ManaServiceServer, player: Player?, regenRaw: any, _contextRaw: any): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end

	local nextRegen = sanitizeNumber(regenRaw, runtime.state.regenPerSecond, 0, 10000)
	if math.abs(nextRegen - runtime.state.regenPerSecond) <= 1e-6 then
		return runtime.state.regenPerSecond
	end

	self:applyState(
		player,
		runtime,
		runtime.state.mana,
		runtime.state.maxMana,
		nextRegen,
		true,
		false
	)
	if runtime.hasResolvedPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:persistRuntime(player, runtime)
	end
	return runtime.state.regenPerSecond
end

function ManaServiceServer.OnHeartbeat(self: ManaServiceServer, dt: number)
	self:stepRegen(dt)
end

function ManaServiceServer.Init(self: ManaServiceServer)
	self.networker = Networker.server.new("ManaService", self, {
		self.RequestSync,
	})
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.playerRuntimes = {}
	self.dataPath = ManaServiceUtils.getDefaultDataPath()
	self.dataLoadTimeoutSeconds = DATA_LOAD_TIMEOUT_SECONDS

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

function ManaServiceServer.Destroy(self: ManaServiceServer)
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

	for player in self.playerRuntimes do
		self:untrackPlayer(player)
	end

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

ManaServiceServer.createRuntime = ManaServiceServer.CreateRuntime
ManaServiceServer.getRuntime = ManaServiceServer.GetRuntime
ManaServiceServer.pushState = ManaServiceServer.PushState
ManaServiceServer.persistRuntime = ManaServiceServer.PersistRuntime
ManaServiceServer.applyState = ManaServiceServer.ApplyState
ManaServiceServer.loadPersistedState = ManaServiceServer.LoadPersistedState
ManaServiceServer.stepRegen = ManaServiceServer.StepRegen
ManaServiceServer.trackPlayer = ManaServiceServer.TrackPlayer
ManaServiceServer.untrackPlayer = ManaServiceServer.UntrackPlayer
ManaServiceServer.requestSync = ManaServiceServer.RequestSync
ManaServiceServer.getState = ManaServiceServer.GetState
ManaServiceServer.isReady = ManaServiceServer.IsReady
ManaServiceServer.getMana = ManaServiceServer.GetMana
ManaServiceServer.getMaxMana = ManaServiceServer.GetMaxMana
ManaServiceServer.getRegenPerSecond = ManaServiceServer.GetRegenPerSecond
ManaServiceServer.canConsumeMana = ManaServiceServer.CanConsumeMana
ManaServiceServer.consumeMana = ManaServiceServer.ConsumeMana
ManaServiceServer.addMana = ManaServiceServer.AddMana
ManaServiceServer.setMana = ManaServiceServer.SetMana
ManaServiceServer.setMaxMana = ManaServiceServer.SetMaxMana
ManaServiceServer.setRegenPerSecond = ManaServiceServer.SetRegenPerSecond
ManaServiceServer.onHeartbeat = ManaServiceServer.OnHeartbeat
ManaServiceServer.init = ManaServiceServer.Init
ManaServiceServer.destroy = ManaServiceServer.Destroy

export type ManaServiceServer = typeof(ManaServiceServer) & {
	networker: Networker.Server,
	playerDataService: PlayerDataServiceServerObject,
	playerRuntimes: { [Player]: PlayerRuntime },
	dataPath: { string },
	dataLoadTimeoutSeconds: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return ManaServiceServer :: ManaServiceServer

