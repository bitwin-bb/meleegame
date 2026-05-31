--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	CombatMachine = require(script.CombatMachine),
	IdleState = require(script.IdleState),
	StartupState = require(script.StartupState),
	ActiveState = require(script.ActiveState),
	RecoveryState = require(script.RecoveryState),
})
