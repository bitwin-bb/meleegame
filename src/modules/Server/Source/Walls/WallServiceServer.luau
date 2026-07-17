local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Signal = require("Signal")

local WallServiceUtils = require("WallServiceUtils")
local WorldGenerationServiceServer = require("WorldGenerationServiceServer")

local WallServiceServer = {}
WallServiceServer.ServiceName = "WallServiceServer"

function WallServiceServer.Init(self: any, _serviceBag: any)
	if self._maid ~= nil then
		return
	end
	self._maid = Maid.new()
	self.wallChanged = Signal.new()
	self._maid:GiveTask(self.wallChanged)
	self._maid:GiveTask(WorldGenerationServiceServer:GetWorld():ObserveChunkWallChanged():Subscribe(function(event: any)
		if self.wallChanged ~= nil then
			self.wallChanged:Fire(event)
		end
	end))
end

function WallServiceServer.GetWallAt(_self: any, tileXRaw: any, tileYRaw: any): number
	return WorldGenerationServiceServer:GetWorld():GetWallAt(tileXRaw, tileYRaw)
end

function WallServiceServer.CanBreakWall(
	_self: any,
	wallIdRaw: any,
	toolTypeRaw: any,
	toolPowerRaw: any?
): (boolean, string?)
	return WallServiceUtils.CanBreakWall(wallIdRaw, toolTypeRaw, toolPowerRaw)
end

function WallServiceServer.SetWallAt(
	_self: any,
	tileXRaw: any,
	tileYRaw: any,
	wallIdRaw: any
): (boolean, number, number)
	return WorldGenerationServiceServer:SetWallAt(tileXRaw, tileYRaw, wallIdRaw)
end

-- Server-internal entry point; callers must supply tool data already verified by server inventory authority.
function WallServiceServer.TryBreakWallAt(
	self: any,
	tileXRaw: any,
	tileYRaw: any,
	toolTypeRaw: any,
	toolPowerRaw: any?
): (boolean, string?, number)
	local wallId = self:GetWallAt(tileXRaw, tileYRaw)
	local canBreak, reason = self:CanBreakWall(wallId, toolTypeRaw, toolPowerRaw)
	if not canBreak then
		return false, reason, wallId
	end

	local changed, previousWallId = self:SetWallAt(tileXRaw, tileYRaw, WallServiceUtils.WALL_ID.NONE)
	return changed, if changed then nil else "unchanged", previousWallId
end

function WallServiceServer.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self.wallChanged = nil
end

return WallServiceServer
