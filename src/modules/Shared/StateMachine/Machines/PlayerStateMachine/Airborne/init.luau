
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	JumpState = require(script:WaitForChild("JumpState")),
	FallState = require(script:WaitForChild("FallState")),
})
