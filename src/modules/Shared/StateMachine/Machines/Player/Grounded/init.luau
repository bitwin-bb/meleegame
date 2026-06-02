--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	IdleState = require(gameRoot.Shared.StateMachine.Machines.Player.Grounded.IdleState),
	RunState = require(gameRoot.Shared.StateMachine.Machines.Player.Grounded.RunState),
	DashState = require(gameRoot.Shared.StateMachine.Machines.Player.Grounded.DashState),
})
