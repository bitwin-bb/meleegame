local DataTemplate = {
	playerData = {
		allowMovementFreeze = false,
		respawnCooldown = 5,
		inventory = {
			capacity = 72,
			selectedSlot = nil,
			slots = {},
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
