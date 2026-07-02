
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Action = require("GoapAction"),
	FindTargetAction = require(script:WaitForChild("FindTargetAction")),
	MoveToTargetAction = require(script:WaitForChild("MoveToTargetAction")),
	AttackTargetAction = require(script:WaitForChild("AttackTargetAction")),
	FleeAction = require(script:WaitForChild("FleeAction")),
	PatrolAction = require(script:WaitForChild("PatrolAction")),
	HealSelfAction = require(script:WaitForChild("HealSelfAction")),
	UseAbilityAction = require(script:WaitForChild("UseAbilityAction")),
})
