--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local SoundServiceUtils = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceUtils)

type SoundServiceState = SoundServiceUtils.SoundServiceState

local SoundServiceServer = {}

local function fireForPlayers(networker: Networker.Server, players: { Player }, methodName: string, ...: any)
	for _, player in players do
		networker:fire(player, methodName, ...)
	end
end

function SoundServiceServer.init(self: SoundServiceServer)
	self.playerStates = {}
	self.networker = Networker.server.new("SoundService", self, {
		self.requestSync,
		self.setMasterVolume,
		self.setCategoryVolume,
		self.setMuted,
	})

	for _, player in Players:GetPlayers() do
		self.playerStates[player] = SoundServiceUtils.createDefaultState()
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self.playerStates[player] = SoundServiceUtils.createDefaultState()
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self.playerStates[player] = nil
	end)
end

function SoundServiceServer.getState(self: SoundServiceServer, player: Player): SoundServiceState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local defaultState = SoundServiceUtils.createDefaultState()
	self.playerStates[player] = defaultState
	return defaultState
end

function SoundServiceServer.pushState(self: SoundServiceServer, player: Player)
	local state = self:getState(player)
	self.networker:fire(player, "applyState", state.masterVolume, state.muted, state.categoryVolumes)
end

function SoundServiceServer.requestSync(self: SoundServiceServer, player: Player)
	self:pushState(player)
end

function SoundServiceServer.setMasterVolume(self: SoundServiceServer, player: Player, masterVolumeRaw: any)
	local currentState = self:getState(player)
	local nextState = SoundServiceUtils.withMasterVolume(currentState, masterVolumeRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function SoundServiceServer.setMuted(self: SoundServiceServer, player: Player, mutedRaw: any)
	local currentState = self:getState(player)
	local nextState = SoundServiceUtils.withMuted(currentState, mutedRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function SoundServiceServer.setCategoryVolume(
	self: SoundServiceServer,
	player: Player,
	categoryRaw: any,
	volumeRaw: any
)
	local currentState = self:getState(player)
	local nextState = SoundServiceUtils.withCategoryVolume(currentState, categoryRaw, volumeRaw)
	self.playerStates[player] = nextState
	self:pushState(player)
end

function SoundServiceServer.playSfxForPlayer(
	self: SoundServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId = SoundServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = SoundServiceUtils.serializePlaybackOptions(optionsRaw, "SFX")
	self.networker:fire(player, "playSfx", soundAssetId, options)
end

function SoundServiceServer.playSfxForAll(self: SoundServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId = SoundServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = SoundServiceUtils.serializePlaybackOptions(optionsRaw, "SFX")
	fireForPlayers(self.networker, Players:GetPlayers(), "playSfx", soundAssetId, options)
end

function SoundServiceServer.playMusicForPlayer(
	self: SoundServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId = SoundServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = SoundServiceUtils.serializePlaybackOptions(optionsRaw, "Music")
	self.networker:fire(player, "playMusic", soundAssetId, options)
end

function SoundServiceServer.playMusicForAll(self: SoundServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId = SoundServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = SoundServiceUtils.serializePlaybackOptions(optionsRaw, "Music")
	fireForPlayers(self.networker, Players:GetPlayers(), "playMusic", soundAssetId, options)
end

function SoundServiceServer.playAmbienceForPlayer(
	self: SoundServiceServer,
	player: Player,
	soundAssetIdRaw: any,
	optionsRaw: any
)
	local soundAssetId = SoundServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = SoundServiceUtils.serializePlaybackOptions(optionsRaw, "Ambience")
	self.networker:fire(player, "playAmbience", soundAssetId, options)
end

function SoundServiceServer.playAmbienceForAll(self: SoundServiceServer, soundAssetIdRaw: any, optionsRaw: any)
	local soundAssetId = SoundServiceUtils.normalizeSoundAssetId(soundAssetIdRaw)
	if soundAssetId == nil then
		return
	end
	local options = SoundServiceUtils.serializePlaybackOptions(optionsRaw, "Ambience")
	fireForPlayers(self.networker, Players:GetPlayers(), "playAmbience", soundAssetId, options)
end

function SoundServiceServer.stopChannelForPlayer(
	self: SoundServiceServer,
	player: Player,
	channelNameRaw: any,
	fadeTimeRaw: any
)
	self.networker:fire(player, "stopChannel", channelNameRaw, fadeTimeRaw)
end

function SoundServiceServer.stopChannelForAll(self: SoundServiceServer, channelNameRaw: any, fadeTimeRaw: any)
	fireForPlayers(self.networker, Players:GetPlayers(), "stopChannel", channelNameRaw, fadeTimeRaw)
end

function SoundServiceServer.stopAllForPlayer(self: SoundServiceServer, player: Player, fadeTimeRaw: any)
	self.networker:fire(player, "stopAll", fadeTimeRaw)
end

function SoundServiceServer.stopAllForAll(self: SoundServiceServer, fadeTimeRaw: any)
	fireForPlayers(self.networker, Players:GetPlayers(), "stopAll", fadeTimeRaw)
end

function SoundServiceServer.destroy(self: SoundServiceServer)
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

type SoundServiceServer = typeof(SoundServiceServer) & {
	networker: Networker.Server,
	playerStates: { [Player]: SoundServiceState },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return SoundServiceServer :: SoundServiceServer
