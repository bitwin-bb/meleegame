local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	StateMachine = require(script:WaitForChild("StateMachineEngine")),
	State = require(script:WaitForChild("StateMachineState")),
	Blackboard = require(script:WaitForChild("StateMachineBlackboard")),
	Transition = require(script:WaitForChild("Transition")),
	StateStack = require(script:WaitForChild("StateMachineStateStack")),
	StateTree = require(script:WaitForChild("StateTree")),
	Types = require(script:WaitForChild("StateMachineTypes")),
})
