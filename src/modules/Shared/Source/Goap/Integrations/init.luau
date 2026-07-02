
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	StateMachineAdapter = require(script:WaitForChild("StateMachineAdapter")),
	MovementAdapter = require(script:WaitForChild("GoapMovementAdapter")),
	CombatAdapter = require(script:WaitForChild("CombatAdapter")),
	AbilityAdapter = require(script:WaitForChild("AbilityAdapter")),
	TargetingAdapter = require(script:WaitForChild("TargetingAdapter")),
	PathfindingAdapter = require(script:WaitForChild("PathfindingAdapter")),
})
