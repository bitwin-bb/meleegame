
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	Player = require(script:WaitForChild("PlayerStateMachine")),
	Combat = require(script:WaitForChild("Combat")),
	Enemies = require(script:WaitForChild("Enemies")),
})
