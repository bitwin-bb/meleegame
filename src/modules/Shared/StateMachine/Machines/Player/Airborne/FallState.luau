--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

local FallState = {}

function FallState.new(): any
	return State.new({
		Name = "Fall",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("MovementState", "Fall")
		end,
	})
end

return FallState
