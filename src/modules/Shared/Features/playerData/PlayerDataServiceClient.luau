--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require(gameRoot.Shared.NetShared.PacketPayload)
local PlayerDataServicePackets = (require :: any)(gameRoot.Shared.NetShared.Packets).PlayerDataService

local function sendPacket(methodName: string, ...: any)
	local packet = PlayerDataServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerDataService`)
		return
	end

	packet.send(PacketPayload.pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = PlayerDataServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerDataService`)
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

local PlayerDataServiceUtils = require(gameRoot.Shared.Features.playerData.PlayerDataServiceUtils)
local Signal = require(quentyPackages.signal.Shared.Signal)

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

function PlayerDataServiceClient.Init(self: PlayerDataServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = PlayerDataServiceUtils.createDefaultState()
	self.stateChanged = Signal.new()

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	sendPacket("requestSync")
end

function PlayerDataServiceClient.ApplyState(
	self: PlayerDataServiceClient,
	dataRaw: any,
	loadStateRaw: any,
	metadataRaw: any?
)
	self.state = PlayerDataServiceUtils.createState(dataRaw, loadStateRaw, self.state, metadataRaw)
	self.stateChanged:Fire(PlayerDataServiceUtils.cloneState(self.state))
end

function PlayerDataServiceClient.RequestSync(self: PlayerDataServiceClient)
	sendPacket("requestSync")
end

function PlayerDataServiceClient.GetState(self: PlayerDataServiceClient): PlayerDataServiceState
	return PlayerDataServiceUtils.cloneState(self.state)
end

function PlayerDataServiceClient.GetData(self: PlayerDataServiceClient): PlayerData
	return PlayerDataServiceUtils.cloneDeep(self.state.data)
end

function PlayerDataServiceClient.GetLoadState(self: PlayerDataServiceClient): LoadState
	return self.state.loadState
end

function PlayerDataServiceClient.IsLoaded(self: PlayerDataServiceClient): boolean
	return PlayerDataServiceUtils.isLoadedState(self.state.loadState)
end

function PlayerDataServiceClient.IsResolved(self: PlayerDataServiceClient): boolean
	return PlayerDataServiceUtils.hasResolvedState(self.state)
end

function PlayerDataServiceClient.GetValue(self: PlayerDataServiceClient, pathRaw: any, fallback: any): any
	return PlayerDataServiceUtils.getValueAtPath(self.state.data, pathRaw, fallback)
end

function PlayerDataServiceClient.GetHpData(self: PlayerDataServiceClient, fallback: any): any
	return self:getValue(PlayerDataServiceUtils.getDefaultHpDataPath(), fallback)
end

function PlayerDataServiceClient.GetCoinsData(self: PlayerDataServiceClient, fallback: any): any
	return self:getValue(PlayerDataServiceUtils.getDefaultCoinsDataPath(), fallback)
end

function PlayerDataServiceClient.Destroy(self: PlayerDataServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end

PlayerDataServiceClient.init = PlayerDataServiceClient.Init
PlayerDataServiceClient.applyState = PlayerDataServiceClient.ApplyState
PlayerDataServiceClient.requestSync = PlayerDataServiceClient.RequestSync
PlayerDataServiceClient.getState = PlayerDataServiceClient.GetState
PlayerDataServiceClient.getData = PlayerDataServiceClient.GetData
PlayerDataServiceClient.getLoadState = PlayerDataServiceClient.GetLoadState
PlayerDataServiceClient.isLoaded = PlayerDataServiceClient.IsLoaded
PlayerDataServiceClient.isResolved = PlayerDataServiceClient.IsResolved
PlayerDataServiceClient.getValue = PlayerDataServiceClient.GetValue
PlayerDataServiceClient.getHpData = PlayerDataServiceClient.GetHpData
PlayerDataServiceClient.getCoinsData = PlayerDataServiceClient.GetCoinsData
PlayerDataServiceClient.destroy = PlayerDataServiceClient.Destroy

type PlayerDataServiceClient = typeof(PlayerDataServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass,
	state: PlayerDataServiceState,
	stateChanged: SignalObject,
	isResolved: (self: PlayerDataServiceClient) -> boolean,
}

return PlayerDataServiceClient :: PlayerDataServiceClient
