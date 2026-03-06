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
	currency = {
		id = "currency",
		displayName = "Currency Compression",
		sortOrder = 10,
		recipeIds = {
			"coin_silver_from_copper",
			"coin_gold_from_silver",
			"coin_platinum_from_gold",
		},
	},
	metalwork = {
		id = "metalwork",
		displayName = "Metalwork",
		sortOrder = 20,
		recipeIds = {
			"forge_copper_shortsword",
			"forge_copper_broadsword",
			"forge_katana",
		},
	},
	alchemy = {
		id = "alchemy",
		displayName = "Alchemy",
		sortOrder = 30,
		recipeIds = {
			"condense_life_crystal",
		},
	},
	recycling = {
		id = "recycling",
		displayName = "Recycling",
		sortOrder = 40,
		recipeIds = {
			"recycle_copper_broadsword",
			"recycle_katana",
		},
	},
}

CraftingTree.recipes = {
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
		requiredStations = { "Workbench" },
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 10,
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
		requiredStations = { "Workbench" },
		requiredBiome = nil,
		unlockConditions = {
			requiredItems = { "SilverCoin" },
		},
		sortOrder = 20,
		isHidden = true,
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
		requiredStations = { "Furnace" },
		requiredBiome = nil,
		unlockConditions = {
			requiredItems = { "GoldCoin" },
		},
		sortOrder = 30,
		isHidden = true,
	},
	{
		id = "forge_copper_shortsword",
		displayName = "Copper Shortsword",
		category = "Weapons",
		ingredients = {
			{ itemId = "Part", amount = 8 },
			{ itemId = "CopperCoin", amount = 20 },
		},
		results = {
			{ itemId = "CopperShortSword", amount = 1 },
		},
		requiredStations = { "Workbench" },
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 110,
		isHidden = false,
	},
	{
		id = "forge_copper_broadsword",
		displayName = "Copper Broadsword",
		category = "Weapons",
		ingredients = {
			{ itemId = "CopperShortSword", amount = 1 },
			{ itemId = "Part", amount = 12 },
			{ itemId = "SilverCoin", amount = 6 },
		},
		results = {
			{ itemId = "CopperBroadSword", amount = 1 },
		},
		requiredStations = { "Anvil" },
		requiredBiome = nil,
		unlockConditions = {
			requiredItems = { "CopperShortSword", "SilverCoin" },
		},
		sortOrder = 120,
		isHidden = true,
	},
	{
		id = "forge_katana",
		displayName = "Katana",
		category = "Weapons",
		ingredients = {
			{ itemId = "CopperBroadSword", amount = 1 },
			{ itemId = "Part", amount = 35 },
			{ itemId = "GoldCoin", amount = 4 },
		},
		results = {
			{ itemId = "Katana", amount = 1 },
		},
		requiredStations = { "Furnace", "Anvil" },
		requiredBiome = nil,
		unlockConditions = {
			requiredItems = { "CopperBroadSword", "GoldCoin" },
		},
		sortOrder = 130,
		isHidden = true,
	},
	{
		id = "condense_life_crystal",
		displayName = "Life Crystal",
		category = "Alchemy",
		ingredients = {
			{ itemId = "Part", amount = 70 },
			{ itemId = "GoldCoin", amount = 12 },
		},
		results = {
			{ itemId = "LifeCrystal", amount = 1 },
		},
		requiredStations = { "AlchemyTable" },
		requiredBiome = "Jungle",
		unlockConditions = {
			requiredItems = { "Part", "GoldCoin" },
		},
		sortOrder = 210,
		isHidden = true,
	},
	{
		id = "recycle_copper_broadsword",
		displayName = "Recycle Copper Broadsword",
		category = "Recycling",
		ingredients = {
			{ itemId = "CopperBroadSword", amount = 1 },
		},
		results = {
			{ itemId = "Part", amount = 20 },
		},
		requiredStations = { "Furnace" },
		requiredBiome = nil,
		unlockConditions = nil,
		sortOrder = 310,
		isHidden = false,
	},
	{
		id = "recycle_katana",
		displayName = "Recycle Katana",
		category = "Recycling",
		ingredients = {
			{ itemId = "Katana", amount = 1 },
		},
		results = {
			{ itemId = "Part", amount = 50 },
			{ itemId = "GoldCoin", amount = 2 },
		},
		requiredStations = { "Furnace" },
		requiredBiome = nil,
		unlockConditions = {
			requiredItems = { "Katana" },
		},
		sortOrder = 320,
		isHidden = true,
	},
}

return CraftingTree
