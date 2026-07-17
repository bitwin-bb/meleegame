
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	IdleState = require("PlayerGroundedIdleState"),
	RunState = require("RunState"),
	DashState = require("DashState"),
})
