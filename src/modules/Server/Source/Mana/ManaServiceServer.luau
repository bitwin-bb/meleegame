local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ManaServiceUtils = require("ManaServiceUtils")
local PacketPayload = require("PacketPayload")
local ManaServicePackets = require("NetPacketsShared").ManaService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = ManaServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for ManaService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = ManaServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for ManaService`)
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
	bindPacket(self, "requestSync")
end

local PlayerDataServiceServer = require("PlayerDataServiceServer")
local PlayerServiceServer = require("PlayerServiceServer")

type ManaServiceState = ManaServiceUtils.ManaServiceState

type PlayerRuntime = {
	state: ManaServiceState,
	loadToken: number,
	hasGotPersistedLoad: boolean,
	stateChangedBeforePersistedLoad: boolean,
	dirty: boolean,
	lastPersistAt: number,
	lastStatePushAt: number,
}

type PlayerDataServiceServerObject = {
	WaitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	IsLoaded: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
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

local ManaServiceServer = {}
ManaServiceServer.ServiceName = "ManaServiceServer"

local STATE_PUSH_INTERVAL = 0.1
local PERSIST_INTERVAL_SECONDS = 2
local DATA_LOAD_TIMEOUT_SECONDS = 20
local REGEN_PUSH_EPSILON = 0.01

local function coerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
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

function ManaServiceServer.CreateRuntime(_self: ManaServiceServer): PlayerRuntime
	return {
		state = ManaServiceUtils.CreateDefaultState(),
		loadToken = 0,
		hasGotPersistedLoad = false,
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

	local nextRuntime = self:CreateRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function ManaServiceServer.PushState(_self: ManaServiceServer, player: Player, runtime: PlayerRuntime, forceRaw: any)
	local force = forceRaw == true
	local now = os.clock()
	if not force and now - runtime.lastStatePushAt < STATE_PUSH_INTERVAL then
		return
	end

	runtime.lastStatePushAt = now
	sendPacket(player, ManaServiceUtils.CLIENT_METHOD_APPLY_STATE, ManaServiceUtils.CloneState(runtime.state))
end

function ManaServiceServer.PersistRuntime(self: ManaServiceServer, player: Player, runtime: PlayerRuntime): boolean
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
	if not playerDataService:IsLoaded(player) then
		return false
	end

	local payload = ManaServiceUtils.SerializeStateForData(runtime.state)
	local success, didSet = pcall(function()
		return playerDataService:SetValue(player, self.dataPath, payload, false)
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
	local nextState = ManaServiceUtils.CreateState(
		nextManaRaw,
		nextMaxManaRaw,
		nextRegenRaw,
		runtime.hasGotPersistedLoad,
		runtime.state
	)
	runtime.state = nextState

	if markDirtyRaw == true then
		runtime.dirty = true
		if not runtime.hasGotPersistedLoad then
			runtime.stateChangedBeforePersistedLoad = true
		end
	end

	self:PushState(player, runtime, forcePushRaw)
end

function ManaServiceServer.LoadPersistedState(self: ManaServiceServer, player: Player, loadToken: number)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local playerDataService = self.playerDataService
	if playerDataService ~= nil then
		pcall(function()
			playerDataService:WaitForData(player, self.dataLoadTimeoutSeconds)
		end)
	end

	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local persistedRaw = nil
	if playerDataService ~= nil then
		local readSuccess, readResult = pcall(function()
			return playerDataService:GetValue(player, self.dataPath, nil)
		end)
		if readSuccess then
			persistedRaw = readResult
		end
	end

	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	runtime.hasGotPersistedLoad = true
	if runtime.stateChangedBeforePersistedLoad then
		runtime.state = ManaServiceUtils.CreateState(
			runtime.state.mana,
			runtime.state.maxMana,
			runtime.state.regenPerSecond,
			true,
			runtime.state
		)
		self:PushState(player, runtime, true)
		if runtime.dirty then
			self:PersistRuntime(player, runtime)
		end
		return
	end

	if persistedRaw ~= nil then
		runtime.state = ManaServiceUtils.CreateStateFromData(persistedRaw, runtime.state, true)
	else
		runtime.state = ManaServiceUtils.CreateState(
			runtime.state.mana,
			runtime.state.maxMana,
			runtime.state.regenPerSecond,
			true,
			runtime.state
		)
		runtime.dirty = true
	end

	self:PushState(player, runtime, true)
	if runtime.dirty then
		self:PersistRuntime(player, runtime)
	end
end

function ManaServiceServer.StepRegen(self: ManaServiceServer, dt: number)
	for player, runtime in self.playerRuntimes do
		local state = runtime.state
		if state.regenPerSecond > 0 and state.mana < state.maxMana then
			local nextMana = math.clamp(state.mana + state.regenPerSecond * dt, 0, state.maxMana)
			if math.abs(nextMana - state.mana) >= REGEN_PUSH_EPSILON then
				self:ApplyState(player, runtime, nextMana, state.maxMana, state.regenPerSecond, true, false)
			end
		end

		if runtime.dirty and runtime.hasGotPersistedLoad then
			if os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
				self:PersistRuntime(player, runtime)
			end
		end
	end
end

function ManaServiceServer.TrackPlayer(self: ManaServiceServer, player: Player)
	local runtime = self:GetRuntime(player)
	runtime.loadToken += 1
	runtime.state = ManaServiceUtils.CreateDefaultState()
	runtime.hasGotPersistedLoad = false
	runtime.stateChangedBeforePersistedLoad = false
	runtime.dirty = false
	runtime.lastPersistAt = 0
	runtime.lastStatePushAt = 0
	self:PushState(player, runtime, true)

	local loadToken = runtime.loadToken
	task.spawn(function()
		self:LoadPersistedState(player, loadToken)
	end)
end

function ManaServiceServer.UntrackPlayer(self: ManaServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:PersistRuntime(player, runtime)
	if self.playerDataService ~= nil then
		pcall(function()
			self.playerDataService:SavePlayerData(player)
		end)
	end

	runtime.loadToken += 1
	self.playerRuntimes[player] = nil
end

function ManaServiceServer.RequestSync(self: ManaServiceServer, player: Player)
	if self.playerRuntimes[player] == nil then
		self:TrackPlayer(player)
		return
	end
	local runtime = self:GetRuntime(player)
	self:PushState(player, runtime, true)
end

function ManaServiceServer.GetState(self: ManaServiceServer, player: Player): ManaServiceState
	local runtime = self:GetRuntime(player)
	return ManaServiceUtils.CloneState(runtime.state)
end

function ManaServiceServer.IsReady(self: ManaServiceServer, player: Player): boolean
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end
	return runtime.hasGotPersistedLoad
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

function ManaServiceServer.CanConsumeMana(
	self: ManaServiceServer,
	player: Player?,
	amountRaw: any,
	_contextRaw: any
): boolean
	if player == nil then
		return false
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end

	local amount = coerceNumber(amountRaw, 0, 0, 1_000_000)
	if amount <= 0 then
		return true
	end
	return runtime.state.mana + 1e-6 >= amount
end

function ManaServiceServer.ConsumeMana(
	self: ManaServiceServer,
	player: Player?,
	amountRaw: any,
	_contextRaw: any
): boolean
	if player == nil then
		return false
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return false
	end

	local amount = coerceNumber(amountRaw, 0, 0, 1_000_000)
	if amount <= 0 then
		return true
	end
	if runtime.state.mana + 1e-6 < amount then
		return false
	end

	self:ApplyState(
		player,
		runtime,
		runtime.state.mana - amount,
		runtime.state.maxMana,
		runtime.state.regenPerSecond,
		true,
		false
	)
	if runtime.hasGotPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:PersistRuntime(player, runtime)
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

	local amount = coerceNumber(amountRaw, 0, 0, 1_000_000)
	if amount <= 0 then
		return runtime.state.mana
	end

	local nextMana = math.clamp(runtime.state.mana + amount, 0, runtime.state.maxMana)
	if math.abs(nextMana - runtime.state.mana) <= 1e-6 then
		return runtime.state.mana
	end

	self:ApplyState(player, runtime, nextMana, runtime.state.maxMana, runtime.state.regenPerSecond, true, false)
	if runtime.hasGotPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:PersistRuntime(player, runtime)
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

	local nextMana = coerceNumber(manaRaw, runtime.state.mana, 0, runtime.state.maxMana)
	if math.abs(nextMana - runtime.state.mana) <= 1e-6 then
		return runtime.state.mana
	end

	self:ApplyState(player, runtime, nextMana, runtime.state.maxMana, runtime.state.regenPerSecond, true, false)
	if runtime.hasGotPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:PersistRuntime(player, runtime)
	end
	return runtime.state.mana
end

function ManaServiceServer.SetMaxMana(
	self: ManaServiceServer,
	player: Player?,
	maxManaRaw: any,
	_contextRaw: any
): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end

	local nextMaxMana = coerceNumber(maxManaRaw, runtime.state.maxMana, 1, 100000)
	local nextMana = math.clamp(runtime.state.mana, 0, nextMaxMana)
	if math.abs(nextMaxMana - runtime.state.maxMana) <= 1e-6 and math.abs(nextMana - runtime.state.mana) <= 1e-6 then
		return runtime.state.maxMana
	end

	self:ApplyState(player, runtime, nextMana, nextMaxMana, runtime.state.regenPerSecond, true, false)
	if runtime.hasGotPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:PersistRuntime(player, runtime)
	end
	return runtime.state.maxMana
end

function ManaServiceServer.SetRegenPerSecond(
	self: ManaServiceServer,
	player: Player?,
	regenRaw: any,
	_contextRaw: any
): number?
	if player == nil then
		return nil
	end
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end

	local nextRegen = coerceNumber(regenRaw, runtime.state.regenPerSecond, 0, 10000)
	if math.abs(nextRegen - runtime.state.regenPerSecond) <= 1e-6 then
		return runtime.state.regenPerSecond
	end

	self:ApplyState(player, runtime, runtime.state.mana, runtime.state.maxMana, nextRegen, true, false)
	if runtime.hasGotPersistedLoad and os.clock() - runtime.lastPersistAt >= PERSIST_INTERVAL_SECONDS then
		self:PersistRuntime(player, runtime)
	end
	return runtime.state.regenPerSecond
end

function ManaServiceServer.OnHeartbeat(self: ManaServiceServer, dt: number)
	self:StepRegen(dt)
end

function ManaServiceServer.Init(self: ManaServiceServer, _serviceBag: any?)
	bindPackets(self)
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.playerRuntimes = {}
	self.dataPath = ManaServiceUtils.GetDefaultDataPath()
	self.dataLoadTimeoutSeconds = DATA_LOAD_TIMEOUT_SECONDS

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
		self:UntrackPlayer(player)
	end
end
export type ManaServiceServer = typeof(ManaServiceServer) & {
	playerDataService: PlayerDataServiceServerObject,
	playerRuntimes: { [Player]: PlayerRuntime },
	dataPath: { string },
	dataLoadTimeoutSeconds: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return ManaServiceServer :: ManaServiceServer
