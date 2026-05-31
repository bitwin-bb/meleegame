--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(script:FindFirstAncestor("Goap").Core.Goal)

local SurviveGoal = {}

function SurviveGoal.new(): any
	return Goal.new({
		Name = "Survive",
		Priority = 20,
		DesiredState = {
			IsSafe = true,
		},
		CanRun = function(_, agent)
			return agent:GetWorldState("HealthLow") == true
		end,
	})
end

SurviveGoal.copy = Table.copy

return SurviveGoal
