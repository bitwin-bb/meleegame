local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Signal = require("Signal")

local BuildServiceUtils = require("BuildServiceUtils")

local TileReplicationService = {}
TileReplicationService.ServiceName = "TileReplicationService"

local function coerceTileId(tileDataRaw: any): number
	if typeof(tileDataRaw) == "table" then
		local tileId = BuildServiceUtils.CoerceTileId((tileDataRaw :: any).TileId or (tileDataRaw :: any).tileId)
		if tileId ~= nil then
			return tileId
		end
	end

	return BuildServiceUtils.CoerceTileId(tileDataRaw) or BuildServiceUtils.AIR_TILE_ID
end

local function cloneDelta(delta: any): any
	return {
		tileX = delta.tileX,
		tileY = delta.tileY,
		tileId = delta.tileId,
		reason = delta.reason,
	}
end

function TileReplicationService.Init(self: any)
	if self._maid ~= nil then
		return
	end

	self._maid = Maid.new()
	self._pendingDeltas = {}
	self._pendingDeltaLookup = {}
	self.tilesChanged = Signal.new()
	self._maid:GiveTask(self.tilesChanged)
end

function TileReplicationService.QueueTileChanged(
	self: any,
	tileXRaw: any,
	tileYRaw: any,
	tileDataRaw: any,
	reasonRaw: any?
): any?
	if self._maid == nil then
		self:Init()
	end

	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return nil
	end

	local key = BuildServiceUtils.PackTileKey(tileX, tileY)
	local reason = if typeof(reasonRaw) == "string" then reasonRaw else "autotile"
	local existingIndex = self._pendingDeltaLookup[key]
	if existingIndex ~= nil then
		local existing = self._pendingDeltas[existingIndex]
		existing.tileId = coerceTileId(tileDataRaw)
		existing.reason = reason
		self.tilesChanged:Fire({ cloneDelta(existing) })
		return cloneDelta(existing)
	end

	local delta = {
		tileX = tileX,
		tileY = tileY,
		tileId = coerceTileId(tileDataRaw),
		reason = reason,
	}
	self._pendingDeltas[#self._pendingDeltas + 1] = delta
	self._pendingDeltaLookup[key] = #self._pendingDeltas
	self.tilesChanged:Fire({ cloneDelta(delta) })
	return cloneDelta(delta)
end

function TileReplicationService.QueueTilesChanged(self: any, deltasRaw: any, reasonRaw: any?): { any }
	local queued = {}
	if typeof(deltasRaw) ~= "table" then
		return queued
	end

	for _, deltaRaw in deltasRaw do
		if typeof(deltaRaw) ~= "table" then
			continue
		end

		local delta = self:QueueTileChanged(
			(deltaRaw :: any).tileX,
			(deltaRaw :: any).tileY,
			(deltaRaw :: any).tileData or (deltaRaw :: any).tileId,
			(deltaRaw :: any).reason or reasonRaw
		)
		if delta ~= nil then
			queued[#queued + 1] = delta
		end
	end

	return queued
end

function TileReplicationService.GetPendingDeltas(self: any): { any }
	local output = {}
	for index, delta in self._pendingDeltas or {} do
		output[index] = cloneDelta(delta)
	end
	return output
end

function TileReplicationService.ConsumeDeltas(self: any): { any }
	local output = self:GetPendingDeltas()
	if self._pendingDeltas ~= nil then
		table.clear(self._pendingDeltas)
	end
	if self._pendingDeltaLookup ~= nil then
		table.clear(self._pendingDeltaLookup)
	end
	return output
end

function TileReplicationService.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	if self._pendingDeltas ~= nil then
		table.clear(self._pendingDeltas)
	end
	if self._pendingDeltaLookup ~= nil then
		table.clear(self._pendingDeltaLookup)
	end
end

return TileReplicationService
