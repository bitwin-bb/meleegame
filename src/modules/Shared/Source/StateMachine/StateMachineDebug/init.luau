
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	StateMachineDebugger = require(script:WaitForChild("StateMachineDebugger")),
	StateHistory = require(script:WaitForChild("StateHistory")),
	StateGraphPrinter = require(script:WaitForChild("StateGraphPrinter")),
})
