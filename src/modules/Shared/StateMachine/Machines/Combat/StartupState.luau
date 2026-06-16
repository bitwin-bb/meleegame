
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

local StartupState = {}

function StartupState.new(): any
	return State.new({
		Name = "Startup",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("CombatState", "Startup")
			blackboard:Set("AttackRequested", false)
		end,
	})
end

return StartupState
