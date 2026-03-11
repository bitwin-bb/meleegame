--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local VFXServiceUtils = require(ReplicatedStorage.Shared.Services.VFXService.VFXServiceUtils)

local VFXServiceServer = {}

local function sanitizePlayers(playersRaw: any): { Player }
	local players = {}
	if typeof(playersRaw) ~= "table" then
		return players
	end

	for _, player in playersRaw do
		if typeof(player) == "Instance" and player:IsA("Player") then
			table.insert(players, player)
		end
	end
	return players
end

local function fireForPlayers(networker: Networker.Server, players: { Player }, methodName: string, ...: any)
	for _, player in players do
		networker:fire(player, methodName, ...)
	end
end

function VFXServiceServer.init(self: VFXServiceServer)
	self.networker = Networker.server.new("VFXService", self)
end

function VFXServiceServer.playForPlayer(
	self: VFXServiceServer,
	player: Player,
	effectSourceRaw: any,
	optionsRaw: any
): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local effectReference = VFXServiceUtils.sanitizeEffectReference(effectSourceRaw)
	if effectReference == nil then
		return false
	end

	local options = VFXServiceUtils.serializePlaybackOptions(optionsRaw)
	self.networker:fire(player, VFXServiceUtils.NETWORK_METHOD_PLAY, effectReference, options)
	return true
end

function VFXServiceServer.playForPlayers(
	self: VFXServiceServer,
	playersRaw: any,
	effectSourceRaw: any,
	optionsRaw: any
): number
	local players = sanitizePlayers(playersRaw)
	if #players <= 0 then
		return 0
	end

	local effectReference = VFXServiceUtils.sanitizeEffectReference(effectSourceRaw)
	if effectReference == nil then
		return 0
	end

	local options = VFXServiceUtils.serializePlaybackOptions(optionsRaw)
	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_PLAY, effectReference, options)
	return #players
end

function VFXServiceServer.playForAll(self: VFXServiceServer, effectSourceRaw: any, optionsRaw: any): number
	local players = Players:GetPlayers()
	if #players <= 0 then
		return 0
	end

	local effectReference = VFXServiceUtils.sanitizeEffectReference(effectSourceRaw)
	if effectReference == nil then
		return 0
	end

	local options = VFXServiceUtils.serializePlaybackOptions(optionsRaw)
	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_PLAY, effectReference, options)
	return #players
end

function VFXServiceServer.stopChannelForPlayer(self: VFXServiceServer, player: Player, channelNameRaw: any): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local channelName = VFXServiceUtils.sanitizeChannelName(channelNameRaw)
	if channelName == nil then
		return false
	end

	self.networker:fire(player, VFXServiceUtils.NETWORK_METHOD_STOP_CHANNEL, channelName)
	return true
end

function VFXServiceServer.stopChannelForPlayers(
	self: VFXServiceServer,
	playersRaw: any,
	channelNameRaw: any
): number
	local players = sanitizePlayers(playersRaw)
	if #players <= 0 then
		return 0
	end

	local channelName = VFXServiceUtils.sanitizeChannelName(channelNameRaw)
	if channelName == nil then
		return 0
	end

	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_STOP_CHANNEL, channelName)
	return #players
end

function VFXServiceServer.stopChannelForAll(self: VFXServiceServer, channelNameRaw: any): number
	local players = Players:GetPlayers()
	if #players <= 0 then
		return 0
	end

	local channelName = VFXServiceUtils.sanitizeChannelName(channelNameRaw)
	if channelName == nil then
		return 0
	end

	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_STOP_CHANNEL, channelName)
	return #players
end

function VFXServiceServer.stopAllForPlayer(self: VFXServiceServer, player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	self.networker:fire(player, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return true
end

function VFXServiceServer.stopAllForPlayers(self: VFXServiceServer, playersRaw: any): number
	local players = sanitizePlayers(playersRaw)
	if #players <= 0 then
		return 0
	end

	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return #players
end

function VFXServiceServer.stopAllForAll(self: VFXServiceServer): number
	local players = Players:GetPlayers()
	if #players <= 0 then
		return 0
	end

	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return #players
end

function VFXServiceServer.destroy(self: VFXServiceServer)
	if self.networker ~= nil then
		self.networker:destroy()
	end
end

type VFXServiceServer = typeof(VFXServiceServer) & {
	playForPlayer: (self: VFXServiceServer, player: Player, effectSourceRaw: any, optionsRaw: any) -> boolean,
	playForPlayers: (self: VFXServiceServer, playersRaw: any, effectSourceRaw: any, optionsRaw: any) -> number,
	playForAll: (self: VFXServiceServer, effectSourceRaw: any, optionsRaw: any) -> number,
	stopChannelForPlayer: (self: VFXServiceServer, player: Player, channelNameRaw: any) -> boolean,
	stopChannelForPlayers: (self: VFXServiceServer, playersRaw: any, channelNameRaw: any) -> number,
	stopChannelForAll: (self: VFXServiceServer, channelNameRaw: any) -> number,
	stopAllForPlayer: (self: VFXServiceServer, player: Player) -> boolean,
	stopAllForPlayers: (self: VFXServiceServer, playersRaw: any) -> number,
	stopAllForAll: (self: VFXServiceServer) -> number,
	networker: Networker.Server,
}

return VFXServiceServer :: VFXServiceServer
