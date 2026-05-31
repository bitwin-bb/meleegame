--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Goal = require(script:FindFirstAncestor("Goap").Core.Goal),
	KillTargetGoal = require(script.KillTargetGoal),
	SurviveGoal = require(script.SurviveGoal),
	PatrolGoal = require(script.PatrolGoal),
	RetreatGoal = require(script.RetreatGoal),
	HealSelfGoal = require(script.HealSelfGoal),
	InvestigateGoal = require(script.InvestigateGoal),
})
