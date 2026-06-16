
local require = require(script.Parent.loader).load(script)

local Nevermore = require(script:WaitForChild("StateMachineNevermore"))
local Table = Nevermore.Get("Table")

return Table.copy({
	Nevermore = Nevermore,
	Client = require(script:WaitForChild("StateMachineClient")),
	Server = require(script:WaitForChild("StateMachineServer")),
	Utils = require(script:WaitForChild("StateMachineUtils")),

	Core = require(script:WaitForChild("StateMachineCore")),
	Guards = require(script:WaitForChild("Guards")),
	Actions = require(script:WaitForChild("StateMachineActions")),
	Adapters = require(script:WaitForChild("Adapters")),
	Runtime = require(script:WaitForChild("StateMachineRuntime")),
	Machines = require(script:WaitForChild("Machines")),
	Debug = require(script:WaitForChild("StateMachineDebug")),
})
