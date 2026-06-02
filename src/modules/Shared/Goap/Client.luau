--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Debug = require(gameRoot.Shared.Goap.Debug),
	Core = require(gameRoot.Shared.Goap.Core),
})
