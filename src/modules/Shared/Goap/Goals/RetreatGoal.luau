--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(script:FindFirstAncestor("Goap").Core.Goal)

local RetreatGoal = {}

function RetreatGoal.new(): any
	return Goal.new({
		Name = "Retreat",
		Priority = 15,
		DesiredState = {
			IsSafe = true,
			TargetInRange = false,
		},
		CanRun = function(_, agent)
			return agent:GetWorldState("HealthLow") == true or agent:GetWorldState("ThreatHigh") == true
		end,
	})
end

RetreatGoal.copy = Table.copy

return RetreatGoal
