--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

local ChaseState = {}

function ChaseState.new(): any
	return State.new({
		Name = "Chase",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("EnemyState", "Chase")
		end,
	})
end

return ChaseState
