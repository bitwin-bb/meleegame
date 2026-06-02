--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require(gameRoot.Shared.Goap.Core.Action)
local MovementAdapter = require(gameRoot.Shared.Goap.Integrations.MovementAdapter)
local StateMachineAdapter = require(gameRoot.Shared.Goap.Integrations.StateMachineAdapter)

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
