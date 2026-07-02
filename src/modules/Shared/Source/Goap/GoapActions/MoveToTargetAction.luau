
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require("GoapAction")
local MovementAdapter = require("GoapMovementAdapter")
local StateMachineAdapter = require("StateMachineAdapter")

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
