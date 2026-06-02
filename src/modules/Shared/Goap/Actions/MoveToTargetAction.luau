--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require(gameRoot.Shared.Goap.Core.Action)
local MovementAdapter = require(gameRoot.Shared.Goap.Integrations.MovementAdapter)
local StateMachineAdapter = require(gameRoot.Shared.Goap.Integrations.StateMachineAdapter)

local MoveToTargetAction = {}

function MoveToTargetAction.new(): any
	return Action.new({
		Name = "MoveToTarget",
		Cost = 2,
		Preconditions = {
			HasTarget = true,
		},
		Effects = {
			TargetInRange = true,
		},
		Start = function(_, agent)
			StateMachineAdapter.ChangeState(agent, "Chase")
			MovementAdapter.MoveToTarget(agent)
		end,
		IsFinished = function(_, agent)
			return agent:GetWorldState("TargetInRange") == true
		end,
	})
end

MoveToTargetAction.copy = Table.copy

return MoveToTargetAction
