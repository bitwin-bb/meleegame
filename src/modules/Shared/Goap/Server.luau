--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Core = require(gameRoot.Shared.Goap.Core),
	Actions = require(gameRoot.Shared.Goap.Actions),
	Goals = require(gameRoot.Shared.Goap.Goals),
	Sensors = require(gameRoot.Shared.Goap.Sensors),
	Agents = require(gameRoot.Shared.Goap.Agents),
	Executors = require(gameRoot.Shared.Goap.Executors),
})
