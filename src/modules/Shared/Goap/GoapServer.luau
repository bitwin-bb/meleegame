
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Core = require("GoapCore"),
	Actions = require("GoapActions"),
	Goals = require("Goals"),
	Sensors = require("Sensors"),
	Agents = require("Agents"),
	Executors = require("Executors"),
})
