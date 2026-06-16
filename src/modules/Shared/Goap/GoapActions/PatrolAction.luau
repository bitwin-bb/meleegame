
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require("GoapAction")
local MovementAdapter = require("GoapMovementAdapter")
local StateMachineAdapter = require("StateMachineAdapter")

local PatrolAction = {}

function PatrolAction.new(): any
	return Action.new({
		Name = "Patrol",
		Cost = 1,
		Effects = {
			Patrolling = true,
		},
		Start = function(_, agent)
			StateMachineAdapter.ChangeState(agent, "Patrol")
			MovementAdapter.Patrol(agent)
		end,
	})
end

PatrolAction.copy = Table.copy

return PatrolAction
