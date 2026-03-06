local Configs = {
	gameVersion = "0.0.1",
	gameName = "Aquaria",
	maxPlayers = 4,

	playerData = {},

	cameraSettings = {
		sideViewEnabled = true,
		serviceEnabled = true,
	},

	cameraData = {
		distance = 60,
		height = 8,
		lookHeight = 8,
		sideSign = 1,
		fieldOfView = 50,
		movementBackAmount = 30,
		movementSpeedForMaxBack = 25,
		movementBackSign = 1,
		mouseInfluenceX = 2,
		mouseInfluenceY = 2,
		cameraSpring = {
			frequency = 5,
			damping = 1,
		},
		fovSpring = {
			frequency = 5,
			damping = 1,
		},
	},

	npcSettings = {
		slime = {
			enabled = true,
			initialSpawnCount = 1,
			maxAlive = 3,
			spawnRate = 1,
			spawnChance = 0.4,
			despawnDistance = 220,
		},
	},

	meleeSettings = {
		debugHitboxEnabled = false,
	},

	crafting = {
		stationScanRadius = 26,
		stationValidationRadius = 26,
		stationScanRateHz = 8,
		biomeScanRateHz = 6,
		clientRequestThrottleSeconds = 0.12,
		serverRequestRateLimitSeconds = 0.08,
		bulkCraftIntervalSeconds = 0.2,
		inventoryWatchIntervalSeconds = 0.2,
		statePushIntervalSeconds = 0.1,
		persistIntervalSeconds = 3,
		dataLoadTimeoutSeconds = 20,
		maxCraftQuantityPerRequest = 99,
		dataPath = { "crafting" },
		stationTagPrefix = "CraftingStation_",
		stationTagById = {
			Workbench = "CraftingStation_Workbench",
			Furnace = "CraftingStation_Furnace",
			Anvil = "CraftingStation_Anvil",
			AlchemyTable = "CraftingStation_AlchemyTable",
		},
	},

	worldGeneration = {
		chunkSize = 32,
		defaultRenderDistanceChunks = 2,
		defaultVerticalRenderDistanceChunks = 2,
		maxConcurrentChunkLoads = 3,
		maxChunkUnloadsPerHeartbeat = 12,
		maxChunkRebuildsPerHeartbeat = 4,
		maxCachedChunkData = 1200,
		maxCachedChunkVisuals = 0,
		maxCollisionPartsPerChunk = 4096,
	},

	worldSimulation = {
		enableClientReplication = false,
	},

	worldAnimatorSettings = {
		enabled = true,
		duration = 1,
		animationType = "riseFade",
		easing = "sine",
		verticalOffset = 100,
		transparencyRelativeToChunkPosition = false,
		minPlayerDistanceToAnimate = 16,
		maxConcurrentAnimations = 8,
		animateExistingChunks = true,
		maxAnimatedPartsPerChunk = 100000,
	},
}

return Configs
