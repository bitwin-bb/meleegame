--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Goal = require(gameRoot.Shared.Goap.Core.Goal),
	KillTargetGoal = require(gameRoot.Shared.Goap.Goals.KillTargetGoal),
	SurviveGoal = require(gameRoot.Shared.Goap.Goals.SurviveGoal),
	PatrolGoal = require(gameRoot.Shared.Goap.Goals.PatrolGoal),
	RetreatGoal = require(gameRoot.Shared.Goap.Goals.RetreatGoal),
	HealSelfGoal = require(gameRoot.Shared.Goap.Goals.HealSelfGoal),
	InvestigateGoal = require(gameRoot.Shared.Goap.Goals.InvestigateGoal),
})
