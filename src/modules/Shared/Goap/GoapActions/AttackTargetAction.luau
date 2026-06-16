
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require("GoapAction")
local CombatAdapter = require("CombatAdapter")
local StateMachineAdapter = require("StateMachineAdapter")

local AttackTargetAction = {}

function AttackTargetAction.new(): any
	return Action.new({
		Name = "AttackTarget",
		Cost = 1,
		Preconditions = {
			HasTarget = true,
			TargetInRange = true,
			CanAttack = true,
		},
		Effects = {
			TargetDead = true,
		},
		Start = function(_, agent)
			StateMachineAdapter.ChangeState(agent, "Attack")
			CombatAdapter.AttackTarget(agent)
		end,
	})
end

AttackTargetAction.copy = Table.copy

return AttackTargetAction
