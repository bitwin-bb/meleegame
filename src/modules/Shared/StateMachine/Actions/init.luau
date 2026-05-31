--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayAnimationAction = require(script.PlayAnimationAction),
	StopAnimationAction = require(script.StopAnimationAction),
	SetVelocityAction = require(script.SetVelocityAction),
	ApplyKnockbackAction = require(script.ApplyKnockbackAction),
	FireRemoteAction = require(script.FireRemoteAction),
	SpawnHitboxAction = require(script.SpawnHitboxAction),
})
