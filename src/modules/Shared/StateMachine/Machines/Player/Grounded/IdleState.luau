--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local IdleState = {}

function IdleState.new(): any
	return State.new({
		Name = "Idle",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("MovementState", "Idle")
		end,
	})
end

return IdleState
