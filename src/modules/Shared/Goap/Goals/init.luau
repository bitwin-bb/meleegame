
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Goal = require("Goal"),
	KillTargetGoal = require(script:WaitForChild("KillTargetGoal")),
	SurviveGoal = require(script:WaitForChild("SurviveGoal")),
	PatrolGoal = require(script:WaitForChild("PatrolGoal")),
	RetreatGoal = require(script:WaitForChild("RetreatGoal")),
	HealSelfGoal = require(script:WaitForChild("HealSelfGoal")),
	InvestigateGoal = require(script:WaitForChild("InvestigateGoal")),
})
