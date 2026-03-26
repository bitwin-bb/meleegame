--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Sift = require(ReplicatedStorage.Packages.Sift)
local NpcServiceUtils = require(ReplicatedStorage.Shared.Services.NpcService.NpcServiceUtils)
local AudioServiceClient = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceClient)

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

function NpcServiceClient.upsertSnapshot(self: NpcServiceClient, snapshot: NpcSnapshot)
	local nextSnapshot = cloneSnapshot(snapshot)
	self.state = {
		byId = Sift.Dictionary.set(self.state.byId, snapshot.id, nextSnapshot),
		orderedIds = appendUniqueOrderedId(self.state.orderedIds, snapshot.id),
		updatedAt = os.clock(),
	}
	self.stateChanged:Fire(self:getState())
end

function NpcServiceClient.removeSnapshot(self: NpcServiceClient, runtimeIdRaw: any)
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

function NpcServiceClient.applyState(self: NpcServiceClient, snapshotsRaw: any)
	self.state = buildStateFromSnapshots(snapshotsRaw)
	self.stateChanged:Fire(self:getState())
end

function NpcServiceClient.onNpcAdded(self: NpcServiceClient, snapshotRaw: any)
	local snapshot = NpcServiceUtils.sanitizeSnapshot(snapshotRaw, nil)
	if snapshot == nil then
		return
	end
	self:upsertSnapshot(snapshot)
end

function NpcServiceClient.onNpcRemoved(self: NpcServiceClient, runtimeIdRaw: any)
	self:removeSnapshot(runtimeIdRaw)
end

function NpcServiceClient.onNpcStateChanged(self: NpcServiceClient, snapshotRaw: any)
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

function NpcServiceClient.onNpcAnimationEvent(self: NpcServiceClient, payloadRaw: any)
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

function NpcServiceClient.requestSync(self: NpcServiceClient)
	self.networker:fire(NpcServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function NpcServiceClient.getState(self: NpcServiceClient): NpcServiceClientState
	return cloneState(self.state)
end

function NpcServiceClient.init(self: NpcServiceClient)
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

function NpcServiceClient.destroy(self: NpcServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end

type NpcServiceClient = typeof(NpcServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	state: NpcServiceClientState,
	lastAnimationEvent: any?,
}

return NpcServiceClient :: NpcServiceClient

