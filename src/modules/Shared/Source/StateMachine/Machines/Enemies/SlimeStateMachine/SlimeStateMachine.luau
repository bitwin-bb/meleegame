
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	SlimeMachine = require("SlimeMachine"),
	IdleState = require("SlimeIdleState"),
	WanderState = require("WanderState"),
	ChaseState = require("ChaseState"),
	HurtState = require("HurtState"),
	DeadState = require("SlimeDeadState"),
})
