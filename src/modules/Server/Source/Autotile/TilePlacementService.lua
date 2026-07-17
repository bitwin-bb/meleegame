local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

local AutotileRegistry = require("AutotileRegistry")
local AutotileService = require("AutotileService")
local BuildServiceUtils = require("BuildServiceUtils")
local TileWorldService = require("TileWorldService")

local TilePlacementService = {}
TilePlacementService.ServiceName = "TilePlacementService"

local function coerceTileData(tileDataRaw: any): any?
	local tileIdRaw = tileDataRaw
	if typeof(tileDataRaw) == "table" then
		tileIdRaw = (tileDataRaw :: any).TileId or (tileDataRaw :: any).tileId
	end

	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileId == nil then
		return nil
	end

	if typeof(tileDataRaw) == "table" then
		local clone = table.clone(tileDataRaw)
		clone.TileId = tileId
		clone.tileId = nil
		local definition = AutotileRegistry.GetDefinition(tileId)
		if definition ~= nil and clone.ConnectGroup == nil then
			clone.ConnectGroup = (definition :: any).ConnectGroup
		end
		return clone
	end

	local definition = AutotileRegistry.GetDefinition(tileId)
	return {
		TileId = tileId,
		ConnectGroup = if definition ~= nil then (definition :: any).ConnectGroup else nil,
	}
end

function TilePlacementService.Init(self: any, _serviceBag: any?)
	if self._maid ~= nil then
		return
	end

	TileWorldService:Init()
	AutotileService:Init()
	self._maid = Maid.new()
end

function TilePlacementService.CanPlaceTile(
	_self: any,
	_player: Player?,
	tileXRaw: any,
	tileYRaw: any,
	tileDataRaw: any
): (boolean, string)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	local tileData = coerceTileData(tileDataRaw)
	if tileX == nil or tileY == nil or tileData == nil then
		return false, "invalid_tile_coordinate_or_id"
	end

	return true, "ok"
end

function TilePlacementService.SetTile(self: any, tileXRaw: any, tileYRaw: any, tileDataRaw: any): (boolean, string)
	if self._maid == nil then
		self:Init()
	end

	local canPlace, reason = self:CanPlaceTile(nil, tileXRaw, tileYRaw, tileDataRaw)
	if not canPlace then
		return false, reason
	end

	local tileData = coerceTileData(tileDataRaw)
	local changed = TileWorldService:SetTile(tileXRaw, tileYRaw, tileData)
	if not changed then
		return false, "no_change"
	end

	return true, "ok"
end

function TilePlacementService.PlaceTile(
	self: any,
	player: Player?,
	tileXRaw: any,
	tileYRaw: any,
	tileDataRaw: any
): (boolean, string)
	local canPlace, reason = self:CanPlaceTile(player, tileXRaw, tileYRaw, tileDataRaw)
	if not canPlace then
		return false, reason
	end

	return self:SetTile(tileXRaw, tileYRaw, tileDataRaw)
end

function TilePlacementService.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
end

return TilePlacementService
