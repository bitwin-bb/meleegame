--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Core = require(script.Parent.Core),
	Actions = require(script.Parent.Actions),
	Goals = require(script.Parent.Goals),
	Sensors = require(script.Parent.Sensors),
	Agents = require(script.Parent.Agents),
	Executors = require(script.Parent.Executors),
})
