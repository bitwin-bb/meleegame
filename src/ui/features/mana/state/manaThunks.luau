--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local manaSlice = require(ReplicatedStorage.UI.features.mana.state.manaSlice)
local ManaServiceClient = require(ReplicatedStorage.Shared.Services.ManaService.ManaServiceClient)
local ManaServiceUtils = require(ReplicatedStorage.Shared.Services.ManaService.ManaServiceUtils)

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

function manaThunks.start(): () -> ()
	if runtime.started then
		return manaThunks.stop
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

	return manaThunks.stop
end

function manaThunks.stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil

	runtime.started = false
	manaSlice.setManaReady(false)
end

function manaThunks.syncFromService(): ManaServiceState
	return syncFromService()
end

function manaThunks.applyState(nextStateRaw: any): ManaServiceState
	return applyState(nextStateRaw)
end

return manaThunks
