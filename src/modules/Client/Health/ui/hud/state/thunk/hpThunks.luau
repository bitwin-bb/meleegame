
local require = require(script.Parent.loader).load(script)

local ConnectionUtils = require("ConnectionUtils")
local HpServiceClient = require("HpServiceClient")
local HpServiceUtils = require("HpServiceUtils")
local ServiceSync = require("ServiceSync")
local hpSlice = require("hpSlice")

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

function hpThunks.Start(): () -> ()
	if runtime.started then
		return hpThunks.Stop
	end

	runtime.started = true
	local isReady = ServiceSync.ReadReady(HpServiceClient, false)
	hpSlice.setHpReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.ConnectStateChanged(
		HpServiceClient,
		function(nextState: HpServiceState)
			applyState(nextState)
			hpSlice.setHpReady(true)
		end
	)
	ServiceSync.RequestSync(HpServiceClient)

	return hpThunks.Stop
end

function hpThunks.Stop()
	ConnectionUtils.Disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	hpSlice.setHpReady(false)
end

function hpThunks.SyncFromService(): HpServiceState
	return syncFromService()
end

function hpThunks.ApplyState(nextStateRaw: any): HpServiceState
	return applyState(nextStateRaw)
end

function hpThunks.GetBeatHeartIndex(): number?
	return hpSlice.beatHeartIndexAtom()
end
return hpThunks
