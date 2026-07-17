
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	StunnedState = require("StunnedState"),
	KnockbackState = require("KnockbackState"),
	DeadState = require("PlayerDeadState"),
})
