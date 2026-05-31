--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	StateMachineAdapter = require(script.StateMachineAdapter),
	MovementAdapter = require(script.MovementAdapter),
	CombatAdapter = require(script.CombatAdapter),
	AbilityAdapter = require(script.AbilityAdapter),
	TargetingAdapter = require(script.TargetingAdapter),
	PathfindingAdapter = require(script.PathfindingAdapter),
})
