--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioService.AudioServiceUtils)

type AudioServiceState = AudioServiceUtils.AudioServiceState

local AudioServiceServer = {}

local function fireForPlayers(networker: Networker.Server, players: { Player }, methodName: string, ...: any)
	for _, player in players do
		networker:fire(player, methodName, ...)
	end
end

function AudioServiceServer.Init(self: AudioServiceServer)
	self.playerStates = {}
	self.networker = Networker.server.new("AudioService", self, {
		self.RequestSync,
		self.SetMasterVolume,
		self.SetCategoryVolume,
		self.SetMuted,
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

function AudioServiceServer.GetState(self: AudioServiceServer, player: Player): AudioServiceState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local defaultState = AudioServiceUtils.createDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function AudioServiceServer.PushState(self: AudioServiceServer, player: Player)
	local state = self:getState(player)
	self.networker:fire(player, "applyState", state.masterVolume, state.muted, state.categoryVolumes)
end

function AudioServiceServer.RequestSync(self: AudioServiceServer, player: Player)
	self:pushState(player)
end

function AudioServiceServer.SetMasterVolume(self: AudioServiceServer, player: Player, masterVolumeRaw: any)
	local currentState = self:getState(player)
	local nextState = AudioServiceUtils.withMasterVolume(currentState, masterVolumeRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function AudioServiceServer.SetMuted(self: AudioServiceServer, player: Player, mutedRaw: any)
	local currentState = self:getState(player)
	local nextState = AudioServiceUtils.withMuted(currentState, mutedRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function AudioServiceServer.SetCategoryVolume(
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

function AudioServiceServer.PlaySfxForPlayer(
	self: AudioServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId, options = AudioServiceUtils.resolvePlaybackRequest(soundAssetIdRaw, optionsRaw, "SFX")
	if soundAssetId == nil then
		return
	end
	self.networker:fire(player, "playSfx", soundAssetId, AudioServiceUtils.serializePlaybackOptions(options, "SFX"))
end

function AudioServiceServer.PlaySfxForAll(self: AudioServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId, options = AudioServiceUtils.resolvePlaybackRequest(soundAssetIdRaw, optionsRaw, "SFX")
	if soundAssetId == nil then
		return
	end
	fireForPlayers(
		self.networker,
		Players:GetPlayers(),
		"playSfx",
		soundAssetId,
		AudioServiceUtils.serializePlaybackOptions(options, "SFX")
	)
end

function AudioServiceServer.PlayMusicForPlayer(
	self: AudioServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId, options = AudioServiceUtils.resolvePlaybackRequest(soundAssetIdRaw, optionsRaw, "Music")
	if soundAssetId == nil then
		return
	end
	self.networker:fire(player, "playMusic", soundAssetId, AudioServiceUtils.serializePlaybackOptions(options, "Music"))
end

function AudioServiceServer.PlayMusicForAll(self: AudioServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId, options = AudioServiceUtils.resolvePlaybackRequest(soundAssetIdRaw, optionsRaw, "Music")
	if soundAssetId == nil then
		return
	end
	fireForPlayers(
		self.networker,
		Players:GetPlayers(),
		"playMusic",
		soundAssetId,
		AudioServiceUtils.serializePlaybackOptions(options, "Music")
	)
end

function AudioServiceServer.StopChannelForPlayer(
	self: AudioServiceServer,
	player: Player,
	channelNameRaw: any,
	fadeTimeRaw: any
)
	self.networker:fire(player, "stopChannel", channelNameRaw, fadeTimeRaw)
end

function AudioServiceServer.StopChannelForAll(self: AudioServiceServer, channelNameRaw: any, fadeTimeRaw: any)
	fireForPlayers(self.networker, Players:GetPlayers(), "stopChannel", channelNameRaw, fadeTimeRaw)
end

function AudioServiceServer.StopAllForPlayer(self: AudioServiceServer, player: Player, fadeTimeRaw: any)
	self.networker:fire(player, "stopAll", fadeTimeRaw)
end

function AudioServiceServer.StopAllForAll(self: AudioServiceServer, fadeTimeRaw: any)
	fireForPlayers(self.networker, Players:GetPlayers(), "stopAll", fadeTimeRaw)
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
	if self.networker then
		self.networker:destroy()
	end
end

AudioServiceServer.init = AudioServiceServer.Init
AudioServiceServer.getState = AudioServiceServer.GetState
AudioServiceServer.pushState = AudioServiceServer.PushState
AudioServiceServer.requestSync = AudioServiceServer.RequestSync
AudioServiceServer.setMasterVolume = AudioServiceServer.SetMasterVolume
AudioServiceServer.setMuted = AudioServiceServer.SetMuted
AudioServiceServer.setCategoryVolume = AudioServiceServer.SetCategoryVolume
AudioServiceServer.playSfxForPlayer = AudioServiceServer.PlaySfxForPlayer
AudioServiceServer.playSfxForAll = AudioServiceServer.PlaySfxForAll
AudioServiceServer.playMusicForPlayer = AudioServiceServer.PlayMusicForPlayer
AudioServiceServer.playMusicForAll = AudioServiceServer.PlayMusicForAll
AudioServiceServer.stopChannelForPlayer = AudioServiceServer.StopChannelForPlayer
AudioServiceServer.stopChannelForAll = AudioServiceServer.StopChannelForAll
AudioServiceServer.stopAllForPlayer = AudioServiceServer.StopAllForPlayer
AudioServiceServer.stopAllForAll = AudioServiceServer.StopAllForAll
AudioServiceServer.destroy = AudioServiceServer.Destroy

type AudioServiceServer = typeof(AudioServiceServer) & {
	networker: Networker.Server,
	playerStates: { [Player]: AudioServiceState },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return AudioServiceServer :: AudioServiceServer


