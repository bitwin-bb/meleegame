
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Goal = require("Goal"),
	KillTargetGoal = require("KillTargetGoal"),
	SurviveGoal = require("SurviveGoal"),
	PatrolGoal = require("PatrolGoal"),
	RetreatGoal = require("RetreatGoal"),
	HealSelfGoal = require("HealSelfGoal"),
	InvestigateGoal = require("InvestigateGoal"),
})
