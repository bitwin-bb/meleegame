local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuffConstants = require("BuffConstants")
local BuffShared = require("BuffShared")

local Swiftness = BuffShared.New({
	definitionOnly = true,
})
local EFFECTS = Table.copy({
	speedMultiplier = 1.25,
	stat = "WalkSpeed",
	modifier = 0.25,
	stackMode = BuffConstants.STACK_MODE_REFRESH,
})

Swiftness:AddBuff(
	"Swiftness",
	12,
	EFFECTS,
	"Increases movement speed.",
	"Movement speed is increased while active."
)

return Swiftness
