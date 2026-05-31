--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	AnimationAdapter = require(script.AnimationAdapter),
	CharacterAdapter = require(script.CharacterAdapter),
	MovementAdapter = require(script.MovementAdapter),
	NetworkerAdapter = require(script.NetworkerAdapter),
	HumanoidAdapter = require(script.HumanoidAdapter),
})
