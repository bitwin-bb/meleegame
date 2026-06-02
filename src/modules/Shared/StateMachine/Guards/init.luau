--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	HasTargetGuard = require(gameRoot.Shared.StateMachine.Guards.HasTargetGuard),
	CooldownReadyGuard = require(gameRoot.Shared.StateMachine.Guards.CooldownReadyGuard),
	HealthBelowGuard = require(gameRoot.Shared.StateMachine.Guards.HealthBelowGuard),
	IsAliveGuard = require(gameRoot.Shared.StateMachine.Guards.IsAliveGuard),
	IsGroundedGuard = require(gameRoot.Shared.StateMachine.Guards.IsGroundedGuard),
	AnimationFinishedGuard = require(gameRoot.Shared.StateMachine.Guards.AnimationFinishedGuard),
})
