local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local BuffConstants = require("BuffConstants")
local BuffServiceClient = require("BuffServiceClient")
local BuffSlice = require("BuffSlice")
local Maid = require("Maid")

type BuffState = BuffSlice.BuffState

local BuffThunks = {}

local runtime = {
	started = false,
	maid = nil :: any?,
}

local function decodeReplicatedRecords(valueRaw: any): { any }
	if typeof(valueRaw) ~= "string" or valueRaw == "" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(valueRaw)
	end)
	if ok and typeof(decoded) == "table" then
		return decoded :: { any }
	end

	return {}
end

local function readPlayerSnapshot(): { any }
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return {}
	end

	return decodeReplicatedRecords(localPlayer:GetAttribute(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE))
end

local function readServiceSnapshot(): { any }
	local ok, records = pcall(function()
		return BuffServiceClient:GetActive()
	end)
	if ok and typeof(records) == "table" then
		return records :: { any }
	end

	local snapshotOk, snapshot = pcall(function()
		return BuffServiceClient:ReadReplicatedSnapshot()
	end)
	if snapshotOk and typeof(snapshot) == "table" and #snapshot > 0 then
		return snapshot :: { any }
	end

	return readPlayerSnapshot()
end

local function applyRecords(recordsRaw: any, sourceRaw: any?): BuffState
	local nextState = BuffSlice.setBuffRecords(recordsRaw, sourceRaw)
	BuffSlice.setBuffReady(true)
	return nextState
end

local function syncFromService(): BuffState
	return applyRecords(readServiceSnapshot(), "Service")
end

function BuffThunks.Start(): () -> ()
	if runtime.started then
		return BuffThunks.Stop
	end

	runtime.started = true
	runtime.maid = Maid.new()
	syncFromService()

	local activeChanged = (BuffServiceClient :: any).ActiveChanged
	if typeof(activeChanged) == "table" and typeof(activeChanged.Connect) == "function" then
		runtime.maid:GiveTask(activeChanged:Connect(function(nextRecords: { any })
			applyRecords(nextRecords, "Service")
		end))
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer ~= nil then
		runtime.maid:GiveTask(
			localPlayer:GetAttributeChangedSignal(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE):Connect(function()
				applyRecords(readPlayerSnapshot(), "Attribute")
			end)
		)
	end

	return BuffThunks.Stop
end

function BuffThunks.Stop()
	if runtime.maid ~= nil then
		runtime.maid:Destroy()
	end

	runtime.maid = nil
	runtime.started = false
	BuffSlice.setBuffReady(false)
end

function BuffThunks.SyncFromService(): BuffState
	return syncFromService()
end

function BuffThunks.ApplySnapshot(recordsRaw: any): BuffState
	return applyRecords(recordsRaw, "Snapshot")
end

function BuffThunks.ApplyState(stateRaw: any): BuffState
	local nextState = BuffSlice.setBuffState(stateRaw)
	BuffSlice.setBuffReady(true)
	return nextState
end

BuffThunks.start = BuffThunks.Start
BuffThunks.stop = BuffThunks.Stop
BuffThunks.syncFromService = BuffThunks.SyncFromService
BuffThunks.applySnapshot = BuffThunks.ApplySnapshot
BuffThunks.applyState = BuffThunks.ApplyState

return BuffThunks
