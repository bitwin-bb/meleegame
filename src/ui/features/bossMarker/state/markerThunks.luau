--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local markerSlice = require(ReplicatedStorage.UI.features.bossMarker.state.markerSlice)
local BossServiceClient = require(ReplicatedStorage.Shared.Services.BossService.BossServiceClient)
local BossServiceUtils = require(ReplicatedStorage.Shared.Services.BossService.BossServiceUtils)

type MarkerState = BossServiceUtils.BossServiceState

local markerThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local function applyState(nextStateRaw: any): MarkerState
	return markerSlice.setMarkerState(nextStateRaw)
end

local function syncFromService(): MarkerState
	return ServiceSync.syncFromService(BossServiceClient, markerSlice.getMarkerState, applyState)
end

function markerThunks.start(): () -> ()
	if runtime.started then
		return markerThunks.stop
	end

	runtime.started = true
	local isReady = ServiceSync.readReady(BossServiceClient, false)
	markerSlice.setMarkerReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(BossServiceClient, function(nextState: MarkerState)
		applyState(nextState)
		markerSlice.setMarkerReady(true)
	end)
	ServiceSync.requestSync(BossServiceClient)

	return markerThunks.stop
end

function markerThunks.stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	markerSlice.setMarkerReady(false)
end

function markerThunks.syncFromService(): MarkerState
	return syncFromService()
end

function markerThunks.applyState(nextStateRaw: any): MarkerState
	return applyState(nextStateRaw)
end

return markerThunks
