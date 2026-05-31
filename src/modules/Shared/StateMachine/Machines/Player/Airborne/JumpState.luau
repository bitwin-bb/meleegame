--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local JumpState = {}

function JumpState.new(): any
	return State.new({
		Name = "Jump",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("MovementState", "Jump")
			blackboard:Set("JumpRequested", false)
		end,
	})
end

return JumpState
