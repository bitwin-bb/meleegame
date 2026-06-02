--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require(gameRoot.Shared.NetShared.PacketPayload)
local NpcServicePackets = (require :: any)(gameRoot.Shared.NetShared.Packets).NpcService

local function sendPacket(methodName: string, ...: any)
	local packet = NpcServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for NpcService`)
		return
	end

	packet.send(PacketPayload.pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = NpcServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for NpcService`)
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
	bindPacket(self, "onNpcAdded")
	bindPacket(self, "onNpcRemoved")
	bindPacket(self, "onNpcStateChanged")
	bindPacket(self, "requestSync")
end

local NpcServiceUtils = require(gameRoot.Shared.Features.npc.NpcServiceUtils)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Signal = require(quentyPackages.signal.Shared.Signal)

type NpcSnapshot = NpcServiceUtils.NpcSnapshot

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> any,
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
		spritePhase = snapshot.spritePhase,
		spriteFrame = snapshot.spriteFrame,
		spriteFrameRate = snapshot.spriteFrameRate,
		spritePhaseElapsed = snapshot.spritePhaseElapsed,
		spritePhaseDuration = snapshot.spritePhaseDuration,
		spriteReceivedAt = snapshot.spriteReceivedAt,
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
				snapshot.spriteReceivedAt = os.clock()
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
	nextSnapshot.spriteReceivedAt = os.clock()
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

function NpcServiceClient.RequestSync(self: NpcServiceClient)
	sendPacket(NpcServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function NpcServiceClient.GetState(self: NpcServiceClient): NpcServiceClientState
	return cloneState(self.state)
end

function NpcServiceClient.Init(self: NpcServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.state = {
		byId = {},
		orderedIds = {},
		updatedAt = os.clock(),
	}

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
NpcServiceClient.requestSync = NpcServiceClient.RequestSync
NpcServiceClient.getState = NpcServiceClient.GetState
NpcServiceClient.init = NpcServiceClient.Init
NpcServiceClient.destroy = NpcServiceClient.Destroy

type NpcServiceClient = typeof(NpcServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	state: NpcServiceClientState,
}

return NpcServiceClient :: NpcServiceClient
