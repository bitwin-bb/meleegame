
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	HasTargetGuard = require("HasTargetGuard"),
	CooldownReadyGuard = require("CooldownReadyGuard"),
	HealthBelowGuard = require("HealthBelowGuard"),
	IsAliveGuard = require("IsAliveGuard"),
	IsGroundedGuard = require("IsGroundedGuard"),
	AnimationFinishedGuard = require("AnimationFinishedGuard"),
})
