
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require("Goal")

local HealSelfGoal = {}

function HealSelfGoal.new(): any
	return Goal.new({
		Name = "HealSelf",
		Priority = 18,
		DesiredState = {
			HealthLow = false,
		},
		CanRun = function(_, agent)
			return agent:GetWorldState("HealthLow") == true
		end,
	})
end

HealSelfGoal.copy = Table.copy

return HealSelfGoal
