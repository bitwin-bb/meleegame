--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Debug = require(script.Parent.Debug),
	Core = require(script.Parent.Core),
})
