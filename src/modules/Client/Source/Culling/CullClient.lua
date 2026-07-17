local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Queue = require("Queue")

local CullUtil = require("CullUtil")

type TileBounds = CullUtil.TileBounds

local CullClient = {}
CullClient.__index = CullClient

local function queueRectangle(self: any, minX: number, minY: number, maxX: number, maxY: number, desired: boolean)
	for tileY = minY, maxY - 1 do
		for tileX = minX, maxX - 1 do
			self:_queueTile(tileX, tileY, desired, false)
		end
	end
end

local function queueBoundsDifference(self: any, source: TileBounds?, excluded: TileBounds?, desired: boolean)
	if source == nil then
		return
	end

	local overlap = CullUtil.IntersectBounds(source, excluded)
	if overlap == nil then
		queueRectangle(self, source.minX, source.minY, source.maxX, source.maxY, desired)
		return
	end

	queueRectangle(self, source.minX, source.minY, source.maxX, overlap.minY, desired)
	queueRectangle(self, source.minX, overlap.maxY, source.maxX, source.maxY, desired)
	queueRectangle(self, source.minX, overlap.minY, overlap.minX, overlap.maxY, desired)
	queueRectangle(self, overlap.maxX, overlap.minY, source.maxX, overlap.maxY, desired)
end

function CullClient.new(optionsRaw: any?): any
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local chunkBounds = CullUtil.GetChunkBounds(
		(options :: any).tileMinX,
		(options :: any).tileMinY,
		(options :: any).width,
		(options :: any).height
	)
	assert(chunkBounds ~= nil, "invalid cull chunk bounds")

	local renderTile = (options :: any).renderTile
	local clearTile = (options :: any).clearTile
	local clearAll = (options :: any).clearAll
	local key = (options :: any).key
	local self = setmetatable({
		_maid = Maid.new(),
		_key = if typeof(key) == "string" and key ~= "" then key else nil,
		_chunkBounds = chunkBounds,
		_width = chunkBounds.maxX - chunkBounds.minX,
		_desiredBounds = nil,
		_activeTileKeys = {},
		_activeTileCount = 0,
		_forceTileKeys = {},
		_queuedTileStates = {},
		_queuedTileCount = 0,
		_addQueue = Queue.new(),
		_removeQueue = Queue.new(),
		_renderTile = if typeof(renderTile) == "function" then renderTile else function() end,
		_clearTile = if typeof(clearTile) == "function" then clearTile else function() end,
		_clearAll = if typeof(clearAll) == "function" then clearAll else nil,
		_destroyed = false,
	}, CullClient)

	self._maid:GiveTask(function()
		table.clear(self._activeTileKeys)
		table.clear(self._forceTileKeys)
		table.clear(self._queuedTileStates)
		self._activeTileCount = 0
		self._queuedTileCount = 0
		self._addQueue = Queue.new()
		self._removeQueue = Queue.new()
	end)

	return self
end

function CullClient._compactQueuesIfNeeded(self: any)
	local physicalCount = self._addQueue:GetCount() + self._removeQueue:GetCount()
	local staleAllowance = math.max(64, self._width * 2)
	if physicalCount <= self._queuedTileCount + staleAllowance then
		return
	end

	local addQueue = Queue.new()
	local removeQueue = Queue.new()
	for tileKey, desired in self._queuedTileStates do
		if desired then
			addQueue:PushRight(tileKey)
		else
			removeQueue:PushRight(tileKey)
		end
	end
	self._addQueue = addQueue
	self._removeQueue = removeQueue
end

function CullClient._getTileKey(self: any, tileX: number, tileY: number): number
	return (tileY - self._chunkBounds.minY) * self._width + (tileX - self._chunkBounds.minX)
end

function CullClient._unpackTileKey(self: any, tileKey: number): (number, number)
	local localY = math.floor(tileKey / self._width)
	local localX = tileKey - localY * self._width
	return self._chunkBounds.minX + localX, self._chunkBounds.minY + localY
end

function CullClient._queueTile(self: any, tileX: number, tileY: number, desired: boolean, force: boolean): boolean
	if self._destroyed or not CullUtil.ContainsTile(self._chunkBounds, tileX, tileY) then
		return false
	end

	local tileKey = self:_getTileKey(tileX, tileY)
	if desired and force then
		self._forceTileKeys[tileKey] = true
	elseif not desired then
		self._forceTileKeys[tileKey] = nil
	end
	local queuedState = self._queuedTileStates[tileKey]
	if queuedState == desired then
		return false
	end

	if queuedState == nil then
		self._queuedTileCount += 1
	end
	self._queuedTileStates[tileKey] = desired
	if desired then
		self._addQueue:PushRight(tileKey)
	else
		self._removeQueue:PushRight(tileKey)
	end
	return true
end

function CullClient.SetVisibleBounds(self: any, visibleBounds: TileBounds?): boolean
	if self._destroyed then
		return false
	end

	local nextBounds = CullUtil.IntersectBounds(self._chunkBounds, visibleBounds)
	if CullUtil.BoundsEqual(self._desiredBounds, nextBounds) then
		return false
	end

	local previousBounds = self._desiredBounds
	self._desiredBounds = CullUtil.CloneBounds(nextBounds)
	queueBoundsDifference(self, previousBounds, nextBounds, false)
	queueBoundsDifference(self, nextBounds, previousBounds, true)
	self:_compactQueuesIfNeeded()
	return true
end

function CullClient.Refresh(self: any): boolean
	if self._destroyed or self._desiredBounds == nil then
		return false
	end

	local queued = false
	local bounds = self._desiredBounds :: TileBounds
	for tileY = bounds.minY, bounds.maxY - 1 do
		for tileX = bounds.minX, bounds.maxX - 1 do
			if self:_queueTile(tileX, tileY, true, true) then
				queued = true
			end
		end
	end
	return queued
end

function CullClient.Reconcile(self: any): boolean
	if self._destroyed then
		return false
	end

	local queued = self:Refresh()
	for tileKey in self._activeTileKeys do
		local tileX, tileY = self:_unpackTileKey(tileKey)
		if not CullUtil.ContainsTile(self._desiredBounds, tileX, tileY) then
			if self:_queueTile(tileX, tileY, false, false) then
				queued = true
			end
		end
	end
	self:_compactQueuesIfNeeded()
	return queued
end

function CullClient.HasWork(self: any): boolean
	return not self._destroyed and (not self._removeQueue:IsEmpty() or not self._addQueue:IsEmpty())
end

function CullClient.Step(self: any, maxTilesRaw: any, deadlineRaw: any?): number
	if self._destroyed then
		return 0
	end

	local maxTiles = if typeof(maxTilesRaw) == "number" then math.max(1, math.floor(maxTilesRaw)) else 1
	local deadline = if typeof(deadlineRaw) == "number" then deadlineRaw else math.huge
	local processed = 0
	self:_compactQueuesIfNeeded()
	while processed < maxTiles and os.clock() < deadline and self:HasWork() do
		local queuedDesired = self._removeQueue:IsEmpty()
		local tileKey = if queuedDesired then self._addQueue:PopLeft() else self._removeQueue:PopLeft()
		if self._queuedTileStates[tileKey] ~= queuedDesired then
			continue
		end
		self._queuedTileStates[tileKey] = nil
		self._queuedTileCount = math.max(0, self._queuedTileCount - 1)
		local tileX, tileY = self:_unpackTileKey(tileKey)

		local isDesired = CullUtil.ContainsTile(self._desiredBounds, tileX, tileY)
		local isActive = self._activeTileKeys[tileKey] == true
		local force = self._forceTileKeys[tileKey] == true
		self._forceTileKeys[tileKey] = nil

		if isDesired and (not isActive or force) then
			self._renderTile(tileX, tileY)
			if not isActive then
				self._activeTileKeys[tileKey] = true
				self._activeTileCount += 1
			end
		elseif not isDesired and isActive then
			self._clearTile(tileX, tileY)
			self._activeTileKeys[tileKey] = nil
			self._activeTileCount = math.max(0, self._activeTileCount - 1)
		end

		processed += 1
	end

	return processed
end

function CullClient.IsTileVisible(self: any, tileX: number, tileY: number): boolean
	return CullUtil.ContainsTile(self._desiredBounds, tileX, tileY)
end

function CullClient.IsTileActive(self: any, tileX: number, tileY: number): boolean
	return CullUtil.ContainsTile(self._chunkBounds, tileX, tileY)
		and self._activeTileKeys[self:_getTileKey(tileX, tileY)] == true
end

function CullClient.GetChunkBounds(self: any): TileBounds
	return CullUtil.CloneBounds(self._chunkBounds) :: TileBounds
end

function CullClient.GetKey(self: any): string?
	return self._key
end

function CullClient.GetActiveTileCount(self: any): number
	return self._activeTileCount
end

function CullClient.Destroy(self: any)
	if self._destroyed then
		return
	end
	self._destroyed = true

	if self._clearAll ~= nil then
		self._clearAll()
	else
		for tileKey in self._activeTileKeys do
			local tileX, tileY = self:_unpackTileKey(tileKey)
			self._clearTile(tileX, tileY)
		end
	end

	self._desiredBounds = nil
	self._activeTileCount = 0
	self._maid:DoCleaning()
	self._maid = nil
end

return CullClient
