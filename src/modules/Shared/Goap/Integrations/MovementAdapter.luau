--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Integrations")
local Table = packages.Table

local Utils = require(script:FindFirstAncestor("Goap").Utils)

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
MovementAdapter.get = MovementAdapter.Get
MovementAdapter.moveToTarget = MovementAdapter.MoveToTarget
MovementAdapter.flee = MovementAdapter.Flee
MovementAdapter.patrol = MovementAdapter.Patrol

return MovementAdapter
