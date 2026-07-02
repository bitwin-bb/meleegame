local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AudioServiceUtils =
	require(script:FindFirstAncestor("game").Shared.Source.Audio:WaitForChild("AudioServiceUtils"))
local PacketPayload = require("PacketPayload")
local AudioServicePackets = require("NetPacketsServer").AudioService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = AudioServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AudioService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = AudioServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AudioService`)
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
	bindPacket(self, "setCategoryVolume")
	bindPacket(self, "setMasterVolume")
	bindPacket(self, "setMuted")
end

type AudioServiceState = AudioServiceUtils.AudioServiceState

local AudioServiceServer = {}

local MISSING_ASSET_ERROR = "no asset found!"

local function fireForPlayers(players: { Player }, methodName: string, ...: any)
	for _, player in players do
		sendPacket(player, methodName, ...)
	end
end

function AudioServiceServer.Init(self: AudioServiceServer)
	self.playerStates = {}
	bindPackets(self)

	for _, player in Players:GetPlayers() do
		self.playerStates[player] = AudioServiceUtils.CreateDefaultState()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self.playerStates[player] = AudioServiceUtils.CreateDefaultState()
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self.playerStates[player] = nil
	end)
end

function AudioServiceServer.GetState(self: AudioServiceServer, player: Player): AudioServiceState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local defaultState = AudioServiceUtils.CreateDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function AudioServiceServer.PushState(self: AudioServiceServer, player: Player)
	local state = self:GetState(player)
	sendPacket(player, "applyState", state.masterVolume, state.muted, state.categoryVolumes)
end

function AudioServiceServer.RequestSync(self: AudioServiceServer, player: Player)
	self:PushState(player)
end

function AudioServiceServer.SetMasterVolume(self: AudioServiceServer, player: Player, masterVolumeRaw: any)
	local currentState = self:GetState(player)
	local nextState = AudioServiceUtils.WithMasterVolume(currentState, masterVolumeRaw)
	self.playerStates[player] = nextState
	self:PushState(player)
end

function AudioServiceServer.SetMuted(self: AudioServiceServer, player: Player, mutedRaw: any)
	local currentState = self:GetState(player)
	local nextState = AudioServiceUtils.WithMuted(currentState, mutedRaw)
	self.playerStates[player] = nextState
	self:PushState(player)
end

function AudioServiceServer.SetCategoryVolume(
	self: AudioServiceServer,
	player: Player,
	categoryRaw: any,
	volumeRaw: any
)
	local currentState = self:GetState(player)
	local nextState = AudioServiceUtils.WithCategoryVolume(currentState, categoryRaw, volumeRaw)
	self.playerStates[player] = nextState
	self:PushState(player)
end

function AudioServiceServer.PlaySfxForPlayer(
	_self: AudioServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId, options = AudioServiceUtils.GetPlaybackRequest(soundAssetIdRaw, optionsRaw, "SFX")
	if soundAssetId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	sendPacket(player, "playSfx", soundAssetId, AudioServiceUtils.SerializePlaybackOptions(options, "SFX"))
end

function AudioServiceServer.PlaySfxForAll(_self: AudioServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId, options = AudioServiceUtils.GetPlaybackRequest(soundAssetIdRaw, optionsRaw, "SFX")
	if soundAssetId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	fireForPlayers(
		Players:GetPlayers(),
		"playSfx",
		soundAssetId,
		AudioServiceUtils.SerializePlaybackOptions(options, "SFX")
	)
end

function AudioServiceServer.PlayMusicForPlayer(
	_self: AudioServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId, options = AudioServiceUtils.GetPlaybackRequest(soundAssetIdRaw, optionsRaw, "Music")
	if soundAssetId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	sendPacket(player, "playMusic", soundAssetId, AudioServiceUtils.SerializePlaybackOptions(options, "Music"))
end

function AudioServiceServer.PlayMusicForAll(_self: AudioServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId, options = AudioServiceUtils.GetPlaybackRequest(soundAssetIdRaw, optionsRaw, "Music")
	if soundAssetId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	fireForPlayers(
		Players:GetPlayers(),
		"playMusic",
		soundAssetId,
		AudioServiceUtils.SerializePlaybackOptions(options, "Music")
	)
end

function AudioServiceServer.StopChannelForPlayer(
	_self: AudioServiceServer,
	player: Player,
	channelNameRaw: any,
	fadeTimeRaw: any
)
	sendPacket(player, "stopChannel", channelNameRaw, fadeTimeRaw)
end

function AudioServiceServer.StopChannelForAll(_self: AudioServiceServer, channelNameRaw: any, fadeTimeRaw: any)
	fireForPlayers(Players:GetPlayers(), "stopChannel", channelNameRaw, fadeTimeRaw)
end

function AudioServiceServer.StopAllForPlayer(_self: AudioServiceServer, player: Player, fadeTimeRaw: any)
	sendPacket(player, "stopAll", fadeTimeRaw)
end

function AudioServiceServer.StopAllForAll(_self: AudioServiceServer, fadeTimeRaw: any)
	fireForPlayers(Players:GetPlayers(), "stopAll", fadeTimeRaw)
end

function AudioServiceServer.Destroy(self: AudioServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
end
type AudioServiceServer = typeof(AudioServiceServer) & {
	playerStates: { [Player]: AudioServiceState },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return AudioServiceServer :: AudioServiceServer
