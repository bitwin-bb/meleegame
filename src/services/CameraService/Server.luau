--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local CameraServiceUtils = require(ReplicatedStorage.Shared.Services.CameraService.CameraServiceUtils)

type CameraState = CameraServiceUtils.CameraState

local CameraServiceServer = {}

function CameraServiceServer.init(self: CameraServiceServer)
	self.playerStates = {}
	self.networker = Networker.server.new("CameraService", self, {
		self.requestSync,
		self.setMode,
	})

	for _, player in Players:GetPlayers() do
		self.playerStates[player] = CameraServiceUtils.createDefaultState()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player)
		self.playerStates[player] = CameraServiceUtils.createDefaultState()
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		self.playerStates[player] = nil
	end)
end

function CameraServiceServer.getState(self: CameraServiceServer, player: Player): CameraState
	local state = self.playerStates[player]
	if state then
		return state
	end

	local defaultState = CameraServiceUtils.createDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function CameraServiceServer.requestSync(self: CameraServiceServer, player: Player)
	local state = self:getState(player)
	self.networker:fire(player, "applyMode", state.mode, state.sideViewConfig)
end

function CameraServiceServer.setMode(self: CameraServiceServer, player: Player, mode: any, sideViewConfig: any)
	local state = self:getState(player)
	local mergedSideViewConfig = CameraServiceUtils.mergeSideViewConfig(state.sideViewConfig, sideViewConfig)
	local nextState = CameraServiceUtils.createCameraState(mode, mergedSideViewConfig)

	self.playerStates[player] = nextState
	self.networker:fire(player, "applyMode", nextState.mode, nextState.sideViewConfig)
end

function CameraServiceServer.destroy(self: CameraServiceServer)
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

type CameraServiceServer = typeof(CameraServiceServer) & {
	networker: Networker.Server,
	playerStates: { [Player]: CameraState },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return CameraServiceServer :: CameraServiceServer
