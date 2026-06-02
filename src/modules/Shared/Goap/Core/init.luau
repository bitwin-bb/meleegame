--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Types = require(gameRoot.Shared.Goap.Core.Types),
	WorldState = require(gameRoot.Shared.Goap.Core.WorldState),
	Blackboard = require(gameRoot.Shared.Goap.Core.Blackboard),
	Action = require(gameRoot.Shared.Goap.Core.Action),
	Goal = require(gameRoot.Shared.Goap.Core.Goal),
	Plan = require(gameRoot.Shared.Goap.Core.Plan),
	Planner = require(gameRoot.Shared.Goap.Core.Planner),
	Sensor = require(gameRoot.Shared.Goap.Core.Sensor),
	Agent = require(gameRoot.Shared.Goap.Core.Agent),
})
