
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	MachineFactory = require(script:WaitForChild("MachineFactory")),
	MachineRegistry = require(script:WaitForChild("MachineRegistry")),
	MachineHandle = require(script:WaitForChild("MachineHandle")),
	MachineJanitor = require(script:WaitForChild("MachineJanitor")),
})
