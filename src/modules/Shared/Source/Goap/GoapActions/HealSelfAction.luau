
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local AbilityAdapter = require("AbilityAdapter")
local Action = require("GoapAction")

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
