local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Rx = require("Rx")
local Signal = require("Signal")

local BuildServiceUtils = require("BuildServiceUtils")

local TileWorldService = {}
TileWorldService.ServiceName = "TileWorldService"

local function getTileKey(tileX: number, tileY: number): string
	return BuildServiceUtils.PackTileKey(tileX, tileY)
end

local function cloneTileData(tileDataRaw: any): any?
	if typeof(tileDataRaw) ~= "table" then
		return nil
	end

	return table.clone(tileDataRaw)
end

local function coerceTileData(tileDataRaw: any): any?
	local tileIdRaw = tileDataRaw
	if typeof(tileDataRaw) == "table" then
		tileIdRaw = (tileDataRaw :: any).TileId or (tileDataRaw :: any).tileId
	end

	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileId == nil or tileId == BuildServiceUtils.AIR_TILE_ID then
		return nil
	end

	if typeof(tileDataRaw) == "table" then
		local clone = table.clone(tileDataRaw)
		clone.TileId = tileId
		clone.tileId = nil
		return clone
	end

	return {
		TileId = tileId,
	}
end

local function tileDataEquals(leftRaw: any, rightRaw: any): boolean
	local leftTileId = if typeof(leftRaw) == "table" then (leftRaw :: any).TileId else nil
	local rightTileId = if typeof(rightRaw) == "table" then (rightRaw :: any).TileId else nil
	local leftConnectGroup = if typeof(leftRaw) == "table" then (leftRaw :: any).ConnectGroup else nil
	local rightConnectGroup = if typeof(rightRaw) == "table" then (rightRaw :: any).ConnectGroup else nil
	return leftTileId == rightTileId and leftConnectGroup == rightConnectGroup
end

function TileWorldService.Init(self: any)
	if self._maid ~= nil then
		return
	end

	self._maid = Maid.new()
	self._tiles = {}
	self.tileChanged = Signal.new()
	self._maid:GiveTask(self.tileChanged)
	self._tileChangedObservable = Rx.fromSignal(self.tileChanged):Pipe({
		Rx.share(),
	})
end

function TileWorldService.ObserveTileChanged(self: any): any
	if self._maid == nil then
		self:Init()
	end
	return self._tileChangedObservable
end

function TileWorldService.GetTile(self: any, tileXRaw: any, tileYRaw: any): any?
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return nil
	end

	return cloneTileData(self._tiles[getTileKey(tileX, tileY)])
end

function TileWorldService.GetTileId(self: any, tileXRaw: any, tileYRaw: any): number
	local tileData = self:GetTile(tileXRaw, tileYRaw)
	if tileData == nil then
		return BuildServiceUtils.AIR_TILE_ID
	end

	return (tileData :: any).TileId or BuildServiceUtils.AIR_TILE_ID
end

function TileWorldService.SetTile(self: any, tileXRaw: any, tileYRaw: any, tileDataRaw: any): (boolean, any?, any?)
	if self._maid == nil then
		self:Init()
	end

	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return false, nil, nil
	end

	local key = getTileKey(tileX, tileY)
	local previousTileData = self._tiles[key]
	local nextTileData = coerceTileData(tileDataRaw)
	if tileDataEquals(previousTileData, nextTileData) then
		return false, cloneTileData(previousTileData), cloneTileData(nextTileData)
	end

	self._tiles[key] = nextTileData
	self.tileChanged:Fire(tileX, tileY, cloneTileData(nextTileData), cloneTileData(previousTileData))
	return true, cloneTileData(previousTileData), cloneTileData(nextTileData)
end

function TileWorldService.GetTileAtCoord(self: any, coordRaw: any): any?
	if typeof(coordRaw) ~= "Vector2" then
		return nil
	end

	return self:GetTile(coordRaw.X, coordRaw.Y)
end

function TileWorldService.SetTileAtCoord(self: any, coordRaw: any, tileDataRaw: any): (boolean, any?, any?)
	if typeof(coordRaw) ~= "Vector2" then
		return false, nil, nil
	end

	return self:SetTile(coordRaw.X, coordRaw.Y, tileDataRaw)
end

function TileWorldService.Clear(self: any)
	if self._tiles ~= nil then
		table.clear(self._tiles)
	end
end

function TileWorldService.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end

	if self._tiles ~= nil then
		table.clear(self._tiles)
	end
	self._tileChangedObservable = nil
end

return TileWorldService
