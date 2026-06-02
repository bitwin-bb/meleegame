--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require(gameRoot.Shared.NetShared.PacketPayload)
local RagdollServicePackets = (require :: any)(gameRoot.Shared.NetShared.Packets).RagdollService

local function sendPacket(methodName: string, ...: any)
	local packet = RagdollServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for RagdollService`)
		return
	end

	packet.send(PacketPayload.pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = RagdollServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for RagdollService`)
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
	bindPacket(self, "requestSelfRagdoll")
	bindPacket(self, "requestSelfRecover")
	bindPacket(self, "requestSync")
end

local RagdollServiceUtils = require(gameRoot.Shared.Features.ragdoll.RagdollServiceUtils)
local Signal = require(quentyPackages.signal.Shared.Signal)

type RagdollServiceState = RagdollServiceUtils.RagdollServiceState

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: RagdollServiceState) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: RagdollServiceState) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local RagdollServiceClient = {}
local SELF_REQUEST_REASON = "SelfRequest"

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

function RagdollServiceClient.Init(self: RagdollServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = RagdollServiceUtils.createDefaultState()
	self.stateChanged = Signal.new()

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	sendPacket("requestSync")
end

function RagdollServiceClient.ApplyState(self: RagdollServiceClient, stateRaw: any)
	local previousState = self.state
	local nextState = RagdollServiceUtils.sanitizeState(stateRaw, previousState)
	self.state = nextState

	if didStateChange(previousState, nextState) then
		self.stateChanged:Fire(RagdollServiceUtils.cloneState(nextState))
	end
end

function RagdollServiceClient.RequestSync(self: RagdollServiceClient)
	sendPacket("requestSync")
end

function RagdollServiceClient.RequestSelfRagdoll(
	self: RagdollServiceClient,
	durationRaw: any,
	reasonRaw: any,
	impulseRaw: any
)
	local duration = RagdollServiceUtils.sanitizeDuration(
		durationRaw,
		RagdollServiceUtils.DEFAULT_SELF_RAGDOLL_DURATION,
		RagdollServiceUtils.MIN_DURATION,
		RagdollServiceUtils.MAX_SELF_REQUEST_DURATION
	)
	local reason = RagdollServiceUtils.sanitizeReason(reasonRaw, SELF_REQUEST_REASON)
	local impulse = if typeof(impulseRaw) == "Vector3" then impulseRaw else nil
	sendPacket("requestSelfRagdoll", duration, reason, impulse)
end

function RagdollServiceClient.RequestSelfRecover(self: RagdollServiceClient)
	sendPacket("requestSelfRecover")
end

function RagdollServiceClient.GetState(self: RagdollServiceClient): RagdollServiceState
	return RagdollServiceUtils.cloneState(self.state)
end

function RagdollServiceClient.IsRagdolled(self: RagdollServiceClient): boolean
	return self.state.isRagdolled
end

function RagdollServiceClient.Destroy(self: RagdollServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end

RagdollServiceClient.init = RagdollServiceClient.Init
RagdollServiceClient.applyState = RagdollServiceClient.ApplyState
RagdollServiceClient.requestSync = RagdollServiceClient.RequestSync
RagdollServiceClient.requestSelfRagdoll = RagdollServiceClient.RequestSelfRagdoll
RagdollServiceClient.requestSelfRecover = RagdollServiceClient.RequestSelfRecover
RagdollServiceClient.getState = RagdollServiceClient.GetState
RagdollServiceClient.isRagdolled = RagdollServiceClient.IsRagdolled
RagdollServiceClient.destroy = RagdollServiceClient.Destroy

export type RagdollServiceClient = typeof(RagdollServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass,
	state: RagdollServiceState,
	stateChanged: SignalObject,
}

return RagdollServiceClient :: RagdollServiceClient
