--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	GoalScorer = require(gameRoot.Shared.Goap.Scorers.GoalScorer),
	PriorityScorer = require(gameRoot.Shared.Goap.Scorers.PriorityScorer),
	HealthScorer = require(gameRoot.Shared.Goap.Scorers.HealthScorer),
	ThreatScorer = require(gameRoot.Shared.Goap.Scorers.ThreatScorer),
})
