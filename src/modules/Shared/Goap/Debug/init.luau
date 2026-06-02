--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	GoapDebugger = require(gameRoot.Shared.Goap.Debug.GoapDebugger),
	PlanPrinter = require(gameRoot.Shared.Goap.Debug.PlanPrinter),
	WorldStateViewer = require(gameRoot.Shared.Goap.Debug.WorldStateViewer),
	GoalDebugger = require(gameRoot.Shared.Goap.Debug.GoalDebugger),
})
