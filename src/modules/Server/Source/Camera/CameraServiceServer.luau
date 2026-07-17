
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local CameraServiceUtils = require("CameraServiceUtils")
local PacketPayload = require("PacketPayload")
local CameraServicePackets = require("NetPacketsShared").CameraService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = CameraServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CameraService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = CameraServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CameraService`)
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
	bindPacket(self, "setMode")
end

type CameraState = CameraServiceUtils.CameraState

local CameraServiceServer = {}
CameraServiceServer.ServiceName = "CameraServiceServer"

function CameraServiceServer.Init(self: CameraServiceServer, _serviceBag: any?)
	self.playerStates = {}
	bindPackets(self)

	for _, player in Players:GetPlayers() do
		self.playerStates[player] = CameraServiceUtils.CreateDefaultState()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player)
		self.playerStates[player] = CameraServiceUtils.CreateDefaultState()
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

	local defaultState = CameraServiceUtils.CreateDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function CameraServiceServer.RequestSync(self: CameraServiceServer, player: Player)
	local state = self:GetState(player)
	sendPacket(player, "applyMode", state.mode, state.sideViewConfig)
end

function CameraServiceServer.SetMode(self: CameraServiceServer, player: Player, mode: any, sideViewConfig: any)
	local state = self:GetState(player)
	local mergedSideViewConfig = CameraServiceUtils.MergeSideViewConfig(state.sideViewConfig, sideViewConfig)
	local nextState = CameraServiceUtils.CreateCameraState(mode, mergedSideViewConfig)

	self.playerStates[player] = nextState
	sendPacket(player, "applyMode", nextState.mode, nextState.sideViewConfig)
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
end
type CameraServiceServer = typeof(CameraServiceServer) & {
	playerStates: { [Player]: CameraState },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return CameraServiceServer :: CameraServiceServer
