local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ManaServiceUtils = require("ManaServiceUtils")
local PacketPayload = require("PacketPayload")
local ManaServicePackets = require("NetSharedPackets").ManaService

local function sendPacket(methodName: string, ...: any)
	local packet = ManaServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for ManaService`)
		return
	end

	packet.send(PacketPayload.pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = ManaServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for ManaService`)
		return
	end

	packet.listen(function(payload: any)
		local handler = self[methodName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyState")
	bindPacket(self, "requestSync")
end

local PlayerDataServiceClient = require("PlayerDataServiceClient")
local PlayerDataServiceUtils = require("PlayerDataServiceUtils")
local Signal = require("Signal")

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
	bindPackets(self)
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
	sendPacket(ManaServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
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
	janitor: JanitorClass,
	state: ManaServiceState,
	hasReceivedServerState: boolean,
	isStateReady: boolean,
	stateChanged: SignalObject,
	isReady: (self: ManaServiceClient) -> boolean,
}

return ManaServiceClient :: ManaServiceClient
