local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local EightWayBlobRule = {}

EightWayBlobRule.Mode = "EightWayBlob"
EightWayBlobRule.IncludeDiagonals = true

local function getTileId(tileRaw: any): number?
	if typeof(tileRaw) ~= "table" then
		return nil
	end

	local tileId = (tileRaw :: any).TileId or (tileRaw :: any).tileId or (tileRaw :: any).id
	if typeof(tileId) ~= "number" then
		return nil
	end
	return math.floor(tileId)
end

local function getConnectGroup(tileRaw: any): string?
	if typeof(tileRaw) ~= "table" then
		return nil
	end

	local connectGroup = (tileRaw :: any).ConnectGroup or (tileRaw :: any).connectGroup
	if typeof(connectGroup) ~= "string" or connectGroup == "" then
		return nil
	end
	return connectGroup
end

function EightWayBlobRule.Connects(tileRaw: any, neighborRaw: any): boolean
	local tileId = getTileId(tileRaw)
	local neighborTileId = getTileId(neighborRaw)
	if tileId == nil or neighborTileId == nil then
		return false
	end

	if tileId == neighborTileId then
		return true
	end

	local connectGroup = getConnectGroup(tileRaw)
	local neighborConnectGroup = getConnectGroup(neighborRaw)
	return connectGroup ~= nil and connectGroup == neighborConnectGroup
end

return Table.readonly(EightWayBlobRule)
