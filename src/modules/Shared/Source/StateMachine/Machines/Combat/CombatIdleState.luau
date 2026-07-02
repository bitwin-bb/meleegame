
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

local IdleState = {}

function IdleState.new(): any
	return State.new({
		Name = "Idle",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("CombatState", "Idle")
		end,
	})
end

return IdleState
