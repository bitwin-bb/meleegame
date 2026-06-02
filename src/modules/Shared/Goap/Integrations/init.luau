--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	StateMachineAdapter = require(gameRoot.Shared.Goap.Integrations.StateMachineAdapter),
	MovementAdapter = require(gameRoot.Shared.Goap.Integrations.MovementAdapter),
	CombatAdapter = require(gameRoot.Shared.Goap.Integrations.CombatAdapter),
	AbilityAdapter = require(gameRoot.Shared.Goap.Integrations.AbilityAdapter),
	TargetingAdapter = require(gameRoot.Shared.Goap.Integrations.TargetingAdapter),
	PathfindingAdapter = require(gameRoot.Shared.Goap.Integrations.PathfindingAdapter),
})
