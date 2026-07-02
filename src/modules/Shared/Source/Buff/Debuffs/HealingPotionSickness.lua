local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local BuffConstants = require("BuffConstants")
local BuffShared = require("BuffShared")

local HealingPotionSickness = BuffShared.New({
	definitionOnly = true,
})
local EFFECTS = Table.copy({
	blocks = {
		"HealingPotion",
	},
	canUseHealingPotions = false,
	stackMode = BuffConstants.STACK_MODE_REFRESH,
})

HealingPotionSickness:AddDebuff(
	"Healing Potion Sickness",
	60,
	EFFECTS,
	"Prevents another healing potion from being used.",
	"Healing potion use is blocked while active."
)

return HealingPotionSickness
