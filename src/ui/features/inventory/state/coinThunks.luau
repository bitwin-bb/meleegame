--!strict
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

local function applyPlayerDataState(nextPlayerDataStateRaw: any): CoinState
	local fallbackState = coinSlice.getCoinState()
	local nextPlayerDataState = if typeof(nextPlayerDataStateRaw) == "table"
		then (nextPlayerDataStateRaw :: PlayerDataServiceState)
		else nil
	if nextPlayerDataState == nil then
		return fallbackState
	end

	local coinsData =
		PlayerDataServiceUtils.getValueAtPath(nextPlayerDataState.data, COINS_DATA_PATH, fallbackState.amounts)
	return coinSlice.setCoinsData(coinsData, nextPlayerDataState.loadState)
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
