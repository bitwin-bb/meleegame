
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

local RecoveryState = {}

function RecoveryState.new(): any
	return State.new({
		Name = "Recovery",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("CombatState", "Recovery")
		end,
		Exit = function(_self: any, machine: any)
			machine:GetBlackboard():Set("QueuedAttack", nil)
		end,
	})
end

return RecoveryState
