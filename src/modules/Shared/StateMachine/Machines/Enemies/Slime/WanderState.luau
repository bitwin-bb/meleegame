--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local WanderState = {}

function WanderState.new(): any
	return State.new({
		Name = "Wander",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("EnemyState", "Wander")
		end,
	})
end

return WanderState
