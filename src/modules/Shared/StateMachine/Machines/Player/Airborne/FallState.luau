--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local FallState = {}

function FallState.new(): any
	return State.new({
		Name = "Fall",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("MovementState", "Fall")
		end,
	})
end

return FallState
