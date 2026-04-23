--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local CameraServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.CameraService.CameraServiceUtils)

type CameraState = CameraServiceUtils.CameraState

local CameraServiceServer = {}

function CameraServiceServer.Init(self: CameraServiceServer)
	self.playerStates = {}
	self.networker = Networker.server.new("CameraService", self, {
		self.RequestSync,
		self.SetMode,
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

function CameraServiceServer.GetState(self: CameraServiceServer, player: Player): CameraState
	local state = self.playerStates[player]
	if state then
		return state
	end

	local defaultState = CameraServiceUtils.createDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function CameraServiceServer.RequestSync(self: CameraServiceServer, player: Player)
	local state = self:getState(player)
	self.networker:fire(player, "applyMode", state.mode, state.sideViewConfig)
end

function CameraServiceServer.SetMode(self: CameraServiceServer, player: Player, mode: any, sideViewConfig: any)
	local state = self:getState(player)
	local mergedSideViewConfig = CameraServiceUtils.mergeSideViewConfig(state.sideViewConfig, sideViewConfig)
	local nextState = CameraServiceUtils.createCameraState(mode, mergedSideViewConfig)

	self.playerStates[player] = nextState
	self.networker:fire(player, "applyMode", nextState.mode, nextState.sideViewConfig)
end

function CameraServiceServer.Destroy(self: CameraServiceServer)
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

CameraServiceServer.init = CameraServiceServer.Init
CameraServiceServer.getState = CameraServiceServer.GetState
CameraServiceServer.requestSync = CameraServiceServer.RequestSync
CameraServiceServer.setMode = CameraServiceServer.SetMode
CameraServiceServer.destroy = CameraServiceServer.Destroy

type CameraServiceServer = typeof(CameraServiceServer) & {
	networker: Networker.Server,
	playerStates: { [Player]: CameraState },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return CameraServiceServer :: CameraServiceServer

