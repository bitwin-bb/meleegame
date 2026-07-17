local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local ServiceBag = require("ServiceBag")
local RagdollServicePackets = require("NetPacketsShared").RagdollService

local function sendPacket(methodName: string, ...: any)
	local packet = RagdollServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for RagdollService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = RagdollServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for RagdollService`)
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
	bindPacket(self, "requestSelfRagdoll")
	bindPacket(self, "requestSelfRecover")
	bindPacket(self, "requestSync")
end

local RagdollServiceUtils = require("RagdollServiceUtils")
local Signal = require("Signal")

type RagdollServiceState = RagdollServiceUtils.RagdollServiceState

type SignalObject = Signal.Signal<...any>

type JanitorClass = any

local RagdollServiceClient = {}
RagdollServiceClient.ServiceName = "AquariaRagdollServiceClient"
local SELF_REQUEST_REASON = "SelfRequest"

RagdollServiceClient.state = RagdollServiceUtils.CreateDefaultState()
RagdollServiceClient.stateChanged = Signal.new()

local function didStateChange(previousState: RagdollServiceState, nextState: RagdollServiceState): boolean
	if previousState.sequence ~= nextState.sequence then
		return true
	end
	if previousState.isRagdolled ~= nextState.isRagdolled then
		return true
	end
	if previousState.reason ~= nextState.reason then
		return true
	end
	if previousState.canRecover ~= nextState.canRecover then
		return true
	end
	if previousState.scheduledRecoveryAt ~= nextState.scheduledRecoveryAt then
		return true
	end
	if previousState.startedAt ~= nextState.startedAt then
		return true
	end
	return false
end

function RagdollServiceClient.Init(self: RagdollServiceClient, serviceBag: ServiceBag.ServiceBag?)
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = self.state or RagdollServiceUtils.CreateDefaultState()
	self.stateChanged = self.stateChanged or Signal.new()

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	sendPacket("requestSync")
end

function RagdollServiceClient.ApplyState(self: RagdollServiceClient, stateRaw: any)
	local previousState = self.state
	local nextState = RagdollServiceUtils.CoerceState(stateRaw, previousState)
	self.state = nextState

	if didStateChange(previousState, nextState) then
		self.stateChanged:Fire(RagdollServiceUtils.CloneState(nextState))
	end
end

function RagdollServiceClient.RequestSync(_self: RagdollServiceClient)
	sendPacket("requestSync")
end

function RagdollServiceClient.RequestSelfRagdoll(
	_self: RagdollServiceClient,
	durationRaw: any,
	reasonRaw: any,
	impulseRaw: any
)
	local duration = RagdollServiceUtils.CoerceDuration(
		durationRaw,
		RagdollServiceUtils.DEFAULT_SELF_RAGDOLL_DURATION,
		RagdollServiceUtils.MIN_DURATION,
		RagdollServiceUtils.MAX_SELF_REQUEST_DURATION
	)
	local reason = RagdollServiceUtils.CoerceReason(reasonRaw, SELF_REQUEST_REASON)
	local impulse = if typeof(impulseRaw) == "Vector3" then impulseRaw else nil
	sendPacket("requestSelfRagdoll", duration, reason, impulse)
end

function RagdollServiceClient.RequestSelfRecover(_self: RagdollServiceClient)
	sendPacket("requestSelfRecover")
end

function RagdollServiceClient.GetState(self: RagdollServiceClient): RagdollServiceState
	return RagdollServiceUtils.CloneState(self.state or RagdollServiceUtils.CreateDefaultState())
end

function RagdollServiceClient.IsRagdolled(self: RagdollServiceClient): boolean
	local state = self.state
	return state ~= nil and state.isRagdolled == true
end

function RagdollServiceClient.Destroy(self: RagdollServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
	self._serviceBag = nil
end
export type RagdollServiceClient = typeof(RagdollServiceClient) & {
	_serviceBag: ServiceBag.ServiceBag?,
	localPlayer: Player,
	janitor: JanitorClass,
	state: RagdollServiceState,
	stateChanged: SignalObject,
}

return RagdollServiceClient :: RagdollServiceClient
