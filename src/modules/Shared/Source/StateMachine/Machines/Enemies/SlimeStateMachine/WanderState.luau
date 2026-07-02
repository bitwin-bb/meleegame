
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

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
