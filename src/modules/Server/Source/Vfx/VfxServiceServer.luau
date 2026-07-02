
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local PacketPayload = require("PacketPayload")
local VFXServicePackets = require("NetPacketsShared").VFXService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = VFXServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for VFXService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local VFXServiceUtils = require("VfxServiceUtils")

local VFXServiceServer = {}

local function CoercePlayers(playersRaw: any): { Player }
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

local function fireForPlayers(players: { Player }, methodName: string, ...: any)
	for _, player in players do
		sendPacket(player, methodName, ...)
	end
end

function VFXServiceServer.Init(_self: VFXServiceServer) end

function VFXServiceServer.PlayForPlayer(
	_self: VFXServiceServer,
	player: Player,
	effectSourceRaw: any,
	optionsRaw: any
): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local effectReference = VFXServiceUtils.CoerceEffectReference(effectSourceRaw)
	if effectReference == nil then
		return false
	end

	local options = VFXServiceUtils.SerializePlaybackOptions(optionsRaw)
	sendPacket(player, VFXServiceUtils.NETWORK_METHOD_PLAY, effectReference, options)
	return true
end

function VFXServiceServer.PlayForPlayers(
	_self: VFXServiceServer,
	playersRaw: any,
	effectSourceRaw: any,
	optionsRaw: any
): number
	local players = CoercePlayers(playersRaw)
	if #players <= 0 then
		return 0
	end

	local effectReference = VFXServiceUtils.CoerceEffectReference(effectSourceRaw)
	if effectReference == nil then
		return 0
	end

	local options = VFXServiceUtils.SerializePlaybackOptions(optionsRaw)
	fireForPlayers(players, VFXServiceUtils.NETWORK_METHOD_PLAY, effectReference, options)
	return #players
end

function VFXServiceServer.PlayForAll(_self: VFXServiceServer, effectSourceRaw: any, optionsRaw: any): number
	local players = Players:GetPlayers()
	if #players <= 0 then
		return 0
	end

	local effectReference = VFXServiceUtils.CoerceEffectReference(effectSourceRaw)
	if effectReference == nil then
		return 0
	end

	local options = VFXServiceUtils.SerializePlaybackOptions(optionsRaw)
	fireForPlayers(players, VFXServiceUtils.NETWORK_METHOD_PLAY, effectReference, options)
	return #players
end

function VFXServiceServer.StopChannelForPlayer(_self: VFXServiceServer, player: Player, channelNameRaw: any): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local channelName = VFXServiceUtils.CoerceChannelName(channelNameRaw)
	if channelName == nil then
		return false
	end

	sendPacket(player, VFXServiceUtils.NETWORK_METHOD_STOP_CHANNEL, channelName)
	return true
end

function VFXServiceServer.StopChannelForPlayers(_self: VFXServiceServer, playersRaw: any, channelNameRaw: any): number
	local players = CoercePlayers(playersRaw)
	if #players <= 0 then
		return 0
	end

	local channelName = VFXServiceUtils.CoerceChannelName(channelNameRaw)
	if channelName == nil then
		return 0
	end

	fireForPlayers(players, VFXServiceUtils.NETWORK_METHOD_STOP_CHANNEL, channelName)
	return #players
end

function VFXServiceServer.StopChannelForAll(_self: VFXServiceServer, channelNameRaw: any): number
	local players = Players:GetPlayers()
	if #players <= 0 then
		return 0
	end

	local channelName = VFXServiceUtils.CoerceChannelName(channelNameRaw)
	if channelName == nil then
		return 0
	end

	fireForPlayers(players, VFXServiceUtils.NETWORK_METHOD_STOP_CHANNEL, channelName)
	return #players
end

function VFXServiceServer.StopAllForPlayer(_self: VFXServiceServer, player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	sendPacket(player, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return true
end

function VFXServiceServer.StopAllForPlayers(_self: VFXServiceServer, playersRaw: any): number
	local players = CoercePlayers(playersRaw)
	if #players <= 0 then
		return 0
	end

	fireForPlayers(players, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return #players
end

function VFXServiceServer.StopAllForAll(_self: VFXServiceServer): number
	local players = Players:GetPlayers()
	if #players <= 0 then
		return 0
	end

	fireForPlayers(players, VFXServiceUtils.NETWORK_METHOD_STOP_ALL)
	return #players
end

function VFXServiceServer.Destroy(_self: VFXServiceServer) end
type VFXServiceServer = typeof(VFXServiceServer) & {
	PlayForPlayer: (self: VFXServiceServer, player: Player, effectSourceRaw: any, optionsRaw: any) -> boolean,
	PlayForPlayers: (self: VFXServiceServer, playersRaw: any, effectSourceRaw: any, optionsRaw: any) -> number,
	PlayForAll: (self: VFXServiceServer, effectSourceRaw: any, optionsRaw: any) -> number,
	StopChannelForPlayer: (self: VFXServiceServer, player: Player, channelNameRaw: any) -> boolean,
	StopChannelForPlayers: (self: VFXServiceServer, playersRaw: any, channelNameRaw: any) -> number,
	StopChannelForAll: (self: VFXServiceServer, channelNameRaw: any) -> number,
	StopAllForPlayer: (self: VFXServiceServer, player: Player) -> boolean,
	StopAllForPlayers: (self: VFXServiceServer, playersRaw: any) -> number,
	StopAllForAll: (self: VFXServiceServer) -> number,
}

return VFXServiceServer :: VFXServiceServer
