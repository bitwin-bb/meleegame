--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require(gameRoot.Shared.Goap.Core.Action)
local MovementAdapter = require(gameRoot.Shared.Goap.Integrations.MovementAdapter)
local StateMachineAdapter = require(gameRoot.Shared.Goap.Integrations.StateMachineAdapter)

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
