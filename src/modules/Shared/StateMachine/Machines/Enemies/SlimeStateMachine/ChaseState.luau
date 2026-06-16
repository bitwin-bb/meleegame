
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

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
