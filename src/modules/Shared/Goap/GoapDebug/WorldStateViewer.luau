
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Debug")
local Table = packages.Table

local Utils = require("GoapUtils")

local WorldStateViewer = {}

local function readValues(worldState: any): { [string]: any }
	if typeof(worldState) ~= "table" then
		return {}
	end
	local toTable = worldState.ToTable or worldState.toTable
	if typeof(toTable) == "function" then
		return toTable(worldState)
	end
	return Table.copy(worldState)
end

function WorldStateViewer.ToLines(worldState: any): { string }
	local values = readValues(worldState)
	local keys = {}
	for key in values do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local lines = {}
	for _, key in keys do
		lines[#lines + 1] = string.format("%s = %s", key, Utils.FormatValue(values[key]))
	end
	return lines
end

function WorldStateViewer.ToString(worldState: any): string
	return table.concat(WorldStateViewer.ToLines(worldState), "\n")
end

WorldStateViewer.copy = Table.copy
return WorldStateViewer
