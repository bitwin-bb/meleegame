--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(gameRoot.Shared.Goap.Core.Goal)

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
