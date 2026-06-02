--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(gameRoot.Shared.Goap.Core.Goal)

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
