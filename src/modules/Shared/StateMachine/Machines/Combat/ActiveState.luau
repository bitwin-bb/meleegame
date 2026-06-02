--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local SpawnHitboxAction = require(gameRoot.Shared.StateMachine.Actions.SpawnHitboxAction)
local State = require(gameRoot.Shared.StateMachine.Core.State)

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
