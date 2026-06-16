
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require("Goal")

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
