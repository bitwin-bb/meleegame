--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	Nevermore = Nevermore,
	Client = require(gameRoot.Shared.StateMachine.Client),
	Server = require(gameRoot.Shared.StateMachine.Server),
	Utils = require(gameRoot.Shared.StateMachine.Utils),

	Core = require(gameRoot.Shared.StateMachine.Core),
	Guards = require(gameRoot.Shared.StateMachine.Guards),
	Actions = require(gameRoot.Shared.StateMachine.Actions),
	Adapters = require(gameRoot.Shared.StateMachine.Adapters),
	Runtime = require(gameRoot.Shared.StateMachine.Runtime),
	Machines = require(gameRoot.Shared.StateMachine.Machines),
	Debug = require(gameRoot.Shared.StateMachine.Debug),
})
