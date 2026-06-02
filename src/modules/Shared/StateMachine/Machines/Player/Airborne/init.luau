--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	JumpState = require(gameRoot.Shared.StateMachine.Machines.Player.Airborne.JumpState),
	FallState = require(gameRoot.Shared.StateMachine.Machines.Player.Airborne.FallState),
})
