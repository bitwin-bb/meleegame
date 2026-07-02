
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Integrations")
local Table = packages.Table

local Utils = require("GoapUtils")

local MovementAdapter = {}

function MovementAdapter.Get(agent: any): any?
	return Utils.ReadBlackboard(agent, "MovementAdapter", Utils.ReadBlackboard(agent, "Movement", nil))
end

function MovementAdapter.MoveToTarget(agent: any): boolean
	local movement = MovementAdapter.Get(agent)
	local target = Utils.ReadBlackboard(agent, "Target", nil)
	local root = Utils.ReadBlackboard(agent, "Root", nil)
	local ok = Utils.CallFirst(
		movement,
		{ "MoveToTarget", "moveToTarget", "MoveTo", "moveTo", "SetTarget", "setTarget" },
		target,
		root
	)
	return ok or target ~= nil
end

function MovementAdapter.Flee(agent: any): boolean
	local movement = MovementAdapter.Get(agent)
	local target = Utils.ReadBlackboard(agent, "Target", nil)
	local ok = Utils.CallFirst(movement, { "Flee", "flee", "MoveAwayFrom", "moveAwayFrom" }, target)
	return ok or target ~= nil
end

function MovementAdapter.Patrol(agent: any): boolean
	local movement = MovementAdapter.Get(agent)
	local path = Utils.ReadBlackboard(agent, "PatrolPath", nil)
	local ok = Utils.CallFirst(movement, { "Patrol", "patrol", "FollowPath", "followPath" }, path)
	return ok or path ~= nil
end

MovementAdapter.copy = Table.copy
return MovementAdapter
