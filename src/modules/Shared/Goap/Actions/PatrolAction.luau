--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require(script:FindFirstAncestor("Goap").Core.Action)
local MovementAdapter = require(script:FindFirstAncestor("Goap").Integrations.MovementAdapter)
local StateMachineAdapter = require(script:FindFirstAncestor("Goap").Integrations.StateMachineAdapter)

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
