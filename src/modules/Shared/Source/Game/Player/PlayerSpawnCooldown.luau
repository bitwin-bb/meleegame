
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local DataTemplate = require("DataTemplate")

local PlayerSpawnCooldown = {}

local DEFAULT_RESPAWN_DELAY = 5
local MIN_RESPAWN_DELAY = 0.1
local MAX_RESPAWN_DELAY = 120

local function coerceRespawnDelay(valueRaw: any, fallbackRaw: any?): number
	local fallbackValue = if typeof(fallbackRaw) == "number" and fallbackRaw == fallbackRaw
		then fallbackRaw
		else DEFAULT_RESPAWN_DELAY

	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return math.clamp(fallbackValue, MIN_RESPAWN_DELAY, MAX_RESPAWN_DELAY)
	end

	return math.clamp(valueRaw, MIN_RESPAWN_DELAY, MAX_RESPAWN_DELAY)
end

local function getConfiguredRespawnDelayFromTemplate(): number?
	if typeof(DataTemplate) ~= "table" then
		return nil
	end

	local playerData = if typeof((DataTemplate :: any).playerData) == "table"
		then (DataTemplate :: any).playerData
		else nil
	if playerData == nil then
		return nil
	end

	local configuredDelayRaw = (playerData :: any).respawnCooldown
	if configuredDelayRaw == nil then
		configuredDelayRaw = (playerData :: any).respawnDelay
	end
	if configuredDelayRaw == nil then
		return nil
	end

	return coerceRespawnDelay(configuredDelayRaw, DEFAULT_RESPAWN_DELAY)
end

function PlayerSpawnCooldown.GetCurrentRespawnDelay(): number
	return coerceRespawnDelay(Players.RespawnTime, DEFAULT_RESPAWN_DELAY)
end

function PlayerSpawnCooldown.GetConfiguredRespawnDelay(): number
	local configuredRespawnDelay = getConfiguredRespawnDelayFromTemplate()
	if configuredRespawnDelay ~= nil then
		return configuredRespawnDelay
	end
	return PlayerSpawnCooldown.GetCurrentRespawnDelay()
end

function PlayerSpawnCooldown.ApplyConfiguredRespawnDelay(): number
	local configuredRespawnDelay = PlayerSpawnCooldown.GetConfiguredRespawnDelay()
	Players.RespawnTime = configuredRespawnDelay
	return configuredRespawnDelay
end

PlayerSpawnCooldown.DEFAULT_RESPAWN_DELAY = DEFAULT_RESPAWN_DELAY
PlayerSpawnCooldown.MIN_RESPAWN_DELAY = MIN_RESPAWN_DELAY
PlayerSpawnCooldown.MAX_RESPAWN_DELAY = MAX_RESPAWN_DELAY
return PlayerSpawnCooldown
