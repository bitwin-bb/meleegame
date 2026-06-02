--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerMachine = require(gameRoot.Shared.StateMachine.Machines.Player.PlayerMachine),
	PlayerBlackboard = require(gameRoot.Shared.StateMachine.Machines.Player.PlayerBlackboard),
	PlayerTransitions = require(gameRoot.Shared.StateMachine.Machines.Player.PlayerTransitions),
	Grounded = require(gameRoot.Shared.StateMachine.Machines.Player.Grounded),
	Airborne = require(gameRoot.Shared.StateMachine.Machines.Player.Airborne),
	Override = require(gameRoot.Shared.StateMachine.Machines.Player.Override),
})
