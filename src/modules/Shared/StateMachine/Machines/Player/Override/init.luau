--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	StunnedState = require(gameRoot.Shared.StateMachine.Machines.Player.Override.StunnedState),
	KnockbackState = require(gameRoot.Shared.StateMachine.Machines.Player.Override.KnockbackState),
	DeadState = require(gameRoot.Shared.StateMachine.Machines.Player.Override.DeadState),
})
