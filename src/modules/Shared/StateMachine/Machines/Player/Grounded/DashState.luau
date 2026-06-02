--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

local DashState = {}

function DashState.new(): any
	return State.new({
		Name = "Dash",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("MovementState", "Dash")
			blackboard:Set("DashRequested", false)
			blackboard:Set("LastDashTime", os.clock())
		end,
	})
end

return DashState
