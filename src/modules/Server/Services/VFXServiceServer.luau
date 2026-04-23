--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local VFXServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.VFXServiceUtils)

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

function VFXServiceServer.Init(self: VFXServiceServer)
	self.networker = Networker.server.new("VFXService", self)
end

function VFXServiceServer.PlayForPlayer(
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

function VFXServiceServer.PlayForPlayers(
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

function VFXServiceServer.PlayForAll(self: VFXServiceServer, effectSourceRaw: any, optionsRaw: any): number
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

function VFXServiceServer.StopChannelForPlayer(self: VFXServiceServer, player: Player, channelNameRaw: any): boolean
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

function VFXServiceServer.StopChannelForPlayers(
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

function VFXServiceServer.StopChannelForAll(self: VFXServiceServer, channelNameRaw: any): number
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

function VFXServiceServer.StopAllForPlayer(self: VFXServiceServer, player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	self.networker:fire(player, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return true
end

function VFXServiceServer.StopAllForPlayers(self: VFXServiceServer, playersRaw: any): number
	local players = sanitizePlayers(playersRaw)
	if #players <= 0 then
		return 0
	end

	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return #players
end

function VFXServiceServer.StopAllForAll(self: VFXServiceServer): number
	local players = Players:GetPlayers()
	if #players <= 0 then
		return 0
	end

	fireForPlayers(self.networker, players, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return #players
end

function VFXServiceServer.Destroy(self: VFXServiceServer)
	if self.networker ~= nil then
		self.networker:destroy()
	end
end

VFXServiceServer.init = VFXServiceServer.Init
VFXServiceServer.playForPlayer = VFXServiceServer.PlayForPlayer
VFXServiceServer.playForPlayers = VFXServiceServer.PlayForPlayers
VFXServiceServer.playForAll = VFXServiceServer.PlayForAll
VFXServiceServer.stopChannelForPlayer = VFXServiceServer.StopChannelForPlayer
VFXServiceServer.stopChannelForPlayers = VFXServiceServer.StopChannelForPlayers
VFXServiceServer.stopChannelForAll = VFXServiceServer.StopChannelForAll
VFXServiceServer.stopAllForPlayer = VFXServiceServer.StopAllForPlayer
VFXServiceServer.stopAllForPlayers = VFXServiceServer.StopAllForPlayers
VFXServiceServer.stopAllForAll = VFXServiceServer.StopAllForAll
VFXServiceServer.destroy = VFXServiceServer.Destroy

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

