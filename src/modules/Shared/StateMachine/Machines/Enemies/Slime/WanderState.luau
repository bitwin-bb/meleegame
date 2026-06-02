--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

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
