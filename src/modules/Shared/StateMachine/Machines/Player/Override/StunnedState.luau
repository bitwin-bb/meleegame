--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local StunnedState = {}

function StunnedState.new(): any
	return State.new({
		Name = "Stunned",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("OverrideState", "Stunned")
		end,
		Exit = function(_self: any, machine: any)
			machine:GetBlackboard():Set("OverrideState", nil)
		end,
	})
end

return StunnedState
