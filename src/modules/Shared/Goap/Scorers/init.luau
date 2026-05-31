--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	GoalScorer = require(script.GoalScorer),
	PriorityScorer = require(script.PriorityScorer),
	HealthScorer = require(script.HealthScorer),
	ThreatScorer = require(script.ThreatScorer),
})
