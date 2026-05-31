--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	Player = require(script.Player),
	Combat = require(script.Combat),
	Enemies = require(script.Enemies),
})
