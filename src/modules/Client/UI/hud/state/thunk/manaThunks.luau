--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local ServiceSync = require(script:FindFirstAncestor("game").Client.UI.core.utils.ServiceSync)
local manaSlice = require(script:FindFirstAncestor("game").Client.UI.hud.state.slice.manaSlice)
local ManaServiceClient = require(script:FindFirstAncestor("game").Client.Services.ManaService.ManaServiceClient)
local ManaServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.ManaService.ManaServiceUtils)

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

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(ManaServiceClient, function(nextState: ManaServiceState)
		applyState(nextState)
		manaSlice.setManaReady(true)
	end)
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
