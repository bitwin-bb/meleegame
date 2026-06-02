--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Nevermore = Nevermore,
	Client = require(gameRoot.Shared.Goap.Client),
	Server = require(gameRoot.Shared.Goap.Server),
	Utils = require(gameRoot.Shared.Goap.Utils),

	Core = require(gameRoot.Shared.Goap.Core),
	Actions = require(gameRoot.Shared.Goap.Actions),
	Goals = require(gameRoot.Shared.Goap.Goals),
	Sensors = require(gameRoot.Shared.Goap.Sensors),
	Scorers = require(gameRoot.Shared.Goap.Scorers),
	Executors = require(gameRoot.Shared.Goap.Executors),
	Agents = require(gameRoot.Shared.Goap.Agents),
	Integrations = require(gameRoot.Shared.Goap.Integrations),
	Debug = require(gameRoot.Shared.Goap.Debug),
})
