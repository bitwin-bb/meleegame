--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	SlimeMachine = require(gameRoot.Shared.StateMachine.Machines.Enemies.Slime.SlimeMachine),
	IdleState = require(gameRoot.Shared.StateMachine.Machines.Enemies.Slime.IdleState),
	WanderState = require(gameRoot.Shared.StateMachine.Machines.Enemies.Slime.WanderState),
	ChaseState = require(gameRoot.Shared.StateMachine.Machines.Enemies.Slime.ChaseState),
	HurtState = require(gameRoot.Shared.StateMachine.Machines.Enemies.Slime.HurtState),
	DeadState = require(gameRoot.Shared.StateMachine.Machines.Enemies.Slime.DeadState),
})
