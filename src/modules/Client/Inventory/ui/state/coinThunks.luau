local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local ConnectionUtils = require("ConnectionUtils")
local PlayerDataServiceClient = require("PlayerDataServiceClient")
local PlayerDataServiceUtils = require("PlayerDataServiceUtils")
local ServiceSync = require("ServiceSync")
local coinSlice = require("coinSlice")

type CoinState = coinSlice.CoinState
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

local coinThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local COINS_DATA_PATH = PlayerDataServiceUtils.GetDefaultCoinsDataPath()
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
		("elapsed=%.3f"):format(
			if typeof(nextPlayerDataState.loadElapsedSeconds) == "number"
				then nextPlayerDataState.loadElapsedSeconds
				else 0
		),
		("loadState=%s"):format(stringifyLogValue(nextPlayerDataState.loadState)),
		("hasInitialLoad=%s"):format(tostring(nextPlayerDataState.hasInitialLoad == true)),
		("isLoading=%s"):format(tostring(nextPlayerDataState.isLoading == true)),
		("totalCopper=%s"):format(stringifyLogValue(nextCoinState.totalCopper)),
	}
	if nextPlayerDataState.lastFailureReason ~= nil then
		fields[#fields + 1] = ("lastFailureReason=%s"):format(stringifyLogValue(nextPlayerDataState.lastFailureReason))
	end
end

local function applyPlayerDataState(nextPlayerDataStateRaw: any): CoinState
	local fallbackState = coinSlice.getCoinState()
	local nextPlayerDataState = if typeof(nextPlayerDataStateRaw) == "table"
		then nextPlayerDataStateRaw :: PlayerDataServiceState
		else nil
	if nextPlayerDataState == nil then
		return fallbackState
	end

	local fallbackCoinsData = if PlayerDataServiceUtils.HasGotState(nextPlayerDataState)
		then coinSlice.createDefaultCoinAmounts()
		else fallbackState.amounts
	local coinsData =
		PlayerDataServiceUtils.GetValueAtPath(nextPlayerDataState.data, COINS_DATA_PATH, fallbackCoinsData)
	local nextCoinState = coinSlice.setCoinsData(coinsData, nextPlayerDataState.loadState)
	logCoinsApplied(nextPlayerDataState, nextCoinState)
	return nextCoinState
end

local function syncFromService(): CoinState
	return ServiceSync.syncFromService(PlayerDataServiceClient, coinSlice.getCoinState, applyPlayerDataState)
end

function coinThunks.Start(): () -> ()
	if runtime.started then
		return coinThunks.Stop
	end

	runtime.started = true
	syncFromService()

	runtime.stateChangedConnection = ServiceSync.ConnectStateChanged(
		PlayerDataServiceClient,
		function(nextState: PlayerDataServiceState)
			applyPlayerDataState(nextState)
		end
	)
	ServiceSync.RequestSync(PlayerDataServiceClient)

	return coinThunks.Stop
end

function coinThunks.Stop()
	ConnectionUtils.Disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil
	runtime.started = false
end

function coinThunks.SyncFromService(): CoinState
	return syncFromService()
end

function coinThunks.ApplyPlayerDataState(nextPlayerDataStateRaw: any): CoinState
	return applyPlayerDataState(nextPlayerDataStateRaw)
end
return coinThunks
