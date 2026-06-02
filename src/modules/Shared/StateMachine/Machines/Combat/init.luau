--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	CombatMachine = require(gameRoot.Shared.StateMachine.Machines.Combat.CombatMachine),
	IdleState = require(gameRoot.Shared.StateMachine.Machines.Combat.IdleState),
	StartupState = require(gameRoot.Shared.StateMachine.Machines.Combat.StartupState),
	ActiveState = require(gameRoot.Shared.StateMachine.Machines.Combat.ActiveState),
	RecoveryState = require(gameRoot.Shared.StateMachine.Machines.Combat.RecoveryState),
})
