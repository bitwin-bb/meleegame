--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Action = require(gameRoot.Shared.Goap.Core.Action)
local CombatAdapter = require(gameRoot.Shared.Goap.Integrations.CombatAdapter)
local StateMachineAdapter = require(gameRoot.Shared.Goap.Integrations.StateMachineAdapter)

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
