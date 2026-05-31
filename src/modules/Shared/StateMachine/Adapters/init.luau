--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	AnimationAdapter = require(script.AnimationAdapter),
	CharacterAdapter = require(script.CharacterAdapter),
	MovementAdapter = require(script.MovementAdapter),
	HumanoidAdapter = require(script.HumanoidAdapter),
})
