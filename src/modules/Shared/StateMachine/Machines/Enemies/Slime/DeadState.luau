--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local DeadState = {}

function DeadState.new(): any
	return State.new({
		Name = "Dead",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("EnemyState", "Dead")
			blackboard:Set("IsDead", true)
		end,
		CanExit = function(): boolean
			return false
		end,
	})
end

return DeadState
