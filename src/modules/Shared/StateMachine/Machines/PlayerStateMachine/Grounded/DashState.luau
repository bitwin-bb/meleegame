
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

local DashState = {}

function DashState.new(): any
	return State.new({
		Name = "Dash",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("MovementState", "Dash")
			blackboard:Set("DashRequested", false)
			blackboard:Set("LastDashTime", os.clock())
		end,
	})
end

return DashState
