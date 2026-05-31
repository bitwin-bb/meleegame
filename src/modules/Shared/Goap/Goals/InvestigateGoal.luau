--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(script:FindFirstAncestor("Goap").Core.Goal)

local InvestigateGoal = {}

function InvestigateGoal.new(): any
	return Goal.new({
		Name = "Investigate",
		Priority = 4,
		DesiredState = {
			Investigated = true,
		},
		CanRun = function(_, agent)
			return agent:GetWorldState("HeardNoise") == true or agent:GetWorldState("SawSuspiciousPoint") == true
		end,
	})
end

InvestigateGoal.copy = Table.copy

return InvestigateGoal
