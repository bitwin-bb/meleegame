--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local ServiceSync = require(script:FindFirstAncestor("game").Client.UI.core.utils.ServiceSync)
local hpSlice = require(script:FindFirstAncestor("game").Client.UI.hud.state.slice.hpSlice)
local HpServiceClient = require(script:FindFirstAncestor("game").Client.Services.HpService.HpServiceClient)
local HpServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.HpService.HpServiceUtils)

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

	return hpThunks.Stop
end

function hpThunks.Stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
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

hpThunks.start = hpThunks.Start
hpThunks.stop = hpThunks.Stop
hpThunks.syncFromService = hpThunks.SyncFromService
hpThunks.applyState = hpThunks.ApplyState
hpThunks.getBeatHeartIndex = hpThunks.GetBeatHeartIndex

return hpThunks
