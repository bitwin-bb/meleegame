--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

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
