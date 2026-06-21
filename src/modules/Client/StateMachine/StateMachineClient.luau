
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	Runtime = require("StateMachineRuntime"),
	Machines = require("Machines"),
	Adapters = require("Adapters"),
})
