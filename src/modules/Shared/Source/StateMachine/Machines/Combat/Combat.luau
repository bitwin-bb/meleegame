
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	CombatMachine = require("CombatMachine"),
	IdleState = require("CombatIdleState"),
	StartupState = require("StartupState"),
	ActiveState = require("ActiveState"),
	RecoveryState = require("RecoveryState"),
})
