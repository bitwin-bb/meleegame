--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	MachineFactory = require(gameRoot.Shared.StateMachine.Runtime.MachineFactory),
	MachineRegistry = require(gameRoot.Shared.StateMachine.Runtime.MachineRegistry),
	MachineHandle = require(gameRoot.Shared.StateMachine.Runtime.MachineHandle),
	MachineJanitor = require(gameRoot.Shared.StateMachine.Runtime.MachineJanitor),
})
