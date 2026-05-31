--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Action = require(script:FindFirstAncestor("Goap").Core.Action),
	FindTargetAction = require(script.FindTargetAction),
	MoveToTargetAction = require(script.MoveToTargetAction),
	AttackTargetAction = require(script.AttackTargetAction),
	FleeAction = require(script.FleeAction),
	PatrolAction = require(script.PatrolAction),
	HealSelfAction = require(script.HealSelfAction),
	UseAbilityAction = require(script.UseAbilityAction),
})
