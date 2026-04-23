--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Sift = require(ReplicatedStorage.Packages.Sift)
local NpcServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.NpcServiceUtils)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioServiceClient)

type NpcSnapshot = NpcServiceUtils.NpcSnapshot

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type NpcServiceClientState = {
	byId: { [string]: NpcSnapshot },
	orderedIds: { string },
	updatedAt: number,
}

local NpcServiceClient = {}

local function cloneSnapshot(snapshot: NpcSnapshot): NpcSnapshot
	return {
		id = snapshot.id,
		npcType = snapshot.npcType,
		displayName = snapshot.displayName,
		state = snapshot.state,
		biomeName = snapshot.biomeName,
		biomeReady = snapshot.biomeReady,
		hp = snapshot.hp,
		maxHp = snapshot.maxHp,
		isAlive = snapshot.isAlive,
		position = snapshot.position,
		updatedAt = snapshot.updatedAt,
		lastReason = snapshot.lastReason,
	}
end

local function cloneState(state: NpcServiceClientState): NpcServiceClientState
	return {
		byId = Sift.Dictionary.map(state.byId, function(snapshot: NpcSnapshot): NpcSnapshot
			return cloneSnapshot(snapshot)
		end),
		orderedIds = Sift.Array.copy(state.orderedIds),
		updatedAt = state.updatedAt,
	}
end

local function appendUniqueOrderedId(orderedIds: { string }, runtimeId: string): { string }
	if Sift.Array.includes(orderedIds, runtimeId) then
		return orderedIds
	end
	return Sift.Array.append(orderedIds, runtimeId)
end

local function buildStateFromSnapshots(snapshotsRaw: any): NpcServiceClientState
	local byId: { [string]: NpcSnapshot } = {}
	local orderedIds: { string } = {}

	if typeof(snapshotsRaw) == "table" then
		for _, rawSnapshot in snapshotsRaw do
			local snapshot = NpcServiceUtils.sanitizeSnapshot(rawSnapshot, nil)
			if snapshot ~= nil then
				byId[snapshot.id] = snapshot
				orderedIds = appendUniqueOrderedId(orderedIds, snapshot.id)
			end
		end
	end

	return {
		byId = byId,
		orderedIds = orderedIds,
		updatedAt = os.clock(),
	}
end

function NpcServiceClient.UpsertSnapshot(self: NpcServiceClient, snapshot: NpcSnapshot)
	local nextSnapshot = cloneSnapshot(snapshot)
	self.state = {
		byId = Sift.Dictionary.set(self.state.byId, snapshot.id, nextSnapshot),
		orderedIds = appendUniqueOrderedId(self.state.orderedIds, snapshot.id),
		updatedAt = os.clock(),
	}
	self.stateChanged:Fire(self:getState())
end

function NpcServiceClient.RemoveSnapshot(self: NpcServiceClient, runtimeIdRaw: any)
	if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
		return
	end

	if self.state.byId[runtimeIdRaw] == nil then
		return
	end

	self.state = {
		byId = Sift.Dictionary.removeKey(self.state.byId, runtimeIdRaw),
		orderedIds = Sift.Array.filter(self.state.orderedIds, function(existingId: string): boolean
			return existingId ~= runtimeIdRaw
		end),
		updatedAt = os.clock(),
	}
	self.stateChanged:Fire(self:getState())
end

function NpcServiceClient.ApplyState(self: NpcServiceClient, snapshotsRaw: any)
	self.state = buildStateFromSnapshots(snapshotsRaw)
	self.stateChanged:Fire(self:getState())
end

function NpcServiceClient.OnNpcAdded(self: NpcServiceClient, snapshotRaw: any)
	local snapshot = NpcServiceUtils.sanitizeSnapshot(snapshotRaw, nil)
	if snapshot == nil then
		return
	end
	self:upsertSnapshot(snapshot)
end

function NpcServiceClient.OnNpcRemoved(self: NpcServiceClient, runtimeIdRaw: any)
	self:removeSnapshot(runtimeIdRaw)
end

function NpcServiceClient.OnNpcStateChanged(self: NpcServiceClient, snapshotRaw: any)
	if typeof(snapshotRaw) ~= "table" then
		return
	end

	local runtimeId = (snapshotRaw :: any).id
	if typeof(runtimeId) ~= "string" or runtimeId == "" then
		return
	end

	local existingSnapshot = self.state.byId[runtimeId]
	local snapshot = NpcServiceUtils.sanitizeSnapshot(snapshotRaw, existingSnapshot)
	if snapshot == nil then
		return
	end
	self:upsertSnapshot(snapshot)
end

function NpcServiceClient.OnNpcAnimationEvent(self: NpcServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end

	self.lastAnimationEvent = payloadRaw
	local clientEffects = (payloadRaw :: any).clientEffects
	if typeof(clientEffects) ~= "table" then
		return
	end

	for _, effect in clientEffects do
		if typeof(effect) ~= "table" then
			continue
		end

		if (effect :: any).kind == "sound" then
			local source = (effect :: any).source
			local options = if typeof((effect :: any).options) == "table" then (effect :: any).options else {}
			AudioServiceClient:playSfx(source, options)
		end
	end
end

function NpcServiceClient.RequestSync(self: NpcServiceClient)
	self.networker:fire(NpcServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function NpcServiceClient.GetState(self: NpcServiceClient): NpcServiceClientState
	return cloneState(self.state)
end

function NpcServiceClient.Init(self: NpcServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("NpcService", self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.state = {
		byId = {},
		orderedIds = {},
		updatedAt = os.clock(),
	}
	self.lastAnimationEvent = nil

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:requestSync()
end

function NpcServiceClient.Destroy(self: NpcServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end

NpcServiceClient.upsertSnapshot = NpcServiceClient.UpsertSnapshot
NpcServiceClient.removeSnapshot = NpcServiceClient.RemoveSnapshot
NpcServiceClient.applyState = NpcServiceClient.ApplyState
NpcServiceClient.onNpcAdded = NpcServiceClient.OnNpcAdded
NpcServiceClient.onNpcRemoved = NpcServiceClient.OnNpcRemoved
NpcServiceClient.onNpcStateChanged = NpcServiceClient.OnNpcStateChanged
NpcServiceClient.onNpcAnimationEvent = NpcServiceClient.OnNpcAnimationEvent
NpcServiceClient.requestSync = NpcServiceClient.RequestSync
NpcServiceClient.getState = NpcServiceClient.GetState
NpcServiceClient.init = NpcServiceClient.Init
NpcServiceClient.destroy = NpcServiceClient.Destroy

type NpcServiceClient = typeof(NpcServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	state: NpcServiceClientState,
	lastAnimationEvent: any?,
}

return NpcServiceClient :: NpcServiceClient


