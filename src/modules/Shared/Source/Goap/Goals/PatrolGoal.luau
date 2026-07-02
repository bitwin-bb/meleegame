
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require("Goal")

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
