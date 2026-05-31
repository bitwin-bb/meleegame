--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(script:FindFirstAncestor("Goap").Core.Goal)

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
