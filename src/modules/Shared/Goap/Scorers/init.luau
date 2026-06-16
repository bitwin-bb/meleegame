
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	GoalScorer = require(script:WaitForChild("GoalScorer")),
	PriorityScorer = require(script:WaitForChild("PriorityScorer")),
	HealthScorer = require(script:WaitForChild("HealthScorer")),
	ThreatScorer = require(script:WaitForChild("ThreatScorer")),
})
