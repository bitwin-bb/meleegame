--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local breathSlice = require(ReplicatedStorage.UI.features.breath.state.breathSlice)
local BreathServiceClient = require(ReplicatedStorage.Shared.Services.BreathService.BreathServiceClient)
local BreathServiceUtils = require(ReplicatedStorage.Shared.Services.BreathService.BreathServiceUtils)

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

function breathThunks.start(): () -> ()
	if runtime.started then
		return breathThunks.stop
	end

	runtime.started = true
	local isReady = ServiceSync.readReady(BreathServiceClient, false)
	breathSlice.setBreathReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(BreathServiceClient, function(nextState: BreathServiceState)
		applyState(nextState)
		breathSlice.setBreathReady(true)
	end)
	ServiceSync.requestSync(BreathServiceClient)

	return breathThunks.stop
end

function breathThunks.stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	breathSlice.setBreathReady(false)
end

function breathThunks.syncFromService(): BreathServiceState
	return syncFromService()
end

function breathThunks.applyState(nextStateRaw: any): BreathServiceState
	return applyState(nextStateRaw)
end

return breathThunks
