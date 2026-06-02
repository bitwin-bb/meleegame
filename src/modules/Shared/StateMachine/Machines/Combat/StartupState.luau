--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local State = require(gameRoot.Shared.StateMachine.Core.State)

local StartupState = {}

function StartupState.new(): any
	return State.new({
		Name = "Startup",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("CombatState", "Startup")
			blackboard:Set("AttackRequested", false)
		end,
	})
end

return StartupState
