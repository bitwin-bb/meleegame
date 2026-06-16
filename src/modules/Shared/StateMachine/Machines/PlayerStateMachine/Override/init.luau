
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	StunnedState = require(script:WaitForChild("StunnedState")),
	KnockbackState = require(script:WaitForChild("KnockbackState")),
	DeadState = require(script:WaitForChild("PlayerDeadState")),
})
