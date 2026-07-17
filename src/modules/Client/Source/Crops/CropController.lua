local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Rx = require("Rx")
local ServiceBag = require("ServiceBag")
local Signal = require("Signal")
local Table = require("Table")
local ValueObject = require("ValueObject")

local BuildServiceClient = require("BuildServiceClient")
local BuildServiceUtils = require("BuildServiceUtils")
local CropTypes = require("CropTypes")
local NetPacketsClient = require("NetPacketsClient")
local PacketPayload = require("PacketPayload")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

local CropPackets = NetPacketsClient.CropService
local NETWORK = CropTypes.Network
local DELTA_OPERATION = CropTypes.DeltaOperation

local CropController = {}
CropController.ServiceName = "CropController"

local activeController: any? = nil
local packetsBound = false

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function cloneSnapshot(snapshotRaw: any): any
	local snapshot = if typeof(snapshotRaw) == "table" then snapshotRaw else {} :: any
	local crops = {}
	for _, stateRaw in snapshot.crops or {} do
		local state = CropTypes.CloneState(stateRaw)
		if state ~= nil then
			crops[#crops + 1] = state
		end
	end
	return {
		revision = if isFiniteNumber(snapshot.revision) then math.max(0, math.floor(snapshot.revision)) else 0,
		crops = crops,
	}
end

local function sendPacket(methodName: string, payload: any)
	local packet = CropPackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CropController`)
		return
	end
	packet.send(PacketPayload.Pack(payload))
end

local function bindPacket(methodName: string)
	local packet = CropPackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CropController`)
		return
	end

	packet.listen(function(payloadRaw: any)
		local controller = activeController
		if controller == nil then
			return
		end
		local count, arguments = PacketPayload.Unpack(payloadRaw)
		if count < 1 then
			return
		end
		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = controller[handlerName]
		if typeof(handler) == "function" then
			handler(controller, arguments[1])
		end
	end)
end

local function bindPackets()
	if packetsBound then
		return
	end
	packetsBound = true
	bindPacket(NETWORK.ApplyState)
	bindPacket(NETWORK.OnActionResult)
	bindPacket(NETWORK.OnChunkSnapshot)
	bindPacket(NETWORK.OnChunkUnloaded)
	bindPacket(NETWORK.OnCropDeltas)
end

function CropController.Init(self: any, serviceBag: any)
	assert(ServiceBag.isServiceBag(serviceBag), "No serviceBag")
	assert(self._serviceBag == nil, "Already initialized")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._revision = 0
	self._cropsByKey = {}
	self._keysByChunk = {}
	self._presentationHandlers = {}
	self.cropChanged = self._maid:Add(Signal.new())
	self.terrainChanged = self._maid:Add(Signal.new())
	self.actionResult = self._maid:Add(Signal.new())
	self._statePulse = self._maid:Add(Signal.new())
	self._stateValue = self._maid:Add(ValueObject.new({
		revision = 0,
		crops = {},
	}, "table"))
	self._stateObservable = self._stateValue:Observe():Pipe({
		Rx.map(cloneSnapshot),
		Rx.shareReplay(1),
	})
	self._cropChangedObservable = Rx.fromSignal(self.cropChanged):Pipe({
		Rx.share(),
	})
	self._terrainChangedObservable = Rx.fromSignal(self.terrainChanged):Pipe({
		Rx.share(),
	})
	self._maid:GiveTask(Rx.fromSignal(self._statePulse)
		:Pipe({
			Rx.throttleDefer(),
		})
		:Subscribe(function()
			self._stateValue.Value = self:GetStateSnapshot()
		end))

	activeController = self
	bindPackets()
end

function CropController.Start(self: any)
	assert(self._serviceBag ~= nil, "Not initialized")
	local chunkSnapshotsChanged = (WorldGenerationServiceClient :: any).chunkSnapshotsChanged
	if chunkSnapshotsChanged ~= nil then
		self._maid:GiveTask(Rx.fromSignal(chunkSnapshotsChanged):Subscribe(function(chunkKey: any)
			if typeof(chunkKey) ~= "string" then
				return
			end
			local snapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
			if typeof(snapshots) == "table" and snapshots[chunkKey] == nil then
				self:_removeChunk(chunkKey, "world_chunk_unloaded")
			end
		end))
	end

	local tileDeltasApplied = (BuildServiceClient :: any).tileDeltasApplied
	if tileDeltasApplied ~= nil then
		self._maid:GiveTask(Rx.fromSignal(tileDeltasApplied):Subscribe(function(deltas: any)
			self.terrainChanged:Fire({
				source = "build",
				deltas = if typeof(deltas) == "table" then deltas else {},
			})
		end))
	end
	self:RequestSync()
end

function CropController._addChunkIndex(self: any, key: string, state: any)
	local worldState = (WorldGenerationServiceClient :: any).state
	local chunkSize = if typeof(worldState) == "table" and isFiniteNumber(worldState.chunkSize)
		then math.max(1, math.floor(worldState.chunkSize))
		else 32
	local chunkKey = CropTypes.GetChunkKey(state.tileX, state.tileY, chunkSize)
	local entries = self._keysByChunk[chunkKey]
	if entries == nil then
		entries = {}
		self._keysByChunk[chunkKey] = entries
	end
	entries[key] = true
end

function CropController._removeChunkIndex(self: any, key: string, state: any)
	local worldState = (WorldGenerationServiceClient :: any).state
	local chunkSize = if typeof(worldState) == "table" and isFiniteNumber(worldState.chunkSize)
		then math.max(1, math.floor(worldState.chunkSize))
		else 32
	local chunkKey = CropTypes.GetChunkKey(state.tileX, state.tileY, chunkSize)
	local entries = self._keysByChunk[chunkKey]
	if entries == nil then
		return
	end
	entries[key] = nil
	if next(entries) == nil then
		self._keysByChunk[chunkKey] = nil
	end
end

function CropController._setCrop(self: any, stateRaw: any): any?
	local state = CropTypes.CloneState(stateRaw)
	if state == nil then
		return nil
	end
	local key = CropTypes.GetTileKey(state.tileX, state.tileY)
	local previous = self._cropsByKey[key]
	if previous ~= nil then
		self:_removeChunkIndex(key, previous)
	end
	self._cropsByKey[key] = state
	self:_addChunkIndex(key, state)
	return CropTypes.CloneState(previous)
end

function CropController._removeCrop(self: any, keyRaw: any): any?
	if typeof(keyRaw) ~= "string" then
		return nil
	end
	local previous = self._cropsByKey[keyRaw]
	if previous == nil then
		return nil
	end
	self:_removeChunkIndex(keyRaw, previous)
	self._cropsByKey[keyRaw] = nil
	return CropTypes.CloneState(previous)
end

function CropController._emitPresentationChange(self: any, change: any)
	self.cropChanged:Fire(change)
	for handler in self._presentationHandlers do
		local callback = (handler :: any).OnCropChanged
		if typeof(callback) == "function" then
			pcall(callback, handler, change)
		end
	end
	self._statePulse:Fire()
end

function CropController._removeChunk(self: any, chunkKeyRaw: any, reasonRaw: any?): number
	if typeof(chunkKeyRaw) ~= "string" then
		return 0
	end
	local entries = self._keysByChunk[chunkKeyRaw]
	if entries == nil then
		return 0
	end
	local keys = Table.keys(entries)
	table.sort(keys)
	local removed = {}
	for _, key in keys do
		local state = self:_removeCrop(key)
		if state ~= nil then
			removed[#removed + 1] = state
		end
	end
	self:_emitPresentationChange({
		kind = "chunk_unloaded",
		chunkKey = chunkKeyRaw,
		crops = removed,
		reason = if typeof(reasonRaw) == "string" then reasonRaw else "chunk_unloaded",
		revision = self._revision,
	})
	return #removed
end

function CropController.ApplyState(self: any, snapshotRaw: any)
	local snapshot = cloneSnapshot(snapshotRaw)
	if snapshot.revision < self._revision then
		return
	end
	table.clear(self._cropsByKey)
	table.clear(self._keysByChunk)
	self._revision = snapshot.revision
	for _, state in snapshot.crops do
		self:_setCrop(state)
	end
	self:_emitPresentationChange({
		kind = "snapshot",
		crops = self:GetAllCrops(),
		revision = self._revision,
	})
end

function CropController.OnChunkSnapshot(self: any, snapshotRaw: any)
	if typeof(snapshotRaw) ~= "table" or typeof((snapshotRaw :: any).chunkKey) ~= "string" then
		return
	end
	local revisionRaw = (snapshotRaw :: any).revision
	if isFiniteNumber(revisionRaw) and revisionRaw < self._revision then
		return
	end
	self._revision = if isFiniteNumber(revisionRaw)
		then math.max(self._revision, math.floor(revisionRaw))
		else self._revision
	local chunkKey = (snapshotRaw :: any).chunkKey
	self:_removeChunk(chunkKey, "chunk_resync")
	local crops = {}
	for _, stateRaw in (snapshotRaw :: any).crops or {} do
		local state = CropTypes.CloneState(stateRaw)
		if state ~= nil then
			self:_setCrop(state)
			crops[#crops + 1] = state
		end
	end
	self:_emitPresentationChange({
		kind = "chunk_snapshot",
		chunkKey = chunkKey,
		crops = crops,
		revision = self._revision,
	})
end

function CropController.OnChunkUnloaded(self: any, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local revisionRaw = (payloadRaw :: any).revision
	if isFiniteNumber(revisionRaw) then
		self._revision = math.max(self._revision, math.floor(revisionRaw))
	end
	self:_removeChunk((payloadRaw :: any).chunkKey, "server_chunk_unloaded")
end

function CropController.OnCropDeltas(self: any, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" or typeof((payloadRaw :: any).deltas) ~= "table" then
		return
	end
	local revisionRaw = (payloadRaw :: any).revision
	if isFiniteNumber(revisionRaw) and revisionRaw < self._revision then
		return
	end
	local applied = {}
	local terrain = {}
	for _, deltaRaw in (payloadRaw :: any).deltas do
		local delta = CropTypes.CloneDelta(deltaRaw)
		if delta == nil then
			continue
		end
		if delta.op == DELTA_OPERATION.Set and delta.crop ~= nil then
			self:_setCrop(delta.crop)
			applied[#applied + 1] = delta
		elseif delta.op == DELTA_OPERATION.Remove then
			self:_removeCrop(delta.key)
			applied[#applied + 1] = delta
		elseif delta.op == DELTA_OPERATION.Terrain then
			terrain[#terrain + 1] = delta
		end
		self._revision = math.max(self._revision, delta.revision)
	end
	if isFiniteNumber(revisionRaw) then
		self._revision = math.max(self._revision, math.floor(revisionRaw))
	end
	if #applied > 0 then
		self:_emitPresentationChange({
			kind = "deltas",
			deltas = applied,
			revision = self._revision,
		})
	end
	if #terrain > 0 then
		self.terrainChanged:Fire({
			source = "crops",
			deltas = terrain,
			revision = self._revision,
		})
	end
end

function CropController.OnActionResult(self: any, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	self.actionResult:Fire(Table.deepCopy(payloadRaw))
end

function CropController.GetCropAt(self: any, tileXRaw: any, tileYRaw: any): any?
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return nil
	end
	return CropTypes.CloneState(self._cropsByKey[CropTypes.GetTileKey(tileX, tileY)])
end

function CropController.GetAllCrops(self: any): { any }
	local keys = Table.keys(self._cropsByKey)
	table.sort(keys)
	local crops = {}
	for _, key in keys do
		local state = CropTypes.CloneState(self._cropsByKey[key])
		if state ~= nil then
			crops[#crops + 1] = state
		end
	end
	return crops
end

function CropController.GetStateSnapshot(self: any): any
	return {
		revision = self._revision,
		crops = self:GetAllCrops(),
	}
end

function CropController.ObserveState(self: any): any
	return self._stateObservable
end

function CropController.ObserveCropChanged(self: any): any
	return self._cropChangedObservable
end

function CropController.ObserveTerrainChanged(self: any): any
	return self._terrainChangedObservable
end

function CropController.ObserveCrop(self: any, tileXRaw: any, tileYRaw: any): any
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	return self._stateObservable:Pipe({
		Rx.map(function()
			if tileX == nil or tileY == nil then
				return nil
			end
			return self:GetCropAt(tileX, tileY)
		end),
	})
end

function CropController.RegisterPresentationHandler(self: any, handlerRaw: any): () -> ()
	if typeof(handlerRaw) ~= "table" then
		return function() end
	end
	self._presentationHandlers[handlerRaw] = true
	return function()
		if self._presentationHandlers ~= nil then
			self._presentationHandlers[handlerRaw] = nil
		end
	end
end

function CropController.Plant(_self: any, cropIdRaw: any, tileXRaw: any, tileYRaw: any, requestIdRaw: any?)
	sendPacket(NETWORK.RequestPlant, {
		cropId = CropTypes.CoerceCropId(cropIdRaw),
		tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw),
		tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw),
		requestId = requestIdRaw,
	})
end

function CropController.Harvest(_self: any, tileXRaw: any, tileYRaw: any, requestIdRaw: any?)
	sendPacket(NETWORK.RequestHarvest, {
		tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw),
		tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw),
		requestId = requestIdRaw,
	})
end

function CropController.RequestSync(_self: any)
	sendPacket(NETWORK.RequestSync, {})
end

function CropController.Destroy(self: any)
	if activeController == self then
		activeController = nil
	end
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	if self._cropsByKey ~= nil then
		table.clear(self._cropsByKey)
	end
	if self._keysByChunk ~= nil then
		table.clear(self._keysByChunk)
	end
	if self._presentationHandlers ~= nil then
		table.clear(self._presentationHandlers)
	end
	self._serviceBag = nil
end

return CropController
