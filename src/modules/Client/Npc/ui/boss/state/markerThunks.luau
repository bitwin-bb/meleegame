
local require = require(script.Parent.loader).load(script)

local BossServiceClient = require("BossServiceClient")
local BossServiceUtils = require("BossServiceUtils")
local ConnectionUtils = require("ConnectionUtils")
local ServiceSync = require("ServiceSync")
local markerSlice = require("markerSlice")

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

function markerThunks.Start(): () -> ()
	if runtime.started then
		return markerThunks.Stop
	end

	runtime.started = true
	local isReady = ServiceSync.ReadReady(BossServiceClient, false)
	markerSlice.setMarkerReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.ConnectStateChanged(BossServiceClient, function(nextState: MarkerState)
		applyState(nextState)
		markerSlice.setMarkerReady(true)
	end)
	ServiceSync.RequestSync(BossServiceClient)

	return markerThunks.Stop
end

function markerThunks.Stop()
	ConnectionUtils.Disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	markerSlice.setMarkerReady(false)
end

function markerThunks.SyncFromService(): MarkerState
	return syncFromService()
end

function markerThunks.ApplyState(nextStateRaw: any): MarkerState
	return applyState(nextStateRaw)
end
return markerThunks
