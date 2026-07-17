local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BreathBinder = require("BreathBinder")
local BreathServiceUtils = require("BreathServiceUtils")
local Configs = require("CoreConfigs")
local HpServiceServer = require("HpServiceServer")
local LiquidServiceServer = require("LiquidServiceServer")
local LiquidServiceUtils = require("LiquidServiceUtils")
local PacketPayload = require("PacketPayload")
local BreathServicePackets = require("NetPacketsShared").BreathService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = BreathServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BreathService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = BreathServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BreathService`)
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

local BinderSupportServer = require("BinderSupportServer")
local PlayerServiceServer = require("PlayerServiceServer")
local Signal = require("Signal")

type BreathServiceConfig = BreathServiceUtils.BreathServiceConfig
type BreathServiceState = BreathServiceUtils.BreathServiceState
type LiquidQueryResult = LiquidServiceUtils.LiquidQueryResult

type SignalObject = Signal.Signal<...any>

type LiquidServiceServerObject = {
	config: LiquidServiceUtils.LiquidServiceConfig,
	GetPlayerLiquidQuery: (self: LiquidServiceServerObject, player: Player) -> LiquidQueryResult,
}

type HpServiceServerObject = {
	DamagePlayer: (self: HpServiceServerObject, player: Player, damageRaw: any) -> number?,
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
BreathServiceServer.ServiceName = "BreathServiceServer"

local function getSourceConfig(): any
	if typeof(Configs) ~= "table" then
		return nil
	end
	return (Configs :: any).breath
end

function BreathServiceServer.CreateRuntime(_self: BreathServiceServer): PlayerRuntime
	return {
		state = BreathServiceUtils.CreateDefaultState(),
		lastDrowningDamageAt = -math.huge,
		lastSurfaceAt = os.clock(),
		lastPushedAt = -math.huge,
		breathDepletedFired = false,
		wasBreathBlocked = false,
	}
end

function BreathServiceServer.GetRuntime(self: BreathServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end
	runtime = self:CreateRuntime()
	runtime.state.maxBreath = self.config.maxBreathSeconds
	runtime.state.breath = self.config.maxBreathSeconds
	runtime.state.graceRemaining = self.config.graceDuration
	self.playerRuntimes[player] = runtime
	return runtime
end

function BreathServiceServer.PushState(self: BreathServiceServer, player: Player)
	local runtime = self:GetRuntime(player)
	sendPacket(player, BreathServiceUtils.CLIENT_METHOD_APPLY_STATE, BreathServiceUtils.CloneState(runtime.state))
	runtime.lastPushedAt = os.clock()
end

function BreathServiceServer.TrackPlayer(self: BreathServiceServer, player: Player)
	local runtime = self:CreateRuntime()
	runtime.state = BreathServiceUtils.CreateState({
		ready = true,
		maxBreath = self.config.maxBreathSeconds,
		breath = self.config.maxBreathSeconds,
		graceRemaining = self.config.graceDuration,
	}, runtime.state)
	self.playerRuntimes[player] = runtime
	self:PushState(player)
end

function BreathServiceServer.UntrackPlayer(self: BreathServiceServer, player: Player)
	self.playerRuntimes[player] = nil
end

function BreathServiceServer.RequestSync(self: BreathServiceServer, player: Player)
	if self.playerRuntimes[player] == nil then
		self:TrackPlayer(player)
		return
	end
	self:PushState(player)
end

function BreathServiceServer.ProcessPlayer(self: BreathServiceServer, player: Player, dt: number)
	local runtime = self:GetRuntime(player)
	local liquidQuery = self.liquidService:GetPlayerLiquidQuery(player)
	local overrideQuery = BreathBinder.QueryCharacterOverride(player.Character)
	if overrideQuery ~= nil then
		liquidQuery = overrideQuery
	end
	local breathBlocked = LiquidServiceUtils.LiquidDamage.ShouldBlockBreath(self.liquidService.config, liquidQuery)
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
				sendPacket(player, BreathServiceUtils.CLIENT_METHOD_ON_EVENT, {
					eventType = BreathServiceUtils.EVENT_BREATH_DEPLETED,
					updatedAt = now,
				})
			end
			if now - runtime.lastDrowningDamageAt >= self.config.drowningTickRate then
				self.hpService:DamagePlayer(player, self.config.drowningDamage)
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
		self:PushState(player)
	end
end

function BreathServiceServer.OnHeartbeat(self: BreathServiceServer, deltaTime: number)
	self.accumulator += deltaTime
	local step = 1 / self.config.updateRate
	while self.accumulator >= step do
		self.accumulator -= step
		for player in self.playerRuntimes do
			self:ProcessPlayer(player, step)
		end
	end
end

function BreathServiceServer.Init(self: BreathServiceServer, serviceBag: any)
	self.config = BreathServiceUtils.CoerceConfig(getSourceConfig(), nil)
	self.playerRuntimes = {} :: { [Player]: PlayerRuntime }
	self.accumulator = 0
	self.liquidService = LiquidServiceServer :: LiquidServiceServerObject
	self.hpService = HpServiceServer :: any
	self.breathDepleted = Signal.new();
	(self :: any).binders = serviceBag:GetService(BinderSupportServer)

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
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:OnHeartbeat(deltaTime)
	end)
end

function BreathServiceServer.Destroy(self: BreathServiceServer)
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
	if self.breathDepleted ~= nil then
		self.breathDepleted:Destroy()
	end
	table.clear(self.playerRuntimes)
end
type BreathServiceServer = typeof(BreathServiceServer) & {
	config: BreathServiceConfig,
	playerRuntimes: { [Player]: PlayerRuntime },
	accumulator: number,
	liquidService: LiquidServiceServerObject,
	hpService: HpServiceServerObject,
	breathDepleted: SignalObject,
	heartbeatConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return BreathServiceServer :: BreathServiceServer
