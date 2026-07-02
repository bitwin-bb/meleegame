
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	AnimationAdapter = require(script:WaitForChild("AnimationAdapter")),
	CharacterAdapter = require(script:WaitForChild("CharacterAdapter")),
	MovementAdapter = require(script:WaitForChild("StateMachineMovementAdapter")),
	HumanoidAdapter = require(script:WaitForChild("HumanoidAdapter")),
})
