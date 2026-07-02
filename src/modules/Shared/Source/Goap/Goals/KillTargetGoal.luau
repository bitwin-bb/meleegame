
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local packages = Nevermore.GetRolePackages("Examples")
local Table = packages.Table

local Goal = require("Goal")

local KillTargetGoal = {}

function KillTargetGoal.new(): any
	return Goal.new({
		Name = "KillTarget",
		Priority = 10,
		DesiredState = {
			TargetDead = true,
		},
		CanRun = function(_, agent)
			return agent:GetWorldState("HasTarget") == true
		end,
	})
end

KillTargetGoal.copy = Table.copy

return KillTargetGoal
