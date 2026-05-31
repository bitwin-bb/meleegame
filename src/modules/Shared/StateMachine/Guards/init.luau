--!strict

local Nevermore = require(script.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	HasTargetGuard = require(script.HasTargetGuard),
	CooldownReadyGuard = require(script.CooldownReadyGuard),
	HealthBelowGuard = require(script.HealthBelowGuard),
	IsAliveGuard = require(script.IsAliveGuard),
	IsGroundedGuard = require(script.IsGroundedGuard),
	AnimationFinishedGuard = require(script.AnimationFinishedGuard),
})
