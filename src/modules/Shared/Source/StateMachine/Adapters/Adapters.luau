
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	AnimationAdapter = require("AnimationAdapter"),
	CharacterAdapter = require("CharacterAdapter"),
	MovementAdapter = require("StateMachineMovementAdapter"),
	HumanoidAdapter = require("HumanoidAdapter"),
})
