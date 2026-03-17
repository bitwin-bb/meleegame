--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local devConsoleSlice = require(ReplicatedStorage.UI.features.devConsole.state.devConsoleSlice)
local DevPromptServiceClient = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceClient)
local DevPromptServiceUtils = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceUtils)

type DevPromptState = DevPromptServiceUtils.DevPromptState
type DevConsoleState = devConsoleSlice.DevConsoleState

local devConsoleThunks = {}

local runtime = {
	started = false,
	stateChangedConnection = nil :: RBXScriptConnection?,
}

local function applyState(nextStateRaw: any): DevConsoleState
	return devConsoleSlice.applyServiceState(nextStateRaw)
end

local function syncFromService(): DevConsoleState
	return ServiceSync.syncFromService(DevPromptServiceClient, devConsoleSlice.getDevConsoleState, function(nextState: DevPromptState)
		return applyState(nextState)
	end)
end

function devConsoleThunks.start(): () -> ()
	if runtime.started then
		return devConsoleThunks.stop
	end

	runtime.started = true
	devConsoleSlice.setStarted(true)
	local isReady = ServiceSync.readReady(DevPromptServiceClient, false)
	devConsoleSlice.setReady(isReady)
	if isReady then
		syncFromService()
	end

	runtime.stateChangedConnection = ServiceSync.connectStateChanged(DevPromptServiceClient, function(nextState: DevPromptState)
		applyState(nextState)
		devConsoleSlice.setReady(true)
	end)
	ServiceSync.requestSync(DevPromptServiceClient)

	return devConsoleThunks.stop
end

function devConsoleThunks.stop()
	ConnectionUtils.disconnect(runtime.stateChangedConnection)
	runtime.stateChangedConnection = nil
	runtime.started = false
	devConsoleSlice.setStarted(false)
	devConsoleSlice.setReady(false)
end

function devConsoleThunks.syncFromService(): DevConsoleState
	return syncFromService()
end

function devConsoleThunks.applyState(nextStateRaw: any): DevConsoleState
	return applyState(nextStateRaw)
end

function devConsoleThunks.toggleVisible(): DevConsoleState
	DevPromptServiceClient:toggle()
	return syncFromService()
end

function devConsoleThunks.setVisible(visibleRaw: any): DevConsoleState
	DevPromptServiceClient:setOpen(visibleRaw == true)
	return syncFromService()
end

function devConsoleThunks.close(): DevConsoleState
	return devConsoleThunks.setVisible(false)
end

function devConsoleThunks.setPromptText(promptTextRaw: any): DevConsoleState
	return devConsoleSlice.setPromptText(promptTextRaw)
end

function devConsoleThunks.clearPromptText(): DevConsoleState
	return devConsoleSlice.clearPromptText()
end

function devConsoleThunks.cycleSuggestion(deltaRaw: any): DevConsoleState
	return devConsoleSlice.cycleSuggestion(deltaRaw)
end

function devConsoleThunks.cycleHistory(deltaRaw: any): DevConsoleState
	return devConsoleSlice.cycleHistory(deltaRaw)
end

function devConsoleThunks.stepSelection(deltaRaw: any): DevConsoleState
	local currentState = devConsoleSlice.getDevConsoleState()
	local promptText = DevPromptServiceUtils.trim(currentState.promptText)
	if promptText ~= "" and #currentState.suggestions > 0 then
		return devConsoleSlice.cycleSuggestion(deltaRaw)
	end
	return devConsoleSlice.cycleHistory(deltaRaw)
end

function devConsoleThunks.applySelectedSuggestion(indexRaw: any?): DevConsoleState
	return devConsoleSlice.applySelectedSuggestion(indexRaw)
end

function devConsoleThunks.clearLocalEntries(): DevConsoleState
	DevPromptServiceClient:clearEntries()
	return syncFromService()
end

function devConsoleThunks.submitPrompt(): boolean
	local promptText = devConsoleSlice.getPromptText()
	if DevPromptServiceUtils.trim(promptText) == "" then
		return false
	end
	local submitted = DevPromptServiceClient:submitCommand(promptText)
	if not submitted then
		return false
	end
	devConsoleSlice.pushHistory(promptText)
	devConsoleSlice.clearPromptText()
	return true
end

function devConsoleThunks.getState(): DevConsoleState
	return devConsoleSlice.getDevConsoleState()
end

return devConsoleThunks
