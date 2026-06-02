--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	Player = require(gameRoot.Shared.StateMachine.Machines.Player),
	Combat = require(gameRoot.Shared.StateMachine.Machines.Combat),
	Enemies = require(gameRoot.Shared.StateMachine.Machines.Enemies),
})
