
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Configs = require(script:FindFirstAncestor("game").Shared:WaitForChild("QueenBeeConfigs"))
local PacketPayload = require("PacketPayload")
local WeatherServicePackets = require("NetSharedPackets").WeatherService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = WeatherServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WeatherService`)
		return
	end

	packet.sendTo(PacketPayload.pack(...), player)
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

		local handler = self[methodName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.unpack(payload)
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

local function sanitizeDeltaTime(dtRaw: any): number
	return WeatherServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
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
	local snapshot = WeatherServiceUtils.cloneState(self.state)
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

	local snapshot = self:createStateSnapshot()
	local player = playerRaw
	if player ~= nil then
		if typeof(player) == "Instance" and player:IsA("Player") then
			sendPacket(player, WeatherServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
		end
		return
	end

	for _, listedPlayer in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(listedPlayer) then
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
	local nextClockTime = WeatherServiceUtils.sanitizeState({
		clockTime = clockTimeRaw,
	}, self.state).clockTime
	self.state.clockTime = nextClockTime
	self.stateDirty = true
	if forceReplicateRaw == true then
		self:pushState(nil, true)
	end
	return self.state.clockTime
end

function WeatherServiceServer.SetDayNightCycleEnabled(
	self: WeatherServiceServer,
	enabledRaw: any,
	forceReplicateRaw: any?
): boolean
	local enabled = WeatherServiceUtils.sanitizeBoolean(enabledRaw, self.state.dayNightCycleEnabled)
	self.state.dayNightCycleEnabled = enabled
	self.state.clockSpeed = if enabled then 24 / self.config.dayDurationSeconds else 0
	self.stateDirty = true
	if forceReplicateRaw == true then
		self:pushState(nil, true)
	end
	return self.state.dayNightCycleEnabled
end

function WeatherServiceServer.SetWeather(
	self: WeatherServiceServer,
	weatherTypeRaw: any,
	transitionSecondsRaw: any?,
	forceReplicateRaw: any?
): WeatherType
	local nextWeatherType = WeatherServiceUtils.sanitizeWeatherType(weatherTypeRaw, self.state.weatherType)
	local transitionSeconds =
		WeatherServiceUtils.sanitizeNumber(transitionSecondsRaw, self.config.weatherTransitionSeconds, 0, 60)

	self.state.weatherType = nextWeatherType
	self.state.weatherTransitionSeconds = transitionSeconds
	self.state.rainIntensity = WeatherServiceUtils.getRainIntensityForWeather(nextWeatherType)
	self.weatherSecondsRemaining = self:rollNextWeatherDurationSeconds()
	self.stateDirty = true

	if forceReplicateRaw == true then
		self:pushState(nil, true)
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
		WeatherServiceUtils.advanceClockTimeWithDayDelta(self.state.clockTime, dt, self.state.clockSpeed)
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
		WeatherServiceUtils.chooseWeightedWeatherType(self.random, self.config, self.state.weatherType)
	self:setWeather(nextWeatherType, self.config.weatherTransitionSeconds, false)
end

function WeatherServiceServer.OnHeartbeat(self: WeatherServiceServer, dtRaw: any)
	local dt = sanitizeDeltaTime(dtRaw)
	if dt <= 0 then
		return
	end

	self:stepDayNight(dt)
	self:stepWeatherCycle(dt)

	local now = os.clock()
	if self.stateDirty or (now - self.lastStatePushAt) >= self.config.statePushIntervalSeconds then
		self:pushState(nil, false)
	end
end

function WeatherServiceServer.TrackPlayer(self: WeatherServiceServer, player: Player)
	self:pushState(player, true)
end

function WeatherServiceServer.UntrackPlayer(_self: WeatherServiceServer, _player: Player)
	return
end

function WeatherServiceServer.RequestSync(self: WeatherServiceServer, player: Player)
	self:pushState(player, true)
end

function WeatherServiceServer.GetState(self: WeatherServiceServer): WeatherServiceState
	return WeatherServiceUtils.cloneState(self.state)
end

function WeatherServiceServer.Init(self: WeatherServiceServer)
	local configSource = if typeof(Configs) == "table" then (Configs :: any).weather else nil
	self.config = WeatherServiceUtils.resolveConfig(configSource, nil)
	self.state = WeatherServiceUtils.createStateFromConfig(self.config)
	self.random = Random.new()
	self.stateDirty = true
	self.lastStatePushAt = 0
	self.weatherSecondsRemaining = self:rollNextWeatherDurationSeconds()

	bindPackets(self)

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

	self:pushState(nil, true)
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

WeatherServiceServer.rollNextWeatherDurationSeconds = WeatherServiceServer.RollNextWeatherDurationSeconds
WeatherServiceServer.createStateSnapshot = WeatherServiceServer.CreateStateSnapshot
WeatherServiceServer.pushState = WeatherServiceServer.PushState
WeatherServiceServer.setClockTime = WeatherServiceServer.SetClockTime
WeatherServiceServer.setDayNightCycleEnabled = WeatherServiceServer.SetDayNightCycleEnabled
WeatherServiceServer.setWeather = WeatherServiceServer.SetWeather
WeatherServiceServer.stepDayNight = WeatherServiceServer.StepDayNight
WeatherServiceServer.stepWeatherCycle = WeatherServiceServer.StepWeatherCycle
WeatherServiceServer.onHeartbeat = WeatherServiceServer.OnHeartbeat
WeatherServiceServer.trackPlayer = WeatherServiceServer.TrackPlayer
WeatherServiceServer.untrackPlayer = WeatherServiceServer.UntrackPlayer
WeatherServiceServer.requestSync = WeatherServiceServer.RequestSync
WeatherServiceServer.getState = WeatherServiceServer.GetState
WeatherServiceServer.init = WeatherServiceServer.Init
WeatherServiceServer.destroy = WeatherServiceServer.Destroy

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
