local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local WallServiceUtils = {}

WallServiceUtils.WALL_ID = Table.readonly({
	NONE = 0,
	DIRT = 1,
	STONE = 2,
	SANDSTONE = 3,
	SNOW = 4,
	MUD = 5,
})

WallServiceUtils.MAX_WALL_ID = WallServiceUtils.WALL_ID.MUD
WallServiceUtils.ToolTypes = Table.readonly({
	Hammer = "hammer",
	Pickaxe = "pickaxe",
})
WallServiceUtils.BreakReasons = Table.readonly({
	NoWall = "no_wall",
	InvalidWall = "invalid_wall",
	RequiresHammer = "requires_hammer",
	InsufficientHammerPower = "insufficient_hammer_power",
})

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function WallServiceUtils.CoerceWallId(wallIdRaw: any): number?
	if not isFiniteNumber(wallIdRaw) then
		return nil
	end

	local wallId = math.floor(wallIdRaw :: number)
	if wallId < WallServiceUtils.WALL_ID.NONE or wallId > WallServiceUtils.MAX_WALL_ID then
		return nil
	end
	return wallId
end

function WallServiceUtils.NormalizeToolType(toolTypeRaw: any): string?
	if typeof(toolTypeRaw) ~= "string" then
		return nil
	end

	local stripped = string.gsub(toolTypeRaw, "%s+", "")
	local normalized = string.lower(stripped)
	return if normalized ~= "" then normalized else nil
end

function WallServiceUtils.CanBreakWall(wallIdRaw: any, toolTypeRaw: any, toolPowerRaw: any?): (boolean, string?)
	local wallId = WallServiceUtils.CoerceWallId(wallIdRaw)
	if wallId == nil then
		return false, WallServiceUtils.BreakReasons.InvalidWall
	end
	if wallId == WallServiceUtils.WALL_ID.NONE then
		return false, WallServiceUtils.BreakReasons.NoWall
	end
	if WallServiceUtils.NormalizeToolType(toolTypeRaw) ~= WallServiceUtils.ToolTypes.Hammer then
		return false, WallServiceUtils.BreakReasons.RequiresHammer
	end
	if toolPowerRaw ~= nil and (not isFiniteNumber(toolPowerRaw) or (toolPowerRaw :: number) <= 0) then
		return false, WallServiceUtils.BreakReasons.InsufficientHammerPower
	end
	return true, nil
end

return Table.readonly(WallServiceUtils)
