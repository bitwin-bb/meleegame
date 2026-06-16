
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Types = require(script:WaitForChild("GoapTypes")),
	WorldState = require(script:WaitForChild("WorldState")),
	Blackboard = require(script:WaitForChild("GoapBlackboard")),
	Action = require(script:WaitForChild("GoapAction")),
	Goal = require(script:WaitForChild("Goal")),
	Plan = require(script:WaitForChild("Plan")),
	Planner = require(script:WaitForChild("Planner")),
	Sensor = require(script:WaitForChild("Sensor")),
	Agent = require(script:WaitForChild("Agent")),
})
