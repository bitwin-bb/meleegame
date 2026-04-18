--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ServerBinderSupport = require(script:FindFirstAncestor("game").Server.Binders.ServerBinderSupport)
local BreathServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BreathService.BreathServiceUtils)
local LiquidServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.LiquidService.LiquidServiceUtils)
local LiquidServiceServer = require(script:FindFirstAncestor("game").Server.Services.LiquidService.LiquidServiceServer)
local HpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpService.HpServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerService.PlayerServiceServer)
local BreathBinder = require(script:FindFirstAncestor("game").Server.Binders.BreathBinder)

type BreathServiceConfig = BreathServiceUtils.BreathServiceConfig
type BreathServiceState = BreathServiceUtils.BreathServiceState
type LiquidQueryResult = LiquidServiceUtils.LiquidQueryResult

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type LiquidServiceServerObject = {
	config: LiquidServiceUtils.LiquidServiceConfig,
	getPlayerLiquidQuery: (self: LiquidServiceServerObject, player: Player) -> LiquidQueryResult,
}

type HpServiceServerObject = {
	damagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
}

type PlayerRuntime = {
	state: BreathServiceState,
	lastDrowningDamageAt: number,
	lastSurfaceAt: number,
	lastPushedAt: number,
	breathDepletedFired: boolean,
	wasBreathBlocked: boolean,
}

local BreathServiceServer = {}

local function resolveSourceConfig(): any
	if typeof(Configs) ~= "table" then
		return nil
	end
	return (Configs :: any).breath
end

function BreathServiceServer:CreateRuntime(): PlayerRuntime
	return {
		state = BreathServiceUtils.createDefaultState(),
		lastDrowningDamageAt = -math.huge,
		lastSurfaceAt = os.clock(),
		lastPushedAt = -math.huge,
		breathDepletedFired = false,
		wasBreathBlocked = false,
	}
end

function BreathServiceServer:GetRuntime(player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end
	runtime = self:createRuntime()
	runtime.state.maxBreath = self.config.maxBreathSeconds
	runtime.state.breath = self.config.maxBreathSeconds
	runtime.state.graceRemaining = self.config.graceDuration
	self.playerRuntimes[player] = runtime
	return runtime
end

function BreathServiceServer:PushState(player: Player)
	local runtime = self:getRuntime(player)
	self.networker:fire(
		player,
		BreathServiceUtils.CLIENT_METHOD_APPLY_STATE,
		BreathServiceUtils.cloneState(runtime.state)
	)
	runtime.lastPushedAt = os.clock()
end

function BreathServiceServer:TrackPlayer(player: Player)
	local runtime = self:createRuntime()
	runtime.state = BreathServiceUtils.createState({
		ready = true,
		maxBreath = self.config.maxBreathSeconds,
		breath = self.config.maxBreathSeconds,
		graceRemaining = self.config.graceDuration,
	}, runtime.state)
	self.playerRuntimes[player] = runtime
	self:pushState(player)
end

function BreathServiceServer:UntrackPlayer(player: Player)
	self.playerRuntimes[player] = nil
end

function BreathServiceServer:RequestSync(player: Player)
	if self.playerRuntimes[player] == nil then
		self:trackPlayer(player)
		return
	end
	self:pushState(player)
end

function BreathServiceServer:ProcessPlayer(player: Player, dt: number)
	local runtime = self:getRuntime(player)
	local liquidQuery = self.liquidService:getPlayerLiquidQuery(player)
	local overrideQuery = BreathBinder.queryCharacterOverride(player.Character)
	if overrideQuery ~= nil then
		liquidQuery = overrideQuery
	end
	local breathBlocked = LiquidServiceUtils.LiquidDamage.shouldBlockBreath(self.liquidService.config, liquidQuery)
	local wasBreathBlocked = runtime.wasBreathBlocked
	local now = os.clock()
	local state = runtime.state

	state.ready = true
	state.submersionRatio = liquidQuery.submersionRatio
	state.breathingLiquidType = liquidQuery.breathingLiquidType
	state.isUnderwater = liquidQuery.meaningfulSubmersion
	state.isBreathingBlocked = breathBlocked

	if breathBlocked then
		if state.graceRemaining > 0 then
			state.graceRemaining = math.max(0, state.graceRemaining - dt)
		else
			state.breath = math.max(0, state.breath - dt)
		end

		if state.breath <= 0 then
			state.isDrowning = true
			if not runtime.breathDepletedFired then
				runtime.breathDepletedFired = true
				self.breathDepleted:Fire(player)
				self.networker:fire(player, BreathServiceUtils.CLIENT_METHOD_ON_EVENT, {
					eventType = BreathServiceUtils.EVENT_BREATH_DEPLETED,
					updatedAt = now,
				})
			end
			if now - runtime.lastDrowningDamageAt >= self.config.drowningTickRate then
				self.hpService:damagePlayer(player, self.config.drowningDamage)
				runtime.lastDrowningDamageAt = now
			end
		else
			state.isDrowning = false
		end
	else
		state.isDrowning = false
		state.graceRemaining = self.config.graceDuration
		if wasBreathBlocked then
			runtime.lastSurfaceAt = now
		end
		if state.breath < state.maxBreath then
			if now - runtime.lastSurfaceAt >= self.config.recoveryDelay then
				state.breath =
					math.min(state.maxBreath, state.breath + dt * state.maxBreath / self.config.recoveryDuration)
			end
		else
			runtime.breathDepletedFired = false
		end
	end

	if state.breath >= state.maxBreath - 0.001 then
		runtime.breathDepletedFired = false
	end
	runtime.wasBreathBlocked = breathBlocked

	if now - runtime.lastPushedAt >= self.config.statePushInterval then
		self:pushState(player)
	end
end

function BreathServiceServer:OnHeartbeat(deltaTime: number)
	self.accumulator += deltaTime
	local step = 1 / self.config.updateRate
	while self.accumulator >= step do
		self.accumulator -= step
		for player in self.playerRuntimes do
			self:processPlayer(player, step)
		end
	end
end

function BreathServiceServer:Init()
	self.config = BreathServiceUtils.sanitizeConfig(resolveSourceConfig(), nil)
	self.playerRuntimes = {} :: { [Player]: PlayerRuntime }
	self.accumulator = 0
	self.liquidService = LiquidServiceServer :: LiquidServiceServerObject
	self.hpService = HpServiceServer :: HpServiceServerObject
	self.breathDepleted = Signal.new()
	self.binders = NevermoreSupport.getService(ServerBinderSupport)

	self.networker = Networker.server.new("BreathService", self, {
		self.RequestSync,
	})

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
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:onHeartbeat(deltaTime)
	end)
end

function BreathServiceServer:Destroy()
	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
	if self.networker ~= nil then
		self.networker:destroy()
		self.networker = nil
	end
	if self.breathDepleted ~= nil then
		self.breathDepleted:Destroy()
	end
	table.clear(self.playerRuntimes)
end

BreathServiceServer.createRuntime = BreathServiceServer.CreateRuntime
BreathServiceServer.getRuntime = BreathServiceServer.GetRuntime
BreathServiceServer.pushState = BreathServiceServer.PushState
BreathServiceServer.trackPlayer = BreathServiceServer.TrackPlayer
BreathServiceServer.untrackPlayer = BreathServiceServer.UntrackPlayer
BreathServiceServer.requestSync = BreathServiceServer.RequestSync
BreathServiceServer.processPlayer = BreathServiceServer.ProcessPlayer
BreathServiceServer.onHeartbeat = BreathServiceServer.OnHeartbeat
BreathServiceServer.init = BreathServiceServer.Init
BreathServiceServer.destroy = BreathServiceServer.Destroy

type BreathServiceServer = typeof(BreathServiceServer) & {
	config: BreathServiceConfig,
	playerRuntimes: { [Player]: PlayerRuntime },
	accumulator: number,
	liquidService: LiquidServiceServerObject,
	hpService: HpServiceServerObject,
	breathDepleted: SignalObject,
	networker: Networker.Server,
	heartbeatConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return BreathServiceServer :: BreathServiceServer
