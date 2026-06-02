--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

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
