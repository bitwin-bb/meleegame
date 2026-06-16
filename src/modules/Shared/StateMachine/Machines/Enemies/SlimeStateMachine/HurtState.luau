
local require = require(script.Parent.loader).load(script)

local State = require("StateMachineState")

local HurtState = {}

function HurtState.new(): any
	return State.new({
		Name = "Hurt",
		Enter = function(_self: any, machine: any)
			local blackboard = machine:GetBlackboard()
			blackboard:Set("EnemyState", "Hurt")
			blackboard:Set("TookDamage", false)
		end,
	})
end

return HurtState
