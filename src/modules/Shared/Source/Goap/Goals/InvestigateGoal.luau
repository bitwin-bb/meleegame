
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require("Goal")

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
