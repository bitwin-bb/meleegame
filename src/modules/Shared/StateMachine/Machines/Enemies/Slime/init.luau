--!strict

local Nevermore = require(script:FindFirstAncestor("StateMachine").Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	SlimeMachine = require(script.SlimeMachine),
	IdleState = require(script.IdleState),
	WanderState = require(script.WanderState),
	ChaseState = require(script.ChaseState),
	HurtState = require(script.HurtState),
	DeadState = require(script.DeadState),
})
