
local require = require(script.Parent.loader).load(script)

local Nevermore = require(script:WaitForChild("GoapNevermore"))
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Nevermore = Nevermore,
	Client = require(script:WaitForChild("GoapClient")),
	Server = require(script:WaitForChild("GoapServer")),
	Utils = require(script:WaitForChild("GoapUtils")),

	Core = require(script:WaitForChild("GoapCore")),
	Actions = require(script:WaitForChild("GoapActions")),
	Goals = require(script:WaitForChild("Goals")),
	Sensors = require(script:WaitForChild("Sensors")),
	Scorers = require(script:WaitForChild("Scorers")),
	Executors = require(script:WaitForChild("Executors")),
	Agents = require(script:WaitForChild("Agents")),
	Integrations = require(script:WaitForChild("Integrations")),
	Debug = require(script:WaitForChild("GoapDebug")),
})
