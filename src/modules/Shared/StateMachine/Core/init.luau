--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	StateMachine = require(gameRoot.Shared.StateMachine.Core.StateMachine),
	State = require(gameRoot.Shared.StateMachine.Core.State),
	Blackboard = require(gameRoot.Shared.StateMachine.Core.Blackboard),
	Transition = require(gameRoot.Shared.StateMachine.Core.Transition),
	StateStack = require(quentyPackages.statestack.Shared.StateStack),
	StateTree = require(gameRoot.Shared.StateMachine.Core.StateTree),
	Types = require(gameRoot.Shared.StateMachine.Core.Types),
})
