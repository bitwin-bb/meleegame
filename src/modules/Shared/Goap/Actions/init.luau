--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Action = require(gameRoot.Shared.Goap.Core.Action),
	FindTargetAction = require(gameRoot.Shared.Goap.Actions.FindTargetAction),
	MoveToTargetAction = require(gameRoot.Shared.Goap.Actions.MoveToTargetAction),
	AttackTargetAction = require(gameRoot.Shared.Goap.Actions.AttackTargetAction),
	FleeAction = require(gameRoot.Shared.Goap.Actions.FleeAction),
	PatrolAction = require(gameRoot.Shared.Goap.Actions.PatrolAction),
	HealSelfAction = require(gameRoot.Shared.Goap.Actions.HealSelfAction),
	UseAbilityAction = require(gameRoot.Shared.Goap.Actions.UseAbilityAction),
})
