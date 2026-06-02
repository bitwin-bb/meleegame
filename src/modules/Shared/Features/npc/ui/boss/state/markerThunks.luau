--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local BossServiceClient = require(gameRoot.Shared.Features.npc.BossServiceClient)
local BossServiceUtils = require(gameRoot.Shared.Features.npc.BossServiceUtils)
local ConnectionUtils = require(gameRoot.Client.UI.core.utils.ConnectionUtils)
local ServiceSync = require(gameRoot.Client.UI.core.utils.ServiceSync)
local markerSlice = require(gameRoot.Shared.Features.npc.ui.boss.state.markerSlice)

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

	return markerThunks.Stop
end

function markerThunks.Stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
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

markerThunks.start = markerThunks.Start
markerThunks.stop = markerThunks.Stop
markerThunks.syncFromService = markerThunks.SyncFromService
markerThunks.applyState = markerThunks.ApplyState

return markerThunks
