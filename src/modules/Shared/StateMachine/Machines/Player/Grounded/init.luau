--!strict

local Nevermore = require(script:FindFirstAncestor("StateMachine").Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	IdleState = require(script.IdleState),
	RunState = require(script.RunState),
	DashState = require(script.DashState),
})
