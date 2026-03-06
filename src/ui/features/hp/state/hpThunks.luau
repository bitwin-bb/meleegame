--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local hpSlice = require(ReplicatedStorage.UI.features.hp.state.hpSlice)
local HpServiceClient = require(ReplicatedStorage.Shared.Services.HpService.HpServiceClient)
local HpServiceUtils = require(ReplicatedStorage.Shared.Services.HpService.HpServiceUtils)

type HpServiceState = HpServiceUtils.HpServiceState

local hpThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local function applyState(nextStateRaw: any): HpServiceState
	return hpSlice.setHpState(nextStateRaw)
end

local function syncFromService(): HpServiceState
	return ServiceSync.syncFromService(HpServiceClient, hpSlice.getHpState, applyState)
end

function hpThunks.start(): () -> ()
	if runtime.started then
		return hpThunks.stop
	end

	runtime.started = true
	local isReady = ServiceSync.readReady(HpServiceClient, false)
	hpSlice.setHpReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(HpServiceClient, function(nextState: HpServiceState)
		applyState(nextState)
		hpSlice.setHpReady(true)
	end)
	ServiceSync.requestSync(HpServiceClient)

	return hpThunks.stop
end

function hpThunks.stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	hpSlice.setHpReady(false)
end

function hpThunks.syncFromService(): HpServiceState
	return syncFromService()
end

function hpThunks.applyState(nextStateRaw: any): HpServiceState
	return applyState(nextStateRaw)
end

function hpThunks.getBeatHeartIndex(): number?
	return hpSlice.beatHeartIndexAtom()
end

return hpThunks
