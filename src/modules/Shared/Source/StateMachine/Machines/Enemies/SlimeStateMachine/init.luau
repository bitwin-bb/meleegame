
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	SlimeMachine = require(script:WaitForChild("SlimeMachine")),
	IdleState = require(script:WaitForChild("SlimeIdleState")),
	WanderState = require(script:WaitForChild("WanderState")),
	ChaseState = require(script:WaitForChild("ChaseState")),
	HurtState = require(script:WaitForChild("HurtState")),
	DeadState = require(script:WaitForChild("SlimeDeadState")),
})
