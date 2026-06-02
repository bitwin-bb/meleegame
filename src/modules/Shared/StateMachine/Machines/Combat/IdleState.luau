--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

local IdleState = {}

function IdleState.new(): any
	return State.new({
		Name = "Idle",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("CombatState", "Idle")
		end,
	})
end

return IdleState
