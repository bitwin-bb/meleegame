
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	IdleState = require(script:WaitForChild("PlayerGroundedIdleState")),
	RunState = require(script:WaitForChild("RunState")),
	DashState = require(script:WaitForChild("DashState")),
})
