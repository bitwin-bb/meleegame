--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local AudioServiceUtils = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceUtils)

type AudioServiceState = AudioServiceUtils.AudioServiceState

local AudioServiceServer = {}

local function fireForPlayers(networker: Networker.Server, players: { Player }, methodName: string, ...: any)
	for _, player in players do
		networker:fire(player, methodName, ...)
	end
end

function AudioServiceServer.init(self: AudioServiceServer)
	self.playerStates = {}
	self.networker = Networker.server.new("AudioService", self, {
		self.requestSync,
		self.setMasterVolume,
		self.setCategoryVolume,
		self.setMuted,
	})

	for _, player in Players:GetPlayers() do
		self.playerStates[player] = AudioServiceUtils.createDefaultState()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self.playerStates[player] = AudioServiceUtils.createDefaultState()
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self.playerStates[player] = nil
	end)
end

function AudioServiceServer.getState(self: AudioServiceServer, player: Player): AudioServiceState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local defaultState = AudioServiceUtils.createDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function AudioServiceServer.pushState(self: AudioServiceServer, player: Player)
	local state = self:getState(player)
	self.networker:fire(player, "applyState", state.masterVolume, state.muted, state.categoryVolumes)
end

function AudioServiceServer.requestSync(self: AudioServiceServer, player: Player)
	self:pushState(player)
end

function AudioServiceServer.setMasterVolume(self: AudioServiceServer, player: Player, masterVolumeRaw: any)
	local currentState = self:getState(player)
	local nextState = AudioServiceUtils.withMasterVolume(currentState, masterVolumeRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function AudioServiceServer.setMuted(self: AudioServiceServer, player: Player, mutedRaw: any)
	local currentState = self:getState(player)
	local nextState = AudioServiceUtils.withMuted(currentState, mutedRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function AudioServiceServer.setCategoryVolume(
	self: AudioServiceServer,
	player: Player,
	categoryRaw: any,
	volumeRaw: any
)
	local currentState = self:getState(player)
	local nextState = AudioServiceUtils.withCategoryVolume(currentState, categoryRaw, volumeRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function AudioServiceServer.playSfxForPlayer(
	self: AudioServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = AudioServiceUtils.serializePlaybackOptions(optionsRaw, "SFX")
	self.networker:fire(player, "playSfx", soundAssetId, options)
end

function AudioServiceServer.playSfxForAll(self: AudioServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = AudioServiceUtils.serializePlaybackOptions(optionsRaw, "SFX")
	fireForPlayers(self.networker, Players:GetPlayers(), "playSfx", soundAssetId, options)
end

function AudioServiceServer.playMusicForPlayer(
	self: AudioServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = AudioServiceUtils.serializePlaybackOptions(optionsRaw, "Music")
	self.networker:fire(player, "playMusic", soundAssetId, options)
end

function AudioServiceServer.playMusicForAll(self: AudioServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = AudioServiceUtils.serializePlaybackOptions(optionsRaw, "Music")
	fireForPlayers(self.networker, Players:GetPlayers(), "playMusic", soundAssetId, options)
end

function AudioServiceServer.playAmbienceForPlayer(
	self: AudioServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = AudioServiceUtils.serializePlaybackOptions(optionsRaw, "Ambience")
	self.networker:fire(player, "playAmbience", soundAssetId, options)
end

function AudioServiceServer.playAmbienceForAll(self: AudioServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId = AudioServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = AudioServiceUtils.serializePlaybackOptions(optionsRaw, "Ambience")
	fireForPlayers(self.networker, Players:GetPlayers(), "playAmbience", soundAssetId, options)
end

function AudioServiceServer.stopChannelForPlayer(
	self: AudioServiceServer,
	player: Player,
	channelNameRaw: any,
	fadeTimeRaw: any
)
	self.networker:fire(player, "stopChannel", channelNameRaw, fadeTimeRaw)
end

function AudioServiceServer.stopChannelForAll(self: AudioServiceServer, channelNameRaw: any, fadeTimeRaw: any)
	fireForPlayers(self.networker, Players:GetPlayers(), "stopChannel", channelNameRaw, fadeTimeRaw)
end

function AudioServiceServer.stopAllForPlayer(self: AudioServiceServer, player: Player, fadeTimeRaw: any)
	self.networker:fire(player, "stopAll", fadeTimeRaw)
end

function AudioServiceServer.stopAllForAll(self: AudioServiceServer, fadeTimeRaw: any)
	fireForPlayers(self.networker, Players:GetPlayers(), "stopAll", fadeTimeRaw)
end

function AudioServiceServer.destroy(self: AudioServiceServer)
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

type AudioServiceServer = typeof(AudioServiceServer) & {
	networker: Networker.Server,
	playerStates: { [Player]: AudioServiceState },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return AudioServiceServer :: AudioServiceServer

