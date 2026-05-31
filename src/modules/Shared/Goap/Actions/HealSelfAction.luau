--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local AbilityAdapter = require(script:FindFirstAncestor("Goap").Integrations.AbilityAdapter)
local Action = require(script:FindFirstAncestor("Goap").Core.Action)

local HealSelfAction = {}

function HealSelfAction.new(): any
	return Action.new({
		Name = "HealSelf",
		Cost = 2,
		Preconditions = {
			HealthLow = true,
		},
		Effects = {
			HealthLow = false,
			IsSafe = true,
		},
		Start = function(_, agent)
			AbilityAdapter.UseAbility(agent, "HealSelf")
		end,
	})
end

HealSelfAction.copy = Table.copy

return HealSelfAction
