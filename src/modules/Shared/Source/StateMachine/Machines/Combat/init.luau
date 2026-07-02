
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	CombatMachine = require(script:WaitForChild("CombatMachine")),
	IdleState = require(script:WaitForChild("CombatIdleState")),
	StartupState = require(script:WaitForChild("StartupState")),
	ActiveState = require(script:WaitForChild("ActiveState")),
	RecoveryState = require(script:WaitForChild("RecoveryState")),
})
