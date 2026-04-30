--!strict

local WorldGenerationServiceUtils = {}

export type WorldGenerationConfig = {
	seed: number,
	chunkSize: number,
	tileSize: number,
	tileDepth: number,
	basePlaneX: number,
	wallPlaneOffset: number,
	horizonDepthBlocks: number,
	backgroundLayerCount: number,
	backgroundLayerThicknessBlocks: number,
	worldOrigin: Vector3,
	minTileY: number,
	maxTileY: number,
	bedrockThickness: number,
	defaultRenderDistanceChunks: number,
	defaultVerticalRenderDistanceChunks: number,
	playerRefreshInterval: number,
	maxConcurrentChunkLoads: number,
	maxChunkUnloadsPerHeartbeat: number,
	maxChunkRebuildsPerHeartbeat: number,
	generationRowsPerYield: number,
	meshingRowsPerYield: number,
	maxCachedChunkData: number,
	maxCachedChunkVisuals: number,
	maxCollisionPartsPerChunk: number,
	maxPoolSize: number,
	debugLog: boolean,
}

export type WorldGenerationServiceState = {
	seed: number,
	chunkSize: number,
	tileSize: number,
	tileDepth: number,
	renderDistanceChunks: number,
	verticalRenderDistanceChunks: number,
	minTileY: number,
	maxTileY: number,
	ready: boolean,
	stats: { [string]: any },
	updatedAt: number,
}

local NETWORK_METHOD_REQUEST_SYNC = "requestSync"
local NETWORK_METHOD_SET_RENDER_DISTANCE = "setRenderDistance"

local DEFAULT_SEED = 13371337
local DEFAULT_CHUNK_SIZE = 32
local DEFAULT_TILE_SIZE = 2
local DEFAULT_TILE_DEPTH = 2
local DEFAULT_BASE_PLANE_X = 0
local DEFAULT_WALL_PLANE_OFFSET = 1.65
local DEFAULT_HORIZON_DEPTH_BLOCKS = 10
local DEFAULT_BACKGROUND_LAYER_COUNT = 4
local DEFAULT_BACKGROUND_LAYER_THICKNESS_BLOCKS = 1
local DEFAULT_WORLD_ORIGIN = Vector3.zero
local DEFAULT_MIN_TILE_Y = -360
local DEFAULT_MAX_TILE_Y = 180
local DEFAULT_BEDROCK_THICKNESS = 4
local DEFAULT_RENDER_DISTANCE_CHUNKS = 4
local DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS = 2
local DEFAULT_PLAYER_REFRESH_INTERVAL = 0.05
local DEFAULT_MAX_CONCURRENT_CHUNK_LOADS = 8
local DEFAULT_MAX_CHUNK_UNLOADS_PER_HEARTBEAT = 12
local DEFAULT_MAX_CHUNK_REBUILDS_PER_HEARTBEAT = 4
local DEFAULT_GENERATION_ROWS_PER_YIELD = 32
local DEFAULT_MESHING_ROWS_PER_YIELD = 64
local DEFAULT_MAX_CACHED_CHUNK_DATA = 1200
local DEFAULT_MAX_CACHED_CHUNK_VISUALS = 0
local DEFAULT_MAX_COLLISION_PARTS_PER_CHUNK = 4096
local DEFAULT_MAX_POOL_SIZE = 9000

local MIN_RENDER_DISTANCE_CHUNKS = 1
local MAX_RENDER_DISTANCE_CHUNKS = 24

WorldGenerationServiceUtils.NETWORK_METHOD_REQUEST_SYNC = NETWORK_METHOD_REQUEST_SYNC
WorldGenerationServiceUtils.NETWORK_METHOD_SET_RENDER_DISTANCE = NETWORK_METHOD_SET_RENDER_DISTANCE
WorldGenerationServiceUtils.DEFAULT_RENDER_DISTANCE_CHUNKS = DEFAULT_RENDER_DISTANCE_CHUNKS
WorldGenerationServiceUtils.DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS = DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS
WorldGenerationServiceUtils.MIN_RENDER_DISTANCE_CHUNKS = MIN_RENDER_DISTANCE_CHUNKS
WorldGenerationServiceUtils.MAX_RENDER_DISTANCE_CHUNKS = MAX_RENDER_DISTANCE_CHUNKS

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
		MIN_RENDER_DISTANCE_CHUNKS,
		MAX_RENDER_DISTANCE_CHUNKS,
		fallback or DEFAULT_RENDER_DISTANCE_CHUNKS
	)
end

function WorldGenerationServiceUtils.SanitizeVerticalRenderDistance(valueRaw: any, fallback: number?): number
	return sanitizeInteger(
		valueRaw,
		MIN_RENDER_DISTANCE_CHUNKS,
		MAX_RENDER_DISTANCE_CHUNKS,
		fallback or DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS
	)
end

function WorldGenerationServiceUtils.CreateDefaultConfig(): WorldGenerationConfig
	return {
		seed = DEFAULT_SEED,
		chunkSize = DEFAULT_CHUNK_SIZE,
		tileSize = DEFAULT_TILE_SIZE,
		tileDepth = DEFAULT_TILE_DEPTH,
		basePlaneX = DEFAULT_BASE_PLANE_X,
		wallPlaneOffset = DEFAULT_WALL_PLANE_OFFSET,
		horizonDepthBlocks = DEFAULT_HORIZON_DEPTH_BLOCKS,
		backgroundLayerCount = DEFAULT_BACKGROUND_LAYER_COUNT,
		backgroundLayerThicknessBlocks = DEFAULT_BACKGROUND_LAYER_THICKNESS_BLOCKS,
		worldOrigin = DEFAULT_WORLD_ORIGIN,
		minTileY = DEFAULT_MIN_TILE_Y,
		maxTileY = DEFAULT_MAX_TILE_Y,
		bedrockThickness = DEFAULT_BEDROCK_THICKNESS,
		defaultRenderDistanceChunks = DEFAULT_RENDER_DISTANCE_CHUNKS,
		defaultVerticalRenderDistanceChunks = DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS,
		playerRefreshInterval = DEFAULT_PLAYER_REFRESH_INTERVAL,
		maxConcurrentChunkLoads = DEFAULT_MAX_CONCURRENT_CHUNK_LOADS,
		maxChunkUnloadsPerHeartbeat = DEFAULT_MAX_CHUNK_UNLOADS_PER_HEARTBEAT,
		maxChunkRebuildsPerHeartbeat = DEFAULT_MAX_CHUNK_REBUILDS_PER_HEARTBEAT,
		generationRowsPerYield = DEFAULT_GENERATION_ROWS_PER_YIELD,
		meshingRowsPerYield = DEFAULT_MESHING_ROWS_PER_YIELD,
		maxCachedChunkData = DEFAULT_MAX_CACHED_CHUNK_DATA,
		maxCachedChunkVisuals = DEFAULT_MAX_CACHED_CHUNK_VISUALS,
		maxCollisionPartsPerChunk = DEFAULT_MAX_COLLISION_PARTS_PER_CHUNK,
		maxPoolSize = DEFAULT_MAX_POOL_SIZE,
		debugLog = false,
	}
end

function WorldGenerationServiceUtils.SanitizeConfig(
	configRaw: any,
	fallbackConfig: WorldGenerationConfig?
): WorldGenerationConfig
	local fallback = if fallbackConfig then fallbackConfig else WorldGenerationServiceUtils.CreateDefaultConfig()
	local source = if typeof(configRaw) == "table" then configRaw else {}

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
			4,
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
		maxPoolSize = sanitizeInteger((source :: any).maxPoolSize, 64, 200000, fallback.maxPoolSize),
		debugLog = if typeof((source :: any).debugLog) == "boolean"
			then (source :: any).debugLog
			else fallback.debugLog,
	}
end

function WorldGenerationServiceUtils.CreateDefaultState(): WorldGenerationServiceState
	return {
		seed = DEFAULT_SEED,
		chunkSize = DEFAULT_CHUNK_SIZE,
		tileSize = DEFAULT_TILE_SIZE,
		tileDepth = DEFAULT_TILE_DEPTH,
		renderDistanceChunks = DEFAULT_RENDER_DISTANCE_CHUNKS,
		verticalRenderDistanceChunks = DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS,
		minTileY = DEFAULT_MIN_TILE_Y,
		maxTileY = DEFAULT_MAX_TILE_Y,
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
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
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
	local statsClone: { [string]: any } = {}
	for key, value in state.stats do
		statsClone[key] = value
	end

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
