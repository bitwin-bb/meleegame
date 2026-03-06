--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local AnimationServiceUtils = require(ReplicatedStorage.Shared.Services.AnimationService.AnimationServiceUtils)

type AnimationProfile = AnimationServiceUtils.AnimationProfile
type AnimationServiceState = AnimationServiceUtils.AnimationServiceState

local AnimationServiceServer = {}

function AnimationServiceServer.init(self: AnimationServiceServer)
	self.profileRegistry = AnimationServiceUtils.createDefaultProfileRegistry()
	self.playerStates = {}
	self.networker = Networker.server.new("AnimationService", self, {
		self.requestSync,
		self.setProfile,
		self.setFootstepsEnabled,
	})

	for _, player in Players:GetPlayers() do
		self.playerStates[player] = AnimationServiceUtils.createDefaultState()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self.playerStates[player] = AnimationServiceUtils.createDefaultState()
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self.playerStates[player] = nil
	end)
end

function AnimationServiceServer.getState(self: AnimationServiceServer, player: Player): AnimationServiceState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local defaultState = AnimationServiceUtils.createDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function AnimationServiceServer.pushState(self: AnimationServiceServer, player: Player)
	local state = self:getState(player)
	self.networker:fire(player, "applyState", state.profileName, state.footstepsEnabled)
end

function AnimationServiceServer.requestSync(self: AnimationServiceServer, player: Player)
	self:pushState(player)
end

function AnimationServiceServer.setProfile(self: AnimationServiceServer, player: Player, profileNameRaw: any)
	local currentState = self:getState(player)
	local nextState = AnimationServiceUtils.createState(
		profileNameRaw,
		currentState.footstepsEnabled,
		self.profileRegistry,
		currentState
	)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function AnimationServiceServer.setFootstepsEnabled(
	self: AnimationServiceServer,
	player: Player,
	footstepsEnabledRaw: any
)
	local currentState = self:getState(player)
	local nextState = AnimationServiceUtils.createState(
		currentState.profileName,
		footstepsEnabledRaw,
		self.profileRegistry,
		currentState
	)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function AnimationServiceServer.getProfileRegistry(self: AnimationServiceServer): { [string]: AnimationProfile }
	return self.profileRegistry
end

function AnimationServiceServer.destroy(self: AnimationServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end

	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	if self.networker then
		self.networker:destroy()
	end
end

type AnimationServiceServer = typeof(AnimationServiceServer) & {
	networker: Networker.Server,
	playerStates: { [Player]: AnimationServiceState },
	profileRegistry: { [string]: AnimationProfile },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return AnimationServiceServer :: AnimationServiceServer
