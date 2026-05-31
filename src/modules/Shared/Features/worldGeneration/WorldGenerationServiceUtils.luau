--!strict

local WorldGenerationConstants = require(script.Parent.WorldGenerationConstants)
local WorldGenerationTypes = require(script.Parent.WorldGenerationTypes)

local WorldGenerationServiceUtils = {}

export type WorldGenerationConfig = WorldGenerationTypes.WorldGenerationConfig
export type WorldGenerationServiceState = WorldGenerationTypes.WorldGenerationServiceState

WorldGenerationServiceUtils.NETWORK_METHOD_REQUEST_SYNC = WorldGenerationConstants.NETWORK_METHOD_REQUEST_SYNC
WorldGenerationServiceUtils.NETWORK_METHOD_SET_RENDER_DISTANCE = WorldGenerationConstants.NETWORK_METHOD_SET_RENDER_DISTANCE
WorldGenerationServiceUtils.DEFAULT_RENDER_DISTANCE_CHUNKS = WorldGenerationConstants.DEFAULT_RENDER_DISTANCE_CHUNKS
WorldGenerationServiceUtils.DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS = WorldGenerationConstants.DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS
WorldGenerationServiceUtils.MIN_RENDER_DISTANCE_CHUNKS = WorldGenerationConstants.MIN_RENDER_DISTANCE_CHUNKS
WorldGenerationServiceUtils.MAX_RENDER_DISTANCE_CHUNKS = WorldGenerationConstants.MAX_RENDER_DISTANCE_CHUNKS

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	local value = math.floor(valueRaw :: number)
	return math.clamp(value, minimum, maximum)
end

local function sanitizeNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw :: number, minimum, maximum)
end

function WorldGenerationServiceUtils.SanitizeRenderDistance(valueRaw: any, fallback: number?): number
	return sanitizeInteger(
		valueRaw,
		WorldGenerationConstants.MIN_RENDER_DISTANCE_CHUNKS,
		WorldGenerationConstants.MAX_RENDER_DISTANCE_CHUNKS,
		fallback or WorldGenerationConstants.DEFAULT_RENDER_DISTANCE_CHUNKS
	)
end

function WorldGenerationServiceUtils.SanitizeVerticalRenderDistance(valueRaw: any, fallback: number?): number
	return sanitizeInteger(
		valueRaw,
		WorldGenerationConstants.MIN_RENDER_DISTANCE_CHUNKS,
		WorldGenerationConstants.MAX_RENDER_DISTANCE_CHUNKS,
		fallback or WorldGenerationConstants.DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS
	)
end

function WorldGenerationServiceUtils.CreateDefaultConfig(): WorldGenerationConfig
	return {
		seed = WorldGenerationConstants.DEFAULT_SEED,
		chunkSize = WorldGenerationConstants.DEFAULT_CHUNK_SIZE,
		tileSize = WorldGenerationConstants.DEFAULT_TILE_SIZE,
		tileDepth = WorldGenerationConstants.DEFAULT_TILE_DEPTH,
		basePlaneX = WorldGenerationConstants.DEFAULT_BASE_PLANE_X,
		wallPlaneOffset = WorldGenerationConstants.DEFAULT_WALL_PLANE_OFFSET,
		horizonDepthBlocks = WorldGenerationConstants.DEFAULT_HORIZON_DEPTH_BLOCKS,
		backgroundLayerCount = WorldGenerationConstants.DEFAULT_BACKGROUND_LAYER_COUNT,
		backgroundLayerThicknessBlocks = WorldGenerationConstants.DEFAULT_BACKGROUND_LAYER_THICKNESS_BLOCKS,
		worldOrigin = WorldGenerationConstants.DEFAULT_WORLD_ORIGIN,
		minTileY = WorldGenerationConstants.DEFAULT_MIN_TILE_Y,
		maxTileY = WorldGenerationConstants.DEFAULT_MAX_TILE_Y,
		bedrockThickness = WorldGenerationConstants.DEFAULT_BEDROCK_THICKNESS,
		defaultRenderDistanceChunks = WorldGenerationConstants.DEFAULT_RENDER_DISTANCE_CHUNKS,
		defaultVerticalRenderDistanceChunks = WorldGenerationConstants.DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS,
		playerRefreshInterval = WorldGenerationConstants.DEFAULT_PLAYER_REFRESH_INTERVAL,
		maxConcurrentChunkLoads = WorldGenerationConstants.DEFAULT_MAX_CONCURRENT_CHUNK_LOADS,
		maxChunkUnloadsPerHeartbeat = WorldGenerationConstants.DEFAULT_MAX_CHUNK_UNLOADS_PER_HEARTBEAT,
		maxChunkRebuildsPerHeartbeat = WorldGenerationConstants.DEFAULT_MAX_CHUNK_REBUILDS_PER_HEARTBEAT,
		generationRowsPerYield = WorldGenerationConstants.DEFAULT_GENERATION_ROWS_PER_YIELD,
		meshingRowsPerYield = WorldGenerationConstants.DEFAULT_MESHING_ROWS_PER_YIELD,
		maxCachedChunkData = WorldGenerationConstants.DEFAULT_MAX_CACHED_CHUNK_DATA,
		maxCachedChunkVisuals = WorldGenerationConstants.DEFAULT_MAX_CACHED_CHUNK_VISUALS,
		maxCollisionPartsPerChunk = WorldGenerationConstants.DEFAULT_MAX_COLLISION_PARTS_PER_CHUNK,
		clientVisualPreloadMarginPixels = WorldGenerationConstants.DEFAULT_CLIENT_VISUAL_PRELOAD_MARGIN_PIXELS,
		clientVisualBuildTimeBudgetSeconds = WorldGenerationConstants.DEFAULT_CLIENT_VISUAL_BUILD_TIME_BUDGET_SECONDS,
		clientVisualUnloadTimeBudgetSeconds = WorldGenerationConstants.DEFAULT_CLIENT_VISUAL_UNLOAD_TIME_BUDGET_SECONDS,
		maxPooledVisualParts = WorldGenerationConstants.DEFAULT_MAX_POOLED_VISUAL_PARTS,
		maxPoolSize = WorldGenerationConstants.DEFAULT_MAX_POOL_SIZE,
		debugLog = false,
	}
end

function WorldGenerationServiceUtils.SanitizeConfig(
	configRaw: any,
	fallbackConfig: WorldGenerationConfig?
): WorldGenerationConfig
	local fallback = if fallbackConfig then fallbackConfig else WorldGenerationServiceUtils.CreateDefaultConfig()
	local source = if typeof(configRaw) == "table" then configRaw else ({} :: any)

	local minTileY = sanitizeInteger((source :: any).minTileY, -2048, 2048, fallback.minTileY)
	local maxTileY = sanitizeInteger((source :: any).maxTileY, -2048, 2048, fallback.maxTileY)

	return {
		seed = sanitizeInteger((source :: any).seed, -2147483648, 2147483647, fallback.seed),
		chunkSize = sanitizeInteger((source :: any).chunkSize, 8, 128, fallback.chunkSize),
		tileSize = sanitizeNumber((source :: any).tileSize, 1, 64, fallback.tileSize),
		tileDepth = sanitizeNumber((source :: any).tileDepth, 0.5, 64, fallback.tileDepth),
		basePlaneX = sanitizeNumber((source :: any).basePlaneX, -4096, 4096, fallback.basePlaneX),
		wallPlaneOffset = sanitizeNumber((source :: any).wallPlaneOffset, 0.1, 64, fallback.wallPlaneOffset),
		horizonDepthBlocks = sanitizeInteger((source :: any).horizonDepthBlocks, 10, 256, fallback.horizonDepthBlocks),
		backgroundLayerCount = sanitizeInteger(
			(source :: any).backgroundLayerCount,
			3,
			6,
			fallback.backgroundLayerCount
		),
		backgroundLayerThicknessBlocks = sanitizeNumber(
			(source :: any).backgroundLayerThicknessBlocks,
			0.5,
			3,
			fallback.backgroundLayerThicknessBlocks
		),
		worldOrigin = if typeof((source :: any).worldOrigin) == "Vector3"
			then (source :: any).worldOrigin
			else fallback.worldOrigin,
		minTileY = math.min(minTileY, maxTileY),
		maxTileY = math.max(minTileY, maxTileY),
		bedrockThickness = sanitizeInteger((source :: any).bedrockThickness, 0, 32, fallback.bedrockThickness),
		defaultRenderDistanceChunks = WorldGenerationServiceUtils.SanitizeRenderDistance(
			(source :: any).defaultRenderDistanceChunks,
			fallback.defaultRenderDistanceChunks
		),
		defaultVerticalRenderDistanceChunks = WorldGenerationServiceUtils.SanitizeVerticalRenderDistance(
			(source :: any).defaultVerticalRenderDistanceChunks,
			fallback.defaultVerticalRenderDistanceChunks
		),
		playerRefreshInterval = sanitizeNumber(
			(source :: any).playerRefreshInterval,
			0.03,
			2,
			fallback.playerRefreshInterval
		),
		maxConcurrentChunkLoads = sanitizeInteger(
			(source :: any).maxConcurrentChunkLoads,
			1,
			16,
			fallback.maxConcurrentChunkLoads
		),
		maxChunkUnloadsPerHeartbeat = sanitizeInteger(
			(source :: any).maxChunkUnloadsPerHeartbeat,
			1,
			128,
			fallback.maxChunkUnloadsPerHeartbeat
		),
		maxChunkRebuildsPerHeartbeat = sanitizeInteger(
			(source :: any).maxChunkRebuildsPerHeartbeat,
			1,
			64,
			fallback.maxChunkRebuildsPerHeartbeat
		),
		generationRowsPerYield = sanitizeInteger(
			(source :: any).generationRowsPerYield,
			1,
			64,
			fallback.generationRowsPerYield
		),
		meshingRowsPerYield = sanitizeInteger(
			(source :: any).meshingRowsPerYield,
			1,
			128,
			fallback.meshingRowsPerYield
		),
		maxCachedChunkData = sanitizeInteger((source :: any).maxCachedChunkData, 16, 4096, fallback.maxCachedChunkData),
		maxCachedChunkVisuals = sanitizeInteger(
			(source :: any).maxCachedChunkVisuals,
			0,
			512,
			fallback.maxCachedChunkVisuals
		),
		maxCollisionPartsPerChunk = sanitizeInteger(
			(source :: any).maxCollisionPartsPerChunk,
			64,
			20000,
			fallback.maxCollisionPartsPerChunk
		),
		clientVisualPreloadMarginPixels = sanitizeInteger(
			(source :: any).clientVisualPreloadMarginPixels,
			0,
			1024,
			fallback.clientVisualPreloadMarginPixels
		),
		clientVisualBuildTimeBudgetSeconds = sanitizeNumber(
			(source :: any).clientVisualBuildTimeBudgetSeconds,
			0.001,
			0.03,
			fallback.clientVisualBuildTimeBudgetSeconds
		),
		clientVisualUnloadTimeBudgetSeconds = sanitizeNumber(
			(source :: any).clientVisualUnloadTimeBudgetSeconds,
			0.001,
			0.03,
			fallback.clientVisualUnloadTimeBudgetSeconds
		),
		maxPooledVisualParts = sanitizeInteger(
			(source :: any).maxPooledVisualParts,
			0,
			50000,
			fallback.maxPooledVisualParts
		),
		maxPoolSize = sanitizeInteger((source :: any).maxPoolSize, 64, 200000, fallback.maxPoolSize),
		debugLog = if typeof((source :: any).debugLog) == "boolean"
			then (source :: any).debugLog
			else fallback.debugLog,
	}
end

function WorldGenerationServiceUtils.CreateDefaultState(): WorldGenerationServiceState
	return {
		seed = WorldGenerationConstants.DEFAULT_SEED,
		chunkSize = WorldGenerationConstants.DEFAULT_CHUNK_SIZE,
		tileSize = WorldGenerationConstants.DEFAULT_TILE_SIZE,
		tileDepth = WorldGenerationConstants.DEFAULT_TILE_DEPTH,
		renderDistanceChunks = WorldGenerationConstants.DEFAULT_RENDER_DISTANCE_CHUNKS,
		verticalRenderDistanceChunks = WorldGenerationConstants.DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS,
		minTileY = WorldGenerationConstants.DEFAULT_MIN_TILE_Y,
		maxTileY = WorldGenerationConstants.DEFAULT_MAX_TILE_Y,
		ready = false,
		stats = {},
		updatedAt = os.clock(),
	}
end

function WorldGenerationServiceUtils.CreateState(
	stateRaw: any,
	fallbackStateRaw: WorldGenerationServiceState?
): WorldGenerationServiceState
	local fallback = if fallbackStateRaw then fallbackStateRaw else WorldGenerationServiceUtils.CreateDefaultState()
	local source = if typeof(stateRaw) == "table" then stateRaw else ({} :: any)
	local minTileY = sanitizeInteger((source :: any).minTileY, -2048, 2048, fallback.minTileY)
	local maxTileY = sanitizeInteger((source :: any).maxTileY, -2048, 2048, fallback.maxTileY)

	return {
		seed = sanitizeInteger((source :: any).seed, -2147483648, 2147483647, fallback.seed),
		chunkSize = sanitizeInteger((source :: any).chunkSize, 8, 128, fallback.chunkSize),
		tileSize = sanitizeNumber((source :: any).tileSize, 1, 64, fallback.tileSize),
		tileDepth = sanitizeNumber((source :: any).tileDepth, 0.5, 64, fallback.tileDepth),
		renderDistanceChunks = WorldGenerationServiceUtils.SanitizeRenderDistance(
			(source :: any).renderDistanceChunks,
			fallback.renderDistanceChunks
		),
		verticalRenderDistanceChunks = WorldGenerationServiceUtils.SanitizeVerticalRenderDistance(
			(source :: any).verticalRenderDistanceChunks,
			fallback.verticalRenderDistanceChunks
		),
		minTileY = math.min(minTileY, maxTileY),
		maxTileY = math.max(minTileY, maxTileY),
		ready = if typeof((source :: any).ready) == "boolean" then (source :: any).ready else fallback.ready,
		stats = if typeof((source :: any).stats) == "table" then (source :: any).stats else fallback.stats,
		updatedAt = os.clock(),
	}
end

function WorldGenerationServiceUtils.CloneState(state: WorldGenerationServiceState): WorldGenerationServiceState
	local statsClone: { [string]: any } = table.clone(state.stats)

	return {
		seed = state.seed,
		chunkSize = state.chunkSize,
		tileSize = state.tileSize,
		tileDepth = state.tileDepth,
		renderDistanceChunks = state.renderDistanceChunks,
		verticalRenderDistanceChunks = state.verticalRenderDistanceChunks,
		minTileY = state.minTileY,
		maxTileY = state.maxTileY,
		ready = state.ready,
		stats = statsClone,
		updatedAt = state.updatedAt,
	}
end

WorldGenerationServiceUtils.sanitizeRenderDistance = WorldGenerationServiceUtils.SanitizeRenderDistance
WorldGenerationServiceUtils.sanitizeVerticalRenderDistance = WorldGenerationServiceUtils.SanitizeVerticalRenderDistance
WorldGenerationServiceUtils.createDefaultConfig = WorldGenerationServiceUtils.CreateDefaultConfig
WorldGenerationServiceUtils.sanitizeConfig = WorldGenerationServiceUtils.SanitizeConfig
WorldGenerationServiceUtils.createDefaultState = WorldGenerationServiceUtils.CreateDefaultState
WorldGenerationServiceUtils.createState = WorldGenerationServiceUtils.CreateState
WorldGenerationServiceUtils.cloneState = WorldGenerationServiceUtils.CloneState

return WorldGenerationServiceUtils
