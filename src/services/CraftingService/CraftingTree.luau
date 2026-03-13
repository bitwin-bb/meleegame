--!strict

local CraftingTree = {}

CraftingTree.version = 1

CraftingTree.stations = {
	Workbench = {
		id = "Workbench",
		displayName = "Workbench",
		tag = "CraftingStation_Workbench",
	},
	Furnace = {
		id = "Furnace",
		displayName = "Furnace",
		tag = "CraftingStation_Furnace",
	},
	Anvil = {
		id = "Anvil",
		displayName = "Anvil",
		tag = "CraftingStation_Anvil",
	},
	AlchemyTable = {
		id = "AlchemyTable",
		displayName = "Alchemy Table",
		tag = "CraftingStation_AlchemyTable",
	},
}

CraftingTree.groups = {
	craftingStations = {
		id = "craftingStations",
		displayName = "Furniture",
		sortOrder = 5,
		recipeIds = {
			"craft_workbench",
		},
	},
	currency = {
		id = "currency",
		displayName = "Currency Compression",
		sortOrder = 10,
		recipeIds = {
			"coin_silver_from_copper",
			"coin_copper_from_silver",
			"coin_gold_from_silver",
			"coin_silver_from_gold",
			"coin_platinum_from_gold",
			"coin_gold_from_platinum",
		},
	},
}

CraftingTree.recipes = {
	{
		id = "craft_workbench",
		displayName = "Workbench",
		category = "Furniture",
		ingredients = {
			{ itemId = "Wood", amount = 10 },
		},
		results = {
			{ itemId = "Workbench", amount = 1 },
		},
		requiredStations = {},
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 5,
		isHidden = false,
	},
	{
		id = "coin_silver_from_copper",
		displayName = "Silver Coin (100 Copper)",
		category = "Currency",
		ingredients = {
			{ itemId = "CopperCoin", amount = 100 },
		},
		results = {
			{ itemId = "SilverCoin", amount = 1 },
		},
		requiredStations = {},
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 10,
		isHidden = false,
	},
	{
		id = "coin_copper_from_silver",
		displayName = "Copper Coin (1 Silver)",
		category = "Currency",
		ingredients = {
			{ itemId = "SilverCoin", amount = 1 },
		},
		results = {
			{ itemId = "CopperCoin", amount = 100 },
		},
		requiredStations = {},
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 15,
		isHidden = false,
	},
	{
		id = "coin_gold_from_silver",
		displayName = "Gold Coin (100 Silver)",
		category = "Currency",
		ingredients = {
			{ itemId = "SilverCoin", amount = 100 },
		},
		results = {
			{ itemId = "GoldCoin", amount = 1 },
		},
		requiredStations = {},
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 20,
		isHidden = false,
	},
	{
		id = "coin_silver_from_gold",
		displayName = "Silver Coin (1 Gold)",
		category = "Currency",
		ingredients = {
			{ itemId = "GoldCoin", amount = 1 },
		},
		results = {
			{ itemId = "SilverCoin", amount = 100 },
		},
		requiredStations = {},
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 25,
		isHidden = false,
	},
	{
		id = "coin_platinum_from_gold",
		displayName = "Platinum Coin (100 Gold)",
		category = "Currency",
		ingredients = {
			{ itemId = "GoldCoin", amount = 100 },
		},
		results = {
			{ itemId = "PlatinumCoin", amount = 1 },
		},
		requiredStations = {},
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 30,
		isHidden = false,
	},
	{
		id = "coin_gold_from_platinum",
		displayName = "Gold Coin (1 Platinum)",
		category = "Currency",
		ingredients = {
			{ itemId = "PlatinumCoin", amount = 1 },
		},
		results = {
			{ itemId = "GoldCoin", amount = 100 },
		},
		requiredStations = {},
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 35,
		isHidden = false,
	},
}

return CraftingTree
