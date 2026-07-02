
local require = require(script.Parent.loader).load(script)

local ApplyKnockbackAction = require("ApplyKnockbackAction")
local State = require("StateMachineState")

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
