
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayAnimationAction = require(script:WaitForChild("PlayAnimationAction")),
	StopAnimationAction = require(script:WaitForChild("StopAnimationAction")),
	SetVelocityAction = require(script:WaitForChild("SetVelocityAction")),
	ApplyKnockbackAction = require(script:WaitForChild("ApplyKnockbackAction")),
	FireRemoteAction = require(script:WaitForChild("FireRemoteAction")),
	SpawnHitboxAction = require(script:WaitForChild("SpawnHitboxAction")),
})
