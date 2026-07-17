
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	StateMachineAdapter = require("StateMachineAdapter"),
	MovementAdapter = require("GoapMovementAdapter"),
	CombatAdapter = require("CombatAdapter"),
	AbilityAdapter = require("AbilityAdapter"),
	TargetingAdapter = require("TargetingAdapter"),
	PathfindingAdapter = require("PathfindingAdapter"),
})
