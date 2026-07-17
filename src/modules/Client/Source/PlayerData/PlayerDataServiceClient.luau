local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local ServiceBag = require("ServiceBag")
local PlayerDataServicePackets = require("NetPacketsShared").PlayerDataService

local function sendPacket(methodName: string, ...: any)
	local packet = PlayerDataServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerDataService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = PlayerDataServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerDataService`)
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

local PlayerDataServiceUtils = require("PlayerDataServiceUtils")
local Signal = require("Signal")

type PlayerData = PlayerDataServiceUtils.PlayerData
type LoadState = PlayerDataServiceUtils.LoadState
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

type SignalObject = Signal.Signal<...any>

type JanitorClass = any

local PlayerDataServiceClient = {}
PlayerDataServiceClient.ServiceName = "PlayerDataServiceClient"

function PlayerDataServiceClient.Init(self: PlayerDataServiceClient, serviceBag: ServiceBag.ServiceBag?)
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = PlayerDataServiceUtils.CreateDefaultState()
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
	self.state = PlayerDataServiceUtils.CreateState(dataRaw, loadStateRaw, self.state, metadataRaw)
	self.stateChanged:Fire(PlayerDataServiceUtils.CloneState(self.state))
end

function PlayerDataServiceClient.RequestSync(_self: PlayerDataServiceClient)
	sendPacket("requestSync")
end

function PlayerDataServiceClient.GetState(self: PlayerDataServiceClient): PlayerDataServiceState
	return PlayerDataServiceUtils.CloneState(self.state)
end

function PlayerDataServiceClient.GetData(self: PlayerDataServiceClient): PlayerData
	return PlayerDataServiceUtils.CloneDeep(self.state.data)
end

function PlayerDataServiceClient.GetLoadState(self: PlayerDataServiceClient): LoadState
	return self.state.loadState
end

function PlayerDataServiceClient.IsLoaded(self: PlayerDataServiceClient): boolean
	return PlayerDataServiceUtils.IsLoadedState(self.state.loadState)
end

function PlayerDataServiceClient.IsGot(self: PlayerDataServiceClient): boolean
	return PlayerDataServiceUtils.HasGotState(self.state)
end

function PlayerDataServiceClient.GetValue(self: PlayerDataServiceClient, pathRaw: any, fallback: any): any
	return PlayerDataServiceUtils.GetValueAtPath(self.state.data, pathRaw, fallback)
end

function PlayerDataServiceClient.GetHpData(self: PlayerDataServiceClient, fallback: any): any
	return self:GetValue(PlayerDataServiceUtils.GetDefaultHpDataPath(), fallback)
end

function PlayerDataServiceClient.GetCoinsData(self: PlayerDataServiceClient, fallback: any): any
	return self:GetValue(PlayerDataServiceUtils.GetDefaultCoinsDataPath(), fallback)
end

function PlayerDataServiceClient.Destroy(self: PlayerDataServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
	self._serviceBag = nil
end
type PlayerDataServiceClient = typeof(PlayerDataServiceClient) & {
	_serviceBag: ServiceBag.ServiceBag?,
	localPlayer: Player,
	janitor: JanitorClass,
	state: PlayerDataServiceState,
	stateChanged: SignalObject,
	isGot: (self: PlayerDataServiceClient) -> boolean,
}

return PlayerDataServiceClient :: PlayerDataServiceClient
