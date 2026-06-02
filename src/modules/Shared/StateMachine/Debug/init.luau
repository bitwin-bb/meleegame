--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	StateMachineDebugger = require(gameRoot.Shared.StateMachine.Debug.StateMachineDebugger),
	StateHistory = require(gameRoot.Shared.StateMachine.Debug.StateHistory),
	StateGraphPrinter = require(gameRoot.Shared.StateMachine.Debug.StateGraphPrinter),
})
