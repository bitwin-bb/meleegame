--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local RecoveryState = {}

function RecoveryState.new(): any
	return State.new({
		Name = "Recovery",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("CombatState", "Recovery")
		end,
		Exit = function(_self: any, machine: any)
			machine:GetBlackboard():Set("QueuedAttack", nil)
		end,
	})
end

return RecoveryState
