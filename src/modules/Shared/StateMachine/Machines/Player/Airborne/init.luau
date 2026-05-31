--!strict

local Nevermore = require(script:FindFirstAncestor("StateMachine").Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	JumpState = require(script.JumpState),
	FallState = require(script.FallState),
})
