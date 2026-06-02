--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

local HurtState = {}

function HurtState.new(): any
	return State.new({
		Name = "Hurt",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("EnemyState", "Hurt")
			blackboard:Set("TookDamage", false)
		end,
	})
end

return HurtState
