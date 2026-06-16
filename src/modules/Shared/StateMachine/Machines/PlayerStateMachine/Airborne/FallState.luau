
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

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
