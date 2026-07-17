
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Action = require("GoapAction"),
	FindTargetAction = require("FindTargetAction"),
	MoveToTargetAction = require("MoveToTargetAction"),
	AttackTargetAction = require("AttackTargetAction"),
	FleeAction = require("FleeAction"),
	PatrolAction = require("PatrolAction"),
	HealSelfAction = require("HealSelfAction"),
	UseAbilityAction = require("UseAbilityAction"),
})
