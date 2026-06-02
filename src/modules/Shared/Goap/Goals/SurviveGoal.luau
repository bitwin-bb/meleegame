--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(gameRoot.Shared.Goap.Core.Goal)

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
