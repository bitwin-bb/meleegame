--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local ManaServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.ManaService.ManaServiceUtils)
local PlayerDataServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerDataService.PlayerDataServiceClient)
local PlayerDataServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerDataService.PlayerDataServiceUtils)

type ManaServiceState = ManaServiceUtils.ManaServiceState
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: ManaServiceState) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: ManaServiceState) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local ManaServiceClient = {}

local function applyPersistedManaSnapshotFromPlayerData(self: ManaServiceClient): boolean
	if PlayerDataServiceClient.isLoaded == nil or not PlayerDataServiceClient:isLoaded() then
		return false
	end

	local persistedManaRaw = PlayerDataServiceClient:getValue(ManaServiceUtils.getDefaultDataPath(), nil)
	if persistedManaRaw == nil then
		return false
	end

	local nextState = ManaServiceUtils.createStateFromData(persistedManaRaw, self.state, true)
	nextState.delta = 0
	nextState.lastSpend = 0
	nextState.lastGain = 0
	self.state = nextState
	self.isStateReady = true
	self.stateChanged:Fire(ManaServiceUtils.cloneState(nextState))
	return true
end

function ManaServiceClient.Init(self: ManaServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("ManaService", self)
	self.janitor = Janitor.new()
	self.state = ManaServiceUtils.createDefaultState()
	self.isStateReady = false
	self.stateChanged = Signal.new()
	self.hasReceivedServerState = false

	applyPersistedManaSnapshotFromPlayerData(self)

	if PlayerDataServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(PlayerDataServiceClient.stateChanged:Connect(function(nextState: PlayerDataServiceState)
			if PlayerDataServiceUtils.isLoadedState(nextState.loadState) then
				if not self.hasReceivedServerState then
					applyPersistedManaSnapshotFromPlayerData(self)
				end
				self:requestSync()
			end
		end))
	end

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:requestSync()
end

function ManaServiceClient.ApplyState(self: ManaServiceClient, stateRaw: any)
	self.state = ManaServiceUtils.sanitizeState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.isStateReady = self.state.isLoaded == true or self.hasReceivedServerState
	self.stateChanged:Fire(ManaServiceUtils.cloneState(self.state))
end

function ManaServiceClient.RequestSync(self: ManaServiceClient)
	self.networker:fire(ManaServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function ManaServiceClient.GetState(self: ManaServiceClient): ManaServiceState
	return ManaServiceUtils.cloneState(self.state)
end

function ManaServiceClient.IsReady(self: ManaServiceClient): boolean
	return self.isStateReady == true
end

function ManaServiceClient.Destroy(self: ManaServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

ManaServiceClient.init = ManaServiceClient.Init
ManaServiceClient.applyState = ManaServiceClient.ApplyState
ManaServiceClient.requestSync = ManaServiceClient.RequestSync
ManaServiceClient.getState = ManaServiceClient.GetState
ManaServiceClient.isReady = ManaServiceClient.IsReady
ManaServiceClient.destroy = ManaServiceClient.Destroy

export type ManaServiceClient = typeof(ManaServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	state: ManaServiceState,
	hasReceivedServerState: boolean,
	isStateReady: boolean,
	stateChanged: SignalObject,
	isReady: (self: ManaServiceClient) -> boolean,
}

return ManaServiceClient :: ManaServiceClient
