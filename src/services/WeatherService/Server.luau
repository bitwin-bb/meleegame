--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local WeatherServiceUtils = require(ReplicatedStorage.Shared.Services.WeatherService.WeatherServiceUtils)

type WeatherType = WeatherServiceUtils.WeatherType
type WeatherServiceConfig = WeatherServiceUtils.WeatherServiceConfig
type WeatherServiceState = WeatherServiceUtils.WeatherServiceState

local WeatherServiceServer = {}

local function sanitizeDeltaTime(dtRaw: any): number
	return WeatherServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
end

function WeatherServiceServer.rollNextWeatherDurationSeconds(self: WeatherServiceServer): number
	local minimum = self.config.weatherDurationMinSeconds
	local maximum = self.config.weatherDurationMaxSeconds
	if maximum <= minimum then
		return minimum
	end
	return self.random:NextNumber(minimum, maximum)
end

function WeatherServiceServer.createStateSnapshot(self: WeatherServiceServer): WeatherServiceState
	local snapshot = WeatherServiceUtils.cloneState(self.state)
	snapshot.ready = self.config.enabled
	snapshot.snapshotServerTime = Workspace:GetServerTimeNow()
	snapshot.updatedAt = os.clock()
	return snapshot
end

function WeatherServiceServer.pushState(self: WeatherServiceServer, playerRaw: any?, forceRaw: any?)
	if self.networker == nil then
		return
	end

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
			self.networker:fire(player, WeatherServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
		end
		return
	end

	for _, listedPlayer in Players:GetPlayers() do
		self.networker:fire(listedPlayer, WeatherServiceUtils.CLIENT_METHOD_APPLY_STATE, snapshot)
	end
	self.stateDirty = false
end

function WeatherServiceServer.setClockTime(self: WeatherServiceServer, clockTimeRaw: any, forceReplicateRaw: any?): number
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

function WeatherServiceServer.setDayNightCycleEnabled(
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

function WeatherServiceServer.setWeather(
	self: WeatherServiceServer,
	weatherTypeRaw: any,
	transitionSecondsRaw: any?,
	forceReplicateRaw: any?
): WeatherType
	local nextWeatherType = WeatherServiceUtils.sanitizeWeatherType(weatherTypeRaw, self.state.weatherType)
	local transitionSeconds = WeatherServiceUtils.sanitizeNumber(
		transitionSecondsRaw,
		self.config.weatherTransitionSeconds,
		0,
		60
	)

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

function WeatherServiceServer.stepDayNight(self: WeatherServiceServer, dt: number)
	if not self.config.enabled then
		return
	end
	if not self.state.dayNightCycleEnabled then
		return
	end
	if self.state.clockSpeed == 0 then
		return
	end

	self.state.clockTime = WeatherServiceUtils.advanceClockTime(self.state.clockTime, dt, self.state.clockSpeed)
	self.stateDirty = true
end

function WeatherServiceServer.stepWeatherCycle(self: WeatherServiceServer, dt: number)
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

	local nextWeatherType = WeatherServiceUtils.chooseWeightedWeatherType(self.random, self.config, self.state.weatherType)
	self:setWeather(nextWeatherType, self.config.weatherTransitionSeconds, false)
end

function WeatherServiceServer.onHeartbeat(self: WeatherServiceServer, dtRaw: any)
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

function WeatherServiceServer.trackPlayer(self: WeatherServiceServer, player: Player)
	if self.networker == nil then
		return
	end
	self:pushState(player, true)
end

function WeatherServiceServer.untrackPlayer(self: WeatherServiceServer, _player: Player)
	return
end

function WeatherServiceServer.requestSync(self: WeatherServiceServer, player: Player)
	self:pushState(player, true)
end

function WeatherServiceServer.getState(self: WeatherServiceServer): WeatherServiceState
	return WeatherServiceUtils.cloneState(self.state)
end

function WeatherServiceServer.init(self: WeatherServiceServer)
	local configSource = if typeof(Configs) == "table" then (Configs :: any).weather else nil
	self.config = WeatherServiceUtils.resolveConfig(configSource, nil)
	self.state = WeatherServiceUtils.createStateFromConfig(self.config)
	self.random = Random.new()
	self.stateDirty = true
	self.lastStatePushAt = 0
	self.weatherSecondsRemaining = self:rollNextWeatherDurationSeconds()

	self.networker = Networker.server.new("WeatherService", self, {
		self.requestSync,
	})

	for _, player in Players:GetPlayers() do
		self:trackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:trackPlayer(player)
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)

	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:onHeartbeat(dt)
	end)

	self:pushState(nil, true)
end

function WeatherServiceServer.destroy(self: WeatherServiceServer)
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

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

export type WeatherServiceServer = typeof(WeatherServiceServer) & {
	networker: Networker.Server,
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