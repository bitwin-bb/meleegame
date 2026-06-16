
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	GoapDebugger = require(script:WaitForChild("GoapDebugger")),
	PlanPrinter = require(script:WaitForChild("PlanPrinter")),
	WorldStateViewer = require(script:WaitForChild("WorldStateViewer")),
	GoalDebugger = require(script:WaitForChild("GoalDebugger")),
})
