--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local coinSlice = require(ReplicatedStorage.UI.features.inventory.state.coinSlice)
local PlayerDataServiceClient = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceClient)
local PlayerDataServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceUtils)

type CoinState = coinSlice.CoinState
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

local coinThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local COINS_DATA_PATH = PlayerDataServiceUtils.getDefaultCoinsDataPath()
local LOCAL_PLAYER = Players.LocalPlayer

local function stringifyLogValue(valueRaw: any): string
	if valueRaw == nil then
		return "nil"
	end
	local valueType = typeof(valueRaw)
	if valueType == "string" or valueType == "number" or valueType == "boolean" then
		return tostring(valueRaw)
	end
	return valueType
end

local function logCoinsApplied(nextPlayerDataState: PlayerDataServiceState, nextCoinState: CoinState)
	local fields = {
		'stage="Coins applied from player data state"',
		("player=%s"):format(LOCAL_PLAYER.Name),
		("userId=%d"):format(LOCAL_PLAYER.UserId),
		("loadToken=%s"):format(stringifyLogValue(nextPlayerDataState.loadToken)),
		("elapsed=%.3f"):format(if typeof(nextPlayerDataState.loadElapsedSeconds) == "number" then nextPlayerDataState.loadElapsedSeconds else 0),
		("loadState=%s"):format(stringifyLogValue(nextPlayerDataState.loadState)),
		("hasResolvedInitialLoad=%s"):format(tostring(nextPlayerDataState.hasResolvedInitialLoad == true)),
		("isLoading=%s"):format(tostring(nextPlayerDataState.isLoading == true)),
		("totalCopper=%s"):format(stringifyLogValue(nextCoinState.totalCopper)),
	}
	if nextPlayerDataState.lastFailureReason ~= nil then
		fields[#fields + 1] = ("lastFailureReason=%s"):format(stringifyLogValue(nextPlayerDataState.lastFailureReason))
	end
	warn("[Coins] " .. table.concat(fields, " "))
end

local function applyPlayerDataState(nextPlayerDataStateRaw: any): CoinState
	local fallbackState = coinSlice.getCoinState()
	local nextPlayerDataState = if typeof(nextPlayerDataStateRaw) == "table"
		then (nextPlayerDataStateRaw :: PlayerDataServiceState)
		else nil
	if nextPlayerDataState == nil then
		return fallbackState
	end

	local fallbackCoinsData = if PlayerDataServiceUtils.hasResolvedState(nextPlayerDataState)
		then coinSlice.createDefaultCoinAmounts()
		else fallbackState.amounts
	local coinsData = PlayerDataServiceUtils.getValueAtPath(nextPlayerDataState.data, COINS_DATA_PATH, fallbackCoinsData)
	local nextCoinState = coinSlice.setCoinsData(coinsData, nextPlayerDataState.loadState)
	logCoinsApplied(nextPlayerDataState, nextCoinState)
	return nextCoinState
end

local function syncFromService(): CoinState
	return ServiceSync.syncFromService(PlayerDataServiceClient, coinSlice.getCoinState, applyPlayerDataState)
end

function coinThunks.start(): () -> ()
	if runtime.started then
		return coinThunks.stop
	end

	runtime.started = true
	syncFromService()

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(PlayerDataServiceClient, function(nextState: PlayerDataServiceState)
		applyPlayerDataState(nextState)
	end)
	ServiceSync.requestSync(PlayerDataServiceClient)

	return coinThunks.stop
end

function coinThunks.stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil
	runtime.started = false
end

function coinThunks.syncFromService(): CoinState
	return syncFromService()
end

function coinThunks.applyPlayerDataState(nextPlayerDataStateRaw: any): CoinState
	return applyPlayerDataState(nextPlayerDataStateRaw)
end

return coinThunks
