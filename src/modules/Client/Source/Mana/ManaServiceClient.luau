local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local ManaServiceUtils = require("ManaServiceUtils")
local PacketPayload = require("PacketPayload")
local ManaServicePackets = require("NetPacketsShared").ManaService

local function sendPacket(methodName: string, ...: any)
	local packet = ManaServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for ManaService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = ManaServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for ManaService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
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

type SignalObject = Signal.Signal<...any>

type JanitorClass = any

local ManaServiceClient = {}

local function applyPersistedManaSnapshotFromPlayerData(self: ManaServiceClient): boolean
	if PlayerDataServiceClient.IsLoaded == nil or not PlayerDataServiceClient:IsLoaded() then
		return false
	end

	local persistedManaRaw = PlayerDataServiceClient:GetValue(ManaServiceUtils.GetDefaultDataPath(), nil)
	if persistedManaRaw == nil then
		return false
	end

	local nextState = ManaServiceUtils.CreateStateFromData(persistedManaRaw, self.state, true)
	nextState.delta = 0
	nextState.lastSpend = 0
	nextState.lastGain = 0
	self.state = nextState
	self.isStateReady = true
	self.stateChanged:Fire(ManaServiceUtils.CloneState(nextState))
	return true
end

function ManaServiceClient.Init(self: ManaServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = ManaServiceUtils.CreateDefaultState()
	self.isStateReady = false
	self.stateChanged = Signal.new()
	self.hasReceivedServerState = false

	applyPersistedManaSnapshotFromPlayerData(self)

	if PlayerDataServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(PlayerDataServiceClient.stateChanged:Connect(function(nextState: PlayerDataServiceState)
			if PlayerDataServiceUtils.IsLoadedState(nextState.loadState) then
				if not self.hasReceivedServerState then
					applyPersistedManaSnapshotFromPlayerData(self)
				end
				self:RequestSync()
			end
		end))
	end

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:RequestSync()
end

function ManaServiceClient.ApplyState(self: ManaServiceClient, stateRaw: any)
	self.state = ManaServiceUtils.CoerceState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.isStateReady = self.state.isLoaded == true or self.hasReceivedServerState
	self.stateChanged:Fire(ManaServiceUtils.CloneState(self.state))
end

function ManaServiceClient.RequestSync(self: ManaServiceClient)
	sendPacket(ManaServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function ManaServiceClient.GetState(self: ManaServiceClient): ManaServiceState
	return ManaServiceUtils.CloneState(self.state)
end

function ManaServiceClient.IsReady(self: ManaServiceClient): boolean
	return self.isStateReady == true
end

function ManaServiceClient.Destroy(self: ManaServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end
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
