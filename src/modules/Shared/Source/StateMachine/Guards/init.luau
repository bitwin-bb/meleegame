
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	HasTargetGuard = require(script:WaitForChild("HasTargetGuard")),
	CooldownReadyGuard = require(script:WaitForChild("CooldownReadyGuard")),
	HealthBelowGuard = require(script:WaitForChild("HealthBelowGuard")),
	IsAliveGuard = require(script:WaitForChild("IsAliveGuard")),
	IsGroundedGuard = require(script:WaitForChild("IsGroundedGuard")),
	AnimationFinishedGuard = require(script:WaitForChild("AnimationFinishedGuard")),
})
