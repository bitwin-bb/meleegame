
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayAnimationAction = require("PlayAnimationAction"),
	StopAnimationAction = require("StopAnimationAction"),
	SetVelocityAction = require("SetVelocityAction"),
	ApplyKnockbackAction = require("ApplyKnockbackAction"),
	FireRemoteAction = require("FireRemoteAction"),
	SpawnHitboxAction = require("SpawnHitboxAction"),
})
