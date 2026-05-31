--!strict

local SpawnHitboxAction = require(script:FindFirstAncestor("StateMachine").Actions.SpawnHitboxAction)
local State = require(script:FindFirstAncestor("StateMachine").Core.State)

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
