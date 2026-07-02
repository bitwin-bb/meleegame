
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerMachine = require(script:WaitForChild("PlayerMachine")),
	PlayerBlackboard = require(script:WaitForChild("PlayerBlackboard")),
	PlayerTransitions = require(script:WaitForChild("PlayerTransitions")),
	Grounded = require(script:WaitForChild("Grounded")),
	Airborne = require(script:WaitForChild("Airborne")),
	Override = require(script:WaitForChild("Override")),
})
