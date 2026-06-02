--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local ConnectionUtils = require(gameRoot.Client.UI.core.utils.ConnectionUtils)
local ManaServiceClient = require(gameRoot.Shared.Features.mana.ManaServiceClient)
local ManaServiceUtils = require(gameRoot.Shared.Features.mana.ManaServiceUtils)
local ServiceSync = require(gameRoot.Client.UI.core.utils.ServiceSync)
local manaSlice = require(gameRoot.Shared.Features.mana.ui.hud.state.slice.manaSlice)

type ManaServiceState = ManaServiceUtils.ManaServiceState

local manaThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local function applyState(nextStateRaw: any): ManaServiceState
	return manaSlice.setManaState(nextStateRaw)
end

local function syncFromService(): ManaServiceState
	return ServiceSync.syncFromService(ManaServiceClient, manaSlice.getManaState, applyState)
end

function manaThunks.Start(): () -> ()
	if runtime.started then
		return manaThunks.Stop
	end

	runtime.started = true
	local isReady = ServiceSync.readReady(ManaServiceClient, false)
	manaSlice.setManaReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(
		ManaServiceClient,
		function(nextState: ManaServiceState)
			applyState(nextState)
			manaSlice.setManaReady(true)
		end
	)
	ServiceSync.requestSync(ManaServiceClient)

	return manaThunks.Stop
end

function manaThunks.Stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	manaSlice.setManaReady(false)
end

function manaThunks.SyncFromService(): ManaServiceState
	return syncFromService()
end

function manaThunks.ApplyState(nextStateRaw: any): ManaServiceState
	return applyState(nextStateRaw)
end

manaThunks.start = manaThunks.Start
manaThunks.stop = manaThunks.Stop
manaThunks.syncFromService = manaThunks.SyncFromService
manaThunks.applyState = manaThunks.ApplyState

return manaThunks
