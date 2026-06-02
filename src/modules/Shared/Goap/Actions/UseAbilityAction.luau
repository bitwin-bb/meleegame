--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local AbilityAdapter = require(gameRoot.Shared.Goap.Integrations.AbilityAdapter)
local Action = require(gameRoot.Shared.Goap.Core.Action)
local StateMachineAdapter = require(gameRoot.Shared.Goap.Integrations.StateMachineAdapter)

local UseAbilityAction = {}

function UseAbilityAction.new(abilityNameRaw: any?): any
	local abilityName = if typeof(abilityNameRaw) == "string" and abilityNameRaw ~= ""
		then abilityNameRaw
		else "Primary"
	return Action.new({
		Name = "UseAbility",
		Cost = 2,
		Preconditions = {
			HasTarget = true,
			CanUseAbility = true,
		},
		Effects = {
			AbilityUsed = true,
		},
		Start = function(_, agent)
			StateMachineAdapter.ChangeState(agent, "Ability")
			AbilityAdapter.UseAbility(agent, abilityName)
		end,
	})
end

UseAbilityAction.copy = Table.copy

return UseAbilityAction
