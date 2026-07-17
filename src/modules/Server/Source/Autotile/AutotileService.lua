local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Rx = require("Rx")
local Signal = require("Signal")

local BuildServiceUtils = require("BuildServiceUtils")
local TileReplicationService = require("TileReplicationService")
local TileWorldService = require("TileWorldService")

local AutotileService = {}
AutotileService.ServiceName = "AutotileService"

local function cloneCoord(coord: any): any
	return {
		tileX = coord.tileX,
		tileY = coord.tileY,
	}
end

function AutotileService.Init(self: any, _serviceBag: any?)
	if self._maid ~= nil then
		return
	end

	TileWorldService:Init()
	TileReplicationService:Init()

	self._maid = Maid.new()
	self._dirtyTiles = {}
	self._dirtyTileLookup = {}
	self.dirtyTilesChanged = Signal.new()
	self._dirtyTilesStateChanged = Signal.new()
	self._maid:GiveTask(self.dirtyTilesChanged)
	self._maid:GiveTask(self._dirtyTilesStateChanged)
	self._dirtyTilesObservable = Rx.fromSignal(self._dirtyTilesStateChanged):Pipe({
		Rx.throttleDefer(),
		Rx.map(function()
			return self:GetDirtyTiles()
		end),
		Rx.startWith({ self:GetDirtyTiles() }),
		Rx.shareReplay(1),
	})
	self._maid:GiveTask(TileWorldService:ObserveTileChanged():Subscribe(function(tileX: number, tileY: number, nextTileData: any?)
		self:OnTileChanged(tileX, tileY, nextTileData)
	end))
end

function AutotileService.ObserveDirtyTiles(self: any): any
	if self._maid == nil then
		self:Init()
	end
	return self._dirtyTilesObservable
end

function AutotileService.MarkDirty(self: any, tileXRaw: any, tileYRaw: any): boolean
	if self._maid == nil then
		self:Init()
	end

	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return false
	end

	local key = BuildServiceUtils.PackTileKey(tileX, tileY)
	if self._dirtyTileLookup[key] == true then
		return false
	end

	local coord = {
		tileX = tileX,
		tileY = tileY,
	}
	self._dirtyTileLookup[key] = true
	self._dirtyTiles[#self._dirtyTiles + 1] = coord
	self._dirtyTilesStateChanged:Fire()
	return true
end

function AutotileService.MarkDirtyAround(self: any, tileXRaw: any, tileYRaw: any): { any }
	local changed = {}
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return changed
	end

	for offsetX = -1, 1 do
		for offsetY = -1, 1 do
			if self:MarkDirty(tileX + offsetX, tileY + offsetY) then
				changed[#changed + 1] = {
					tileX = tileX + offsetX,
					tileY = tileY + offsetY,
				}
			end
		end
	end

	if #changed > 0 then
		self.dirtyTilesChanged:Fire(changed)
	end
	return changed
end

function AutotileService.OnTileChanged(self: any, tileX: number, tileY: number, nextTileData: any?)
	self:MarkDirtyAround(tileX, tileY)
	TileReplicationService:QueueTileChanged(tileX, tileY, nextTileData, "autotile")
end

function AutotileService.GetDirtyTiles(self: any): { any }
	local output = {}
	for index, coord in self._dirtyTiles or {} do
		output[index] = cloneCoord(coord)
	end
	return output
end

function AutotileService.ConsumeDirtyTiles(self: any): { any }
	local output = self:GetDirtyTiles()
	if self._dirtyTiles ~= nil then
		table.clear(self._dirtyTiles)
	end
	if self._dirtyTileLookup ~= nil then
		table.clear(self._dirtyTileLookup)
	end
	if self._dirtyTilesStateChanged ~= nil then
		self._dirtyTilesStateChanged:Fire()
	end
	return output
end

function AutotileService.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	if self._dirtyTiles ~= nil then
		table.clear(self._dirtyTiles)
	end
	if self._dirtyTileLookup ~= nil then
		table.clear(self._dirtyTileLookup)
	end
	self._dirtyTilesObservable = nil
	self._dirtyTilesStateChanged = nil
end

return AutotileService
