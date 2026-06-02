--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	ActionRunner = require(gameRoot.Shared.Goap.Executors.ActionRunner),
	PlanExecutor = require(gameRoot.Shared.Goap.Executors.PlanExecutor),
	PlanValidator = require(gameRoot.Shared.Goap.Executors.PlanValidator),
})
