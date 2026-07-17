
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AnimationServiceUtils = require("AnimationServiceUtils")
local PacketPayload = require("PacketPayload")
local AnimationServicePackets = require("NetPacketsShared").AnimationService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = AnimationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AnimationService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = AnimationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AnimationService`)
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
	bindPacket(self, "setFootstepsEnabled")
	bindPacket(self, "setProfile")
end

type AnimationProfile = AnimationServiceUtils.AnimationProfile
type AnimationServiceState = AnimationServiceUtils.AnimationServiceState

local AnimationServiceServer = {}
AnimationServiceServer.ServiceName = "AnimationServiceServer"

function AnimationServiceServer.Init(self: AnimationServiceServer, _serviceBag: any?)
	self.profileRegistry = AnimationServiceUtils.CreateDefaultProfileRegistry()
	self.playerStates = {}
	bindPackets(self)

	for _, player in Players:GetPlayers() do
		self.playerStates[player] = AnimationServiceUtils.CreateDefaultState()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self.playerStates[player] = AnimationServiceUtils.CreateDefaultState()
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self.playerStates[player] = nil
	end)
end

function AnimationServiceServer.GetState(self: AnimationServiceServer, player: Player): AnimationServiceState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local defaultState = AnimationServiceUtils.CreateDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function AnimationServiceServer.PushState(self: AnimationServiceServer, player: Player)
	local state = self:GetState(player)
	sendPacket(player, "applyState", state.profileName, state.footstepsEnabled)
end

function AnimationServiceServer.RequestSync(self: AnimationServiceServer, player: Player)
	self:PushState(player)
end

function AnimationServiceServer.SetProfile(self: AnimationServiceServer, player: Player, profileNameRaw: any)
	local currentState = self:GetState(player)
	local nextState = AnimationServiceUtils.CreateState(
		profileNameRaw,
		currentState.footstepsEnabled,
		self.profileRegistry,
		currentState
	)
	self.playerStates[player] = nextState
	self:PushState(player)
end

function AnimationServiceServer.SetFootstepsEnabled(
	self: AnimationServiceServer,
	player: Player,
	footstepsEnabledRaw: any
)
	local currentState = self:GetState(player)
	local nextState = AnimationServiceUtils.CreateState(
		currentState.profileName,
		footstepsEnabledRaw,
		self.profileRegistry,
		currentState
	)
	self.playerStates[player] = nextState
	self:PushState(player)
end

function AnimationServiceServer.GetProfileRegistry(self: AnimationServiceServer): { [string]: AnimationProfile }
	return self.profileRegistry
end

function AnimationServiceServer.Destroy(self: AnimationServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end

	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
end
type AnimationServiceServer = typeof(AnimationServiceServer) & {
	playerStates: { [Player]: AnimationServiceState },
	profileRegistry: { [string]: AnimationProfile },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return AnimationServiceServer :: AnimationServiceServer
