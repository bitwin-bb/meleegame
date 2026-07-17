
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerMachine = require("PlayerMachine"),
	PlayerBlackboard = require("PlayerBlackboard"),
	PlayerTransitions = require("PlayerTransitions"),
	Grounded = require("Grounded"),
	Airborne = require("Airborne"),
	Override = require("Override"),
})
