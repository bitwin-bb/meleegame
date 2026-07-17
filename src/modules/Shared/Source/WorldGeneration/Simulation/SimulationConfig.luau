local require = require(script.Parent.loader).load(script)

local Config = {}

export type BiomeThresholdConfig = {
	desertHeat: number,
	snowCold: number,
	jungleHumidity: number,
	corruptionNoise: number,
}

export type SimulationConfig = {
	seed: number,
	enableClientReplication: boolean,
	tileSize: number,
	chunkSize: number,
	chunkHeight: number,
	chunkDepth: number,
	clusterSize: number,
	nearSurfaceDepth: number,
	biomeTransitionWidth: number,
	streamRadiusChunks: number,
	streamVerticalRadiusChunks: number,
	renderRadiusChunks: number,
	renderVerticalRadiusChunks: number,
	unloadPaddingChunks: number,
	maxStreamSendsPerPlayerPerTick: number,
	maxRuntimeSecondsPerTick: number,
	maxChunksPerRuntimeTick: number,
	runtimeClusterSlice: number,
	runtimeEntitySlice: number,
	budgetCorruptionClustersPerTick: number,
	budgetBiomeSpreadClustersPerTick: number,
	budgetAiEntitiesPerTick: number,
	budgetPhysicsEntitiesPerTick: number,
	entityBatchSize: number,
	entityCapacityPerChunk: number,
	corruptionSpreadRate: number,
	corruptionDecayRate: number,
	corruptionActivationThreshold: number,
	lodNearDistance: number,
	lodFarDistance: number,
	cacheTablePoolSize: number,
	cacheArrayPoolSize: number,
	maxPartPoolSize: number,
	enableDebug: boolean,
	enableProfiling: boolean,
	biomeThresholds: BiomeThresholdConfig,
}

local DEFAULT_CONFIG: SimulationConfig = {
	seed = 13371337,
	enableClientReplication = false,
	tileSize = 2,
	chunkSize = 32,
	chunkHeight = 32,
	chunkDepth = 32,
	clusterSize = 2,
	nearSurfaceDepth = 10,
	biomeTransitionWidth = 8,
	streamRadiusChunks = 6,
	streamVerticalRadiusChunks = 3,
	renderRadiusChunks = 3,
	renderVerticalRadiusChunks = 2,
	unloadPaddingChunks = 2,
	maxStreamSendsPerPlayerPerTick = 6,
	maxRuntimeSecondsPerTick = 0.0035,
	maxChunksPerRuntimeTick = 24,
	runtimeClusterSlice = 64,
	runtimeEntitySlice = 128,
	budgetCorruptionClustersPerTick = 2048,
	budgetBiomeSpreadClustersPerTick = 2048,
	budgetAiEntitiesPerTick = 1024,
	budgetPhysicsEntitiesPerTick = 1024,
	entityBatchSize = 128,
	entityCapacityPerChunk = 256,
	corruptionSpreadRate = 0.11,
	corruptionDecayRate = 0.015,
	corruptionActivationThreshold = 0.35,
	lodNearDistance = 160,
	lodFarDistance = 420,
	cacheTablePoolSize = 256,
	cacheArrayPoolSize = 256,
	maxPartPoolSize = 8000,
	enableDebug = false,
	enableProfiling = false,
	biomeThresholds = {
		desertHeat = 0.33,
		snowCold = -0.35,
		jungleHumidity = 0.28,
		corruptionNoise = 0.52,
	},
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function coerceNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function coerceInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function coerceBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

local function coerceBiomeThresholds(source: any, fallback: BiomeThresholdConfig): BiomeThresholdConfig
	local raw = if typeof(source) == "table" then source else {} :: any
	return {
		desertHeat = coerceNumber((raw :: any).desertHeat, -1, 1, fallback.desertHeat),
		snowCold = coerceNumber((raw :: any).snowCold, -1, 1, fallback.snowCold),
		jungleHumidity = coerceNumber((raw :: any).jungleHumidity, -1, 1, fallback.jungleHumidity),
		corruptionNoise = coerceNumber((raw :: any).corruptionNoise, -1, 1, fallback.corruptionNoise),
	}
end

function Config.CreateDefault(): SimulationConfig
	return {
		seed = DEFAULT_CONFIG.seed,
		enableClientReplication = DEFAULT_CONFIG.enableClientReplication,
		tileSize = DEFAULT_CONFIG.tileSize,
		chunkSize = DEFAULT_CONFIG.chunkSize,
		chunkHeight = DEFAULT_CONFIG.chunkHeight,
		chunkDepth = DEFAULT_CONFIG.chunkDepth,
		clusterSize = DEFAULT_CONFIG.clusterSize,
		nearSurfaceDepth = DEFAULT_CONFIG.nearSurfaceDepth,
		biomeTransitionWidth = DEFAULT_CONFIG.biomeTransitionWidth,
		streamRadiusChunks = DEFAULT_CONFIG.streamRadiusChunks,
		streamVerticalRadiusChunks = DEFAULT_CONFIG.streamVerticalRadiusChunks,
		renderRadiusChunks = DEFAULT_CONFIG.renderRadiusChunks,
		renderVerticalRadiusChunks = DEFAULT_CONFIG.renderVerticalRadiusChunks,
		unloadPaddingChunks = DEFAULT_CONFIG.unloadPaddingChunks,
		maxStreamSendsPerPlayerPerTick = DEFAULT_CONFIG.maxStreamSendsPerPlayerPerTick,
		maxRuntimeSecondsPerTick = DEFAULT_CONFIG.maxRuntimeSecondsPerTick,
		maxChunksPerRuntimeTick = DEFAULT_CONFIG.maxChunksPerRuntimeTick,
		runtimeClusterSlice = DEFAULT_CONFIG.runtimeClusterSlice,
		runtimeEntitySlice = DEFAULT_CONFIG.runtimeEntitySlice,
		budgetCorruptionClustersPerTick = DEFAULT_CONFIG.budgetCorruptionClustersPerTick,
		budgetBiomeSpreadClustersPerTick = DEFAULT_CONFIG.budgetBiomeSpreadClustersPerTick,
		budgetAiEntitiesPerTick = DEFAULT_CONFIG.budgetAiEntitiesPerTick,
		budgetPhysicsEntitiesPerTick = DEFAULT_CONFIG.budgetPhysicsEntitiesPerTick,
		entityBatchSize = DEFAULT_CONFIG.entityBatchSize,
		entityCapacityPerChunk = DEFAULT_CONFIG.entityCapacityPerChunk,
		corruptionSpreadRate = DEFAULT_CONFIG.corruptionSpreadRate,
		corruptionDecayRate = DEFAULT_CONFIG.corruptionDecayRate,
		corruptionActivationThreshold = DEFAULT_CONFIG.corruptionActivationThreshold,
		lodNearDistance = DEFAULT_CONFIG.lodNearDistance,
		lodFarDistance = DEFAULT_CONFIG.lodFarDistance,
		cacheTablePoolSize = DEFAULT_CONFIG.cacheTablePoolSize,
		cacheArrayPoolSize = DEFAULT_CONFIG.cacheArrayPoolSize,
		maxPartPoolSize = DEFAULT_CONFIG.maxPartPoolSize,
		enableDebug = DEFAULT_CONFIG.enableDebug,
		enableProfiling = DEFAULT_CONFIG.enableProfiling,
		biomeThresholds = {
			desertHeat = DEFAULT_CONFIG.biomeThresholds.desertHeat,
			snowCold = DEFAULT_CONFIG.biomeThresholds.snowCold,
			jungleHumidity = DEFAULT_CONFIG.biomeThresholds.jungleHumidity,
			corruptionNoise = DEFAULT_CONFIG.biomeThresholds.corruptionNoise,
		},
	}
end

function Config.Coerce(configRaw: any, fallbackRaw: SimulationConfig?): SimulationConfig
	local fallback = if fallbackRaw ~= nil then fallbackRaw else Config.CreateDefault()
	local source = if typeof(configRaw) == "table" then configRaw else {} :: any
	local chunkSize = coerceInteger((source :: any).chunkSize, 8, 128, fallback.chunkSize)
	local chunkHeight = coerceInteger((source :: any).chunkHeight, 8, 256, fallback.chunkHeight)
	local chunkDepth = coerceInteger((source :: any).chunkDepth, 8, 128, fallback.chunkDepth)

	local result: SimulationConfig = {
		seed = coerceInteger((source :: any).seed, -2147483648, 2147483647, fallback.seed),
		enableClientReplication = coerceBoolean(
			(source :: any).enableClientReplication,
			fallback.enableClientReplication
		),
		tileSize = coerceNumber((source :: any).tileSize, 0.5, 8, fallback.tileSize),
		chunkSize = chunkSize,
		chunkHeight = chunkHeight,
		chunkDepth = chunkDepth,
		clusterSize = 2,
		nearSurfaceDepth = coerceInteger((source :: any).nearSurfaceDepth, 1, 64, fallback.nearSurfaceDepth),
		biomeTransitionWidth = coerceInteger(
			(source :: any).biomeTransitionWidth,
			2,
			64,
			fallback.biomeTransitionWidth
		),
		streamRadiusChunks = coerceInteger((source :: any).streamRadiusChunks, 1, 32, fallback.streamRadiusChunks),
		streamVerticalRadiusChunks = coerceInteger(
			(source :: any).streamVerticalRadiusChunks,
			1,
			16,
			fallback.streamVerticalRadiusChunks
		),
		renderRadiusChunks = coerceInteger((source :: any).renderRadiusChunks, 1, 32, fallback.renderRadiusChunks),
		renderVerticalRadiusChunks = coerceInteger(
			(source :: any).renderVerticalRadiusChunks,
			1,
			16,
			fallback.renderVerticalRadiusChunks
		),
		unloadPaddingChunks = coerceInteger((source :: any).unloadPaddingChunks, 0, 8, fallback.unloadPaddingChunks),
		maxStreamSendsPerPlayerPerTick = coerceInteger(
			(source :: any).maxStreamSendsPerPlayerPerTick,
			1,
			64,
			fallback.maxStreamSendsPerPlayerPerTick
		),
		maxRuntimeSecondsPerTick = coerceNumber(
			(source :: any).maxRuntimeSecondsPerTick,
			0.0005,
			0.02,
			fallback.maxRuntimeSecondsPerTick
		),
		maxChunksPerRuntimeTick = coerceInteger(
			(source :: any).maxChunksPerRuntimeTick,
			1,
			256,
			fallback.maxChunksPerRuntimeTick
		),
		runtimeClusterSlice = coerceInteger(
			(source :: any).runtimeClusterSlice,
			8,
			4096,
			fallback.runtimeClusterSlice
		),
		runtimeEntitySlice = coerceInteger((source :: any).runtimeEntitySlice, 8, 4096, fallback.runtimeEntitySlice),
		budgetCorruptionClustersPerTick = coerceInteger(
			(source :: any).budgetCorruptionClustersPerTick,
			8,
			200000,
			fallback.budgetCorruptionClustersPerTick
		),
		budgetBiomeSpreadClustersPerTick = coerceInteger(
			(source :: any).budgetBiomeSpreadClustersPerTick,
			8,
			200000,
			fallback.budgetBiomeSpreadClustersPerTick
		),
		budgetAiEntitiesPerTick = coerceInteger(
			(source :: any).budgetAiEntitiesPerTick,
			8,
			200000,
			fallback.budgetAiEntitiesPerTick
		),
		budgetPhysicsEntitiesPerTick = coerceInteger(
			(source :: any).budgetPhysicsEntitiesPerTick,
			8,
			200000,
			fallback.budgetPhysicsEntitiesPerTick
		),
		entityBatchSize = coerceInteger((source :: any).entityBatchSize, 8, 2048, fallback.entityBatchSize),
		entityCapacityPerChunk = coerceInteger(
			(source :: any).entityCapacityPerChunk,
			16,
			4096,
			fallback.entityCapacityPerChunk
		),
		corruptionSpreadRate = coerceNumber(
			(source :: any).corruptionSpreadRate,
			0,
			1,
			fallback.corruptionSpreadRate
		),
		corruptionDecayRate = coerceNumber((source :: any).corruptionDecayRate, 0, 1, fallback.corruptionDecayRate),
		corruptionActivationThreshold = coerceNumber(
			(source :: any).corruptionActivationThreshold,
			0,
			1,
			fallback.corruptionActivationThreshold
		),
		lodNearDistance = coerceNumber((source :: any).lodNearDistance, 32, 2048, fallback.lodNearDistance),
		lodFarDistance = coerceNumber((source :: any).lodFarDistance, 64, 4096, fallback.lodFarDistance),
		cacheTablePoolSize = coerceInteger((source :: any).cacheTablePoolSize, 8, 8192, fallback.cacheTablePoolSize),
		cacheArrayPoolSize = coerceInteger((source :: any).cacheArrayPoolSize, 8, 8192, fallback.cacheArrayPoolSize),
		maxPartPoolSize = coerceInteger((source :: any).maxPartPoolSize, 128, 50000, fallback.maxPartPoolSize),
		enableDebug = coerceBoolean((source :: any).enableDebug, fallback.enableDebug),
		enableProfiling = coerceBoolean((source :: any).enableProfiling, fallback.enableProfiling),
		biomeThresholds = coerceBiomeThresholds((source :: any).biomeThresholds, fallback.biomeThresholds),
	}

	if result.lodFarDistance < result.lodNearDistance then
		result.lodFarDistance = result.lodNearDistance
	end
	if result.renderRadiusChunks > result.streamRadiusChunks then
		result.renderRadiusChunks = result.streamRadiusChunks
	end
	if result.renderVerticalRadiusChunks > result.streamVerticalRadiusChunks then
		result.renderVerticalRadiusChunks = result.streamVerticalRadiusChunks
	end

	return result
end

return Config
