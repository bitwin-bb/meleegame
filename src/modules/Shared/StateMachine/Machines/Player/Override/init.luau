--!strict

local Nevermore = require(script:FindFirstAncestor("StateMachine").Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	StunnedState = require(script.StunnedState),
	KnockbackState = require(script.KnockbackState),
	DeadState = require(script.DeadState),
})
