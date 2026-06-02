--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local ApplyKnockbackAction = require(gameRoot.Shared.StateMachine.Actions.ApplyKnockbackAction)
local State = require(gameRoot.Shared.StateMachine.Core.State)

local KnockbackState = {}

function KnockbackState.new(): any
	return State.new({
		Name = "Knockback",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("OverrideState", "Knockback")
			ApplyKnockbackAction.Perform(machine, nil)
		end,
		Exit = function(_self: any, machine: any)
			machine:GetBlackboard():Set("OverrideState", nil)
		end,
	})
end

return KnockbackState
