local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local NpcServicePackets = require("NetPacketsShared").NpcService

local function sendPacket(methodName: string, ...: any)
	local packet = NpcServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for NpcService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = NpcServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for NpcService`)
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
	bindPacket(self, "onNpcAdded")
	bindPacket(self, "onNpcRemoved")
	bindPacket(self, "onNpcStateChanged")
	bindPacket(self, "requestSync")
end

local NpcServiceUtils = require("NpcServiceUtils")
local Sift = require(ReplicatedStorage.Packages.Sift)
local Signal = require("Signal")

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

local function createDefaultState(): NpcServiceClientState
	return {
		byId = {},
		orderedIds = {},
		updatedAt = os.clock(),
	}
end

local NpcServiceClient = {
	state = createDefaultState(),
	stateChanged = Signal.new(),
}

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

local function cloneState(stateRaw: any?): NpcServiceClientState
	if typeof(stateRaw) ~= "table" then
		return createDefaultState()
	end
	local state = stateRaw :: NpcServiceClientState
	local sourceById = if typeof(state.byId) == "table" then state.byId else {}
	local sourceOrderedIds = if typeof(state.orderedIds) == "table" then state.orderedIds else {}
	local updatedAt = if typeof(state.updatedAt) == "number" then state.updatedAt else os.clock()

	return {
		byId = Sift.Dictionary.map(sourceById, function(snapshot: NpcSnapshot): NpcSnapshot
			return cloneSnapshot(snapshot)
		end),
		orderedIds = Sift.Array.copy(sourceOrderedIds),
		updatedAt = updatedAt,
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
			local snapshot = NpcServiceUtils.CoerceSnapshot(rawSnapshot, nil)
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
	self.stateChanged:Fire(self:GetState())
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
	self.stateChanged:Fire(self:GetState())
end

function NpcServiceClient.ApplyState(self: NpcServiceClient, snapshotsRaw: any)
	self.state = buildStateFromSnapshots(snapshotsRaw)
	self.stateChanged:Fire(self:GetState())
end

function NpcServiceClient.OnNpcAdded(self: NpcServiceClient, snapshotRaw: any)
	local snapshot = NpcServiceUtils.CoerceSnapshot(snapshotRaw, nil)
	if snapshot == nil then
		return
	end
	self:UpsertSnapshot(snapshot)
end

function NpcServiceClient.OnNpcRemoved(self: NpcServiceClient, runtimeIdRaw: any)
	self:RemoveSnapshot(runtimeIdRaw)
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
	local snapshot = NpcServiceUtils.CoerceSnapshot(snapshotRaw, existingSnapshot)
	if snapshot == nil then
		return
	end
	self:UpsertSnapshot(snapshot)
end

function NpcServiceClient.RequestSync(_self: NpcServiceClient)
	sendPacket(NpcServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function NpcServiceClient.GetState(self: NpcServiceClient): NpcServiceClientState
	return cloneState(self.state)
end

function NpcServiceClient.Init(self: NpcServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.stateChanged = self.stateChanged or Signal.new()
	self.state = createDefaultState()

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self:RequestSync()
end

function NpcServiceClient.Destroy(self: NpcServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end
type NpcServiceClient = typeof(NpcServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	state: NpcServiceClientState,
}

return NpcServiceClient :: NpcServiceClient
