--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayAnimationAction = require(gameRoot.Shared.StateMachine.Actions.PlayAnimationAction),
	StopAnimationAction = require(gameRoot.Shared.StateMachine.Actions.StopAnimationAction),
	SetVelocityAction = require(gameRoot.Shared.StateMachine.Actions.SetVelocityAction),
	ApplyKnockbackAction = require(gameRoot.Shared.StateMachine.Actions.ApplyKnockbackAction),
	FireRemoteAction = require(gameRoot.Shared.StateMachine.Actions.FireRemoteAction),
	SpawnHitboxAction = require(gameRoot.Shared.StateMachine.Actions.SpawnHitboxAction),
})
