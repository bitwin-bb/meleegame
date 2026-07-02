
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require("GoapAction")
local MovementAdapter = require("GoapMovementAdapter")
local StateMachineAdapter = require("StateMachineAdapter")

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
