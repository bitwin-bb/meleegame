--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local ServiceSync = require(script:FindFirstAncestor("game").Client.UI.core.utils.ServiceSync)
local breathSlice = require(script:FindFirstAncestor("game").Client.UI.features.breath.state.breathSlice)
local BreathServiceClient = require(script:FindFirstAncestor("game").Client.Services.BreathServiceClient)
local BreathServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BreathServiceUtils)

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

	return breathThunks.Stop
end

function breathThunks.Stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
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

breathThunks.start = breathThunks.Start
breathThunks.stop = breathThunks.Stop
breathThunks.syncFromService = breathThunks.SyncFromService
breathThunks.applyState = breathThunks.ApplyState

return breathThunks
