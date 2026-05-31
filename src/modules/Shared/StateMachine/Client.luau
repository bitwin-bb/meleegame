--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	Runtime = require(script.Parent.Runtime),
	Machines = require(script.Parent.Machines),
	Adapters = require(script.Parent.Adapters),
})
