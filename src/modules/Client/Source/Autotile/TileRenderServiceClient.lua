local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local Maid = require("Maid")
local Queue = require("Queue")
local Rx = require("Rx")
local Signal = require("Signal")

local BuildServiceUtils = require("BuildServiceUtils")

local TileRenderServiceClient = {}
TileRenderServiceClient.__index = TileRenderServiceClient

local DEFAULT_MAX_TILE_UPDATES_PER_HEARTBEAT = 96

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function coerceUpdateBudget(valueRaw: any): number
	if not isFiniteNumber(valueRaw) then
		return DEFAULT_MAX_TILE_UPDATES_PER_HEARTBEAT
	end
	return math.max(1, math.floor(valueRaw))
end

local function createEventStream(signal: any, kind: string): any
	return Rx.fromSignal(signal):Pipe({
		Rx.map(function(payload: any)
			return {
				kind = kind,
				payload = payload,
			}
		end),
	})
end

function TileRenderServiceClient.new(optionsRaw: any?): any
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local updateTile = (options :: any).updateTile
	local refreshAll = (options :: any).refreshAll

	local self = setmetatable({
		_maid = Maid.new(),
		_maxTileUpdatesPerHeartbeat = coerceUpdateBudget((options :: any).maxTileUpdatesPerHeartbeat),
		_queueChanged = Signal.new(),
		_queuedTileKeys = {},
		_refreshRequested = false,
		_tileUpdateQueue = Queue.new(),
		_updateTile = if typeof(updateTile) == "function" then updateTile else function() end,
		_refreshAll = if typeof(refreshAll) == "function" then refreshAll else function() end,
		_flushRequested = false,
	}, TileRenderServiceClient)

	self._maid:GiveTask(self._queueChanged)
	self._maid:GiveTask(Rx.fromSignal(self._queueChanged):Pipe({
		Rx.throttleDefer(),
	}):Subscribe(function()
		self._flushRequested = true
	end))
	self._maid:GiveTask(Rx.fromSignal(RunService.Heartbeat):Subscribe(function()
		self:Flush()
	end))

	local eventStreams = {}
	if (options :: any).tileDeltasApplied ~= nil then
		table.insert(eventStreams, createEventStream((options :: any).tileDeltasApplied, "tileDeltas"))
	end
	if (options :: any).stateChanged ~= nil then
		table.insert(eventStreams, createEventStream((options :: any).stateChanged, "stateChanged"))
	end
	if #eventStreams > 0 then
		local eventStream = if #eventStreams == 1 then eventStreams[1] else Rx.merge(eventStreams)
		self._maid:GiveTask(eventStream:Subscribe(function(event: any)
			if event.kind == "tileDeltas" then
				self:QueueTileDeltas(event.payload)
			else
				self:RequestRefresh()
			end
		end))
	end

	return self
end

function TileRenderServiceClient._queueTileUpdate(self: any, tileX: number, tileY: number): boolean
	local tileKey = BuildServiceUtils.PackTileKey(tileX, tileY)
	if self._queuedTileKeys[tileKey] then
		return false
	end

	self._queuedTileKeys[tileKey] = true
	self._tileUpdateQueue:PushRight({
		tileX = tileX,
		tileY = tileY,
		tileKey = tileKey,
	})
	return true
end

function TileRenderServiceClient.QueueTileDeltas(self: any, deltasRaw: any): number
	if typeof(deltasRaw) ~= "table" or self._tileUpdateQueue == nil then
		return 0
	end

	local queuedCount = 0
	for _, deltaRaw in deltasRaw do
		if typeof(deltaRaw) ~= "table" then
			continue
		end

		local tileX = BuildServiceUtils.CoerceTileCoordinate((deltaRaw :: any).tileX)
		local tileY = BuildServiceUtils.CoerceTileCoordinate((deltaRaw :: any).tileY)
		if tileX == nil or tileY == nil then
			continue
		end

		for offsetX = -1, 1 do
			for offsetY = -1, 1 do
				if self:_queueTileUpdate(tileX + offsetX, tileY + offsetY) then
					queuedCount += 1
				end
			end
		end
	end

	if queuedCount > 0 then
		self._queueChanged:Fire()
	end
	return queuedCount
end

function TileRenderServiceClient.QueueChunkBoundary(self: any, chunkKeyRaw: any, chunkSizeRaw: any): number
	if self._tileUpdateQueue == nil then
		return 0
	end

	local chunkX, chunkY = BuildServiceUtils.UnpackChunkKey(chunkKeyRaw)
	if chunkX == nil or chunkY == nil then
		return 0
	end

	local chunkSize = if isFiniteNumber(chunkSizeRaw) then math.max(1, math.floor(chunkSizeRaw :: number)) else 32
	local minTileX = chunkX * chunkSize
	local minTileY = chunkY * chunkSize
	local maxTileX = minTileX + chunkSize - 1
	local maxTileY = minTileY + chunkSize - 1
	local edgeTileXs = { minTileX - 1, minTileX, maxTileX, maxTileX + 1 }
	local edgeTileYs = { minTileY - 1, minTileY, maxTileY, maxTileY + 1 }
	local queuedCount = 0

	for tileY = minTileY - 1, maxTileY + 1 do
		for _, tileX in edgeTileXs do
			if self:_queueTileUpdate(tileX, tileY) then
				queuedCount += 1
			end
		end
	end
	for tileX = minTileX - 1, maxTileX + 1 do
		for _, tileY in edgeTileYs do
			if self:_queueTileUpdate(tileX, tileY) then
				queuedCount += 1
			end
		end
	end

	if queuedCount > 0 then
		self._queueChanged:Fire()
	end
	return queuedCount
end

function TileRenderServiceClient.RequestRefresh(self: any)
	if self._tileUpdateQueue == nil then
		return
	end

	self._refreshRequested = true
	self._queueChanged:Fire()
end

function TileRenderServiceClient.Flush(self: any): number
	if self._tileUpdateQueue == nil or not self._flushRequested then
		return 0
	end

	if self._refreshRequested then
		self._refreshRequested = false
		self._flushRequested = false
		self._tileUpdateQueue = Queue.new()
		table.clear(self._queuedTileKeys)
		self._refreshAll()
		return 1
	end

	local updateCount = 0
	while updateCount < self._maxTileUpdatesPerHeartbeat and not self._tileUpdateQueue:IsEmpty() do
		local update = self._tileUpdateQueue:PopLeft()
		self._queuedTileKeys[update.tileKey] = nil
		self._updateTile(update.tileX, update.tileY)
		updateCount += 1
	end

	self._flushRequested = not self._tileUpdateQueue:IsEmpty()
	return updateCount
end

function TileRenderServiceClient.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	if self._queuedTileKeys ~= nil then
		table.clear(self._queuedTileKeys)
	end
	self._tileUpdateQueue = nil
end

return TileRenderServiceClient
