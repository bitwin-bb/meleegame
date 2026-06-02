--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local AbilityAdapter = require(gameRoot.Shared.Goap.Integrations.AbilityAdapter)
local Action = require(gameRoot.Shared.Goap.Core.Action)

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
