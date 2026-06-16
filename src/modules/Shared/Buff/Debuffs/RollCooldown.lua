local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuffConstants = require("BuffConstants")
local BuffShared = require("BuffShared")

local RollCooldown = BuffShared.new({
	definitionOnly = true,
})
local EFFECTS = Table.copy({
	action = "Roll",
	canRoll = false,
	stackMode = BuffConstants.STACK_MODE_REFRESH,
})

RollCooldown:AddDebuff(
	"Roll Cooldown",
	1.2,
	EFFECTS,
	"Roll is recovering.",
	"Rolling is blocked until the cooldown expires."
)

return RollCooldown
