--!strict

local Nevermore = require(script.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Nevermore = Nevermore,
	Client = require(script.Client),
	Server = require(script.Server),
	Utils = require(script.Utils),

	Core = require(script.Core),
	Actions = require(script.Actions),
	Goals = require(script.Goals),
	Sensors = require(script.Sensors),
	Scorers = require(script.Scorers),
	Executors = require(script.Executors),
	Agents = require(script.Agents),
	Integrations = require(script.Integrations),
	Debug = require(script.Debug),
})
