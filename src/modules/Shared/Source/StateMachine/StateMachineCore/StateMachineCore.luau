local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	StateMachine = require("StateMachineEngine"),
	State = require("StateMachineState"),
	Blackboard = require("StateMachineBlackboard"),
	Transition = require("Transition"),
	StateStack = require("StateMachineStateStack"),
	StateTree = require("StateTree"),
	Types = require("StateMachineTypes"),
})
