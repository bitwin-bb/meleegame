
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	Player = require("PlayerStateMachine"),
	Combat = require("Combat"),
	Enemies = require("Enemies"),
})
