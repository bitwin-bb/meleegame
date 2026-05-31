--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require(script:FindFirstAncestor("Goap").Core.Action)
local MovementAdapter = require(script:FindFirstAncestor("Goap").Integrations.MovementAdapter)
local StateMachineAdapter = require(script:FindFirstAncestor("Goap").Integrations.StateMachineAdapter)

local FleeAction = {}

function FleeAction.new(): any
	return Action.new({
		Name = "Flee",
		Cost = 2,
		Preconditions = {
			HealthLow = true,
		},
		Effects = {
			IsSafe = true,
			TargetInRange = false,
		},
		Start = function(_, agent)
			StateMachineAdapter.ChangeState(agent, "Flee")
			MovementAdapter.Flee(agent)
		end,
	})
end

FleeAction.copy = Table.copy

return FleeAction
