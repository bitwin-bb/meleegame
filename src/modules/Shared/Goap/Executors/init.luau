
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	ActionRunner = require(script:WaitForChild("ActionRunner")),
	PlanExecutor = require(script:WaitForChild("PlanExecutor")),
	PlanValidator = require(script:WaitForChild("PlanValidator")),
})
