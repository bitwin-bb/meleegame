
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Integrations")
local Table = packages.Table

local Utils = require("GoapUtils")

local PathfindingAdapter = {}

function PathfindingAdapter.Get(agent: any): any?
	return Utils.ReadBlackboard(agent, "PathfindingAdapter", Utils.ReadBlackboard(agent, "Pathfinding", nil))
end

function PathfindingAdapter.ComputePath(agent: any, destinationRaw: any?): any?
	local pathfinding = PathfindingAdapter.Get(agent)
	local root = Utils.ReadBlackboard(agent, "Root", nil)
	local destination = if destinationRaw ~= nil then destinationRaw else Utils.ReadBlackboard(agent, "Target", nil)
	local ok, result =
		Utils.CallFirst(pathfinding, { "ComputePath", "computePath", "FindPath", "findPath" }, root, destination)
	if ok and result ~= nil then
		agent:GetBlackboard():Set("Path", result)
		return result
	end
	return nil
end

PathfindingAdapter.copy = Table.copy
PathfindingAdapter.get = PathfindingAdapter.Get
PathfindingAdapter.computePath = PathfindingAdapter.ComputePath

return PathfindingAdapter
