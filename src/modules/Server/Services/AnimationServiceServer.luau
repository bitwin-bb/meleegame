--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local AnimationServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AnimationServiceUtils)

type AnimationProfile = AnimationServiceUtils.AnimationProfile
type AnimationServiceState = AnimationServiceUtils.AnimationServiceState

local AnimationServiceServer = {}

function AnimationServiceServer.Init(self: AnimationServiceServer)
	self.profileRegistry = AnimationServiceUtils.createDefaultProfileRegistry()
	self.playerStates = {}
	self.networker = Networker.server.new("AnimationService", self, {
		self.RequestSync,
		self.SetProfile,
		self.SetFootstepsEnabled,
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

function AnimationServiceServer.GetState(self: AnimationServiceServer, player: Player): AnimationServiceState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local defaultState = AnimationServiceUtils.createDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function AnimationServiceServer.PushState(self: AnimationServiceServer, player: Player)
	local state = self:getState(player)
	self.networker:fire(player, "applyState", state.profileName, state.footstepsEnabled)
end

function AnimationServiceServer.RequestSync(self: AnimationServiceServer, player: Player)
	self:pushState(player)
end

function AnimationServiceServer.SetProfile(self: AnimationServiceServer, player: Player, profileNameRaw: any)
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

function AnimationServiceServer.SetFootstepsEnabled(
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

	if self.networker then
		self.networker:destroy()
	end
end

AnimationServiceServer.init = AnimationServiceServer.Init
AnimationServiceServer.getState = AnimationServiceServer.GetState
AnimationServiceServer.pushState = AnimationServiceServer.PushState
AnimationServiceServer.requestSync = AnimationServiceServer.RequestSync
AnimationServiceServer.setProfile = AnimationServiceServer.SetProfile
AnimationServiceServer.setFootstepsEnabled = AnimationServiceServer.SetFootstepsEnabled
AnimationServiceServer.getProfileRegistry = AnimationServiceServer.GetProfileRegistry
AnimationServiceServer.destroy = AnimationServiceServer.Destroy

type AnimationServiceServer = typeof(AnimationServiceServer) & {
	networker: Networker.Server,
	playerStates: { [Player]: AnimationServiceState },
	profileRegistry: { [string]: AnimationProfile },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return AnimationServiceServer :: AnimationServiceServer

