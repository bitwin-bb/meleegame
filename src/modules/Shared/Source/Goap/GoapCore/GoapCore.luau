
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Types = require("GoapTypes"),
	WorldState = require("WorldState"),
	Blackboard = require("GoapBlackboard"),
	Action = require("GoapAction"),
	Goal = require("Goal"),
	Plan = require("Plan"),
	Planner = require("Planner"),
	Sensor = require("Sensor"),
	Agent = require("Agent"),
})
