local require = require(script.Parent.loader).load(script)

local DataTemplate = {
	playerData = {
		allowMovementFreeze = false,
		respawnCooldown = 5,
		inventory = {
			capacity = 72,
			selectedSlot = nil,
			slots = {
				{
					index = 1,
					stackId = "starter_copper_broadsword",
					itemId = "CopperBroadSword",
					amount = 1,
					maxStack = 1,
				},
				{
					index = 2,
					stackId = "starter_copper_pickaxe",
					itemId = "CopperPickaxe",
					amount = 1,
					maxStack = 1,
				},
				{
					index = 3,
					stackId = "starter_copper_axe",
					itemId = "CopperAxe",
					amount = 1,
					maxStack = 1,
				},
			},
		},
		coins = {
			copper = 0,
			silver = 0,
			gold = 0,
			platinum = 0,
		},
		crafting = {
			knownRecipeIds = {},
			discoveredItemIds = {},
			progressionFlags = {},
		},
		invincibilityFrames = {
			duration = 0.75,
			flickerInterval = 0.08,
			highlightFillTransparency = 0,
			highlightOutlineTransparency = 0,
		},
	},
}

return DataTemplate
