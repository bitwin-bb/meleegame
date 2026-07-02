
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Configs = require("CoreConfigs")
local PacketPayload = require("PacketPayload")
local WeatherServicePackets = require("NetPacketsShared").WeatherService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = WeatherServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WeatherService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = WeatherServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WeatherService`)
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

local PlayerServiceServer = require("PlayerServiceServer")
local WeatherServiceUtils = require("WeatherServiceUtils")

type WeatherType = WeatherServiceUtils.WeatherType
type WeatherServiceConfig = WeatherServiceUtils.WeatherServiceConfig
type WeatherServiceState = WeatherServiceUtils.WeatherServiceState

local WeatherServiceServer = {}

local function CoerceDeltaTime(dtRaw: any): number
	return WeatherServiceUtils.CoerceNumber(dtRaw, 0, 0, 1)
end

function WeatherServiceServer.RollNextWeatherDurationSeconds(self: WeatherServiceServer): number
	local minimum = self.config.weatherDurationMinSeconds
	local maximum = self.config.weatherDurationMaxSeconds
	if maximum <= minimum then
		return minimum
	end
	return self.random:NextNumber(minimum, maximum)
end

function WeatherServiceServer.CreateStateSnapshot(self: WeatherServiceServer): WeatherServiceState
	local snapshot = WeatherServiceUtils.CloneState(self.state)
	snapshot.ready = self.config.enabled
	snapshot.snapshotServerTime = Workspace:GetServerTimeNow()
	snapshot.updatedAt = os.clock()
	return snapshot
end

function WeatherServiceServer.PushState(self: WeatherServiceServer, playerRaw: any?, forceRaw: any?)
	local force = forceRaw == true
	local now = os.clock()
	if not force and now - self.lastStatePushAt < self.config.statePushIntervalSeconds then
		return
	end
	self.lastStatePushAt = now

	local snapshot = self:CreateStateSnapshot()
	local player = playerRaw
	if player ~= nil then
		if typeof(player) == "Instance" and player:IsA("Player") then
			sendPacket(player, WeatherServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
		end
		return
	end

	for _, listedPlayer in Players:GetPlayers() do
		if PlayerServiceServer:IsGameplayActiveForPlayer(listedPlayer) then
			sendPacket(listedPlayer, WeatherServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
		end
	end
	self.stateDirty = false
end

function WeatherServiceServer.SetClockTime(
	self: WeatherServiceServer,
	clockTimeRaw: any,
	forceReplicateRaw: any?
): number
	local nextClockTime = WeatherServiceUtils.CoerceState({
		clockTime = clockTimeRaw,
	}, self.state).clockTime
	self.state.clockTime = nextClockTime
	self.stateDirty = true
	if forceReplicateRaw == true then
		self:PushState(nil, true)
	end
	return self.state.clockTime
end

function WeatherServiceServer.SetDayNightCycleEnabled(
	self: WeatherServiceServer,
	enabledRaw: any,
	forceReplicateRaw: any?
): boolean
	local enabled = WeatherServiceUtils.CoerceBoolean(enabledRaw, self.state.dayNightCycleEnabled)
	self.state.dayNightCycleEnabled = enabled
	self.state.clockSpeed = if enabled then 24 / self.config.dayDurationSeconds else 0
	self.stateDirty = true
	if forceReplicateRaw == true then
		self:PushState(nil, true)
	end
	return self.state.dayNightCycleEnabled
end

function WeatherServiceServer.SetWeather(
	self: WeatherServiceServer,
	weatherTypeRaw: any,
	transitionSecondsRaw: any?,
	forceReplicateRaw: any?
): WeatherType
	local nextWeatherType = WeatherServiceUtils.CoerceWeatherType(weatherTypeRaw, self.state.weatherType)
	local transitionSeconds =
		WeatherServiceUtils.CoerceNumber(transitionSecondsRaw, self.config.weatherTransitionSeconds, 0, 60)

	self.state.weatherType = nextWeatherType
	self.state.weatherTransitionSeconds = transitionSeconds
	self.state.rainIntensity = WeatherServiceUtils.GetRainIntensityForWeather(nextWeatherType)
	self.weatherSecondsRemaining = self:RollNextWeatherDurationSeconds()
	self.stateDirty = true

	if forceReplicateRaw == true then
		self:PushState(nil, true)
	end

	return self.state.weatherType
end

function WeatherServiceServer.StepDayNight(self: WeatherServiceServer, dt: number)
	if not self.config.enabled then
		return
	end
	if not self.state.dayNightCycleEnabled then
		return
	end
	if self.state.clockSpeed == 0 then
		return
	end

	local advanceResult =
		WeatherServiceUtils.AdvanceClockTimeWithDayDelta(self.state.clockTime, dt, self.state.clockSpeed)
	self.state.clockTime = advanceResult.clockTime
	if advanceResult.dayDelta > 0 then
		self.state.worldDayIndex += advanceResult.dayDelta
	end
	self.stateDirty = true
end

function WeatherServiceServer.StepWeatherCycle(self: WeatherServiceServer, dt: number)
	if not self.config.enabled then
		return
	end
	if not self.config.weatherCycleEnabled then
		return
	end

	self.weatherSecondsRemaining -= dt
	if self.weatherSecondsRemaining > 0 then
		return
	end

	local nextWeatherType =
		WeatherServiceUtils.ChooseWeightedWeatherType(self.random, self.config, self.state.weatherType)
	self:SetWeather(nextWeatherType, self.config.weatherTransitionSeconds, false)
end

function WeatherServiceServer.OnHeartbeat(self: WeatherServiceServer, dtRaw: any)
	local dt = CoerceDeltaTime(dtRaw)
	if dt <= 0 then
		return
	end

	self:StepDayNight(dt)
	self:StepWeatherCycle(dt)

	local now = os.clock()
	if self.stateDirty or (now - self.lastStatePushAt) >= self.config.statePushIntervalSeconds then
		self:PushState(nil, false)
	end
end

function WeatherServiceServer.TrackPlayer(self: WeatherServiceServer, player: Player)
	self:PushState(player, true)
end

function WeatherServiceServer.UntrackPlayer(_self: WeatherServiceServer, _player: Player)
	return
end

function WeatherServiceServer.RequestSync(self: WeatherServiceServer, player: Player)
	self:PushState(player, true)
end

function WeatherServiceServer.GetState(self: WeatherServiceServer): WeatherServiceState
	return WeatherServiceUtils.CloneState(self.state)
end

function WeatherServiceServer.Init(self: WeatherServiceServer)
	local configSource = if typeof(Configs) == "table" then (Configs :: any).weather else nil
	self.config = WeatherServiceUtils.GetConfig(configSource, nil)
	self.state = WeatherServiceUtils.CreateStateFromConfig(self.config)
	self.random = Random.new()
	self.stateDirty = true
	self.lastStatePushAt = 0
	self.weatherSecondsRemaining = self:RollNextWeatherDurationSeconds()

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

	self:PushState(nil, true)
end

function WeatherServiceServer.Destroy(self: WeatherServiceServer)
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
end
export type WeatherServiceServer = typeof(WeatherServiceServer) & {
	config: WeatherServiceConfig,
	state: WeatherServiceState,
	random: Random,
	stateDirty: boolean,
	lastStatePushAt: number,
	weatherSecondsRemaining: number,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return WeatherServiceServer :: WeatherServiceServer
