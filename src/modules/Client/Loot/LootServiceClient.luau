local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local LootServiceUtils = require("LootServiceUtils")
local PacketPayload = require("PacketPayload")
local LootServicePackets = require("NetSharedPackets").LootService

local function sendPacket(methodName: string, ...: any)
	local packet = LootServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for LootService`)
		return
	end

	packet.send(PacketPayload.pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = LootServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for LootService`)
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
	bindPacket(self, "requestDropFromSlot")
	bindPacket(self, "requestDropSelectedSlot")
	bindPacket(self, "requestSync")
end

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local LootServiceClient = {}

function LootServiceClient.ApplyState(self: LootServiceClient, _payloadRaw: any) end

function LootServiceClient.RequestSync(self: LootServiceClient)
	sendPacket(LootServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function LootServiceClient.RequestDropFromSlot(
	self: LootServiceClient,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	sendPacket(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SLOT, slotIndexRaw, amountRaw, throwDirectionRaw)
end

function LootServiceClient.RequestDropSelectedSlot(self: LootServiceClient, amountRaw: any, throwDirectionRaw: any)
	sendPacket(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SELECTED, amountRaw, throwDirectionRaw)
end

function LootServiceClient.ResolveDropAmount(self: LootServiceClient, amountRaw: any, fallbackAmountRaw: any?): number
	return LootServiceUtils.resolveDropAmount(amountRaw, fallbackAmountRaw)
end

function LootServiceClient.Init(self: LootServiceClient)
	bindPackets(self)
	self.janitor = Janitor.new()
	self:requestSync()
end

function LootServiceClient.Destroy(self: LootServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

LootServiceClient.applyState = LootServiceClient.ApplyState
LootServiceClient.requestSync = LootServiceClient.RequestSync
LootServiceClient.requestDropFromSlot = LootServiceClient.RequestDropFromSlot
LootServiceClient.requestDropSelectedSlot = LootServiceClient.RequestDropSelectedSlot
LootServiceClient.resolveDropAmount = LootServiceClient.ResolveDropAmount
LootServiceClient.init = LootServiceClient.Init
LootServiceClient.destroy = LootServiceClient.Destroy

type LootServiceClient = typeof(LootServiceClient) & {
	janitor: JanitorClass,
}

return LootServiceClient :: LootServiceClient
