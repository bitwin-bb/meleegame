
local require = require(script.Parent.loader).load(script)

local BreathServiceClient = require("BreathServiceClient")
local BreathServiceUtils = require("BreathServiceUtils")
local ConnectionUtils = require("ConnectionUtils")
local ServiceSync = require("ServiceSync")
local breathSlice = require("BreathSlice")

type BreathServiceState = BreathServiceUtils.BreathServiceState

local breathThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local function applyState(nextStateRaw: any): BreathServiceState
	return breathSlice.setBreathState(nextStateRaw)
end

local function syncFromService(): BreathServiceState
	return ServiceSync.syncFromService(BreathServiceClient, breathSlice.getBreathState, applyState)
end

function breathThunks.Start(): () -> ()
	if runtime.started then
		return breathThunks.Stop
	end

	runtime.started = true
	local isReady = ServiceSync.ReadReady(BreathServiceClient, false)
	breathSlice.setBreathReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.ConnectStateChanged(
		BreathServiceClient,
		function(nextState: BreathServiceState)
			applyState(nextState)
			breathSlice.setBreathReady(true)
		end
	)
	ServiceSync.RequestSync(BreathServiceClient)

	return breathThunks.Stop
end

function breathThunks.Stop()
	ConnectionUtils.Disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	breathSlice.setBreathReady(false)
end

function breathThunks.SyncFromService(): BreathServiceState
	return syncFromService()
end

function breathThunks.ApplyState(nextStateRaw: any): BreathServiceState
	return applyState(nextStateRaw)
end
return breathThunks
