--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Types = require(script.Types),
	WorldState = require(script.WorldState),
	Blackboard = require(script.Blackboard),
	Action = require(script.Action),
	Goal = require(script.Goal),
	Plan = require(script.Plan),
	Planner = require(script.Planner),
	Sensor = require(script.Sensor),
	Agent = require(script.Agent),
})
