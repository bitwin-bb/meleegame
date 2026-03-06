--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local PlayerDataServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceUtils)

type PlayerData = PlayerDataServiceUtils.PlayerData
type LoadState = PlayerDataServiceUtils.LoadState
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: PlayerDataServiceState) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: PlayerDataServiceState) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local PlayerDataServiceClient = {}

function PlayerDataServiceClient.init(self: PlayerDataServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("PlayerDataService", self)
	self.janitor = Janitor.new()
	self.state = PlayerDataServiceUtils.createDefaultState()
	self.stateChanged = Signal.new()

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self.networker:fire("requestSync")
end

function PlayerDataServiceClient.applyState(self: PlayerDataServiceClient, dataRaw: any, loadStateRaw: any)
	self.state = PlayerDataServiceUtils.createState(dataRaw, loadStateRaw, self.state)
	self.stateChanged:Fire(PlayerDataServiceUtils.cloneState(self.state))
end

function PlayerDataServiceClient.requestSync(self: PlayerDataServiceClient)
	self.networker:fire("requestSync")
end

function PlayerDataServiceClient.getState(self: PlayerDataServiceClient): PlayerDataServiceState
	return PlayerDataServiceUtils.cloneState(self.state)
end

function PlayerDataServiceClient.getData(self: PlayerDataServiceClient): PlayerData
	return PlayerDataServiceUtils.cloneDeep(self.state.data)
end

function PlayerDataServiceClient.getLoadState(self: PlayerDataServiceClient): LoadState
	return self.state.loadState
end

function PlayerDataServiceClient.isLoaded(self: PlayerDataServiceClient): boolean
	return PlayerDataServiceUtils.isLoadedState(self.state.loadState)
end

function PlayerDataServiceClient.getValue(self: PlayerDataServiceClient, pathRaw: any, fallback: any): any
	return PlayerDataServiceUtils.getValueAtPath(self.state.data, pathRaw, fallback)
end

function PlayerDataServiceClient.getHpData(self: PlayerDataServiceClient, fallback: any): any
	return self:getValue(PlayerDataServiceUtils.getDefaultHpDataPath(), fallback)
end

function PlayerDataServiceClient.getCoinsData(self: PlayerDataServiceClient, fallback: any): any
	return self:getValue(PlayerDataServiceUtils.getDefaultCoinsDataPath(), fallback)
end

function PlayerDataServiceClient.destroy(self: PlayerDataServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end

type PlayerDataServiceClient = typeof(PlayerDataServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	state: PlayerDataServiceState,
	stateChanged: SignalObject,
}

return PlayerDataServiceClient :: PlayerDataServiceClient
