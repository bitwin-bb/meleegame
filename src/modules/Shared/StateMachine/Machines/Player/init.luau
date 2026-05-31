--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerMachine = require(script.PlayerMachine),
	PlayerBlackboard = require(script.PlayerBlackboard),
	PlayerTransitions = require(script.PlayerTransitions),
	Grounded = require(script.Grounded),
	Airborne = require(script.Airborne),
	Override = require(script.Override),
})
