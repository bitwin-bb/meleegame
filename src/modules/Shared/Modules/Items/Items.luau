return {
	["PlatinumCoin"] = {
		name = "Platinum Coin",
		description = "A coin made of platinum. It is worth a lot of money!",
	},
	["GoldCoin"] = {
		name = "Gold Coin",
		description = "Ah yes, Gold!",
	},
	["SilverCoin"] = {
		name = "Silver Coin",
		description = "I mean, it's worth something. Sure is better than nothing!",
	},
	["CopperCoin"] = {
		name = "Copper Coin",
		description = "You're poor",
	},
	["Acorn"] = {
		name = "Acorn",
		description = "Your first ever crop! This can be planted to grow into a tree that produces more acorns!",
	},
	["Part"] = {
		name = "Part",
		description = "Loose crafting scrap salvaged from fallen enemies and equipment.",
	},
	["LifeCrystal"] = {
		name = "Life Crystal",
		description = "A condensed crystal that radiates restorative energy.",
	},
	["CopperOre"] = {
		name = "Copper Ore",
		description = "A chunk of copper-bearing stone ready to be smelted or crafted with.",
	},
	["Gel"] = {
		name = "Gel",
		description = "A sticky blob of slime residue dropped by defeated slimes.",
	},
	["Torch"] = {
		name = "Torch",
		description = "A simple handheld light source crafted from gel and wood.",
		useCase = "Light source",
		deployable = {
			placementProfile = "Torch",
			stationTag = "LightSource_Torch",
			placementDistance = 5,
			maxPlacementDistance = 12,
		},
	},
	["Workbench"] = {
		name = "Workbench",
		description = "A crafting station built for standard crafting.",
		useCase = "Placeable furniture",
		deployable = {
			stationId = "Workbench",
			stationTag = "CraftingStation_Workbench",
			placementDistance = 6,
			maxPlacementDistance = 16,
		},
	},
}
