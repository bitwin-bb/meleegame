--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RagdollServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.RagdollService.RagdollServiceUtils)

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
	self.networker = Networker.client.new("RagdollService", self)
	self.janitor = Janitor.new()
	self.state = RagdollServiceUtils.createDefaultState()
	self.stateChanged = Signal.new()

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self.networker:fire("requestSync")
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
	self.networker:fire("requestSync")
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
	self.networker:fire("requestSelfRagdoll", duration, reason, impulse)
end

function RagdollServiceClient.RequestSelfRecover(self: RagdollServiceClient)
	self.networker:fire("requestSelfRecover")
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
	networker: Networker.Client,
	janitor: JanitorClass,
	state: RagdollServiceState,
	stateChanged: SignalObject,
}

return RagdollServiceClient :: RagdollServiceClient
