--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require(gameRoot.Shared.Goap.Core.Goal)

local PatrolGoal = {}

function PatrolGoal.new(): any
	return Goal.new({
		Name = "Patrol",
		Priority = 1,
		DesiredState = {
			Patrolling = true,
		},
		CanRun = function(_, agent)
			return agent:GetWorldState("HasTarget") ~= true
		end,
	})
end

PatrolGoal.copy = Table.copy

return PatrolGoal
