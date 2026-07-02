
local require = require(script.Parent.loader).load(script)

local SpawnHitboxAction = require("SpawnHitboxAction")
local State = require("StateMachineState")

local ActiveState = {}

function ActiveState.new(): any
	return State.new({
		Name = "Active",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("CombatState", "Active")
			SpawnHitboxAction.Perform(machine, machine:GetBlackboard():Get("HitboxConfig"))
		end,
	})
end

return ActiveState
