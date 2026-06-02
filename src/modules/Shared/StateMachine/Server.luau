--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	Runtime = require(gameRoot.Shared.StateMachine.Runtime),
	Machines = require(gameRoot.Shared.StateMachine.Machines),
	Adapters = require(gameRoot.Shared.StateMachine.Adapters),
})
