local require = require(script.Parent.loader).load(script)

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Sift: any = require(ReplicatedStorage.Packages.Sift)
local Workspace = game:GetService("Workspace")

local Brio: any = require("Brio")
local Maid = require("Maid")
local Octree = require("Octree")
local Queue: any = require("Queue")
local Rx: any = require("Rx")
local RxBrioUtils: any = require("RxBrioUtils")
local RxSignal: any = require("RxSignal")
local Signal = require("Signal")
local String = require("String")

local Biome = require("Biome")
local Cache = require("GenerationCache")
local Cave = require("Cave")
local Configs = require("CoreConfigs")
local Liquid = require("Liquid")
local ProceduralTree = require("WorldGenerationTree")
local Structures = require("Structures")
local TagBinder = require("TagBinder")
local TileComponent = require("Tile")
local TileMaterial = require("TileMaterial")
local WallServiceUtils = require("WallServiceUtils")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationColor = require("WorldGenerationColor")
local WorldGenerationConstants = require("WorldGenerationConstants")
local WorldGenerationDesert = require("WorldGenerationDesert")
local WorldGenerationSnow = require("WorldGenerationSnow")

type BiomeClass = Biome.Biome
type CaveClass = Cave.Cave
type LiquidGenerationClass = Liquid.LiquidGeneration
type StructuresClass = Structures.Structures
type StructureGenerationResult = Structures.StructureGenerationResult
type CacheClass = Cache.Cache
type ColumnProfile = Biome.ColumnProfile
type ProceduralTreeConfig = ProceduralTree.ProceduralTreeConfig
type MaidClass = any
type SignalObject = Signal.Signal<...any>
type ObservableObject = any
type RxSignalObject = any
type BrioObject = any
type OctreeNodeObject = {
	SetPosition: (self: OctreeNodeObject, position: Vector3) -> (),
	Destroy: (self: OctreeNodeObject) -> (),
}
type QueueClass<T> = any

type TreeVariantConfig = {
	config: ProceduralTreeConfig,
	biomeType: number?,
	biomeId: number?,
}

type TileVisual = {
	name: string,
	color: Color3,
	material: Enum.Material,
	transparency: number,
}

type BackgroundLayerData = {
	layerIndex: number,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tiles: { number },
}

type TreeSpawnData = {
	tileX: number,
	tileY: number,
	variantIndex: number,
	seed: number,
	biomeType: number,
	biomeId: number,
	templateIndex: number?,
}

type PropSpawnData = {
	tileX: number,
	tileY: number,
	propId: number,
	variantIndex: number,
	seed: number,
	biomeType: number,
	biomeId: number,
}

type ChunkData = {
	key: string,
	chunkX: number,
	chunkY: number,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tiles: { number },
	walls: { number },
	liquids: { number },
	depthLayers: { number },
	depthBelowSurface: { number },
	biomeIds: { number },
	surfaceBiomeIds: { number },
	biomeTypes: { number },
	dominantBiomeId: number,
	dominantBiomeType: number,
	backgroundLayers: { BackgroundLayerData },
	trees: { TreeSpawnData },
	props: { PropSpawnData },
	generatedAt: number,
	lastAccessedAt: number,
}

type ChunkVisual = {
	key: string,
	chunkX: number,
	chunkY: number,
	model: Model,
	terrainFolder: Folder?,
	backgroundFolder: Folder?,
	treesFolder: Folder?,
	parts: { BasePart },
	loadedAt: number,
	lastAccessedAt: number,
}

type ChunkDirtyBounds = {
	minTileX: number,
	minTileY: number,
	maxTileX: number,
	maxTileY: number,
}

type ChunkLifecycleObserver = {
	OnChunkCollisionReady: ((self: any, chunkX: number, chunkY: number, context: any?) -> ())?,
	OnChunkCollisionUnloaded: ((self: any, chunkX: number, chunkY: number, context: any?) -> ())?,
	OnChunkTerrainChanged: ((
		self: any,
		chunkX: number,
		chunkY: number,
		dirtyBounds: ChunkDirtyBounds,
		context: any?
	) -> ())?,
}

type ChunkLifecycleConnection = {
	Disconnect: (self: ChunkLifecycleConnection) -> (),
}

type ChunkLifecycleEvent = {
	chunkKey: string,
	chunkX: number,
	chunkY: number,
	reason: string,
	context: { [string]: any },
}

type ChunkTerrainChangedEvent = ChunkLifecycleEvent & {
	dirtyBounds: ChunkDirtyBounds,
}

type ChunkDemandChangedEvent = {
	chunkKey: string,
	previousDemand: number,
	nextDemand: number,
}

type PlayerInterestChangedEvent = {
	player: Player,
	focusPosition: Vector3?,
	centerChunkX: number?,
	centerChunkY: number?,
	renderDistance: number,
	verticalRenderDistance: number,
	interestKeys: { [string]: boolean },
}

type PlayerRuntime = {
	maid: MaidClass,
	brio: BrioObject,
	renderDistance: number,
	verticalRenderDistance: number,
	interestKeys: { [string]: boolean },
	refreshAccumulator: number,
	forceRefresh: boolean,
	lastChunkX: number?,
	lastChunkY: number?,
	focusPosition: Vector3?,
	focusNode: OctreeNodeObject?,
}

type GreedyRect = {
	x: number,
	y: number,
	width: number,
	height: number,
	value: number,
}

type DepthLayer = Cave.DepthLayer

type ChasmSeedColumn = {
	worldX: number,
	surfaceY: number,
}

type ChasmWalker = {
	x: number,
	y: number,
	depthRemaining: number,
	baseRadius: number,
	driftVelocity: number,
	branchChance: number,
	seedValue: number,
	generation: number,
}

type BiomeBlendAxisData = {
	primaryColumn: ColumnProfile,
	secondaryColumn: ColumnProfile?,
	edgeDistance: number,
}

export type TileIdMap = {
	AIR: number,
	GRASS: number,
	JUNGLE_GRASS: number,
	WOOD: number,
	DIRT: number,
	STONE: number,
	SAND: number,
	SANDSTONE: number,
	SNOW: number,
	ICE: number,
	MUD: number,
	CLAY: number,
	COPPER_ORE: number,
	IRON_ORE: number,
	SILVER_ORE: number,
	GOLD_ORE: number,
	CORRUPT_GRASS: number,
	CORRUPT_SOIL: number,
	CORRUPT_STONE: number,
}

export type WallIdMap = {
	NONE: number,
	DIRT: number,
	STONE: number,
	SANDSTONE: number,
	SNOW: number,
	MUD: number,
}

export type BiomeIdMap = {
	FOREST: number,
	DESERT: number,
	SNOW: number,
	JUNGLE: number,
}

export type BiomeTypeMap = {
	NORMAL: number,
	CORRUPTION: number,
}

export type WorldGenerationConfig = {
	seed: number?,
	chunkSize: number?,
	tileSize: number?,
	tileDepth: number?,
	basePlaneX: number?,
	wallPlaneOffset: number?,
	horizonDepthBlocks: number?,
	backgroundLayerCount: number?,
	backgroundLayerThicknessBlocks: number?,
	worldOrigin: Vector3?,
	minTileY: number?,
	maxTileY: number?,
	bedrockThickness: number?,
	defaultRenderDistanceChunks: number?,
	defaultVerticalRenderDistanceChunks: number?,
	playerRefreshInterval: number?,
	maxConcurrentChunkLoads: number?,
	maxChunkUnloadsPerHeartbeat: number?,
	generationRowsPerYield: number?,
	meshingRowsPerYield: number?,
	maxCachedChunkData: number?,
	maxCachedChunkVisuals: number?,
	maxPoolSize: number?,
	clientVisualPreloadMarginPixels: number?,
	clientVisualBuildTimeBudgetSeconds: number?,
	clientVisualUnloadTimeBudgetSeconds: number?,
	maxPooledVisualParts: number?,
	parent: Instance?,
	desertConfig: any?,
	snowConfig: any?,
}

local WorldGeneration = {}
WorldGeneration.__index = WorldGeneration

export type WorldGeneration = typeof(setmetatable({} :: any, WorldGeneration))

local TILE_ID: TileIdMap = {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	SANDSTONE = 5,
	SNOW = 6,
	ICE = 7,
	MUD = 8,
	CLAY = 9,
	COPPER_ORE = 10,
	IRON_ORE = 11,
	SILVER_ORE = 12,
	GOLD_ORE = 13,
	CORRUPT_GRASS = 14,
	CORRUPT_SOIL = 15,
	CORRUPT_STONE = 16,
	JUNGLE_GRASS = 17,
	WOOD = 18,
}

local function getMaxTileId(tileIdMap: { [string]: number }): number
	local maxTileId = 0
	for _, tileId in tileIdMap do
		if tileId > maxTileId then
			maxTileId = tileId
		end
	end
	return maxTileId
end

local MAX_TILE_ID = getMaxTileId(TILE_ID)

local WALL_ID = WallServiceUtils.WALL_ID :: WallIdMap
local MAX_WALL_ID = WallServiceUtils.MAX_WALL_ID

local BIOME_ID: BiomeIdMap = {
	FOREST = 1,
	DESERT = 2,
	SNOW = 3,
	JUNGLE = 4,
}

local BIOME_TYPE: BiomeTypeMap = {
	NORMAL = 1,
	CORRUPTION = 2,
}

local PROP_ID = {
	CORRUPTION_SPIKE = 1,
	DESERT_CACTUS = 2,
	DEAD_BUSH = 3,
	DESERT_ROCK = 4,
	SNOW_PILE = 5,
	ICE_SPIKE = 6,
}

local DEPTH_LAYER_CODE = {
	SKY = 0,
	SURFACE = 1,
	UNDERGROUND = 2,
	CAVERN = 3,
	DEEP = 4,
}

local TILE_VISUALS: { [number]: TileVisual } = WorldGenerationColor.TILE_VISUALS
local TREE_PALETTE_CORRUPTION_1 = WorldGenerationColor.TREE_PALETTES.Corruption1
	or {
		BranchColor = Color3.fromRGB(56, 39, 89),
		LeafColor = Color3.fromRGB(153, 92, 210),
	}
local TREE_PALETTE_CORRUPTION_2 = WorldGenerationColor.TREE_PALETTES.Corruption2
	or {
		BranchColor = Color3.fromRGB(49, 33, 81),
		LeafColor = Color3.fromRGB(171, 101, 231),
	}
local TREE_PALETTE_JUNGLE_1 = WorldGenerationColor.TREE_PALETTES.Jungle1
	or {
		BranchColor = Color3.fromRGB(88, 65, 42),
		LeafColor = Color3.fromRGB(67, 178, 86),
	}
local TREE_PALETTE_JUNGLE_2 = WorldGenerationColor.TREE_PALETTES.Jungle2
	or {
		BranchColor = Color3.fromRGB(82, 60, 39),
		LeafColor = Color3.fromRGB(74, 192, 96),
	}
local TREE_PALETTE_SNOW_1 = WorldGenerationColor.TREE_PALETTES.Snow1
	or {
		BranchColor = Color3.fromRGB(89, 75, 70),
		LeafColor = Color3.fromRGB(220, 238, 244),
	}
local TREE_PALETTE_SNOW_2 = WorldGenerationColor.TREE_PALETTES.Snow2
	or {
		BranchColor = Color3.fromRGB(74, 68, 81),
		LeafColor = Color3.fromRGB(197, 226, 239),
	}

local DEFAULT_SEED = 93847583
local DEFAULT_CHUNK_SIZE = 32
local _DEFAULT_TILE_SIZE = 2
local _DEFAULT_TILE_DEPTH = 2
local DEFAULT_BASE_PLANE_X = 0
local DEFAULT_WALL_PLANE_OFFSET = WorldGenerationConstants.DEFAULT_WALL_PLANE_OFFSET
local DEFAULT_HORIZON_DEPTH_BLOCKS = 10
local DEFAULT_BACKGROUND_LAYER_COUNT = 1
local DEFAULT_BACKGROUND_LAYER_THICKNESS_BLOCKS = 1
local DEFAULT_MIN_TILE_Y = -360
local DEFAULT_MAX_TILE_Y = 180
local DEFAULT_BEDROCK_THICKNESS = 4
local DEFAULT_RENDER_DISTANCE_CHUNKS = 4
local DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS = 2
local DEFAULT_PLAYER_REFRESH_INTERVAL = 0.05
local DEFAULT_MAX_CONCURRENT_CHUNK_LOADS = 8
local DEFAULT_MAX_CHUNK_UNLOADS_PER_HEARTBEAT = 12
local DEFAULT_GENERATION_ROWS_PER_YIELD = 32
local DEFAULT_MESHING_RECTS_PER_YIELD = 64
local DEFAULT_MAX_CACHED_CHUNK_DATA = 1200
local DEFAULT_MAX_CACHED_CHUNK_VISUALS = 0
local DEFAULT_POOL_SIZE = 9000
local FIXED_TILE_SIZE_STUDS = 2
local FIXED_TILE_DEPTH_STUDS = 2
local DEFAULT_PRELOAD_FOCUS_SURFACE_OFFSET_TILES = 4
local DEFAULT_WORLD_FOLDER_NAME = "WorldGeneration"
local DEFAULT_WORLD_CHUNKS_FOLDER_NAME = "Chunks"
local DEFAULT_WORLD_COLLISION_FOLDER_NAME = "CollisionChunks"
local SKIP_WORLD_ANIMATOR_ATTRIBUTE = "SkipWorldAnimator"
local WORLD_ANIMATOR_CHUNK_ATTRIBUTE = "WorldAnimatorChunk"
local BACKGROUND_LAYER_BOUNDS_PADDING_TILES = 5
local MISSING_ASSET_ERROR = "no asset found!"

local BG_SEED_X_MULTIPLIER = 0.000193
local BG_SEED_Y_MULTIPLIER = 0.000327
local BG_PRIMARY_OFFSET_X = 1547.42
local BG_PRIMARY_OFFSET_Y = 907.13
local BG_SECONDARY_OFFSET_X = 1781.64
local BG_SECONDARY_OFFSET_Y = 1113.25
local BG_CRACK_OFFSET_X = 1961.09
local BG_CRACK_OFFSET_Y = 1289.88
local BG_LAYER_CONNECTION_OFFSET_X = 2143.37
local BG_LAYER_CONNECTION_OFFSET_Y = 1477.58
local GRASS_TEMPLATE_X_ROTATION_FIX = CFrame.Angles(math.rad(90), 0, 0)
local TREE_REQUIRED_AIR_CLEARANCE = 3
local TREE_SPACING_TILES = 8
local TREE_FOOTPRINT_RADIUS_TILES = 2
local TREE_MAX_NEAR_SURFACE_STEP_TILES = 1
local TREE_MAX_FOOTPRINT_SURFACE_STEP_TILES = 2
local TREE_MIN_VISUAL_SPACING_TILES = 6
local TREE_SPACING_PRIORITY_SALT = 15485863
local _TREE_PLANE_DEPTH_ALPHA = 0.5
local _TREE_SURFACE_OFFSET_Y_TILES = 1
local TREE_SLOT_NOISE_FREQUENCY = 0.739
local TREE_VARIANT_NOISE_FREQUENCY_X = 0.413
local TREE_VARIANT_NOISE_FREQUENCY_Y = 0.217
local UINT32_MAX = 0xFFFFFFFF
local INT32_SIGN_BIT = 0x80000000
local UINT32_WRAP = 4294967296
local CORRUPTION_CHASM_CHUNK_SPAWN_CHANCE = 0.74
local CORRUPTION_CHASM_MIN_SEEDS = 1
local CORRUPTION_CHASM_MAX_SEEDS = 3
local CORRUPTION_CHASM_MIN_DEPTH = 26
local CORRUPTION_CHASM_MAX_DEPTH = 94
local CORRUPTION_CHASM_MIN_RADIUS = 1.2
local CORRUPTION_CHASM_MAX_RADIUS = 4.6
local CORRUPTION_CHASM_RADIUS_VARIATION = 1.3
local CORRUPTION_CHASM_RADIUS_NOISE_FREQUENCY = 0.137
local CORRUPTION_CHASM_WORM_NOISE_FREQUENCY = 0.089
local CORRUPTION_CHASM_WORM_OFFSET_X = 2683.43
local CORRUPTION_CHASM_WORM_OFFSET_Y = 2917.12
local CORRUPTION_CHASM_RADIUS_OFFSET_X = 3191.87
local CORRUPTION_CHASM_RADIUS_OFFSET_Y = 3461.29
local CORRUPTION_CHASM_RANDOM_DRIFT_BIAS = 0.22
local CORRUPTION_CHASM_MAX_DRIFT_PER_STEP = 1.4
local CORRUPTION_CHASM_MIN_SEED_SPACING = 5
local CORRUPTION_CHASM_BRANCH_CHANCE = 0.07
local CORRUPTION_CHASM_MAX_BRANCHES = 8
local CORRUPTION_CHASM_MAX_BRANCH_GENERATION = 2
local CORRUPTION_CHASM_BRANCH_MIN_DEPTH = 8
local CORRUPTION_CHASM_BRANCH_MIN_RADIUS = 0.85
local CORRUPTION_CHASM_SMOOTHING_PASSES = 2
local CORRUPTION_CHASM_MIN_SOLID_NEIGHBORS = 4
local BIOME_BLEND_CLUSTER_SIZE_TILES = 2
local BIOME_BLEND_TRANSITION_WIDTH_TILES = 8
local BIOME_BLEND_EDGE_SCAN_TILES = 20
local BIOME_BLEND_MIN_SECONDARY_CHANCE = 0.3
local BIOME_BLEND_MAX_SECONDARY_CHANCE = 0.5
local BIOME_BLEND_NOISE_WEIGHT = 0.28
local BIOME_BLEND_NOISE_FREQUENCY = 0.371
local BIOME_BLEND_NOISE_OFFSET_X = 3697.21
local BIOME_BLEND_NOISE_OFFSET_Y = 4021.57
local BIOME_BLEND_NOISE_OFFSET_Z = 4391.63
local BIOME_BLEND_TIE_BREAK_SALT = 7919
local BIOME_BLEND_CLUSTER_ROLL_SALT = 104729
local DESERT_CACTUS_SLOT_NOISE_FREQUENCY = 0.511
local _DESERT_CLUTTER_SLOT_NOISE_FREQUENCY = 0.427
local DESERT_ROCK_SLOT_NOISE_FREQUENCY = 0.389
local DESERT_PROP_VARIANT_NOISE_FREQUENCY_X = 0.293
local DESERT_PROP_VARIANT_NOISE_FREQUENCY_Y = 0.187
local SNOW_PILE_SLOT_NOISE_FREQUENCY = 0.463

WorldGeneration.TILE_ID = TILE_ID
WorldGeneration.WALL_ID = WALL_ID
WorldGeneration.BIOME_ID = BIOME_ID
WorldGeneration.BIOME_TYPE = BIOME_TYPE
WorldGeneration.PROP_ID = PROP_ID
WorldGeneration.TILE_VISUALS = TILE_VISUALS

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw :: number, minimum, maximum)
end

local function coerceInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	local value = math.floor(valueRaw :: number)
	return math.clamp(value, minimum, maximum)
end

local function cloneBooleanLookup(sourceRaw: any): { [string]: boolean }
	local clone = {}
	if typeof(sourceRaw) ~= "table" then
		return clone
	end

	for key, value in sourceRaw do
		if typeof(key) == "string" and value == true then
			clone[key] = true
		end
	end

	return clone
end

local function cloneDictionaryShallow(sourceRaw: any): { [string]: any }
	local clone = {}
	if typeof(sourceRaw) ~= "table" then
		return clone
	end

	for key, value in sourceRaw do
		if typeof(key) == "string" then
			clone[key] = value
		end
	end

	return clone
end

local function countLookupEntries(lookup: { [any]: any }): number
	local count = 0
	for _ in lookup do
		count += 1
	end
	return count
end

local function didVectorMeaningfullyChange(previous: Vector3?, nextValue: Vector3?, minimumDistance: number): boolean
	if previous == nil or nextValue == nil then
		return previous ~= nextValue
	end

	return (previous - nextValue).Magnitude >= minimumDistance
end

local function configureOctree(spatialIndex: any, maxRegionSize: number, maxDepth: number): any
	if typeof(spatialIndex) ~= "table" then
		return spatialIndex
	end

	spatialIndex._maxDepth = maxDepth
	spatialIndex._maxRegionSize = { maxRegionSize, maxRegionSize, maxRegionSize }
	return spatialIndex
end

local function packChunkKey(chunkX: number, chunkY: number): string
	return `{chunkX}:{chunkY}`
end

local function applyTileStudSurfaces(part: BasePart)
	TileMaterial.ApplyStudSurfaces(part)
end

local function _applyTileSmoothSurfaces(part: BasePart)
	TileMaterial.ApplySmoothSurfaces(part)
end

local assignCreatedTileMaterial = TileMaterial.ApplyTileMaterial

local function unpackChunkKey(chunkKey: string): (number?, number?)
	local xRaw, yRaw = string.match(chunkKey, "^(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil then
		return nil, nil
	end

	local chunkX = tonumber(xRaw)
	local chunkY = tonumber(yRaw)
	if chunkX == nil or chunkY == nil then
		return nil, nil
	end

	return chunkX, chunkY
end

local function toChunkCoordinate(tile: number, chunkSize: number): number
	return math.floor(tile / chunkSize)
end

local function toTileCoordinate(worldAxis: number, tileSize: number): number
	return math.floor(worldAxis / tileSize)
end

local function computeTileIndex(localX: number, localY: number, width: number): number
	return localY * width + localX + 1
end

local function getTileMetadataId(self: WorldGeneration, tileIdRaw: any): number
	if not isFiniteNumber(tileIdRaw) then
		return self.tileId.AIR
	end

	return coerceInteger(tileIdRaw, self.tileId.AIR, MAX_TILE_ID, self.tileId.AIR)
end

local function getTileMetadataRectValue(rectangleRaw: { [any]: any }): any
	return rectangleRaw.tileId or rectangleRaw.value or rectangleRaw.id
end

local function getTileMetadataRectAxis(
	startRaw: any,
	sizeRaw: any,
	endRaw: any,
	maxExclusive: number
): (number?, number?)
	if maxExclusive <= 0 then
		return nil
	end

	local start = coerceInteger(startRaw, 0, maxExclusive - 1, 0)
	local size = if isFiniteNumber(sizeRaw)
		then coerceInteger(sizeRaw, 1, maxExclusive - start, 1)
		elseif isFiniteNumber(endRaw) then coerceInteger(
			(endRaw :: number) - start + 1,
			1,
			maxExclusive - start,
			1
		)
		else 1
	if size <= 0 then
		return nil
	end

	return start, math.min(maxExclusive - 1, start + size - 1)
end

local function encodeDepthLayer(depthLayer: DepthLayer): number
	if depthLayer == "Sky" then
		return DEPTH_LAYER_CODE.SKY
	end
	if depthLayer == "Surface" then
		return DEPTH_LAYER_CODE.SURFACE
	end
	if depthLayer == "Underground" then
		return DEPTH_LAYER_CODE.UNDERGROUND
	end
	if depthLayer == "Cavern" then
		return DEPTH_LAYER_CODE.CAVERN
	end
	return DEPTH_LAYER_CODE.DEEP
end

local function decodeDepthLayer(depthLayerCodeRaw: any): DepthLayer
	local depthLayerCode = if isFiniteNumber(depthLayerCodeRaw)
		then math.floor(depthLayerCodeRaw :: number)
		else DEPTH_LAYER_CODE.UNDERGROUND
	if depthLayerCode == DEPTH_LAYER_CODE.SKY then
		return "Sky"
	end
	if depthLayerCode == DEPTH_LAYER_CODE.SURFACE then
		return "Surface"
	end
	if depthLayerCode == DEPTH_LAYER_CODE.CAVERN then
		return "Cavern"
	end
	if depthLayerCode == DEPTH_LAYER_CODE.DEEP then
		return "Deep"
	end
	return "Underground"
end

local function hasNonAirNeighborOrSelf(
	values: { number },
	width: number,
	height: number,
	localX: number,
	localY: number
): boolean
	local minY = math.max(0, localY - 1)
	local maxY = math.min(height - 1, localY + 1)
	local minX = math.max(0, localX - 1)
	local maxX = math.min(width - 1, localX + 1)

	for scanY = minY, maxY do
		for scanX = minX, maxX do
			if values[computeTileIndex(scanX, scanY, width)] ~= TILE_ID.AIR then
				return true
			end
		end
	end

	return false
end

local function sampleBackgroundOctaveNoise(
	seed: number,
	x: number,
	y: number,
	baseFrequency: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	offsetX: number,
	offsetY: number
): number
	local frequency = baseFrequency
	local amplitude = 1
	local total = 0
	local amplitudeSum = 0

	for octave = 1, octaves do
		local sample = math.noise(
			(x + offsetX + octave * 0.91) * frequency,
			(y + offsetY + octave * 0.63) * frequency,
			seed * BG_SEED_X_MULTIPLIER + octave * BG_SEED_Y_MULTIPLIER
		)
		total += sample * amplitude
		amplitudeSum += amplitude
		frequency *= lacunarity
		amplitude *= persistence
	end

	if amplitudeSum <= 0 then
		return 0
	end

	return total / amplitudeSum
end

local function sampleBackgroundOctaveNoise3D(
	seed: number,
	x: number,
	y: number,
	z: number,
	baseFrequency: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	offsetX: number,
	offsetY: number
): number
	local frequency = baseFrequency
	local amplitude = 1
	local total = 0
	local amplitudeSum = 0

	for octave = 1, octaves do
		local sample = math.noise(
			(x + offsetX + octave * 0.91) * frequency,
			(y + offsetY + octave * 0.63) * frequency,
			(z + seed * BG_SEED_X_MULTIPLIER + octave * BG_SEED_Y_MULTIPLIER) * frequency
		)
		total += sample * amplitude
		amplitudeSum += amplitude
		frequency *= lacunarity
		amplitude *= persistence
	end

	if amplitudeSum <= 0 then
		return 0
	end

	return total / amplitudeSum
end

local function createRuntimeInstanceName(): string
	local guid = String.removePostfix(String.removePrefix(HttpService:GenerateGUID(true), "{"), "}")
	return string.format("%03d", (tonumber(string.sub(guid, 1, 8), 16) or 0) % 1000)
end

local function createPartTemplate(): Part
	local part = TileComponent.CreatePart({
		name = createRuntimeInstanceName(),
		anchored = true,
		locked = true,
		castShadow = false,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		size = Vector3.new(1, 1, 1),
	})
	applyTileStudSurfaces(part)
	return part
end

local function getWorldGenerationAssetsFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets == nil then
		return nil
	end
	local worldGeneration = assets:FindFirstChild("WorldGeneration")
	if worldGeneration ~= nil and worldGeneration:IsA("Folder") then
		return worldGeneration
	end
	return nil
end

local function getTilesTemplateFolder(): Folder?
	local worldGeneration = getWorldGenerationAssetsFolder()
	if worldGeneration == nil then
		return nil
	end
	local tiles = worldGeneration:FindFirstChild("Tiles")
	if tiles ~= nil and tiles:IsA("Folder") then
		return tiles
	end
	return nil
end

local function getAssetTemplate(parent: Instance?, childName: string): Instance?
	if parent == nil then
		return nil
	end

	local child = parent:FindFirstChild(childName)
	if child == nil then
		return nil
	end
	return child
end

local function createFallbackTileTemplate(templateName: string): BasePart
	local part = createPartTemplate()
	part.Name = templateName
	return part
end

local function getTileTemplate(parent: Instance?, childName: string): Instance
	return getAssetTemplate(parent, childName) or createFallbackTileTemplate(childName)
end

local function _GetTreesTemplateFolder(): Folder?
	local worldGeneration = getWorldGenerationAssetsFolder()
	if worldGeneration == nil then
		return nil
	end
	local trees = worldGeneration:FindFirstChild("Trees")
	if trees ~= nil and trees:IsA("Folder") then
		return trees
	end
	return nil
end

local function cloneTileTemplate(source: Instance?): Instance?
	if source == nil then
		return nil
	end
	if source:IsA("Model") or source:IsA("BasePart") then
		return source:Clone()
	end
	return nil
end

local function shouldApplyGrassRotationFix(self: WorldGeneration, tileId: number): boolean
	return tileId == self.tileId.GRASS or tileId == self.tileId.CORRUPT_GRASS or tileId == self.tileId.JUNGLE_GRASS
end

local function isTreeSurfaceTile(self: WorldGeneration, tileId: number): boolean
	return tileId == self.tileId.GRASS
		or tileId == self.tileId.JUNGLE_GRASS
		or tileId == self.tileId.CORRUPT_GRASS
		or tileId == self.tileId.DIRT
		or tileId == self.tileId.MUD
		or tileId == self.tileId.CORRUPT_SOIL
		or tileId == self.tileId.SNOW
end

local function getExposedSurfaceCapTileId(
	self: WorldGeneration,
	tileId: number,
	biomeId: number,
	biomeType: number
): number
	if biomeType == self.biomeType.CORRUPTION then
		if tileId == self.tileId.CORRUPT_SOIL then
			return self.tileId.CORRUPT_GRASS
		end
		return tileId
	end

	if biomeId == self.biomeId.JUNGLE then
		if tileId == self.tileId.MUD then
			return self.tileId.JUNGLE_GRASS
		end
		return tileId
	end

	if biomeId == self.biomeId.SNOW then
		if tileId == self.tileId.DIRT then
			return self.tileId.SNOW
		end
		return tileId
	end

	if biomeId == self.biomeId.FOREST then
		if tileId == self.tileId.DIRT then
			return self.tileId.GRASS
		end
	end

	return tileId
end

local SURFACE_CAP_NEIGHBOR_OFFSETS = {
	{ x = 0, y = 1 },
	{ x = -1, y = 0 },
	{ x = 1, y = 0 },
}

function WorldGeneration.ApplyExposedSurfaceCaps(
	self: WorldGeneration,
	tiles: { number },
	biomeIds: { number },
	biomeTypes: { number },
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	getOutsideTileIdRaw: any?
): number
	local getOutsideTileId = if typeof(getOutsideTileIdRaw) == "function" then getOutsideTileIdRaw else nil
	local function getNeighborTileId(sourceTiles: { number }, localX: number, localY: number): number
		if localX >= 0 and localX < width and localY >= 0 and localY < height then
			return sourceTiles[computeTileIndex(localX, localY, width)]
		end
		if getOutsideTileId ~= nil then
			return getOutsideTileId(tileMinX + localX, tileMinY + localY)
		end
		return self.tileId.AIR
	end

	local changedCount = 0
	for localY = 0, height - 1 do
		for localX = 0, width - 1 do
			local tileIndex = computeTileIndex(localX, localY, width)
			local tileId = tiles[tileIndex]
			if tileId == self.tileId.AIR then
				continue
			end

			local isExposed = false
			for _, offset in SURFACE_CAP_NEIGHBOR_OFFSETS do
				local neighborTileId = getNeighborTileId(tiles, localX + offset.x, localY + offset.y)
				if neighborTileId == self.tileId.AIR then
					isExposed = true
					break
				end
			end

			if not isExposed then
				continue
			end

			local capTileId = getExposedSurfaceCapTileId(self, tileId, biomeIds[tileIndex], biomeTypes[tileIndex])
			if capTileId ~= tileId then
				tiles[tileIndex] = capTileId
				changedCount += 1
			end
		end
	end

	-- Terraria's inner ledge frame depends on grass metadata in the buried tile
	-- shared by the vertical and horizontal grass faces. Read a frozen first-pass
	-- snapshot so newly filled corners cannot cascade through the subsurface.
	local cappedTiles = Sift.Array.copy(tiles)
	for localY = 0, height - 1 do
		for localX = 0, width - 1 do
			local tileIndex = computeTileIndex(localX, localY, width)
			local tileId = cappedTiles[tileIndex]
			local capTileId = getExposedSurfaceCapTileId(self, tileId, biomeIds[tileIndex], biomeTypes[tileIndex])
			local isGrassCap = capTileId == self.tileId.GRASS
				or capTileId == self.tileId.JUNGLE_GRASS
				or capTileId == self.tileId.CORRUPT_GRASS
			if not isGrassCap then
				continue
			end

			local hasGrassAbove = getNeighborTileId(cappedTiles, localX, localY + 1) == capTileId
			local hasLeftInnerCorner = getNeighborTileId(cappedTiles, localX - 1, localY) == capTileId
				and getNeighborTileId(cappedTiles, localX - 1, localY + 1) == self.tileId.AIR
			local hasRightInnerCorner = getNeighborTileId(cappedTiles, localX + 1, localY) == capTileId
				and getNeighborTileId(cappedTiles, localX + 1, localY + 1) == self.tileId.AIR
			if hasGrassAbove and (hasLeftInnerCorner or hasRightInnerCorner) then
				tiles[tileIndex] = capTileId
				changedCount += 1
			end
		end
	end

	return changedCount
end

local function _collectTemplateInstances(sourceFolder: Folder?): { Instance }
	local instances: { Instance } = {}
	if sourceFolder == nil then
		return instances
	end

	for _, child in sourceFolder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(instances, child)
		end
	end

	table.sort(instances, function(a: Instance, b: Instance): boolean
		return a.Name < b.Name
	end)

	return instances
end

local function createProceduralTreeVariantConfigs(): { TreeVariantConfig }
	return {
		{
			biomeType = BIOME_TYPE.NORMAL,
			config = {
				Algorithm = "Recursive",
				MaxDepth = 4,
				BranchAngleRange = NumberRange.new(16, 34),
				LengthScale = 0.73,
				ThicknessScale = 0.75,
				BranchChance = 0.52,
				InitialLength = 9.2,
				InitialThickness = 1.35,
				TrunkWobbleAngle = 6,
				LeafSizeMin = Vector3.new(2.6, 1.8, 2.6),
				LeafSizeMax = Vector3.new(4.2, 3.2, 4.2),
				LeavesPerTerminalMin = 1,
				LeavesPerTerminalMax = 2,
				MaxBranchParts = 34,
				MaxLeafParts = 26,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Normal1",
			},
		},
		{
			biomeType = BIOME_TYPE.NORMAL,
			config = {
				Algorithm = "Recursive",
				MaxDepth = 5,
				BranchAngleRange = NumberRange.new(18, 42),
				LengthScale = 0.7,
				ThicknessScale = 0.72,
				BranchChance = 0.6,
				InitialLength = 10.8,
				InitialThickness = 1.45,
				TrunkWobbleAngle = 8,
				LeafSizeMin = Vector3.new(2.8, 2, 2.8),
				LeafSizeMax = Vector3.new(4.8, 3.5, 4.8),
				LeavesPerTerminalMin = 1,
				LeavesPerTerminalMax = 2,
				MaxBranchParts = 44,
				MaxLeafParts = 34,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Normal2",
			},
		},
		{
			biomeType = BIOME_TYPE.NORMAL,
			config = {
				Algorithm = "LSystemStyle",
				MaxDepth = 5,
				BranchAngleRange = NumberRange.new(20, 48),
				LengthScale = 0.68,
				ThicknessScale = 0.7,
				BranchChance = 0.63,
				InitialLength = 11.4,
				InitialThickness = 1.5,
				TrunkWobbleAngle = 9,
				LeafSizeMin = Vector3.new(3, 2.1, 3),
				LeafSizeMax = Vector3.new(5.2, 3.8, 5.2),
				LeavesPerTerminalMin = 1,
				LeavesPerTerminalMax = 3,
				MaxBranchParts = 54,
				MaxLeafParts = 42,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Normal3",
			},
		},
		{
			biomeType = BIOME_TYPE.NORMAL,
			config = {
				Algorithm = "LSystemStyle",
				MaxDepth = 6,
				BranchAngleRange = NumberRange.new(24, 54),
				LengthScale = 0.66,
				ThicknessScale = 0.68,
				BranchChance = 0.66,
				InitialLength = 12.5,
				InitialThickness = 1.62,
				TrunkWobbleAngle = 11,
				LeafSizeMin = Vector3.new(3.2, 2.2, 3.2),
				LeafSizeMax = Vector3.new(5.8, 4.2, 5.8),
				LeavesPerTerminalMin = 2,
				LeavesPerTerminalMax = 3,
				MaxBranchParts = 66,
				MaxLeafParts = 52,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Normal4",
			},
		},
		{
			biomeType = BIOME_TYPE.CORRUPTION,
			config = {
				Algorithm = "Recursive",
				MaxDepth = 5,
				BranchAngleRange = NumberRange.new(28, 58),
				LengthScale = 0.66,
				ThicknessScale = 0.67,
				BranchChance = 0.74,
				InitialLength = 11,
				InitialThickness = 1.52,
				TrunkWobbleAngle = 12,
				LeafSizeMin = Vector3.new(2.3, 1.4, 2.3),
				LeafSizeMax = Vector3.new(3.8, 2.8, 3.8),
				LeavesPerTerminalMin = 1,
				LeavesPerTerminalMax = 2,
				MaxBranchParts = 58,
				MaxLeafParts = 28,
				BranchColor = TREE_PALETTE_CORRUPTION_1.BranchColor,
				LeafColor = TREE_PALETTE_CORRUPTION_1.LeafColor,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Corruption1",
			},
		},
		{
			biomeType = BIOME_TYPE.CORRUPTION,
			config = {
				Algorithm = "LSystemStyle",
				MaxDepth = 6,
				BranchAngleRange = NumberRange.new(32, 62),
				LengthScale = 0.64,
				ThicknessScale = 0.64,
				BranchChance = 0.78,
				InitialLength = 12.2,
				InitialThickness = 1.58,
				TrunkWobbleAngle = 14,
				LeafSizeMin = Vector3.new(2.1, 1.2, 2.1),
				LeafSizeMax = Vector3.new(3.3, 2.4, 3.3),
				LeavesPerTerminalMin = 1,
				LeavesPerTerminalMax = 2,
				MaxBranchParts = 74,
				MaxLeafParts = 30,
				BranchColor = TREE_PALETTE_CORRUPTION_2.BranchColor,
				LeafColor = TREE_PALETTE_CORRUPTION_2.LeafColor,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Corruption2",
			},
		},
		{
			biomeType = BIOME_TYPE.NORMAL,
			biomeId = BIOME_ID.JUNGLE,
			config = {
				Algorithm = "Recursive",
				MaxDepth = 7,
				BranchAngleRange = NumberRange.new(12, 26),
				LengthScale = 0.79,
				ThicknessScale = 0.78,
				BranchChance = 0.56,
				InitialLength = 18.5,
				InitialThickness = 1.95,
				TrunkWobbleAngle = 4,
				UpwardBias = 0.78,
				LeafSizeMin = Vector3.new(4.2, 2.6, 4.2),
				LeafSizeMax = Vector3.new(7.1, 4.8, 7.1),
				LeavesPerTerminalMin = 2,
				LeavesPerTerminalMax = 4,
				MaxBranchParts = 124,
				MaxLeafParts = 108,
				BranchColor = TREE_PALETTE_JUNGLE_1.BranchColor,
				LeafColor = TREE_PALETTE_JUNGLE_1.LeafColor,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Jungle1",
			},
		},
		{
			biomeType = BIOME_TYPE.NORMAL,
			biomeId = BIOME_ID.JUNGLE,
			config = {
				Algorithm = "LSystemStyle",
				MaxDepth = 8,
				BranchAngleRange = NumberRange.new(14, 30),
				LengthScale = 0.77,
				ThicknessScale = 0.76,
				BranchChance = 0.62,
				InitialLength = 20.8,
				InitialThickness = 2.12,
				TrunkWobbleAngle = 5,
				UpwardBias = 0.86,
				LeafSizeMin = Vector3.new(4.6, 2.9, 4.6),
				LeafSizeMax = Vector3.new(7.8, 5.2, 7.8),
				LeavesPerTerminalMin = 2,
				LeavesPerTerminalMax = 4,
				MaxBranchParts = 148,
				MaxLeafParts = 126,
				BranchColor = TREE_PALETTE_JUNGLE_2.BranchColor,
				LeafColor = TREE_PALETTE_JUNGLE_2.LeafColor,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Jungle2",
			},
		},
		{
			biomeType = BIOME_TYPE.NORMAL,
			biomeId = BIOME_ID.SNOW,
			config = {
				Algorithm = "Recursive",
				MaxDepth = 5,
				BranchAngleRange = NumberRange.new(14, 28),
				LengthScale = 0.72,
				ThicknessScale = 0.74,
				BranchChance = 0.44,
				InitialLength = 13.8,
				InitialThickness = 1.58,
				TrunkWobbleAngle = 3,
				UpwardBias = 0.81,
				LeafSizeMin = Vector3.new(2.2, 2.8, 2.2),
				LeafSizeMax = Vector3.new(3.6, 5, 3.6),
				LeavesPerTerminalMin = 1,
				LeavesPerTerminalMax = 2,
				MaxBranchParts = 72,
				MaxLeafParts = 44,
				BranchColor = TREE_PALETTE_SNOW_1.BranchColor,
				LeafColor = TREE_PALETTE_SNOW_1.LeafColor,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Snow1",
			},
		},
		{
			biomeType = BIOME_TYPE.NORMAL,
			biomeId = BIOME_ID.SNOW,
			config = {
				Algorithm = "LSystemStyle",
				MaxDepth = 6,
				BranchAngleRange = NumberRange.new(10, 22),
				LengthScale = 0.7,
				ThicknessScale = 0.72,
				BranchChance = 0.38,
				InitialLength = 14.6,
				InitialThickness = 1.66,
				TrunkWobbleAngle = 2,
				UpwardBias = 0.88,
				LeafSizeMin = Vector3.new(2.1, 3, 2.1),
				LeafSizeMax = Vector3.new(3.2, 5.8, 3.2),
				LeavesPerTerminalMin = 1,
				LeavesPerTerminalMax = 2,
				MaxBranchParts = 82,
				MaxLeafParts = 52,
				BranchColor = TREE_PALETTE_SNOW_2.BranchColor,
				LeafColor = TREE_PALETTE_SNOW_2.LeafColor,
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Snow2",
			},
		},
	}
end

local function getTreeVariantIndexByAlpha(treeVariantCount: number, alpha: number): number
	local count = math.max(1, treeVariantCount)
	return math.clamp(math.floor(alpha * count) + 1, 1, count)
end

local function computeProceduralTreeSeed(worldSeed: number, tileX: number, tileY: number, variantIndex: number): number
	local a = bit32.band(worldSeed, UINT32_MAX)
	local b = bit32.band(tileX * 73856093, UINT32_MAX)
	local c = bit32.band(tileY * 19349663, UINT32_MAX)
	local d = bit32.band(variantIndex * 83492791, UINT32_MAX)
	local mixed = bit32.bxor(a, b, c, d)
	mixed = bit32.band(mixed * 1664525 + 1013904223, UINT32_MAX)
	if mixed >= INT32_SIGN_BIT then
		return mixed - UINT32_WRAP
	end
	return mixed
end

local function toUnsignedInt32(value: number): number
	if value < 0 then
		return value + UINT32_WRAP
	end
	return value
end

local function deterministicUnitInterval(seed: number, x: number, y: number, z: number, salt: number): number
	local mixed = computeProceduralTreeSeed(seed + salt * 131, x + salt * 17, y - salt * 23, z + salt * 29)
	return math.clamp(toUnsignedInt32(mixed) / UINT32_MAX, 0, 1)
end

local function columnsShareBiomeSignature(left: ColumnProfile, right: ColumnProfile): boolean
	return left.biomeId == right.biomeId and left.biomeType == right.biomeType
end

local function copyColumnWithSurfaceY(column: ColumnProfile, surfaceY: number): ColumnProfile
	if column.surfaceY == surfaceY then
		return column
	end

	return {
		biomeId = column.biomeId,
		biomeType = column.biomeType,
		surfaceY = surfaceY,
		stoneStartDepth = column.stoneStartDepth,
		topTileId = column.topTileId,
		subsurfaceTileId = column.subsurfaceTileId,
		deepTileId = column.deepTileId,
		snowDetailNoise = column.snowDetailNoise,
		snowIceNoise = column.snowIceNoise,
	}
end

local function getDominantBiomeType(biomeTypes: { number }, fallbackBiomeType: number): number
	local counts: { [number]: number } = {}
	local selectedBiomeType = fallbackBiomeType
	local selectedCount = 0

	for _, biomeType in biomeTypes do
		local nextCount = (counts[biomeType] or 0) + 1
		counts[biomeType] = nextCount
		if nextCount > selectedCount then
			selectedCount = nextCount
			selectedBiomeType = biomeType
		end
	end

	return selectedBiomeType
end

local function getDominantBiomeId(biomeIds: { number }, fallbackBiomeId: number): number
	local counts: { [number]: number } = {}
	local selectedBiomeId = fallbackBiomeId
	local selectedCount = 0

	for _, biomeId in biomeIds do
		local nextCount = (counts[biomeId] or 0) + 1
		counts[biomeId] = nextCount
		if nextCount > selectedCount then
			selectedCount = nextCount
			selectedBiomeId = biomeId
		end
	end

	return selectedBiomeId
end

local function populateChunkBiomeIdsFromColumns(self: WorldGeneration, chunkData: ChunkData, biomeIds: { number })
	local biomeIdByColumn = Sift.Array.create(chunkData.width, self.biomeId.FOREST)
	for localX = 0, chunkData.width - 1 do
		local worldTileX = chunkData.tileMinX + localX
		local column = self.biomeGenerator:GetColumnProfile(worldTileX)
		biomeIdByColumn[localX + 1] = column.biomeId
	end

	for localY = 0, chunkData.height - 1 do
		for localX = 0, chunkData.width - 1 do
			local tileIndex = computeTileIndex(localX, localY, chunkData.width)
			biomeIds[tileIndex] = biomeIdByColumn[localX + 1]
		end
	end
end

local function populateChunkSurfaceBiomeIds(self: WorldGeneration, chunkData: ChunkData, surfaceBiomeIds: { number })
	for localX = 0, chunkData.width - 1 do
		local worldTileX = chunkData.tileMinX + localX
		local column = self.biomeGenerator:GetColumnProfile(worldTileX)
		surfaceBiomeIds[localX + 1] = column.biomeId
	end
end

local function ensureChunkBiomeMetadata(self, chunkData: ChunkData)
	local chunkDataRaw = chunkData :: any
	if chunkDataRaw._metadataValidated == true then
		if typeof(chunkDataRaw.surfaceBiomeIds) ~= "table" then
			chunkDataRaw.surfaceBiomeIds = Sift.Array.create(chunkData.width, self.biomeId.FOREST)
			populateChunkSurfaceBiomeIds(self, chunkData, chunkDataRaw.surfaceBiomeIds)
		end
		return
	end
	local totalTiles = chunkData.width * chunkData.height
	if typeof(chunkDataRaw.biomeTypes) ~= "table" then
		chunkDataRaw.biomeTypes = Sift.Array.create(totalTiles, self.biomeType.NORMAL)
	end
	if typeof(chunkDataRaw.biomeIds) ~= "table" then
		chunkDataRaw.biomeIds = Sift.Array.create(totalTiles, self.biomeId.FOREST)
		populateChunkBiomeIdsFromColumns(self, chunkData, chunkDataRaw.biomeIds)
	end
	if typeof(chunkDataRaw.surfaceBiomeIds) ~= "table" then
		chunkDataRaw.surfaceBiomeIds = Sift.Array.create(chunkData.width, self.biomeId.FOREST)
		populateChunkSurfaceBiomeIds(self, chunkData, chunkDataRaw.surfaceBiomeIds)
	end
	if typeof(chunkDataRaw.depthLayers) ~= "table" then
		chunkDataRaw.depthLayers = Sift.Array.create(totalTiles)
	end
	if typeof(chunkDataRaw.depthBelowSurface) ~= "table" then
		chunkDataRaw.depthBelowSurface = Sift.Array.create(totalTiles)
	end
	if typeof(chunkDataRaw.props) ~= "table" then
		chunkDataRaw.props = {}
	end

	local biomeTypes = chunkDataRaw.biomeTypes :: { number }
	local biomeIds = chunkDataRaw.biomeIds :: { number }
	local surfaceBiomeIds = chunkDataRaw.surfaceBiomeIds :: { number }
	local depthLayers = chunkDataRaw.depthLayers :: { number }
	local depthBelowSurface = chunkDataRaw.depthBelowSurface :: { number }
	for tileIndex = 1, totalTiles do
		local depthLayerCodeRaw = depthLayers[tileIndex]
		local hasDepthLayerCode = isFiniteNumber(depthLayerCodeRaw)
		if hasDepthLayerCode then
			depthLayers[tileIndex] = coerceInteger(
				depthLayerCodeRaw,
				DEPTH_LAYER_CODE.SKY,
				DEPTH_LAYER_CODE.DEEP,
				DEPTH_LAYER_CODE.UNDERGROUND
			)
		end

		local depthBelowSurfaceRaw = depthBelowSurface[tileIndex]
		local hasDepthBelowSurface = isFiniteNumber(depthBelowSurfaceRaw)
		if hasDepthBelowSurface then
			depthBelowSurface[tileIndex] = coerceInteger(depthBelowSurfaceRaw, -8192, 8192, 0)
		end

		if hasDepthLayerCode and hasDepthBelowSurface then
			continue
		end

		local zeroBasedIndex = tileIndex - 1
		local localX = zeroBasedIndex % chunkData.width
		local localY = math.floor(zeroBasedIndex / chunkData.width)
		local worldTileY = chunkData.tileMinY + localY
		if worldTileY < self.minTileY or worldTileY > self.maxTileY then
			if not hasDepthLayerCode then
				depthLayers[tileIndex] = DEPTH_LAYER_CODE.SKY
			end
			if not hasDepthBelowSurface then
				depthBelowSurface[tileIndex] = -1
			end
			continue
		end

		local worldTileX = chunkData.tileMinX + localX
		local column = self.biomeGenerator:GetColumnProfile(worldTileX)
		local depthLayer, depthValue = self.caveGenerator:GetDepthLayer(column.surfaceY, worldTileY)
		if not hasDepthLayerCode then
			depthLayers[tileIndex] = encodeDepthLayer(depthLayer)
		end
		if not hasDepthBelowSurface then
			depthBelowSurface[tileIndex] = depthValue
		end
	end
	for tileIndex = 1, totalTiles do
		local biomeType = biomeTypes[tileIndex]
		if biomeType == self.biomeType.NORMAL or biomeType == self.biomeType.CORRUPTION then
			continue
		end
		biomeTypes[tileIndex] = self.biomeType.NORMAL :: number
	end
	for tileIndex = 1, totalTiles do
		local biomeId = biomeIds[tileIndex]
		if
			biomeId == self.biomeId.FOREST
			or biomeId == self.biomeId.DESERT
			or biomeId == self.biomeId.SNOW
			or biomeId == self.biomeId.JUNGLE
		then
			continue
		end
		biomeIds[tileIndex] = self.biomeId.FOREST :: number
	end
	for columnIndex = 1, chunkData.width do
		local biomeId = surfaceBiomeIds[columnIndex]
		if
			biomeId == self.biomeId.FOREST
			or biomeId == self.biomeId.DESERT
			or biomeId == self.biomeId.SNOW
			or biomeId == self.biomeId.JUNGLE
		then
			continue
		end
		surfaceBiomeIds[columnIndex] = self.biomeId.FOREST :: number
	end

	local treesRaw = chunkDataRaw.trees
	if typeof(treesRaw) == "table" then
		for _, treeDataRaw in treesRaw do
			if typeof(treeDataRaw) ~= "table" then
				continue
			end
			local treeDataAny = treeDataRaw :: any
			if not isFiniteNumber(treeDataAny.biomeType) then
				treeDataAny.biomeType = self.biomeType.NORMAL
			end
			if not isFiniteNumber(treeDataAny.biomeId) then
				local fallbackBiomeId = self.biomeId.FOREST
				if isFiniteNumber(treeDataAny.tileX) and isFiniteNumber(treeDataAny.tileY) then
					local localX = math.floor(treeDataAny.tileX) - chunkData.tileMinX
					local localY = math.floor(treeDataAny.tileY) - chunkData.tileMinY
					if localX >= 0 and localX < chunkData.width and localY >= 0 and localY < chunkData.height then
						local tileIndex = computeTileIndex(localX, localY, chunkData.width)
						fallbackBiomeId = biomeIds[tileIndex] or fallbackBiomeId
					end
				end
				treeDataAny.biomeId = fallbackBiomeId
			end
		end
	end

	local propsRaw = chunkDataRaw.props
	if typeof(propsRaw) == "table" then
		for _, propDataRaw in propsRaw do
			if typeof(propDataRaw) ~= "table" then
				continue
			end
			local propDataAny = propDataRaw :: any
			if not isFiniteNumber(propDataAny.biomeType) then
				propDataAny.biomeType = self.biomeType.NORMAL
			else
				propDataAny.biomeType = coerceInteger(
					propDataAny.biomeType,
					self.biomeType.NORMAL :: number,
					self.biomeType.CORRUPTION :: number,
					self.biomeType.NORMAL :: number
				)
			end
			if not isFiniteNumber(propDataAny.biomeId) then
				local fallbackBiomeId = self.biomeId.FOREST
				if isFiniteNumber(propDataAny.tileX) and isFiniteNumber(propDataAny.tileY) then
					local localX = math.floor(propDataAny.tileX) - chunkData.tileMinX
					local localY = math.floor(propDataAny.tileY) - chunkData.tileMinY
					if localX >= 0 and localX < chunkData.width and localY >= 0 and localY < chunkData.height then
						local tileIndex = computeTileIndex(localX, localY, chunkData.width)
						fallbackBiomeId = biomeIds[tileIndex] or fallbackBiomeId
					end
				end
				propDataAny.biomeId = fallbackBiomeId
			else
				propDataAny.biomeId = coerceInteger(
					propDataAny.biomeId,
					self.biomeId.FOREST :: number,
					self.biomeId.JUNGLE :: number,
					self.biomeId.FOREST :: number
				)
			end
		end
	end

	chunkDataRaw.dominantBiomeType = getDominantBiomeType(biomeTypes, self.biomeType.NORMAL :: number)
	chunkDataRaw.dominantBiomeId = getDominantBiomeId(biomeIds, self.biomeId.FOREST :: number)
	chunkDataRaw._metadataValidated = true
end

local function ensureChunkWallData(self: WorldGeneration, chunkData: ChunkData)
	local chunkDataRaw = chunkData :: any
	if chunkDataRaw._wallsValidated == true and typeof(chunkDataRaw.walls) == "table" then
		return
	end

	local totalTiles = chunkData.width * chunkData.height
	local walls = if typeof(chunkDataRaw.walls) == "table"
		then chunkDataRaw.walls :: { number }
		else Sift.Array.create(totalTiles, self.wallId.NONE)
	chunkDataRaw.walls = walls

	for tileIndex = 1, totalTiles do
		local wallIdRaw = walls[tileIndex]
		if isFiniteNumber(wallIdRaw) then
			local wallId = math.floor(wallIdRaw :: number)
			if wallId >= self.wallId.NONE and wallId <= MAX_WALL_ID then
				walls[tileIndex] = wallId
				continue
			end
		end

		walls[tileIndex] = self.caveGenerator:GetWall(
			chunkData.tiles[tileIndex] or self.tileId.AIR,
			chunkData.biomeIds[tileIndex] or self.biomeId.FOREST,
			decodeDepthLayer(chunkData.depthLayers[tileIndex]),
			chunkData.depthBelowSurface[tileIndex] or -1
		)
	end

	chunkDataRaw._wallsValidated = true
end

local function carveCorruptionChasmsForChunk(
	self: WorldGeneration,
	chunkX: number,
	chunkY: number,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tiles: { number },
	biomeTypes: { number },
	columnProfiles: { ColumnProfile }
)
	local corruptionColumns: { ChasmSeedColumn } = {}
	for localX = 0, width - 1 do
		local column = columnProfiles[localX + 1]
		if column ~= nil and column.biomeType == self.biomeType.CORRUPTION then
			local surfaceY = column.surfaceY
			if surfaceY >= self.minTileY and surfaceY <= self.maxTileY then
				corruptionColumns[#corruptionColumns + 1] = {
					worldX = tileMinX + localX,
					surfaceY = surfaceY,
				}
			end
		end
	end

	if #corruptionColumns <= 0 then
		return
	end

	local chunkSeed = computeProceduralTreeSeed(self.seed, chunkX * 157 + 811, chunkY * 193 - 271, 4901)
	local random = Random.new(chunkSeed)
	if random:NextNumber() > CORRUPTION_CHASM_CHUNK_SPAWN_CHANCE then
		return
	end

	local maxSeeds = math.min(CORRUPTION_CHASM_MAX_SEEDS, #corruptionColumns)
	if maxSeeds <= 0 then
		return
	end
	local minSeeds = math.min(CORRUPTION_CHASM_MIN_SEEDS, maxSeeds)
	local seedCount = random:NextInteger(minSeeds, maxSeeds)
	if seedCount <= 0 then
		return
	end

	local selectedColumns: { ChasmSeedColumn } = {}
	local selectionAttempts = 0
	while #selectedColumns < seedCount and selectionAttempts < seedCount * 14 do
		selectionAttempts += 1
		local candidate = corruptionColumns[random:NextInteger(1, #corruptionColumns)]
		if candidate == nil then
			continue
		end
		local accepted = true
		for _, selectedColumn in selectedColumns do
			if math.abs(selectedColumn.worldX - candidate.worldX) < CORRUPTION_CHASM_MIN_SEED_SPACING then
				accepted = false
				break
			end
		end
		if accepted then
			selectedColumns[#selectedColumns + 1] = candidate
		end
	end

	if #selectedColumns <= 0 then
		local fallbackColumn = corruptionColumns[random:NextInteger(1, #corruptionColumns)]
		if fallbackColumn == nil then
			return
		end
		selectedColumns[1] = fallbackColumn
	end

	local walkers: { ChasmWalker } = {}
	for seedIndex, seedColumn in selectedColumns do
		local walkerSeed = computeProceduralTreeSeed(
			self.seed,
			seedColumn.worldX + chunkX * 29 + seedIndex * 13,
			seedColumn.surfaceY + chunkY * 17 - seedIndex * 7,
			6203 + seedIndex * 31
		)
		walkers[#walkers + 1] = {
			x = seedColumn.worldX + random:NextNumber(-0.4, 0.4),
			y = seedColumn.surfaceY + 0.5,
			depthRemaining = random:NextInteger(CORRUPTION_CHASM_MIN_DEPTH, CORRUPTION_CHASM_MAX_DEPTH),
			baseRadius = random:NextNumber(CORRUPTION_CHASM_MIN_RADIUS, CORRUPTION_CHASM_MAX_RADIUS),
			driftVelocity = random:NextNumber(-0.3, 0.3),
			branchChance = CORRUPTION_CHASM_BRANCH_CHANCE,
			seedValue = walkerSeed,
			generation = 0,
		}
	end

	local tileMaxX = tileMinX + width - 1
	local tileMaxY = tileMinY + height - 1
	local smoothingMask = Sift.Array.create(width * height, false)
	local carvedAny = false

	local function markSmoothingNeighborhood(localX: number, localY: number)
		local minLocalY = math.max(0, localY - 1)
		local maxLocalY = math.min(height - 1, localY + 1)
		local minLocalX = math.max(0, localX - 1)
		local maxLocalX = math.min(width - 1, localX + 1)
		for scanLocalY = minLocalY, maxLocalY do
			for scanLocalX = minLocalX, maxLocalX do
				local index = computeTileIndex(scanLocalX, scanLocalY, width)
				smoothingMask[index] = true
			end
		end
	end

	local function carveCircle(centerX: number, centerY: number, radius: number)
		local minWorldX = math.max(tileMinX, math.floor(centerX - radius))
		local maxWorldX = math.min(tileMaxX, math.ceil(centerX + radius))
		local minWorldY = math.max(tileMinY, self.minTileY, math.floor(centerY - radius))
		local maxWorldY = math.min(tileMaxY, self.maxTileY, math.ceil(centerY + radius))
		local radiusSquared = radius * radius

		for worldY = minWorldY, maxWorldY do
			local localY = worldY - tileMinY
			for worldX = minWorldX, maxWorldX do
				local dx = worldX - centerX
				local dy = worldY - centerY
				if dx * dx + dy * dy > radiusSquared then
					continue
				end

				local localX = worldX - tileMinX
				local index = computeTileIndex(localX, localY, width)
				if biomeTypes[index] ~= self.biomeType.CORRUPTION then
					continue
				end

				if tiles[index] ~= self.tileId.AIR then
					tiles[index] = self.tileId.AIR
					carvedAny = true
				end
				markSmoothingNeighborhood(localX, localY)
			end
		end
	end

	local spawnedBranches = 0
	while #walkers > 0 do
		local walker = table.remove(walkers, #walkers)
		if walker == nil then
			break
		end
		local stepIndex = 0

		while walker.depthRemaining > 0 do
			if walker.y < self.minTileY then
				break
			end

			local radiusNoise = math.noise(
				(walker.x + CORRUPTION_CHASM_RADIUS_OFFSET_X + walker.seedValue * BG_SEED_X_MULTIPLIER)
					* CORRUPTION_CHASM_RADIUS_NOISE_FREQUENCY,
				(walker.y + CORRUPTION_CHASM_RADIUS_OFFSET_Y - stepIndex * 0.41)
					* CORRUPTION_CHASM_RADIUS_NOISE_FREQUENCY,
				self.seed * BG_SEED_Y_MULTIPLIER
			)
			local radius = math.clamp(
				walker.baseRadius + radiusNoise * CORRUPTION_CHASM_RADIUS_VARIATION,
				CORRUPTION_CHASM_MIN_RADIUS,
				CORRUPTION_CHASM_MAX_RADIUS
			)
			carveCircle(walker.x, walker.y, radius)

			walker.depthRemaining -= 1
			if walker.depthRemaining <= 0 then
				break
			end

			stepIndex += 1
			local driftNoise = math.noise(
				(walker.x + CORRUPTION_CHASM_WORM_OFFSET_X + stepIndex * 0.73) * CORRUPTION_CHASM_WORM_NOISE_FREQUENCY,
				(walker.y + CORRUPTION_CHASM_WORM_OFFSET_Y) * CORRUPTION_CHASM_WORM_NOISE_FREQUENCY,
				(walker.seedValue + self.seed * 3.17) * BG_SEED_X_MULTIPLIER
			)
			local randomBias = random:NextNumber(-1, 1) * CORRUPTION_CHASM_RANDOM_DRIFT_BIAS
			walker.driftVelocity = math.clamp(
				walker.driftVelocity * 0.81 + driftNoise * 0.62 + randomBias,
				-CORRUPTION_CHASM_MAX_DRIFT_PER_STEP,
				CORRUPTION_CHASM_MAX_DRIFT_PER_STEP
			)
			walker.x += walker.driftVelocity
			walker.y -= 1

			if
				spawnedBranches < CORRUPTION_CHASM_MAX_BRANCHES
				and walker.generation < CORRUPTION_CHASM_MAX_BRANCH_GENERATION
				and walker.depthRemaining >= CORRUPTION_CHASM_BRANCH_MIN_DEPTH
				and random:NextNumber() < walker.branchChance
			then
				spawnedBranches += 1
				local branchDepth = math.max(
					CORRUPTION_CHASM_BRANCH_MIN_DEPTH,
					math.floor(walker.depthRemaining * random:NextNumber(0.35, 0.62))
				)
				local branchRadius = math.clamp(
					walker.baseRadius * random:NextNumber(0.52, 0.84),
					CORRUPTION_CHASM_BRANCH_MIN_RADIUS,
					CORRUPTION_CHASM_MAX_RADIUS
				)
				local branchSeed = computeProceduralTreeSeed(
					walker.seedValue,
					math.floor(walker.x * 7 + spawnedBranches * 13),
					math.floor(walker.y * 11 - spawnedBranches * 17),
					7001 + spawnedBranches * 19
				)
				walkers[#walkers + 1] = {
					x = walker.x + random:NextNumber(-1.25, 1.25),
					y = walker.y,
					depthRemaining = branchDepth,
					baseRadius = branchRadius,
					driftVelocity = walker.driftVelocity + random:NextNumber(-0.35, 0.35),
					branchChance = walker.branchChance * 0.58,
					seedValue = branchSeed,
					generation = walker.generation + 1,
				}
			end
		end
	end

	if not carvedAny then
		return
	end

	local totalTiles = width * height
	for _ = 1, CORRUPTION_CHASM_SMOOTHING_PASSES do
		local removals = Sift.Array.create(totalTiles, false)
		local removalCount = 0

		for tileIndex = 1, totalTiles do
			if not smoothingMask[tileIndex] then
				continue
			end
			if tiles[tileIndex] == self.tileId.AIR or biomeTypes[tileIndex] ~= self.biomeType.CORRUPTION then
				continue
			end

			local linearIndex = tileIndex - 1
			local localX = linearIndex % width
			local localY = math.floor(linearIndex / width)
			local minNeighborY = math.max(0, localY - 1)
			local maxNeighborY = math.min(height - 1, localY + 1)
			local minNeighborX = math.max(0, localX - 1)
			local maxNeighborX = math.min(width - 1, localX + 1)
			local solidNeighborCount = 0

			for neighborY = minNeighborY, maxNeighborY do
				for neighborX = minNeighborX, maxNeighborX do
					if neighborX == localX and neighborY == localY then
						continue
					end
					local neighborIndex = computeTileIndex(neighborX, neighborY, width)
					if tiles[neighborIndex] ~= self.tileId.AIR then
						solidNeighborCount += 1
					end
				end
			end

			if solidNeighborCount < CORRUPTION_CHASM_MIN_SOLID_NEIGHBORS then
				removals[tileIndex] = true
				removalCount += 1
			end
		end

		if removalCount <= 0 then
			break
		end

		for tileIndex = 1, totalTiles do
			if removals[tileIndex] then
				tiles[tileIndex] = self.tileId.AIR
			end
		end
	end
end

local function ensureChunkLiquidData(self: WorldGeneration, chunkData: ChunkData)
	local chunkDataRaw = chunkData :: any
	if chunkDataRaw._liquidValidated == true then
		return
	end
	local totalTiles = chunkData.width * chunkData.height
	if typeof(chunkDataRaw.liquids) == "table" and #chunkDataRaw.liquids >= totalTiles then
		chunkDataRaw._liquidValidated = true
		return
	end

	if self.liquidGenerator == nil then
		chunkDataRaw.liquids = Sift.Array.create(totalTiles, 0)
		chunkDataRaw._liquidValidated = true
		return
	end

	local liquidGeneratorRaw = self.liquidGenerator :: any
	local scanRadius = BACKGROUND_LAYER_BOUNDS_PADDING_TILES
	if typeof(liquidGeneratorRaw) == "table" then
		local liquidConfig = liquidGeneratorRaw.config
		if typeof(liquidConfig) == "table" and typeof(liquidConfig.generation) == "table" then
			scanRadius = math.max(
				scanRadius,
				coerceInteger(
					(liquidConfig.generation :: any).depressionScanRadius,
					1,
					64,
					BACKGROUND_LAYER_BOUNDS_PADDING_TILES
				)
			)
		end
	end

	local scanWidth = chunkData.width + scanRadius * 2
	local scanColumnMinX = chunkData.tileMinX - scanRadius
	local scanColumnProfiles: { ColumnProfile } = Sift.Array.create(scanWidth)
	local columnProfiles: { ColumnProfile } = Sift.Array.create(chunkData.width)
	for localX = 0, scanWidth - 1 do
		local worldTileX = scanColumnMinX + localX
		local column = self.biomeGenerator:GetColumnProfile(worldTileX)
		scanColumnProfiles[localX + 1] = column
		if localX >= scanRadius and localX < scanRadius + chunkData.width then
			columnProfiles[localX - scanRadius + 1] = column
		end
	end

	chunkDataRaw.dominantBiomeType = getDominantBiomeType(chunkData.biomeTypes, self.biomeType.NORMAL)
	chunkDataRaw.dominantBiomeId = getDominantBiomeId(chunkData.biomeIds, self.biomeId.FOREST)
	chunkDataRaw.liquids = self.liquidGenerator:GenerateChunkLiquids({
		seed = self.seed,
		chunkX = chunkData.chunkX,
		chunkY = chunkData.chunkY,
		tileMinX = chunkData.tileMinX,
		tileMinY = chunkData.tileMinY,
		width = chunkData.width,
		height = chunkData.height,
		tiles = chunkData.tiles,
		depthBelowSurface = chunkData.depthBelowSurface,
		biomeIds = chunkData.biomeIds,
		biomeTypes = chunkData.biomeTypes,
		dominantBiomeId = chunkDataRaw.dominantBiomeId,
		dominantBiomeType = chunkDataRaw.dominantBiomeType,
		columnProfiles = columnProfiles,
		scanColumnProfiles = scanColumnProfiles,
		scanColumnMinX = scanColumnMinX,
	})
	chunkDataRaw._liquidValidated = true
end

function WorldGeneration.RepairIntersectingTileMetadata(
	self: WorldGeneration,
	tilesRaw: any,
	widthRaw: any,
	heightRaw: any
): ({ number }, number)
	local width = coerceInteger(widthRaw, 1, 512, self.chunkSize)
	local height = coerceInteger(heightRaw, 1, 512, self.chunkSize)
	local totalTiles = width * height
	if typeof(tilesRaw) ~= "table" then
		return Sift.Array.create(totalTiles, self.tileId.AIR), 0
	end

	local tiles = tilesRaw :: { [any]: any }
	local hasRectangleMetadata = false
	for _, tileValue in tiles do
		if typeof(tileValue) == "table" then
			hasRectangleMetadata = true
			break
		end
	end
	if not hasRectangleMetadata then
		return tilesRaw :: { number }, 0
	end

	local repairedTiles = Sift.Array.create(totalTiles, self.tileId.AIR)
	local occupiedTiles = Sift.Array.create(totalTiles, false)
	local overlapCount = 0

	local function assignTile(tileIndex: number, tileId: number)
		if tileIndex < 1 or tileIndex > totalTiles or tileId == self.tileId.AIR then
			return
		end
		if occupiedTiles[tileIndex] then
			overlapCount += 1
			return
		end

		occupiedTiles[tileIndex] = true
		repairedTiles[tileIndex] = tileId
	end

	for tileIndex = 1, totalTiles do
		local tileValue = tiles[tileIndex]
		if typeof(tileValue) == "table" then
			continue
		end

		assignTile(tileIndex, getTileMetadataId(self, tileValue))
	end

	for _, rectangleRaw in tiles do
		if typeof(rectangleRaw) ~= "table" then
			continue
		end

		local rectangle = rectangleRaw :: { [any]: any }
		local tileId = getTileMetadataId(self, getTileMetadataRectValue(rectangle))
		if tileId == self.tileId.AIR then
			continue
		end

		local minX, maxX = getTileMetadataRectAxis(
			rectangle.x or rectangle.localX or rectangle.minX,
			rectangle.width,
			rectangle.maxX,
			width
		)
		local minY, maxY = getTileMetadataRectAxis(
			rectangle.y or rectangle.localY or rectangle.minY,
			rectangle.height,
			rectangle.maxY,
			height
		)
		if minX == nil or maxX == nil or minY == nil or maxY == nil then
			continue
		end

		for localY = minY, maxY do
			for localX = minX, maxX do
				assignTile(computeTileIndex(localX, localY, width), tileId)
			end
		end
	end

	return repairedTiles, overlapCount
end

function WorldGeneration.RepairChunkTileMetadataOverlaps(
	self: WorldGeneration,
	chunkData: ChunkData,
	forceRepairRaw: any?
): number
	local chunkDataRaw = chunkData :: any
	if forceRepairRaw ~= true and chunkDataRaw._tileMetadataOverlapRepaired == true then
		return 0
	end

	local repairedTiles, overlapCount =
		self:RepairIntersectingTileMetadata(chunkData.tiles, chunkData.width, chunkData.height)
	chunkData.tiles = repairedTiles

	for _, layerData in chunkData.backgroundLayers do
		local repairedLayerTiles, layerOverlapCount =
			self:RepairIntersectingTileMetadata(layerData.tiles, layerData.width, layerData.height)
		layerData.tiles = repairedLayerTiles
		overlapCount += layerOverlapCount
	end

	chunkDataRaw._tileMetadataOverlapRepaired = true
	return overlapCount
end

function WorldGeneration.New(configRaw: WorldGenerationConfig?): WorldGeneration
	local config = if typeof(configRaw) == "table" then configRaw else {} :: any
	local parent = if typeof((config :: any).parent) == "Instance"
		then (config :: any).parent :: Instance
		else WorkspaceFolders.GetOrCreateGameFolder()

	local chunkSize = coerceInteger((config :: any).chunkSize, 8, 128, DEFAULT_CHUNK_SIZE)
	local minTileY = coerceInteger((config :: any).minTileY, -2048, 2048, DEFAULT_MIN_TILE_Y)
	local maxTileY = coerceInteger((config :: any).maxTileY, -2048, 2048, DEFAULT_MAX_TILE_Y)
	local seed = coerceInteger((config :: any).seed, -2147483648, 2147483647, DEFAULT_SEED)
	local desertConfig = if typeof((config :: any).desertConfig) == "table"
		then (config :: any).desertConfig
		else WorldGenerationDesert
	local snowConfig = if typeof((config :: any).snowConfig) == "table"
		then (config :: any).snowConfig
		else WorldGenerationSnow

	local self = setmetatable({
		maid = Maid.new() :: MaidClass,
		seed = seed,
		chunkSize = chunkSize,
		tileSize = FIXED_TILE_SIZE_STUDS,
		tileDepth = FIXED_TILE_DEPTH_STUDS,
		basePlaneX = clampNumber((config :: any).basePlaneX, -4096, 4096, DEFAULT_BASE_PLANE_X),
		wallPlaneOffset = clampNumber((config :: any).wallPlaneOffset, 0.1, 64, DEFAULT_WALL_PLANE_OFFSET),
		horizonDepthBlocks = coerceInteger(
			(config :: any).horizonDepthBlocks,
			DEFAULT_HORIZON_DEPTH_BLOCKS,
			256,
			DEFAULT_HORIZON_DEPTH_BLOCKS
		),
		backgroundLayerCount = coerceInteger(
			(config :: any).backgroundLayerCount,
			1,
			1,
			DEFAULT_BACKGROUND_LAYER_COUNT
		),
		backgroundLayerThicknessBlocks = clampNumber(
			(config :: any).backgroundLayerThicknessBlocks,
			0.5,
			3,
			DEFAULT_BACKGROUND_LAYER_THICKNESS_BLOCKS
		),
		worldOrigin = if typeof((config :: any).worldOrigin) == "Vector3"
			then (config :: any).worldOrigin
			else Vector3.zero,
		minTileY = math.min(minTileY, maxTileY),
		maxTileY = math.max(minTileY, maxTileY),
		bedrockThickness = coerceInteger((config :: any).bedrockThickness, 0, 32, DEFAULT_BEDROCK_THICKNESS),
		defaultRenderDistanceChunks = coerceInteger(
			(config :: any).defaultRenderDistanceChunks,
			1,
			24,
			DEFAULT_RENDER_DISTANCE_CHUNKS
		),
		defaultVerticalRenderDistanceChunks = coerceInteger(
			(config :: any).defaultVerticalRenderDistanceChunks,
			1,
			24,
			DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS
		),
		playerRefreshInterval = clampNumber(
			(config :: any).playerRefreshInterval,
			0.03,
			2,
			DEFAULT_PLAYER_REFRESH_INTERVAL
		),
		maxConcurrentChunkLoads = coerceInteger(
			(config :: any).maxConcurrentChunkLoads,
			1,
			16,
			DEFAULT_MAX_CONCURRENT_CHUNK_LOADS
		),
		maxChunkUnloadsPerHeartbeat = coerceInteger(
			(config :: any).maxChunkUnloadsPerHeartbeat,
			1,
			128,
			DEFAULT_MAX_CHUNK_UNLOADS_PER_HEARTBEAT
		),
		generationRowsPerYield = coerceInteger(
			(config :: any).generationRowsPerYield,
			1,
			64,
			DEFAULT_GENERATION_ROWS_PER_YIELD
		),
		meshingRectsPerYield = coerceInteger(
			(config :: any).meshingRowsPerYield,
			1,
			128,
			DEFAULT_MESHING_RECTS_PER_YIELD
		),
		maxCachedChunkData = coerceInteger((config :: any).maxCachedChunkData, 16, 4096, DEFAULT_MAX_CACHED_CHUNK_DATA),
		maxCachedChunkVisuals = coerceInteger(
			(config :: any).maxCachedChunkVisuals,
			0,
			512,
			DEFAULT_MAX_CACHED_CHUNK_VISUALS
		),
		maxCollisionPartsPerChunk = coerceInteger((config :: any).maxCollisionPartsPerChunk, 64, 20000, 4096),
		maxPoolSize = coerceInteger((config :: any).maxPoolSize, 64, 200000, DEFAULT_POOL_SIZE),
		parent = parent,
		desertConfig = desertConfig,
		snowConfig = snowConfig,
		tileId = TILE_ID,
		wallId = WALL_ID,
		biomeId = BIOME_ID,
		biomeType = BIOME_TYPE,
		propId = PROP_ID,
		tileVisuals = TILE_VISUALS,
		worldFolder = nil :: Folder?,
		chunksFolder = nil :: Folder?,
		collisionChunksFolder = nil :: Folder?,
		heartbeatConnection = nil :: RBXScriptConnection?,
		initialized = false,
		playerRuntimes = {} :: { [Player]: PlayerRuntime },
		playerFocusOctree = configureOctree(Octree.new(), math.max(512, chunkSize * FIXED_TILE_SIZE_STUDS * 64), 6),
		playerFocusNodes = {} :: { [Player]: OctreeNodeObject },
		maxTrackedRenderDistanceChunks = coerceInteger(
			(config :: any).defaultRenderDistanceChunks,
			1,
			24,
			DEFAULT_RENDER_DISTANCE_CHUNKS
		),
		maxTrackedVerticalRenderDistanceChunks = coerceInteger(
			(config :: any).defaultVerticalRenderDistanceChunks,
			1,
			24,
			DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS
		),
		chunkInterestPlayers = {} :: { [string]: { [Player]: boolean } },
		chunkDemand = {} :: { [string]: number },
		chunkRevisions = {} :: { [string]: number },
		chunkOverrides = {} :: { [string]: { [number]: number } },
		chunkWallOverrides = {} :: { [string]: { [number]: number } },
		chunkBiomeOverrides = {} :: { [string]: { [number]: number } },
		chunkLiquidOverrides = {} :: { [string]: { [number]: number } },
		dirtyChunkLookup = {} :: { [string]: boolean },
		dirtyChunkQueue = Queue.new() :: QueueClass<string>,
		cache = nil :: CacheClass?,
		loadedChunkVisuals = {} :: { [string]: ChunkVisual },
		loadedChunkCount = 0,
		cachedChunkVisuals = {} :: { [string]: ChunkVisual },
		cachedChunkVisualCount = 0,
		loadQueue = {} :: { string },
		loadQueueHead = 1,
		loadQueueTail = 0,
		pendingLoadLookup = {} :: { [string]: boolean },
		loadingLookup = {} :: { [string]: boolean },
		activeLoadWorkers = 0,
		unloadQueue = Queue.new() :: QueueClass<string>,
		pendingUnloadLookup = {} :: { [string]: boolean },
		chunkRebuildQueue = Queue.new() :: QueueClass<string>,
		pendingRebuildLookup = {} :: { [string]: boolean },
		chunkLifecycleObservers = {} :: { [number]: ChunkLifecycleObserver },
		nextChunkLifecycleObserverId = 0,
		maxChunkRebuildsPerHeartbeat = coerceInteger((config :: any).maxChunkRebuildsPerHeartbeat, 1, 64, 4),
		cachePruneAccumulator = 0,
		loadedChunkAuditAccumulator = 0,
		liquidGenerator = nil :: LiquidGenerationClass?,
		_chunkCollisionReadySignal = Signal.new() :: SignalObject,
		_chunkCollisionUnloadedSignal = Signal.new() :: SignalObject,
		_chunkTerrainChangedSignal = Signal.new() :: SignalObject,
		_chunkWallChangedSignal = Signal.new() :: SignalObject,
		_chunkDemandChangedSignal = Signal.new() :: SignalObject,
		_playerInterestChangedSignal = Signal.new() :: SignalObject,
		_playerFocusChangedSignal = Signal.new() :: SignalObject,
		_trackedPlayerBrioSignal = Signal.new() :: SignalObject,
		_statsPulseSignal = Signal.new() :: SignalObject,
	}, WorldGeneration)

	self.backgroundLayerThicknessBlocks = math.max(0.5, self.backgroundLayerThicknessBlocks)
	local maxLayersByDepth = math.max(2, math.floor(self.horizonDepthBlocks / self.backgroundLayerThicknessBlocks))
	self.backgroundLayerCount = math.min(self.backgroundLayerCount, maxLayersByDepth)
	self.focusUpdateMinimumDistanceStuds = math.max(0.5, self.tileSize * 0.5)
	self.statsChangedSignal = RxSignal.new(function(): ObservableObject
		return self:ObserveStats() :: ObservableObject
	end) :: RxSignalObject
	self.chunkCollisionReadySignal = RxSignal.new(function(): ObservableObject
		return self:ObserveChunkCollisionReady() :: ObservableObject
	end) :: RxSignalObject
	self.chunkCollisionUnloadedSignal = RxSignal.new(function(): ObservableObject
		return self:ObserveChunkCollisionUnloaded() :: ObservableObject
	end) :: RxSignalObject
	self.chunkTerrainChangedSignal = RxSignal.new(function(): ObservableObject
		return self:ObserveChunkTerrainChanged() :: ObservableObject
	end) :: RxSignalObject
	self.chunkWallChangedSignal = RxSignal.new(function(): ObservableObject
		return self:ObserveChunkWallChanged() :: ObservableObject
	end) :: RxSignalObject
	self.playerInterestChangedSignal = RxSignal.new(function(): ObservableObject
		return self:ObservePlayerInterest() :: ObservableObject
	end) :: RxSignalObject
	self.playerFocusChangedSignal = RxSignal.new(function(): ObservableObject
		return self:ObservePlayerFocusChanged() :: ObservableObject
	end) :: RxSignalObject
	self.trackedPlayerBrioSignal = RxSignal.new(function(): ObservableObject
		return self:ObserveTrackedPlayersBrio() :: ObservableObject
	end) :: RxSignalObject
	self.maid:GiveTask(self._chunkCollisionReadySignal)
	self.maid:GiveTask(self._chunkCollisionUnloadedSignal)
	self.maid:GiveTask(self._chunkTerrainChangedSignal)
	self.maid:GiveTask(self._chunkWallChangedSignal)
	self.maid:GiveTask(self._chunkDemandChangedSignal)
	self.maid:GiveTask(self._playerInterestChangedSignal)
	self.maid:GiveTask(self._playerFocusChangedSignal)
	self.maid:GiveTask(self._trackedPlayerBrioSignal)
	self.maid:GiveTask(self._statsPulseSignal)

	self.cache = Cache.New({
		maxPoolSize = self.maxPoolSize,
		maxCachedChunkData = self.maxCachedChunkData,
		createPart = createPartTemplate,
	} :: any)

	local tilesFolder = getTilesTemplateFolder()
	self.tileTemplatesByTileId = {
		[self.tileId.STONE] = getTileTemplate(tilesFolder, "Stone"),
		[self.tileId.DIRT] = getTileTemplate(tilesFolder, "Dirt"),
		[self.tileId.GRASS] = getTileTemplate(tilesFolder, "Grass"),
		[self.tileId.JUNGLE_GRASS] = getTileTemplate(tilesFolder, "JungleGrass"),
		[self.tileId.WOOD] = getTileTemplate(tilesFolder, "Wood"),
		[self.tileId.CORRUPT_STONE] = getTileTemplate(tilesFolder, "CorruptStone"),
		[self.tileId.CORRUPT_SOIL] = getTileTemplate(tilesFolder, "CorruptSoil"),
		[self.tileId.CORRUPT_GRASS] = getTileTemplate(tilesFolder, "CorruptGrass"),
	}
	self.treeVariantConfigs = createProceduralTreeVariantConfigs()

	self.biomeGenerator = Biome.New({
		seed = self.seed,
		tileId = self.tileId,
		biomeId = self.biomeId,
		biomeType = self.biomeType,
		desertConfig = self.desertConfig,
		snowConfig = self.snowConfig,
	})
	self.caveGenerator = Cave.New({
		seed = self.seed,
		tileId = {
			AIR = self.tileId.AIR,
		},
		wallId = self.wallId,
		biomeId = self.biomeId,
		snowConfig = self.snowConfig,
	})
	self.structuresGenerator = Structures.New({
		seed = self.seed,
		tileId = self.tileId,
		biomeId = self.biomeId,
		biomeType = self.biomeType,
		desertConfig = self.desertConfig,
	})
	local liquidConfigSource = (config :: any).liquidConfig
	if typeof(liquidConfigSource) ~= "table" and typeof(Configs) == "table" then
		liquidConfigSource = (Configs :: any).liquid
	end
	self.liquidGenerator = Liquid.New(liquidConfigSource)

	return self
end

function WorldGeneration.CreateFolders(self: WorldGeneration)
	if self.worldFolder ~= nil and self.chunksFolder ~= nil and self.collisionChunksFolder ~= nil then
		return
	end

	local worldFolder = TileComponent.CreateFolder({
		name = DEFAULT_WORLD_FOLDER_NAME,
		parent = self.parent,
		attributes = {
			Seed = self.seed,
			ChunkSize = self.chunkSize,
			TileSize = self.tileSize,
			TileDepth = self.tileDepth,
			BasePlaneX = self.basePlaneX,
			WallPlaneOffset = self.wallPlaneOffset,
			HorizonDepthBlocks = self.horizonDepthBlocks,
			BackgroundLayerCount = self.backgroundLayerCount,
			WorldOriginX = self.worldOrigin.X,
			WorldOriginY = self.worldOrigin.Y,
			WorldOriginZ = self.worldOrigin.Z,
		},
	})
	WorkspaceFolders.ManageFolder(worldFolder, self.parent)

	local chunksFolder = TileComponent.CreateFolder({
		name = DEFAULT_WORLD_CHUNKS_FOLDER_NAME,
		parent = worldFolder,
	} :: any)
	WorkspaceFolders.ManageFolder(chunksFolder, worldFolder)

	local collisionChunksFolder = TileComponent.CreateFolder({
		name = DEFAULT_WORLD_COLLISION_FOLDER_NAME,
		parent = worldFolder,
	} :: any)
	WorkspaceFolders.ManageFolder(collisionChunksFolder, worldFolder)

	self.worldFolder = worldFolder
	self.chunksFolder = chunksFolder
	self.collisionChunksFolder = collisionChunksFolder
end

function WorldGeneration.Init(self: WorldGeneration)
	if self.initialized then
		return
	end

	self:CreateFolders()
	self.initialized = true
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:OnHeartbeat(deltaTime)
	end)
	self.maid:GiveTask(self.heartbeatConnection)
	self:PulseStatsChanged()
end

function WorldGeneration.OnHeartbeat(self: WorldGeneration, deltaTime: number)
	self:UpdateTrackedPlayers(deltaTime)
	self:AuditLoadedChunksForUnload(deltaTime)
	self:ProcessDirtyChunkQueue()
	self:ProcessUnloadQueue()
	self:PumpLoadQueue()
	self:ProcessChunkRebuildQueue()
	self:PruneChunkDataCache(deltaTime)
	self:PruneCachedChunkVisuals()
end

function WorldGeneration.IsChunkYWithinWorldBounds(self: WorldGeneration, chunkY: number): boolean
	local chunkTileMinY = chunkY * self.chunkSize
	local chunkTileMaxY = chunkTileMinY + self.chunkSize - 1
	if chunkTileMaxY < self.minTileY then
		return false
	end
	if chunkTileMinY > self.maxTileY then
		return false
	end
	return true
end

function WorldGeneration.EnqueueLoadByKey(self: WorldGeneration, chunkKey: string)
	if self.pendingLoadLookup[chunkKey] then
		return
	end
	if self.loadingLookup[chunkKey] then
		return
	end
	if self.loadedChunkVisuals[chunkKey] then
		return
	end

	self.pendingLoadLookup[chunkKey] = true
	self.loadQueueTail += 1
	self.loadQueue[self.loadQueueTail] = chunkKey
	self:PulseStatsChanged()
end

function WorldGeneration.EnqueueUnloadByKey(self: WorldGeneration, chunkKey: string)
	if self.pendingUnloadLookup[chunkKey] then
		return
	end

	self.pendingUnloadLookup[chunkKey] = true
	self.unloadQueue:PushRight(chunkKey)
	self:PulseStatsChanged()
end

function WorldGeneration.GetChunkLoadPriority(self: WorldGeneration, chunkKey: string): number
	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return math.huge
	end

	local bestDistanceSquared = math.huge
	local hasInterestedPlayerWithoutFocus = false
	for _, runtime in self.playerRuntimes do
		if runtime.interestKeys[chunkKey] ~= true then
			continue
		end

		local centerChunkX = runtime.lastChunkX
		local centerChunkY = runtime.lastChunkY
		if (centerChunkX == nil or centerChunkY == nil) and runtime.focusPosition ~= nil then
			local tileX = toTileCoordinate(runtime.focusPosition.Z - self.worldOrigin.Z, self.tileSize)
			local tileY = toTileCoordinate(runtime.focusPosition.Y - self.worldOrigin.Y, self.tileSize)
			centerChunkX = toChunkCoordinate(tileX, self.chunkSize)
			centerChunkY = toChunkCoordinate(tileY, self.chunkSize)
		end

		if centerChunkX == nil or centerChunkY == nil then
			hasInterestedPlayerWithoutFocus = true
			continue
		end

		local deltaX = chunkX - centerChunkX
		local deltaY = chunkY - centerChunkY
		bestDistanceSquared = math.min(bestDistanceSquared, deltaX * deltaX + deltaY * deltaY)
	end

	if bestDistanceSquared < math.huge then
		return bestDistanceSquared
	end
	return if hasInterestedPlayerWithoutFocus then 0 else math.huge
end

function WorldGeneration.CompactLoadQueue(self: WorldGeneration)
	while self.loadQueueHead <= self.loadQueueTail and self.loadQueue[self.loadQueueHead] == nil do
		self.loadQueueHead += 1
	end

	if self.loadQueueHead <= self.loadQueueTail then
		return
	end

	table.clear(self.loadQueue)
	self.loadQueueHead = 1
	self.loadQueueTail = 0
end

function WorldGeneration.DequeueLoadKey(self: WorldGeneration): string?
	if self.loadQueueHead > self.loadQueueTail then
		if self.loadQueueHead ~= 1 or self.loadQueueTail ~= 0 then
			table.clear(self.loadQueue)
			self.loadQueueHead = 1
			self.loadQueueTail = 0
		end
		return nil
	end

	local bestIndex: number? = nil
	local bestChunkKey: string? = nil
	local bestPriority = math.huge
	for queueIndex = self.loadQueueHead, self.loadQueueTail do
		local queuedChunkKey = self.loadQueue[queueIndex]
		if queuedChunkKey == nil then
			continue
		end

		if
			(self.chunkDemand[queuedChunkKey] or 0) <= 0
			or self.loadedChunkVisuals[queuedChunkKey] ~= nil
			or self.loadingLookup[queuedChunkKey] == true
		then
			self.loadQueue[queueIndex] = nil
			self.pendingLoadLookup[queuedChunkKey] = nil
			continue
		end

		local priority = self:GetChunkLoadPriority(queuedChunkKey)
		if bestIndex == nil or priority < bestPriority then
			bestIndex = queueIndex
			bestChunkKey = queuedChunkKey
			bestPriority = priority
		end
	end

	if bestIndex == nil or bestChunkKey == nil then
		self:CompactLoadQueue()
		return nil
	end

	self.loadQueue[bestIndex] = nil
	self:CompactLoadQueue()

	return bestChunkKey
end

function WorldGeneration.DequeueUnloadKey(self: WorldGeneration): string?
	if self.unloadQueue:IsEmpty() then
		return nil
	end

	local chunkKey = self.unloadQueue:PopLeft()
	if chunkKey == nil then
		return nil
	end

	return chunkKey
end

function WorldGeneration.MarkChunkDirtyByKey(self: WorldGeneration, chunkKey: string)
	if self.dirtyChunkLookup[chunkKey] then
		return
	end
	self.dirtyChunkLookup[chunkKey] = true
	self.dirtyChunkQueue:PushRight(chunkKey)
	self:PulseStatsChanged()
end

function WorldGeneration.DequeueDirtyChunkKey(self: WorldGeneration): string?
	if self.dirtyChunkQueue:IsEmpty() then
		return nil
	end

	local chunkKey = self.dirtyChunkQueue:PopLeft()
	if chunkKey == nil then
		return nil
	end

	return chunkKey
end

function WorldGeneration.EnqueueChunkRebuildByKey(self: WorldGeneration, chunkKey: string)
	if self.pendingRebuildLookup[chunkKey] then
		return
	end

	self.pendingRebuildLookup[chunkKey] = true
	self.chunkRebuildQueue:PushRight(chunkKey)
	self:PulseStatsChanged()
end

function WorldGeneration.DequeueChunkRebuildKey(self: WorldGeneration): string?
	if self.chunkRebuildQueue:IsEmpty() then
		return nil
	end

	local chunkKey = self.chunkRebuildQueue:PopLeft()
	if chunkKey == nil then
		return nil
	end

	return chunkKey
end

function WorldGeneration.ProcessDirtyChunkQueue(self: WorldGeneration)
	local processed = 0
	local maxProcessed = 256

	while processed < maxProcessed do
		local chunkKey = self:DequeueDirtyChunkKey()
		if chunkKey == nil then
			break
		end

		processed += 1
		self.dirtyChunkLookup[chunkKey] = nil
		if self.loadedChunkVisuals[chunkKey] ~= nil then
			self:EnqueueChunkRebuildByKey(chunkKey)
		end
	end
end

function WorldGeneration.RebuildLoadedChunkByKey(self: WorldGeneration, chunkKey: string, contextRaw: any?): boolean
	local previousVisual = self.loadedChunkVisuals[chunkKey]
	if previousVisual == nil then
		return false
	end
	local context = if typeof(contextRaw) == "table" then contextRaw :: { [string]: any } else {} :: any

	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return false
	end
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return false
	end

	local cachedVisual = self.cachedChunkVisuals[chunkKey]
	if cachedVisual ~= nil then
		self.cachedChunkVisuals[chunkKey] = nil
		self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
		self:ReleaseChunkVisual(cachedVisual)
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local replacementVisual = self:BuildChunkVisual(chunkData)
	local currentVisual = self.loadedChunkVisuals[chunkKey]
	if currentVisual ~= previousVisual then
		self:ReleaseChunkVisual(replacementVisual)
		return false
	end

	if (self.chunkDemand[chunkKey] or 0) <= 0 then
		self:ReleaseChunkVisual(replacementVisual)
		return false
	end

	self.loadedChunkVisuals[chunkKey] = replacementVisual
	self:AttachChunkVisual(replacementVisual)
	self:ReleaseChunkVisual(previousVisual)
	self:NotifyChunkCollisionReady(chunkKey, {
		reason = if typeof(context.reason) == "string" then context.reason else "rebuildReady",
		fromCache = false,
		rebuilt = true,
	})
	return true
end

function WorldGeneration.ProcessChunkRebuildQueue(self: WorldGeneration)
	local processed = 0
	while processed < self.maxChunkRebuildsPerHeartbeat do
		local chunkKey = self:DequeueChunkRebuildKey()
		if chunkKey == nil then
			break
		end

		self.pendingRebuildLookup[chunkKey] = nil
		if self.loadedChunkVisuals[chunkKey] == nil then
			continue
		end
		if self.loadingLookup[chunkKey] then
			self:EnqueueChunkRebuildByKey(chunkKey)
			continue
		end

		self:RebuildLoadedChunkByKey(chunkKey, {
			reason = "rebuildReady",
		})
		processed += 1
	end
end

function WorldGeneration.BumpChunkRevisionByKey(self: WorldGeneration, chunkKey: string): number
	local current = self.chunkRevisions[chunkKey] or 0
	local nextRevision = current + 1
	if nextRevision >= 2147483647 then
		nextRevision = 1
	end
	self.chunkRevisions[chunkKey] = nextRevision
	return nextRevision
end

function WorldGeneration.GetChunkRevisionByKey(self: WorldGeneration, chunkKey: string): number
	return self.chunkRevisions[chunkKey] or 0
end

function WorldGeneration.PulseStatsChanged(self: WorldGeneration)
	self._statsPulseSignal:Fire()
end

function WorldGeneration.RecomputeTrackedRenderDistanceBounds(self: WorldGeneration)
	local maxRenderDistance = self.defaultRenderDistanceChunks
	local maxVerticalRenderDistance = self.defaultVerticalRenderDistanceChunks

	for _, runtime in self.playerRuntimes do
		if runtime.renderDistance > maxRenderDistance then
			maxRenderDistance = runtime.renderDistance
		end
		if runtime.verticalRenderDistance > maxVerticalRenderDistance then
			maxVerticalRenderDistance = runtime.verticalRenderDistance
		end
	end

	self.maxTrackedRenderDistanceChunks = maxRenderDistance
	self.maxTrackedVerticalRenderDistanceChunks = maxVerticalRenderDistance
end

function WorldGeneration.UpdateTrackedPlayerFocusIndex(
	self: WorldGeneration,
	player: Player,
	runtime: PlayerRuntime,
	focusPositionRaw: Vector3?
)
	local focusPosition = if typeof(focusPositionRaw) == "Vector3" then focusPositionRaw else nil
	local existingNode = runtime.focusNode

	if focusPosition == nil then
		if existingNode ~= nil then
			existingNode:Destroy()
			runtime.focusNode = nil
			self.playerFocusNodes[player] = nil
		end
		runtime.focusPosition = nil
		return
	end

	if existingNode == nil then
		local nextNode = self.playerFocusOctree:CreateNode(focusPosition, player) :: OctreeNodeObject
		runtime.focusNode = nextNode
		self.playerFocusNodes[player] = nextNode
	else
		existingNode:SetPosition(focusPosition)
	end

	runtime.focusPosition = focusPosition
end

function WorldGeneration.SetPlayerChunkInterest(
	self: WorldGeneration,
	player: Player,
	runtime: PlayerRuntime,
	chunkKey: string,
	enabled: boolean
)
	if enabled then
		runtime.interestKeys[chunkKey] = true
		local interestedPlayers = self.chunkInterestPlayers[chunkKey]
		if interestedPlayers == nil then
			interestedPlayers = {}
			self.chunkInterestPlayers[chunkKey] = interestedPlayers
		end
		interestedPlayers[player] = true
		return
	end

	runtime.interestKeys[chunkKey] = nil
	local interestedPlayers = self.chunkInterestPlayers[chunkKey]
	if interestedPlayers == nil then
		return
	end

	interestedPlayers[player] = nil
	if next(interestedPlayers) == nil then
		self.chunkInterestPlayers[chunkKey] = nil
	end
end

function WorldGeneration.BuildPlayerInterestChangedEvent(
	_self: WorldGeneration,
	player: Player,
	runtime: PlayerRuntime,
	focusPositionRaw: Vector3?,
	centerChunkX: number?,
	centerChunkY: number?
): PlayerInterestChangedEvent
	return {
		player = player,
		focusPosition = if typeof(focusPositionRaw) == "Vector3" then focusPositionRaw else nil,
		centerChunkX = centerChunkX,
		centerChunkY = centerChunkY,
		renderDistance = runtime.renderDistance,
		verticalRenderDistance = runtime.verticalRenderDistance,
		interestKeys = cloneBooleanLookup(runtime.interestKeys),
	}
end

function WorldGeneration.ObserveStats(self: WorldGeneration): ObservableObject
	return Rx.fromSignal(self._statsPulseSignal):Pipe({
		Rx.startWith({ false }),
		Rx.map(function()
			return self:GetStats()
		end),
		Rx.shareReplay(1),
	}) :: ObservableObject
end

function WorldGeneration.ObserveChunkCollisionReady(self: WorldGeneration, chunkKeyRaw: any?): ObservableObject
	local chunkKey = if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then chunkKeyRaw else nil
	return Rx.fromSignal(self._chunkCollisionReadySignal):Pipe({
		Rx.where(function(event: ChunkLifecycleEvent)
			return chunkKey == nil or event.chunkKey == chunkKey
		end),
	}) :: ObservableObject
end

function WorldGeneration.ObserveChunkCollisionUnloaded(self: WorldGeneration, chunkKeyRaw: any?): ObservableObject
	local chunkKey = if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then chunkKeyRaw else nil
	return Rx.fromSignal(self._chunkCollisionUnloadedSignal):Pipe({
		Rx.where(function(event: ChunkLifecycleEvent)
			return chunkKey == nil or event.chunkKey == chunkKey
		end),
	}) :: ObservableObject
end

function WorldGeneration.ObserveChunkTerrainChanged(self: WorldGeneration, chunkKeyRaw: any?): ObservableObject
	local chunkKey = if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then chunkKeyRaw else nil
	return Rx.fromSignal(self._chunkTerrainChangedSignal):Pipe({
		Rx.where(function(event: ChunkTerrainChangedEvent)
			return chunkKey == nil or event.chunkKey == chunkKey
		end),
	}) :: ObservableObject
end

function WorldGeneration.ObserveChunkWallChanged(self: WorldGeneration, chunkKeyRaw: any?): ObservableObject
	local chunkKey = if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then chunkKeyRaw else nil
	return Rx.fromSignal(self._chunkWallChangedSignal):Pipe({
		Rx.where(function(event: ChunkTerrainChangedEvent)
			return chunkKey == nil or event.chunkKey == chunkKey
		end),
	}) :: ObservableObject
end

function WorldGeneration.ObserveChunkDemand(self: WorldGeneration, chunkKeyRaw: any?): ObservableObject
	local chunkKey = if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then chunkKeyRaw else nil
	return Rx.fromSignal(self._chunkDemandChangedSignal):Pipe({
		Rx.where(function(event: ChunkDemandChangedEvent)
			return chunkKey == nil or event.chunkKey == chunkKey
		end),
	}) :: ObservableObject
end

function WorldGeneration.ObservePlayerInterest(self: WorldGeneration, playerRaw: any?): ObservableObject
	local targetPlayer = if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then playerRaw else nil
	return Rx.fromSignal(self._playerInterestChangedSignal):Pipe({
		Rx.where(function(event: PlayerInterestChangedEvent)
			return targetPlayer == nil or event.player == targetPlayer
		end),
	}) :: ObservableObject
end

function WorldGeneration.ObservePlayerFocusChanged(self: WorldGeneration, playerRaw: any?): ObservableObject
	local targetPlayer = if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then playerRaw else nil
	return Rx.fromSignal(self._playerFocusChangedSignal):Pipe({
		Rx.where(function(event: PlayerInterestChangedEvent)
			return targetPlayer == nil or event.player == targetPlayer
		end),
	}) :: ObservableObject
end

function WorldGeneration.ObserveTrackedPlayersBrio(self: WorldGeneration): ObservableObject
	return Rx.fromSignal(self._trackedPlayerBrioSignal):Pipe({
		Rx.where(function(brio)
			return brio ~= nil
		end),
		RxBrioUtils.toBrio(),
		Rx.share(),
	}) :: ObservableObject
end

function WorldGeneration.ObservePlayerFocus(self: WorldGeneration, player: Player): ObservableObject
	return Rx.defer(function()
		local runtime = self.playerRuntimes[player]
		if runtime == nil then
			return Rx.EMPTY
		end

		return Rx.merge({
			Rx.of(
				self:BuildPlayerInterestChangedEvent(
					player,
					runtime,
					runtime.focusPosition,
					runtime.lastChunkX,
					runtime.lastChunkY
				)
			),
			RxBrioUtils.completeOnDeath(runtime.brio, self:ObservePlayerFocusChanged(player)),
		})
	end) :: ObservableObject
end

function WorldGeneration.GetTrackedPlayerFocusPosition(self: WorldGeneration, player: Player): Vector3?
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end

	return runtime.focusPosition
end

function WorldGeneration.GetPlayersInterestedInChunk(self: WorldGeneration, chunkKeyRaw: any): { Player }
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return {}
	end

	local interestedPlayers = self.chunkInterestPlayers[chunkKeyRaw]
	if interestedPlayers == nil then
		return {}
	end

	local players = {}
	for player in interestedPlayers do
		players[#players + 1] = player
	end
	return players
end

function WorldGeneration.GetPlayersNearWorldPosition(
	self: WorldGeneration,
	worldPositionRaw: any,
	radiusRaw: any,
	maxCountRaw: any?
): { Player }
	if typeof(worldPositionRaw) ~= "Vector3" then
		return {}
	end

	local radius = if isFiniteNumber(radiusRaw) then math.max(0, radiusRaw :: number) else 0
	if radius <= 0 then
		return {}
	end

	local candidates
	if isFiniteNumber(maxCountRaw) and (maxCountRaw :: number) > 0 then
		candidates = {
			self.playerFocusOctree:KNearestNeighborsSearch(worldPositionRaw, math.floor(maxCountRaw :: number), radius),
		}
	else
		candidates = { self.playerFocusOctree:RadiusSearch(worldPositionRaw, radius) }
	end

	local players = {}
	local seen = {} :: { [Player]: boolean }
	local candidatePlayers = candidates[1]
	if typeof(candidatePlayers) ~= "table" then
		return players
	end

	for _, player in candidatePlayers do
		if
			typeof(player) == "Instance"
			and player:IsA("Player")
			and self.playerRuntimes[player] ~= nil
			and not seen[player]
		then
			seen[player] = true
			players[#players + 1] = player
		end
	end

	return players
end

function WorldGeneration.GetPlayersNearChunk(
	self: WorldGeneration,
	chunkXRaw: any,
	chunkYRaw: any,
	extraRadiusChunksRaw: any?
): { Player }
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return {}
	end

	local chunkX = math.floor(chunkXRaw :: number)
	local chunkY = math.floor(chunkYRaw :: number)
	local extraRadiusChunks = if isFiniteNumber(extraRadiusChunksRaw)
		then math.max(0, extraRadiusChunksRaw :: number)
		else 0
	local centerTileX = chunkX * self.chunkSize + self.chunkSize * 0.5
	local centerTileY = chunkY * self.chunkSize + self.chunkSize * 0.5
	local worldPosition = self:ComputeTileCenterPosition(centerTileX, centerTileY, 0)
	local horizontalRadiusChunks = self.maxTrackedRenderDistanceChunks + extraRadiusChunks + 1
	local verticalRadiusChunks = self.maxTrackedVerticalRenderDistanceChunks + extraRadiusChunks + 1
	local radiusStuds = math.max(horizontalRadiusChunks, verticalRadiusChunks) * self.chunkSize * self.tileSize
	return self:GetPlayersNearWorldPosition(worldPosition, radiusStuds)
end

function WorldGeneration.RegisterChunkLifecycleObserver(
	self: WorldGeneration,
	observerRaw: any
): ChunkLifecycleConnection?
	if typeof(observerRaw) ~= "table" then
		return nil
	end

	self.nextChunkLifecycleObserverId += 1
	local observerId = self.nextChunkLifecycleObserverId
	self.chunkLifecycleObservers[observerId] = observerRaw :: ChunkLifecycleObserver
	local disconnected = false

	return {
		Disconnect = function(_self: ChunkLifecycleConnection)
			if disconnected then
				return
			end
			disconnected = true
			self.chunkLifecycleObservers[observerId] = nil
		end,
	}
end

function WorldGeneration.NotifyChunkCollisionReady(self: WorldGeneration, chunkKey: string, contextRaw: any?)
	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return
	end
	local context = cloneDictionaryShallow(contextRaw)

	for _, observer in self.chunkLifecycleObservers do
		local callback = (observer :: any).OnChunkCollisionReady
		if typeof(callback) ~= "function" then
			continue
		end
		pcall(function()
			callback(observer, chunkX, chunkY, context)
		end)
	end

	self._chunkCollisionReadySignal:Fire({
		chunkKey = chunkKey,
		chunkX = chunkX,
		chunkY = chunkY,
		reason = if typeof(context.reason) == "string" then context.reason else "loaded",
		context = context,
	})
	self:PulseStatsChanged()
end

function WorldGeneration.NotifyChunkCollisionUnloaded(self: WorldGeneration, chunkKey: string, contextRaw: any?)
	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return
	end
	local context = cloneDictionaryShallow(contextRaw)

	for _, observer in self.chunkLifecycleObservers do
		local callback = (observer :: any).OnChunkCollisionUnloaded
		if typeof(callback) ~= "function" then
			continue
		end
		pcall(function()
			callback(observer, chunkX, chunkY, context)
		end)
	end

	self._chunkCollisionUnloadedSignal:Fire({
		chunkKey = chunkKey,
		chunkX = chunkX,
		chunkY = chunkY,
		reason = if typeof(context.reason) == "string" then context.reason else "unloaded",
		context = context,
	})
	self:PulseStatsChanged()
end

function WorldGeneration.NotifyChunkTerrainChanged(
	self: WorldGeneration,
	chunkKey: string,
	dirtyBounds: ChunkDirtyBounds,
	contextRaw: any?
)
	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return
	end
	local context = cloneDictionaryShallow(contextRaw)

	for _, observer in self.chunkLifecycleObservers do
		local callback = (observer :: any).OnChunkTerrainChanged
		if typeof(callback) ~= "function" then
			continue
		end
		pcall(function()
			callback(observer, chunkX, chunkY, dirtyBounds, context)
		end)
	end

	self._chunkTerrainChangedSignal:Fire({
		chunkKey = chunkKey,
		chunkX = chunkX,
		chunkY = chunkY,
		dirtyBounds = dirtyBounds,
		reason = if typeof(context.reason) == "string" then context.reason else "terrainChanged",
		context = context,
	})
	self:PulseStatsChanged()
end

function WorldGeneration.NotifyChunkWallChanged(
	self: WorldGeneration,
	chunkKey: string,
	dirtyBounds: ChunkDirtyBounds,
	contextRaw: any?
)
	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return
	end
	local context = cloneDictionaryShallow(contextRaw)
	self._chunkWallChangedSignal:Fire({
		chunkKey = chunkKey,
		chunkX = chunkX,
		chunkY = chunkY,
		dirtyBounds = dirtyBounds,
		reason = if typeof(context.reason) == "string" then context.reason else "wallChanged",
		context = context,
	})
end

function WorldGeneration.IsChunkCollisionReady(self: WorldGeneration, chunkXRaw: any, chunkYRaw: any): boolean
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return false
	end

	local chunkX = math.floor(chunkXRaw :: number)
	local chunkY = math.floor(chunkYRaw :: number)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return false
	end

	local chunkKey = packChunkKey(chunkX, chunkY)
	local visual = self.loadedChunkVisuals[chunkKey]
	if visual == nil then
		return false
	end
	if self.loadingLookup[chunkKey] then
		return false
	end
	if self.dirtyChunkLookup[chunkKey] or self.pendingRebuildLookup[chunkKey] then
		return false
	end
	if visual.model:GetAttribute("ChunkCollisionReady") ~= true then
		return false
	end
	return true
end

function WorldGeneration.IsChunkCollisionReadyByKey(self: WorldGeneration, chunkKeyRaw: any): boolean
	if typeof(chunkKeyRaw) ~= "string" then
		return false
	end
	local chunkX, chunkY = unpackChunkKey(chunkKeyRaw)
	if chunkX == nil or chunkY == nil then
		return false
	end
	return self:IsChunkCollisionReady(chunkX, chunkY)
end

function WorldGeneration.GetLoadedCollisionChunkCount(self: WorldGeneration): number
	return self.loadedChunkCount
end

function WorldGeneration.AuditLoadedChunksForUnload(self: WorldGeneration, deltaTime: number)
	self.loadedChunkAuditAccumulator += deltaTime
	if self.loadedChunkAuditAccumulator < 0.25 then
		return
	end
	self.loadedChunkAuditAccumulator = 0

	for chunkKey in self.loadedChunkVisuals do
		if (self.chunkDemand[chunkKey] or 0) <= 0 then
			self:EnqueueUnloadByKey(chunkKey)
		end
	end

	for chunkKey in self.chunkDemand do
		if (self.chunkDemand[chunkKey] or 0) <= 0 then
			continue
		end

		local visual = self.loadedChunkVisuals[chunkKey]
		if visual ~= nil then
			if
				visual.model:GetAttribute("ChunkCollisionReady") ~= true
				and not self.loadingLookup[chunkKey]
				and not self.dirtyChunkLookup[chunkKey]
				and not self.pendingRebuildLookup[chunkKey]
			then
				self:AttachChunkVisual(visual)
				self:NotifyChunkCollisionReady(chunkKey, {
					reason = "auditReady",
					selfHealed = true,
				})
			end
			continue
		end
		if self.loadingLookup[chunkKey] then
			continue
		end

		self:EnqueueLoadByKey(chunkKey)
	end
end

function WorldGeneration.AdjustChunkDemand(self: WorldGeneration, chunkKey: string, delta: number)
	if delta == 0 then
		return
	end

	local current = self.chunkDemand[chunkKey] or 0
	local nextDemand = current + delta
	if nextDemand < 0 then
		nextDemand = 0
	end

	if nextDemand == 0 then
		if current ~= 0 then
			self.chunkDemand[chunkKey] = nil
			self:EnqueueUnloadByKey(chunkKey)
			self._chunkDemandChangedSignal:Fire({
				chunkKey = chunkKey,
				previousDemand = current,
				nextDemand = 0,
			})
			self:PulseStatsChanged()
		end
		return
	end

	self.chunkDemand[chunkKey] = nextDemand
	if current == 0 then
		self:EnqueueLoadByKey(chunkKey)
	end
	if current ~= nextDemand then
		self._chunkDemandChangedSignal:Fire({
			chunkKey = chunkKey,
			previousDemand = current,
			nextDemand = nextDemand,
		})
		self:PulseStatsChanged()
	end
end

function WorldGeneration.ClearPlayerInterest(self: WorldGeneration, player: Player, runtime: PlayerRuntime)
	local chunkKeys = {}
	for chunkKey in runtime.interestKeys do
		chunkKeys[#chunkKeys + 1] = chunkKey
	end

	for _, chunkKey in chunkKeys do
		self:AdjustChunkDemand(chunkKey, -1)
		self:SetPlayerChunkInterest(player, runtime, chunkKey, false)
	end
end

function WorldGeneration.TrackPlayer(
	self: WorldGeneration,
	player: Player,
	renderDistanceRaw: any?,
	verticalRenderDistanceRaw: any?
)
	if self.playerRuntimes[player] then
		self:SetPlayerRenderDistance(player, renderDistanceRaw, verticalRenderDistanceRaw)
		return
	end

	local renderDistance = coerceInteger(renderDistanceRaw, 1, 24, self.defaultRenderDistanceChunks)
	local verticalRenderDistance =
		coerceInteger(verticalRenderDistanceRaw, 1, 24, self.defaultVerticalRenderDistanceChunks)
	local runtimeMaid = Maid.new() :: MaidClass

	local runtime: PlayerRuntime = {
		maid = runtimeMaid,
		brio = nil :: any,
		renderDistance = renderDistance,
		verticalRenderDistance = verticalRenderDistance,
		interestKeys = {},
		refreshAccumulator = self.playerRefreshInterval,
		forceRefresh = true,
		lastChunkX = nil,
		lastChunkY = nil,
		focusPosition = nil,
		focusNode = nil,
	}
	local runtimeBrio = Brio.new(player, runtime) :: BrioObject
	runtime.brio = runtimeBrio

	runtimeMaid:GiveTask(runtimeBrio)
	runtimeMaid:GiveTask(player.CharacterAdded:Connect(function()
		runtime.forceRefresh = true
		runtime.refreshAccumulator = self.playerRefreshInterval
	end))
	runtimeMaid:GiveTask(player.CharacterRemoving:Connect(function()
		runtime.forceRefresh = true
		runtime.refreshAccumulator = self.playerRefreshInterval
	end))

	self.playerRuntimes[player] = runtime
	self:RecomputeTrackedRenderDistanceBounds()
	self._trackedPlayerBrioSignal:Fire(runtimeBrio)
	self:PulseStatsChanged()
	self:RefreshPlayerInterest(player, runtime)
end
function WorldGeneration.UntrackPlayer(self: WorldGeneration, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:ClearPlayerInterest(player, runtime)
	self:UpdateTrackedPlayerFocusIndex(player, runtime, nil)
	runtime.brio:Kill()
	runtime.maid:Destroy()
	self.playerRuntimes[player] = nil
	self:RecomputeTrackedRenderDistanceBounds()
	self:PulseStatsChanged()
end

function WorldGeneration.SetPlayerRenderDistance(
	self: WorldGeneration,
	player: Player,
	renderDistanceRaw: any,
	verticalRenderDistanceRaw: any?
)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:TrackPlayer(player, renderDistanceRaw, verticalRenderDistanceRaw)
		return
	end

	local nextRenderDistance = coerceInteger(renderDistanceRaw, 1, 24, runtime.renderDistance)
	local nextVerticalRenderDistance = coerceInteger(verticalRenderDistanceRaw, 1, 24, runtime.verticalRenderDistance)

	if runtime.renderDistance ~= nextRenderDistance then
		runtime.renderDistance = nextRenderDistance
		runtime.forceRefresh = true
	end
	if runtime.verticalRenderDistance ~= nextVerticalRenderDistance then
		runtime.verticalRenderDistance = nextVerticalRenderDistance
		runtime.forceRefresh = true
	end

	if runtime.forceRefresh then
		runtime.refreshAccumulator = self.playerRefreshInterval
	end
	self:RecomputeTrackedRenderDistanceBounds()
	self:PulseStatsChanged()
end

function WorldGeneration.GetPlayerRenderDistance(self: WorldGeneration, player: Player): (number, number)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return self.defaultRenderDistanceChunks, self.defaultVerticalRenderDistanceChunks
	end

	return runtime.renderDistance, runtime.verticalRenderDistance
end

function WorldGeneration.GetPlayerInterestKeys(self: WorldGeneration, player: Player): { [string]: boolean }
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return {}
	end

	local clone: { [string]: boolean } = {}
	for chunkKey in runtime.interestKeys do
		clone[chunkKey] = true
	end
	return clone
end

function WorldGeneration.GetPlayerRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local rootCandidate = character:FindFirstChild("HumanoidRootPart")
	if rootCandidate and rootCandidate:IsA("BasePart") then
		return rootCandidate
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local humanoidRoot = humanoid.RootPart
		if humanoidRoot then
			return humanoidRoot
		end
	end

	local primaryPart = character.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local lowerTorso = character:FindFirstChild("LowerTorso")
	if lowerTorso and lowerTorso:IsA("BasePart") then
		return lowerTorso
	end

	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	return nil
end

function WorldGeneration.GetPlayerFocusPosition(self: WorldGeneration, player: Player): Vector3?
	local rootPart = WorldGeneration.GetPlayerRootPart(player)
	if rootPart ~= nil then
		return rootPart.Position
	end

	local character = player.Character
	if character == nil then
		return self:GetDefaultPlayerFocusPosition()
	end

	local ok, pivot = pcall(function(): CFrame
		return character:GetPivot()
	end)
	if ok then
		return (pivot :: CFrame).Position
	end

	return self:GetDefaultPlayerFocusPosition()
end

function WorldGeneration.GetDefaultPlayerFocusPosition(self: WorldGeneration): Vector3
	local spawnLocation = Workspace:FindFirstChild("SpawnLocation", true)
	if spawnLocation ~= nil and spawnLocation:IsA("BasePart") then
		return Vector3.new(self.worldOrigin.X + self.basePlaneX, spawnLocation.Position.Y, spawnLocation.Position.Z)
	end

	local column = self.biomeGenerator:GetColumnProfile(0)
	return self:ComputeTileCenterPosition(0.5, column.surfaceY + DEFAULT_PRELOAD_FOCUS_SURFACE_OFFSET_TILES, 0)
end

function WorldGeneration.RefreshPlayerInterest(self: WorldGeneration, player: Player, runtimeRaw: PlayerRuntime?)
	local runtime = if runtimeRaw then runtimeRaw else self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	local previousFocusPosition = runtime.focusPosition
	local focusPosition = self:GetPlayerFocusPosition(player)
	if focusPosition == nil then
		if next(runtime.interestKeys) ~= nil then
			self:ClearPlayerInterest(player, runtime)
			self._playerInterestChangedSignal:Fire(self:BuildPlayerInterestChangedEvent(player, runtime, nil, nil, nil))
		end
		if previousFocusPosition ~= nil then
			self._playerFocusChangedSignal:Fire(self:BuildPlayerInterestChangedEvent(player, runtime, nil, nil, nil))
		end
		self:UpdateTrackedPlayerFocusIndex(player, runtime, nil)
		runtime.lastChunkX = nil
		runtime.lastChunkY = nil
		runtime.forceRefresh = false
		self:PulseStatsChanged()
		return
	end

	local tileX = toTileCoordinate(focusPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(focusPosition.Y - self.worldOrigin.Y, self.tileSize)
	local centerChunkX = toChunkCoordinate(tileX, self.chunkSize)
	local centerChunkY = toChunkCoordinate(tileY, self.chunkSize)
	local minChunkY = toChunkCoordinate(self.minTileY, self.chunkSize)
	local maxChunkY = toChunkCoordinate(self.maxTileY, self.chunkSize)
	centerChunkY = math.clamp(centerChunkY, minChunkY, maxChunkY)
	local focusChanged =
		didVectorMeaningfullyChange(previousFocusPosition, focusPosition, self.focusUpdateMinimumDistanceStuds)

	if focusChanged then
		self:UpdateTrackedPlayerFocusIndex(player, runtime, focusPosition)
		self._playerFocusChangedSignal:Fire(
			self:BuildPlayerInterestChangedEvent(player, runtime, focusPosition, centerChunkX, centerChunkY)
		)
	end

	if not runtime.forceRefresh and runtime.lastChunkX == centerChunkX and runtime.lastChunkY == centerChunkY then
		return
	end

	local nextInterest: { [string]: boolean } = {}
	local nextInterestEntries = {}
	local previousInterest = cloneBooleanLookup(runtime.interestKeys)
	local radiusSquared = runtime.renderDistance * runtime.renderDistance

	for offsetY = -runtime.verticalRenderDistance, runtime.verticalRenderDistance do
		local chunkY = centerChunkY + offsetY
		if not self:IsChunkYWithinWorldBounds(chunkY) then
			continue
		end

		for offsetX = -runtime.renderDistance, runtime.renderDistance do
			if offsetX * offsetX + offsetY * offsetY > radiusSquared then
				continue
			end

			local chunkX = centerChunkX + offsetX
			local chunkKey = packChunkKey(chunkX, chunkY)
			nextInterest[chunkKey] = true
			nextInterestEntries[#nextInterestEntries + 1] = {
				chunkKey = chunkKey,
				distanceSquared = offsetX * offsetX + offsetY * offsetY,
			}
		end
	end

	table.sort(nextInterestEntries, function(left, right)
		if left.distanceSquared ~= right.distanceSquared then
			return left.distanceSquared < right.distanceSquared
		end
		return left.chunkKey < right.chunkKey
	end)

	for _, entry in nextInterestEntries do
		local chunkKey = entry.chunkKey
		if previousInterest[chunkKey] then
			continue
		end
		self:AdjustChunkDemand(chunkKey, 1)
		self:SetPlayerChunkInterest(player, runtime, chunkKey, true)
	end

	for chunkKey in previousInterest do
		if nextInterest[chunkKey] then
			continue
		end
		self:AdjustChunkDemand(chunkKey, -1)
		self:SetPlayerChunkInterest(player, runtime, chunkKey, false)
	end

	runtime.lastChunkX = centerChunkX
	runtime.lastChunkY = centerChunkY
	runtime.forceRefresh = false
	self._playerInterestChangedSignal:Fire(
		self:BuildPlayerInterestChangedEvent(player, runtime, focusPosition, centerChunkX, centerChunkY)
	)
	self:PulseStatsChanged()
end

function WorldGeneration.UpdateTrackedPlayers(self: WorldGeneration, deltaTime: number)
	for player, runtime in self.playerRuntimes do
		runtime.refreshAccumulator += deltaTime
		if runtime.forceRefresh or runtime.refreshAccumulator >= self.playerRefreshInterval then
			runtime.refreshAccumulator = 0
			self:RefreshPlayerInterest(player, runtime)
		end
	end
end

function WorldGeneration.AcquirePart(self: WorldGeneration): BasePart
	local cache = self.cache
	if cache == nil then
		return createPartTemplate()
	end
	return cache:AcquirePart()
end

function WorldGeneration.ReleasePart(self: WorldGeneration, part: BasePart)
	local cache = self.cache
	if cache == nil then
		part:Destroy()
		return
	end
	cache:ReleasePart(part)
end

function WorldGeneration.ComputeTileCenterPosition(
	self: WorldGeneration,
	tileCenterX: number,
	tileCenterY: number,
	planeOffsetX: number
): Vector3
	return Vector3.new(
		self.worldOrigin.X + self.basePlaneX + planeOffsetX,
		self.worldOrigin.Y + tileCenterY * self.tileSize,
		self.worldOrigin.Z + tileCenterX * self.tileSize
	)
end

function WorldGeneration.StyleTerrainPart(self: WorldGeneration, part: BasePart, tileId: number)
	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	part.Name = createRuntimeInstanceName()
	part.Color = style.color
	part.Material = style.material
	part.Transparency = style.transparency
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	applyTileStudSurfaces(part)
	assignCreatedTileMaterial(part, tileId)
end

function WorldGeneration.GetTerrainTileTemplate(self: WorldGeneration, tileId: number): Instance?
	local templatesByTileId = self.tileTemplatesByTileId
	if templatesByTileId == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	local template = templatesByTileId[tileId]
	if template == nil then
		error(MISSING_ASSET_ERROR, 0)
	end
	return template
end

function WorldGeneration.PlaceTerrainTileTemplate(
	self: WorldGeneration,
	tileTemplate: Instance,
	parent: Instance,
	position: Vector3,
	tileId: number
): boolean
	local cloned = cloneTileTemplate(tileTemplate)
	if cloned == nil then
		error(MISSING_ASSET_ERROR, 0)
	end

	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	cloned.Name = style.name
	local rotationFix = if shouldApplyGrassRotationFix(self, tileId)
		then GRASS_TEMPLATE_X_ROTATION_FIX
		else CFrame.identity
	local placementCFrame = CFrame.new(position) * rotationFix
	if cloned:IsA("Model") then
		cloned:PivotTo(placementCFrame)
		for _, descendant in cloned:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = true
				descendant.CanQuery = true
				descendant.CanTouch = false
				descendant.Color = style.color
				descendant.Material = style.material
				descendant.Transparency = style.transparency
				descendant.CastShadow = false
				applyTileStudSurfaces(descendant)
				assignCreatedTileMaterial(descendant, tileId)
			end
		end
	elseif cloned:IsA("BasePart") then
		cloned.CFrame = placementCFrame
		cloned.Anchored = true
		cloned.CanCollide = true
		cloned.CanQuery = true
		cloned.CanTouch = false
		cloned.Color = style.color
		cloned.Material = style.material
		cloned.Transparency = style.transparency
		cloned.CastShadow = false
		applyTileStudSurfaces(cloned)
		assignCreatedTileMaterial(cloned, tileId)
	end

	cloned.Parent = parent
	return true
end

function WorldGeneration.PlaceBackgroundTileTemplate(
	self: WorldGeneration,
	tileTemplate: Instance,
	parent: Instance,
	position: Vector3,
	tileId: number,
	layerIndex: number,
	_totalLayers: number
): boolean
	local cloned = cloneTileTemplate(tileTemplate)
	if cloned == nil then
		error(MISSING_ASSET_ERROR, 0)
	end

	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	local rotationFix = if shouldApplyGrassRotationFix(self, tileId)
		then GRASS_TEMPLATE_X_ROTATION_FIX
		else CFrame.identity
	local placementCFrame = CFrame.new(position) * rotationFix

	cloned.Name = `{style.name}Background_{layerIndex}`
	if cloned:IsA("Model") then
		cloned:PivotTo(placementCFrame)
		for _, descendant in cloned:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.CastShadow = false
				descendant.Color = style.color
				descendant.Material = style.material
				descendant.Transparency = 0
				applyTileStudSurfaces(descendant)
				assignCreatedTileMaterial(descendant, tileId)
			end
		end
	elseif cloned:IsA("BasePart") then
		cloned.CFrame = placementCFrame
		cloned.Anchored = true
		cloned.CanCollide = false
		cloned.CanQuery = false
		cloned.CanTouch = false
		cloned.CastShadow = false
		cloned.Color = style.color
		cloned.Material = style.material
		cloned.Transparency = 0
		applyTileStudSurfaces(cloned)
		assignCreatedTileMaterial(cloned, tileId)
	end

	cloned.Parent = parent
	return true
end

function WorldGeneration.PlaceTreeTemplate(
	_self: WorldGeneration,
	treeTemplate: Instance,
	parent: Instance,
	position: Vector3
): boolean
	local cloned = cloneTileTemplate(treeTemplate)
	if cloned == nil then
		error(MISSING_ASSET_ERROR, 0)
	end

	local placementCFrame = CFrame.new(position)
	if cloned:IsA("Model") then
		cloned:PivotTo(placementCFrame)
		local boundsCFrame, boundsSize = cloned:GetBoundingBox()
		local boundsBottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
		local bottomAlignmentOffsetY = position.Y - boundsBottomY
		if math.abs(bottomAlignmentOffsetY) > 0.0001 then
			cloned:PivotTo(cloned:GetPivot() + Vector3.new(0, bottomAlignmentOffsetY, 0))
		end
		for _, descendant in cloned:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
	elseif cloned:IsA("BasePart") then
		cloned.CFrame = placementCFrame + Vector3.new(0, cloned.Size.Y * 0.5, 0)
		cloned.Anchored = true
		cloned.CanCollide = false
		cloned.CanQuery = false
		cloned.CanTouch = false
	end

	cloned.Parent = parent
	return true
end

function WorldGeneration.StyleBackgroundPart(
	self: WorldGeneration,
	part: BasePart,
	tileId: number,
	_layerIndex: number?,
	_totalLayers: number?
)
	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	part.Name = createRuntimeInstanceName()
	part.Color = style.color
	part.Material = style.material
	part.Transparency = 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	applyTileStudSurfaces(part)
	assignCreatedTileMaterial(part, tileId)
end

function WorldGeneration.SampleSharedBackgroundDensity(self: WorldGeneration, tileX: number, tileY: number): number
	local warpedX = tileX * 0.82 + 37.4
	local warpedY = tileY * 0.71 - 52.8
	local primaryNoise = sampleBackgroundOctaveNoise(
		self.seed + 941,
		warpedX,
		warpedY,
		0.017,
		3,
		2.04,
		0.53,
		BG_PRIMARY_OFFSET_X,
		BG_PRIMARY_OFFSET_Y
	)
	local secondaryNoise = sampleBackgroundOctaveNoise(
		self.seed - 317,
		warpedX,
		warpedY,
		0.039,
		2,
		2,
		0.5,
		BG_SECONDARY_OFFSET_X,
		BG_SECONDARY_OFFSET_Y
	)
	return primaryNoise * 0.74 + secondaryNoise * 0.26
end

function WorldGeneration.ShouldFillBackgroundLayer(
	self: WorldGeneration,
	layerIndex: number,
	sharedDensity: number,
	tileX: number,
	tileY: number,
	depthLayer: DepthLayer,
	depthBelowSurface: number
): boolean
	if depthLayer == "Sky" then
		return false
	end
	if depthLayer == "Surface" then
		return true
	end

	local layerAlpha = if self.backgroundLayerCount > 1 then (layerIndex - 1) / (self.backgroundLayerCount - 1) else 0

	local warpedX = tileX * (0.73 + layerAlpha * 0.24) + layerIndex * 19.7
	local warpedY = tileY * (0.67 + layerAlpha * 0.19) - layerIndex * 13.1
	local layerZ = layerIndex * 9.73 + depthBelowSurface * 0.31
	local detailNoise = sampleBackgroundOctaveNoise3D(
		self.seed + 719 + layerIndex * 173,
		warpedX,
		warpedY,
		layerZ,
		0.024 + layerAlpha * 0.017,
		3,
		2.08,
		0.51,
		BG_PRIMARY_OFFSET_X + layerIndex * 61.4,
		BG_SECONDARY_OFFSET_Y + layerIndex * 44.2
	)
	local pocketNoise = sampleBackgroundOctaveNoise3D(
		self.seed - 421 - layerIndex * 211,
		warpedX,
		warpedY,
		layerZ + 17.2,
		0.052 + layerAlpha * 0.021,
		2,
		2,
		0.5,
		BG_SECONDARY_OFFSET_X + layerIndex * 73.6,
		BG_PRIMARY_OFFSET_Y - layerIndex * 39.3
	)
	local crackFrequency = 0.048 + layerAlpha * 0.018
	local crackNoise = math.abs(
		math.noise(
			(tileX + BG_CRACK_OFFSET_X + layerIndex * 83.5) * crackFrequency,
			(tileY + BG_CRACK_OFFSET_Y - layerIndex * 57.8) * crackFrequency,
			(layerZ + self.seed + layerIndex * 307) * BG_SEED_Y_MULTIPLIER
		)
	)

	local density = sharedDensity * 0.42 + detailNoise * 0.43 + pocketNoise * 0.15
	local carveThreshold = 0.72
	if depthLayer == "Underground" then
		carveThreshold = 0.72
	elseif depthLayer == "Cavern" then
		carveThreshold = 0.6
	elseif depthLayer == "Deep" then
		carveThreshold = 0.57
	end
	carveThreshold += layerAlpha * 0.04
	if layerIndex % 2 == 0 then
		carveThreshold -= 0.012
	end

	local shouldCarve = density > carveThreshold
	local crackCutoff = 0.038
	if depthLayer == "Cavern" then
		crackCutoff = 0.058
	elseif depthLayer == "Deep" then
		crackCutoff = 0.053
	end
	if layerIndex % 2 == 1 then
		crackCutoff += 0.004
	end
	if crackNoise < crackCutoff then
		shouldCarve = true
	end

	return not shouldCarve
end

function WorldGeneration.GetBackgroundTileIdForLayer(
	self: WorldGeneration,
	layerIndex: number,
	column: ColumnProfile,
	sharedDensity: number,
	tileX: number,
	tileY: number,
	depthLayer: DepthLayer,
	depthBelowSurface: number
): number
	if depthBelowSurface < 0 then
		return self.tileId.AIR
	end

	local soilDepthLimit = math.max(2, math.min(column.stoneStartDepth - 1, 6))
	if depthBelowSurface <= soilDepthLimit then
		return self.biomeGenerator:GetTileForDepth(column, depthBelowSurface)
	end

	if not self:ShouldFillBackgroundLayer(layerIndex, sharedDensity, tileX, tileY, depthLayer, depthBelowSurface) then
		return self.tileId.AIR
	end

	local backgroundDepth = depthBelowSurface + math.max(0, layerIndex - 1)
	if depthLayer == "Deep" then
		backgroundDepth += 1
	end
	backgroundDepth = math.max(soilDepthLimit + 1, backgroundDepth)
	return self.biomeGenerator:GetTileForDepth(column, backgroundDepth)
end

function WorldGeneration.GetForegroundTileAt(
	self: WorldGeneration,
	column: ColumnProfile,
	worldTileX: number,
	worldTileY: number
): (number, DepthLayer, number)
	local depthLayer, depthBelowSurface = self.caveGenerator:GetDepthLayer(column.surfaceY, worldTileY)

	local tileId = self.tileId.AIR
	if depthBelowSurface >= 0 then
		local baseTileId = self.biomeGenerator:GetTileForDepth(column, depthBelowSurface)
		local isBedrock = worldTileY <= self.minTileY + self.bedrockThickness
		if isBedrock then
			tileId = self.tileId.STONE
		else
			local shouldCarve =
				self.caveGenerator:ShouldCarve(worldTileX, worldTileY, column.biomeId, depthLayer, depthBelowSurface)
			if shouldCarve then
				tileId = self.tileId.AIR
			else
				tileId = self.structuresGenerator:GetOreTile(
					baseTileId,
					worldTileX,
					worldTileY,
					depthLayer,
					depthBelowSurface
				)
			end
		end
	end

	return tileId, depthLayer, depthBelowSurface
end

function WorldGeneration.IsTreeAnchorTile(self: WorldGeneration, worldTileX: number): boolean
	local treeCell = math.floor(worldTileX / TREE_SPACING_TILES)
	local slotAlpha = math.clamp(
		(math.noise((treeCell + 0.5) * TREE_SLOT_NOISE_FREQUENCY, self.seed * BG_SEED_Y_MULTIPLIER, 73.4) + 1) * 0.5,
		0,
		1
	)
	local slot = math.clamp(math.floor(slotAlpha * TREE_SPACING_TILES), 0, TREE_SPACING_TILES - 1)
	return worldTileX == treeCell * TREE_SPACING_TILES + slot
end

function WorldGeneration.IsSurfaceAnchorTile(
	self: WorldGeneration,
	worldTileX: number,
	spacingTiles: number,
	slotNoiseFrequency: number,
	salt: number
): boolean
	local spacing = math.max(2, spacingTiles)
	local anchorCell = math.floor(worldTileX / spacing)
	local slotAlpha = math.clamp(
		(
			math.noise(
				(anchorCell + salt * 0.37) * slotNoiseFrequency,
				self.seed * BG_SEED_Y_MULTIPLIER + salt * 0.11,
				51.8 + salt * 0.07
			) + 1
		) * 0.5,
		0,
		1
	)
	local slot = math.clamp(math.floor(slotAlpha * spacing), 0, spacing - 1)
	return worldTileX == anchorCell * spacing + slot
end

function WorldGeneration.GetTreeTemplateIndex(
	self: WorldGeneration,
	worldTileX: number,
	surfaceTileY: number,
	biomeType: number,
	biomeId: number
): number?
	if not self:IsTreeAnchorTile(worldTileX) then
		return nil
	end

	local matchingSpecificVariants: { number } = {}
	local matchingGeneralVariants: { number } = {}
	for variantIndex, variantConfig in self.treeVariantConfigs do
		local configuredBiomeType = variantConfig.biomeType
		if configuredBiomeType ~= nil and configuredBiomeType ~= biomeType then
			continue
		end
		local configuredBiomeId = variantConfig.biomeId
		if configuredBiomeId ~= nil then
			if configuredBiomeId == biomeId then
				matchingSpecificVariants[#matchingSpecificVariants + 1] = variantIndex
			end
		else
			matchingGeneralVariants[#matchingGeneralVariants + 1] = variantIndex
		end
	end

	local matchingVariants = if #matchingSpecificVariants > 0 then matchingSpecificVariants else matchingGeneralVariants
	if #matchingVariants <= 0 then
		for variantIndex = 1, #self.treeVariantConfigs do
			matchingVariants[#matchingVariants + 1] = variantIndex
		end
	end
	if #matchingVariants <= 0 then
		return nil
	end

	local variantAlpha = math.clamp(
		(
			math.noise(
				(worldTileX + 179.3) * TREE_VARIANT_NOISE_FREQUENCY_X,
				(surfaceTileY - 61.7) * TREE_VARIANT_NOISE_FREQUENCY_Y,
				self.seed * BG_SEED_X_MULTIPLIER
			) + 1
		) * 0.5,
		0,
		1
	)
	local variantSlot = getTreeVariantIndexByAlpha(#matchingVariants, variantAlpha)
	return matchingVariants[variantSlot]
end

function WorldGeneration.HasTreeAirClearance(
	self: WorldGeneration,
	column: ColumnProfile,
	worldTileX: number,
	surfaceTileY: number
): boolean
	return self:HasAirClearance(column, worldTileX, surfaceTileY, TREE_REQUIRED_AIR_CLEARANCE)
end

function WorldGeneration.HasAirClearance(
	self: WorldGeneration,
	column: ColumnProfile,
	worldTileX: number,
	surfaceTileY: number,
	requiredAirTiles: number
): boolean
	for offset = 1, math.max(1, requiredAirTiles) do
		local scanTileY = surfaceTileY + offset
		if scanTileY > self.maxTileY then
			continue
		end

		local scanTileId = self:GetForegroundTileAt(column, worldTileX, scanTileY)
		if scanTileId ~= self.tileId.AIR then
			return false
		end
	end

	return true
end

function WorldGeneration.IsWithinBiomeTransitionBuffer(
	_self: WorldGeneration,
	getColumnProfile: (worldTileX: number) -> ColumnProfile,
	worldTileX: number,
	expectedBiomeId: number,
	expectedBiomeType: number,
	bufferTiles: number
): boolean
	for offset = -math.max(0, bufferTiles), math.max(0, bufferTiles), 2 do
		local column = getColumnProfile(worldTileX + offset)
		if column.biomeId ~= expectedBiomeId or column.biomeType ~= expectedBiomeType then
			return false
		end
	end

	return true
end

function WorldGeneration.GetDesertPropVariantIndex(
	self: WorldGeneration,
	worldTileX: number,
	surfaceTileY: number,
	variantCount: number
): number
	local count = math.max(1, variantCount)
	local variantAlpha = math.clamp(
		(
			math.noise(
				(worldTileX + 97.3) * DESERT_PROP_VARIANT_NOISE_FREQUENCY_X,
				(surfaceTileY - 41.9) * DESERT_PROP_VARIANT_NOISE_FREQUENCY_Y,
				self.seed * BG_SEED_X_MULTIPLIER
			) + 1
		) * 0.5,
		0,
		1
	)
	return math.clamp(math.floor(variantAlpha * count) + 1, 1, count)
end

function WorldGeneration.GenerateChunkData(self: WorldGeneration, chunkX: number, chunkY: number): ChunkData
	local width = self.chunkSize
	local height = self.chunkSize
	local tileMinX = chunkX * width
	local tileMinY = chunkY * height
	local tiles = Sift.Array.create(width * height, self.tileId.AIR)
	local walls = Sift.Array.create(width * height, self.wallId.NONE)
	local depthLayers = Sift.Array.create(width * height, DEPTH_LAYER_CODE.SKY)
	local depthBelowSurface = Sift.Array.create(width * height, -1)
	local biomeIds = Sift.Array.create(width * height, self.biomeId.FOREST)
	local surfaceBiomeIds = Sift.Array.create(width, self.biomeId.FOREST)
	local biomeTypes = Sift.Array.create(width * height, self.biomeType.NORMAL)
	local backgroundPadding = BACKGROUND_LAYER_BOUNDS_PADDING_TILES
	local backgroundWidth = width + backgroundPadding * 2
	local backgroundHeight = height + backgroundPadding * 2
	local backgroundTileMinX = tileMinX - backgroundPadding
	local backgroundTileMinY = tileMinY - backgroundPadding
	local backgroundLayers: { BackgroundLayerData } = Sift.Array.create(self.backgroundLayerCount)
	for layerIndex = 1, self.backgroundLayerCount do
		backgroundLayers[layerIndex] = {
			layerIndex = layerIndex,
			tileMinX = backgroundTileMinX,
			tileMinY = backgroundTileMinY,
			width = backgroundWidth,
			height = backgroundHeight,
			tiles = Sift.Array.create(backgroundWidth * backgroundHeight, self.tileId.AIR),
		}
	end
	local backgroundColumnProfiles: { ColumnProfile } = Sift.Array.create(backgroundWidth)
	local backgroundDepthColumnProfiles: { { ColumnProfile } } = Sift.Array.create(self.backgroundLayerCount)
	local columnProfiles: { ColumnProfile } = Sift.Array.create(width)
	local biomeBlendColumnCache = {} :: { [number]: ColumnProfile }
	local biomeBlendAxisCache = {} :: { [number]: BiomeBlendAxisData }
	local biomeBlendClusterCache = {} :: { [string]: ColumnProfile }
	local backgroundBiomeBlendColumnCaches: { { [number]: ColumnProfile } } =
		Sift.Array.create(self.backgroundLayerCount)
	local backgroundBiomeBlendAxisCaches: { { [number]: BiomeBlendAxisData } } =
		Sift.Array.create(self.backgroundLayerCount)
	local backgroundBiomeBlendClusterCaches: { { [string]: ColumnProfile } } =
		Sift.Array.create(self.backgroundLayerCount)

	for layerIndex = 1, self.backgroundLayerCount do
		backgroundDepthColumnProfiles[layerIndex] = Sift.Array.create(backgroundWidth)
		backgroundBiomeBlendColumnCaches[layerIndex] = {}
		backgroundBiomeBlendAxisCaches[layerIndex] = {}
		backgroundBiomeBlendClusterCaches[layerIndex] = {}
	end

	local function getColumnProfileForBlend(worldTileX: number): ColumnProfile
		local cached = biomeBlendColumnCache[worldTileX]
		if cached ~= nil then
			return cached
		end

		local sampled = self.biomeGenerator:GetColumnProfile(worldTileX)
		biomeBlendColumnCache[worldTileX] = sampled
		return sampled
	end

	local function getBiomeBlendAxisData(clusterX: number): BiomeBlendAxisData
		local cached = biomeBlendAxisCache[clusterX]
		if cached ~= nil then
			return cached
		end

		local clusterSampleX = clusterX * BIOME_BLEND_CLUSTER_SIZE_TILES
		local primaryColumn = getColumnProfileForBlend(clusterSampleX)
		local secondaryColumn: ColumnProfile? = nil
		local edgeDistance = BIOME_BLEND_EDGE_SCAN_TILES + 1

		for offset = 1, BIOME_BLEND_EDGE_SCAN_TILES do
			local leftColumn = getColumnProfileForBlend(clusterSampleX - offset)
			local hasLeftNeighbor = not columnsShareBiomeSignature(leftColumn, primaryColumn)
			local rightColumn = getColumnProfileForBlend(clusterSampleX + offset)
			local hasRightNeighbor = not columnsShareBiomeSignature(rightColumn, primaryColumn)

			if not hasLeftNeighbor and not hasRightNeighbor then
				continue
			end

			edgeDistance = offset
			if hasLeftNeighbor and hasRightNeighbor then
				local tieAlpha = deterministicUnitInterval(self.seed, clusterX, 0, offset, BIOME_BLEND_TIE_BREAK_SALT)
				secondaryColumn = if tieAlpha < 0.5 then leftColumn else rightColumn
			elseif hasLeftNeighbor then
				secondaryColumn = leftColumn
			else
				secondaryColumn = rightColumn
			end
			break
		end

		local axisData = {
			primaryColumn = primaryColumn,
			secondaryColumn = secondaryColumn,
			edgeDistance = edgeDistance,
		}
		biomeBlendAxisCache[clusterX] = axisData
		return axisData
	end

	local function getClusterBlendedColumn(
		worldTileX: number,
		worldTileY: number,
		blendDepthBelowSurface: number,
		baseColumn: ColumnProfile
	): ColumnProfile
		if blendDepthBelowSurface < 0 then
			return baseColumn
		end

		local clusterX = math.floor(worldTileX / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterY = math.floor(worldTileY / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterZ = math.floor(blendDepthBelowSurface / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterKey = `{clusterX}:{clusterY}:{clusterZ}`
		local cached = biomeBlendClusterCache[clusterKey]
		if cached ~= nil then
			return copyColumnWithSurfaceY(cached, baseColumn.surfaceY)
		end

		local axisData = getBiomeBlendAxisData(clusterX)
		local selectedColumn = axisData.primaryColumn
		local secondaryColumn = axisData.secondaryColumn

		if secondaryColumn ~= nil and axisData.edgeDistance <= BIOME_BLEND_TRANSITION_WIDTH_TILES then
			local distanceSpan = math.max(1, BIOME_BLEND_TRANSITION_WIDTH_TILES - 1)
			local distanceAlpha = 1 - math.clamp((axisData.edgeDistance - 1) / distanceSpan, 0, 1)
			local edgeNoise = math.noise(
				(clusterX + BIOME_BLEND_NOISE_OFFSET_X) * BIOME_BLEND_NOISE_FREQUENCY,
				(clusterY + BIOME_BLEND_NOISE_OFFSET_Y) * BIOME_BLEND_NOISE_FREQUENCY,
				(clusterZ + BIOME_BLEND_NOISE_OFFSET_Z + self.seed * BG_SEED_X_MULTIPLIER) * BIOME_BLEND_NOISE_FREQUENCY
			)
			local noiseAlpha = (edgeNoise + 1) * 0.5
			local blendFactor =
				math.clamp(distanceAlpha * (1 - BIOME_BLEND_NOISE_WEIGHT) + noiseAlpha * BIOME_BLEND_NOISE_WEIGHT, 0, 1)
			local secondaryChance = BIOME_BLEND_MIN_SECONDARY_CHANCE
				+ (BIOME_BLEND_MAX_SECONDARY_CHANCE - BIOME_BLEND_MIN_SECONDARY_CHANCE) * blendFactor
			local roll =
				deterministicUnitInterval(self.seed, clusterX, clusterY, clusterZ, BIOME_BLEND_CLUSTER_ROLL_SALT)
			if roll < secondaryChance then
				selectedColumn = secondaryColumn
			end
		end

		biomeBlendClusterCache[clusterKey] = selectedColumn
		return copyColumnWithSurfaceY(selectedColumn, baseColumn.surfaceY)
	end

	local function getBlendedColumnForTile(
		worldTileX: number,
		worldTileY: number,
		baseColumn: ColumnProfile
	): ColumnProfile
		local _, blendDepthBelowSurface = self.caveGenerator:GetDepthLayer(baseColumn.surfaceY, worldTileY)
		return getClusterBlendedColumn(worldTileX, worldTileY, blendDepthBelowSurface, baseColumn)
	end

	local function getBackgroundColumnProfileForBlend(layerIndex: number, worldTileX: number): ColumnProfile
		local layerCache = backgroundBiomeBlendColumnCaches[layerIndex]
		local cached = layerCache[worldTileX]
		if cached ~= nil then
			return cached
		end

		local baseColumn = getColumnProfileForBlend(worldTileX)
		local sampled = self.biomeGenerator:GetDepthColumnProfile(worldTileX, layerIndex, baseColumn)
		layerCache[worldTileX] = sampled
		return sampled
	end

	local function getBackgroundBiomeBlendAxisData(layerIndex: number, clusterX: number): BiomeBlendAxisData
		local layerAxisCache = backgroundBiomeBlendAxisCaches[layerIndex]
		local cached = layerAxisCache[clusterX]
		if cached ~= nil then
			return cached
		end

		local clusterSampleX = clusterX * BIOME_BLEND_CLUSTER_SIZE_TILES
		local primaryColumn = getBackgroundColumnProfileForBlend(layerIndex, clusterSampleX)
		local secondaryColumn: ColumnProfile? = nil
		local edgeDistance = BIOME_BLEND_EDGE_SCAN_TILES + 1

		for offset = 1, BIOME_BLEND_EDGE_SCAN_TILES do
			local leftColumn = getBackgroundColumnProfileForBlend(layerIndex, clusterSampleX - offset)
			local hasLeftNeighbor = not columnsShareBiomeSignature(leftColumn, primaryColumn)
			local rightColumn = getBackgroundColumnProfileForBlend(layerIndex, clusterSampleX + offset)
			local hasRightNeighbor = not columnsShareBiomeSignature(rightColumn, primaryColumn)

			if not hasLeftNeighbor and not hasRightNeighbor then
				continue
			end

			edgeDistance = offset
			if hasLeftNeighbor and hasRightNeighbor then
				local tieAlpha =
					deterministicUnitInterval(self.seed, clusterX, layerIndex, offset, BIOME_BLEND_TIE_BREAK_SALT)
				secondaryColumn = if tieAlpha < 0.5 then leftColumn else rightColumn
			elseif hasLeftNeighbor then
				secondaryColumn = leftColumn
			else
				secondaryColumn = rightColumn
			end
			break
		end

		local axisData = {
			primaryColumn = primaryColumn,
			secondaryColumn = secondaryColumn,
			edgeDistance = edgeDistance,
		}
		layerAxisCache[clusterX] = axisData
		return axisData
	end

	local function getBackgroundClusterBlendedColumn(
		layerIndex: number,
		worldTileX: number,
		worldTileY: number,
		backgroundDepthBelowSurface: number,
		baseColumn: ColumnProfile
	): ColumnProfile
		if backgroundDepthBelowSurface < 0 then
			return baseColumn
		end

		local clusterX = math.floor(worldTileX / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterY = math.floor(worldTileY / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterZ = math.floor(backgroundDepthBelowSurface / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterKey = `{clusterX}:{clusterY}:{clusterZ}`
		local layerClusterCache = backgroundBiomeBlendClusterCaches[layerIndex]
		local cached = layerClusterCache[clusterKey]
		if cached ~= nil then
			return copyColumnWithSurfaceY(cached, baseColumn.surfaceY)
		end

		local axisData = getBackgroundBiomeBlendAxisData(layerIndex, clusterX)
		local selectedColumn = axisData.primaryColumn
		local secondaryColumn = axisData.secondaryColumn

		if secondaryColumn ~= nil and axisData.edgeDistance <= BIOME_BLEND_TRANSITION_WIDTH_TILES then
			local distanceSpan = math.max(1, BIOME_BLEND_TRANSITION_WIDTH_TILES - 1)
			local distanceAlpha = 1 - math.clamp((axisData.edgeDistance - 1) / distanceSpan, 0, 1)
			local edgeNoise = math.noise(
				(clusterX + BIOME_BLEND_NOISE_OFFSET_X) * BIOME_BLEND_NOISE_FREQUENCY,
				(clusterY + BIOME_BLEND_NOISE_OFFSET_Y) * BIOME_BLEND_NOISE_FREQUENCY,
				(clusterZ + layerIndex * 5.37 + BIOME_BLEND_NOISE_OFFSET_Z + self.seed * BG_SEED_X_MULTIPLIER)
					* BIOME_BLEND_NOISE_FREQUENCY
			)
			local noiseAlpha = (edgeNoise + 1) * 0.5
			local blendFactor =
				math.clamp(distanceAlpha * (1 - BIOME_BLEND_NOISE_WEIGHT) + noiseAlpha * BIOME_BLEND_NOISE_WEIGHT, 0, 1)
			local secondaryChance = BIOME_BLEND_MIN_SECONDARY_CHANCE
				+ (BIOME_BLEND_MAX_SECONDARY_CHANCE - BIOME_BLEND_MIN_SECONDARY_CHANCE) * blendFactor
			local roll = deterministicUnitInterval(
				self.seed,
				clusterX,
				clusterY,
				clusterZ + layerIndex * 37,
				BIOME_BLEND_CLUSTER_ROLL_SALT
			)
			if roll < secondaryChance then
				selectedColumn = secondaryColumn
			end
		end

		layerClusterCache[clusterKey] = selectedColumn
		return copyColumnWithSurfaceY(selectedColumn, baseColumn.surfaceY)
	end

	local function getBackgroundBlendedColumnForTile(
		layerIndex: number,
		worldTileX: number,
		worldTileY: number,
		baseColumn: ColumnProfile
	): ColumnProfile
		local _, blendDepthBelowSurface = self.caveGenerator:GetDepthLayer(baseColumn.surfaceY, worldTileY)
		return getBackgroundClusterBlendedColumn(layerIndex, worldTileX, worldTileY, blendDepthBelowSurface, baseColumn)
	end

	for localX = 0, backgroundWidth - 1 do
		local worldTileX = backgroundTileMinX + localX
		local column = self.biomeGenerator:GetColumnProfile(worldTileX)
		backgroundColumnProfiles[localX + 1] = column
		biomeBlendColumnCache[worldTileX] = column

		for layerIndex = 1, self.backgroundLayerCount do
			local backgroundColumn = self.biomeGenerator:GetDepthColumnProfile(worldTileX, layerIndex, column)
			backgroundDepthColumnProfiles[layerIndex][localX + 1] = backgroundColumn
			backgroundBiomeBlendColumnCaches[layerIndex][worldTileX] = backgroundColumn
		end
	end

	for localX = 0, width - 1 do
		local column = backgroundColumnProfiles[localX + backgroundPadding + 1]
		columnProfiles[localX + 1] = column
		surfaceBiomeIds[localX + 1] = column.biomeId
	end

	for localY = 0, height - 1 do
		local worldTileY = tileMinY + localY
		for localX = 0, width - 1 do
			local worldTileX = tileMinX + localX
			local index = computeTileIndex(localX, localY, width)
			local baseColumn = columnProfiles[localX + 1]
			if worldTileY < self.minTileY or worldTileY > self.maxTileY then
				biomeIds[index] = baseColumn.biomeId
				biomeTypes[index] = baseColumn.biomeType
				tiles[index] = self.tileId.AIR
				depthLayers[index] = DEPTH_LAYER_CODE.SKY
				depthBelowSurface[index] = -1
				continue
			end

			local column = getBlendedColumnForTile(worldTileX, worldTileY, baseColumn)
			biomeIds[index] = column.biomeId
			biomeTypes[index] = column.biomeType
			local tileId, depthLayer, tileDepthBelowSurface = self:GetForegroundTileAt(column, worldTileX, worldTileY)
			tiles[index] = tileId
			depthLayers[index] = encodeDepthLayer(depthLayer)
			depthBelowSurface[index] = tileDepthBelowSurface
		end

		if localY > 0 and localY % self.generationRowsPerYield == 0 then
			task.wait()
		end
	end

	carveCorruptionChasmsForChunk(
		self,
		chunkX,
		chunkY,
		tileMinX,
		tileMinY,
		width,
		height,
		tiles,
		biomeTypes,
		columnProfiles
	)

	local structureGenerationResult: StructureGenerationResult = self.structuresGenerator:GenerateChunkStructures({
		chunkX = chunkX,
		chunkY = chunkY,
		tileMinX = tileMinX,
		tileMinY = tileMinY,
		width = width,
		height = height,
		getColumnProfile = getColumnProfileForBlend,
		computeTileIndex = computeTileIndex,
	})
	for tileIndex, overrideTileId in structureGenerationResult.tileOverrides do
		tiles[tileIndex] = overrideTileId
	end

	self:ApplyExposedSurfaceCaps(
		tiles,
		biomeIds,
		biomeTypes,
		tileMinX,
		tileMinY,
		width,
		height,
		function(worldTileX: number, worldTileY: number): number
			if worldTileY < self.minTileY or worldTileY > self.maxTileY then
				return self.tileId.AIR
			end

			local baseColumn = getColumnProfileForBlend(worldTileX)
			local column = getBlendedColumnForTile(worldTileX, worldTileY, baseColumn)
			return select(1, self:GetForegroundTileAt(column, worldTileX, worldTileY))
		end
	)

	for localY = 0, height - 1 do
		for localX = 0, width - 1 do
			local index = computeTileIndex(localX, localY, width)
			walls[index] = self.caveGenerator:GetWall(
				tiles[index],
				biomeIds[index],
				decodeDepthLayer(depthLayers[index]),
				depthBelowSurface[index]
			)
		end

		if localY > 0 and localY % self.generationRowsPerYield == 0 then
			task.wait()
		end
	end

	for localY = 0, backgroundHeight - 1 do
		local worldTileY = backgroundTileMinY + localY
		if worldTileY < self.minTileY or worldTileY > self.maxTileY then
			continue
		end

		for localX = 0, backgroundWidth - 1 do
			local worldTileX = backgroundTileMinX + localX
			local backgroundIndex = computeTileIndex(localX, localY, backgroundWidth)
			local sharedBackgroundDensity = self:SampleSharedBackgroundDensity(worldTileX, worldTileY)
			for layerIndex = 1, self.backgroundLayerCount do
				local baseColumn = backgroundDepthColumnProfiles[layerIndex][localX + 1]
				local column = getBackgroundBlendedColumnForTile(layerIndex, worldTileX, worldTileY, baseColumn)
				local _, depthLayer, tileDepthBelowSurface = self:GetForegroundTileAt(column, worldTileX, worldTileY)
				if tileDepthBelowSurface < 0 then
					continue
				end

				local layerData = backgroundLayers[layerIndex]
				local backgroundTileId = self:GetBackgroundTileIdForLayer(
					layerIndex,
					column,
					sharedBackgroundDensity,
					worldTileX,
					worldTileY,
					depthLayer,
					tileDepthBelowSurface
				)
				if backgroundTileId ~= self.tileId.AIR then
					layerData.tiles[backgroundIndex] = backgroundTileId
				end
			end
		end

		if localY > 0 and localY % self.generationRowsPerYield == 0 then
			task.wait()
		end
	end

	local foregroundAnchorTiles = Sift.Array.create(backgroundWidth * backgroundHeight, self.tileId.AIR)
	for foregroundLocalY = 0, height - 1 do
		for foregroundLocalX = 0, width - 1 do
			local foregroundIndex = computeTileIndex(foregroundLocalX, foregroundLocalY, width)
			local foregroundTileId = tiles[foregroundIndex]
			if foregroundTileId == self.tileId.AIR then
				continue
			end

			local backgroundLocalX = foregroundLocalX + backgroundPadding
			local backgroundLocalY = foregroundLocalY + backgroundPadding
			local backgroundIndex = computeTileIndex(backgroundLocalX, backgroundLocalY, backgroundWidth)
			foregroundAnchorTiles[backgroundIndex] = foregroundTileId
		end
	end

	for layerIndex = 1, self.backgroundLayerCount do
		local previousTiles = if layerIndex == 1 then foregroundAnchorTiles else backgroundLayers[layerIndex - 1].tiles
		local currentTiles = backgroundLayers[layerIndex].tiles

		for localY = 0, backgroundHeight - 1 do
			local worldTileY = backgroundTileMinY + localY
			if worldTileY < self.minTileY or worldTileY > self.maxTileY then
				continue
			end

			for localX = 0, backgroundWidth - 1 do
				local index = computeTileIndex(localX, localY, backgroundWidth)
				local anchoredToPrevious =
					hasNonAirNeighborOrSelf(previousTiles, backgroundWidth, backgroundHeight, localX, localY)

				if not anchoredToPrevious then
					currentTiles[index] = self.tileId.AIR
					continue
				end

				if currentTiles[index] ~= self.tileId.AIR then
					continue
				end

				local worldTileX = backgroundTileMinX + localX
				local baseColumn = backgroundDepthColumnProfiles[layerIndex][localX + 1]
				local column = getBackgroundBlendedColumnForTile(layerIndex, worldTileX, worldTileY, baseColumn)
				local _, depthLayer, tileDepthBelowSurface = self:GetForegroundTileAt(column, worldTileX, worldTileY)
				if tileDepthBelowSurface < 0 then
					continue
				end
				if depthLayer == "Sky" then
					continue
				end

				local fillNoise = math.noise(
					(worldTileX + BG_LAYER_CONNECTION_OFFSET_X + layerIndex * 11.7) * 0.083,
					(worldTileY + BG_LAYER_CONNECTION_OFFSET_Y - layerIndex * 7.1) * 0.083,
					self.seed * BG_SEED_X_MULTIPLIER
				)
				if fillNoise < -0.1 then
					continue
				end

				local connectionDepth = math.max(0, tileDepthBelowSurface + layerIndex - 1)
				currentTiles[index] = self.biomeGenerator:GetTileForDepth(column, connectionDepth)
			end

			if localY > 0 and localY % self.generationRowsPerYield == 0 then
				task.wait()
			end
		end
	end

	local lastLayer = backgroundLayers[self.backgroundLayerCount]
	if lastLayer then
		local lastLayerTiles = lastLayer.tiles
		for localY = 0, backgroundHeight - 1 do
			local worldTileY = backgroundTileMinY + localY
			if worldTileY < self.minTileY or worldTileY > self.maxTileY then
				continue
			end

			for localX = 0, backgroundWidth - 1 do
				local index = computeTileIndex(localX, localY, backgroundWidth)
				if lastLayerTiles[index] ~= self.tileId.AIR then
					continue
				end

				local worldTileX = backgroundTileMinX + localX
				local baseColumn = backgroundDepthColumnProfiles[self.backgroundLayerCount][localX + 1]
				local column =
					getBackgroundBlendedColumnForTile(self.backgroundLayerCount, worldTileX, worldTileY, baseColumn)
				local _, _, tileDepthBelowSurface = self:GetForegroundTileAt(column, worldTileX, worldTileY)
				if tileDepthBelowSurface < 0 then
					continue
				end

				lastLayerTiles[index] =
					self.biomeGenerator:GetTileForDepth(column, tileDepthBelowSurface + self.backgroundLayerCount)
			end

			if localY > 0 and localY % self.generationRowsPerYield == 0 then
				task.wait()
			end
		end
	end

	local trees: { TreeSpawnData } = {}
	local props: { PropSpawnData } = {}
	local desertDecorationSettings = if typeof(self.desertConfig) == "table"
			and typeof((self.desertConfig :: any).Decoration) == "table"
		then (self.desertConfig :: any).Decoration :: { [string]: any }
		else {} :: any
	local snowDecorationSettings = if typeof(self.snowConfig) == "table"
			and typeof((self.snowConfig :: any).Decoration) == "table"
		then (self.snowConfig :: any).Decoration :: { [string]: any }
		else {} :: any
	local chunkTileMaxY = tileMinY + height - 1
	local function hasReservedSurfaceTileNear(worldTileX: number, radius: number): boolean
		for scanTileX = worldTileX - radius, worldTileX + radius do
			if structureGenerationResult.reservedSurfaceTiles[scanTileX] == true then
				return true
			end
		end
		return false
	end

	local function getValidationTileId(worldTileX: number, worldTileY: number, column: ColumnProfile): number
		local localValidationX = worldTileX - tileMinX
		local localValidationY = worldTileY - tileMinY
		if
			localValidationX >= 0
			and localValidationX < width
			and localValidationY >= 0
			and localValidationY < height
		then
			return tiles[computeTileIndex(localValidationX, localValidationY, width)]
		end

		local tileId = self:GetForegroundTileAt(column, worldTileX, worldTileY)
		return tileId
	end

	local function hasSurfaceSupportTile(worldTileX: number, surfaceTileY: number, column: ColumnProfile): boolean
		local supportTileY = surfaceTileY - 1
		if supportTileY < self.minTileY then
			return true
		end

		return getValidationTileId(worldTileX, supportTileY, column) ~= self.tileId.AIR
	end

	local function hasNearbyHigherPriorityTreeAnchor(worldTileX: number, surfaceTileY: number): boolean
		local currentPriority =
			deterministicUnitInterval(self.seed, worldTileX, surfaceTileY, 0, TREE_SPACING_PRIORITY_SALT)
		for offset = -TREE_MIN_VISUAL_SPACING_TILES, TREE_MIN_VISUAL_SPACING_TILES do
			if offset == 0 then
				continue
			end

			local scanTileX = worldTileX + offset
			if not self:IsTreeAnchorTile(scanTileX) then
				continue
			end

			local scanColumn = getColumnProfileForBlend(scanTileX)
			if math.abs(scanColumn.surfaceY - surfaceTileY) > TREE_MAX_FOOTPRINT_SURFACE_STEP_TILES then
				continue
			end

			local scanPriority =
				deterministicUnitInterval(self.seed, scanTileX, scanColumn.surfaceY, 0, TREE_SPACING_PRIORITY_SALT)
			if scanPriority < currentPriority then
				return true
			end
		end

		return false
	end

	local function isTreePlacementSupported(
		worldTileX: number,
		surfaceTileY: number,
		column: ColumnProfile,
		surfaceTileId: number
	): boolean
		if not isTreeSurfaceTile(self, surfaceTileId) then
			return false
		end
		if hasReservedSurfaceTileNear(worldTileX, TREE_FOOTPRINT_RADIUS_TILES) then
			return false
		end
		if not hasSurfaceSupportTile(worldTileX, surfaceTileY, column) then
			return false
		end
		if hasNearbyHigherPriorityTreeAnchor(worldTileX, surfaceTileY) then
			return false
		end

		local leftSurfaceY = surfaceTileY
		local rightSurfaceY = surfaceTileY
		for offset = -TREE_FOOTPRINT_RADIUS_TILES, TREE_FOOTPRINT_RADIUS_TILES do
			local scanTileX = worldTileX + offset
			local scanColumn = if offset == 0 then column else getColumnProfileForBlend(scanTileX)
			local step = math.abs(scanColumn.surfaceY - surfaceTileY)
			local maxAllowedStep = if math.abs(offset) <= 1
				then TREE_MAX_NEAR_SURFACE_STEP_TILES
				else TREE_MAX_FOOTPRINT_SURFACE_STEP_TILES
			if step > maxAllowedStep then
				return false
			end

			local scanSurfaceTileId = getValidationTileId(scanTileX, scanColumn.surfaceY, scanColumn)
			if scanSurfaceTileId == self.tileId.AIR then
				return false
			end
			if not hasSurfaceSupportTile(scanTileX, scanColumn.surfaceY, scanColumn) then
				return false
			end

			if offset == -1 then
				leftSurfaceY = scanColumn.surfaceY
			elseif offset == 1 then
				rightSurfaceY = scanColumn.surfaceY
			end
		end

		local isOneTileSpike = surfaceTileY > leftSurfaceY + TREE_MAX_NEAR_SURFACE_STEP_TILES
			and surfaceTileY > rightSurfaceY + TREE_MAX_NEAR_SURFACE_STEP_TILES
		local isSharpHole = surfaceTileY + TREE_MAX_NEAR_SURFACE_STEP_TILES < leftSurfaceY
			and surfaceTileY + TREE_MAX_NEAR_SURFACE_STEP_TILES < rightSurfaceY
		return not isOneTileSpike and not isSharpHole
	end

	for localX = 0, width - 1 do
		local worldTileX = tileMinX + localX
		local column = columnProfiles[localX + 1]
		local surfaceTileY = column.surfaceY
		if surfaceTileY < tileMinY or surfaceTileY > chunkTileMaxY then
			continue
		end
		if surfaceTileY < self.minTileY or surfaceTileY > self.maxTileY then
			continue
		end

		local localSurfaceY = surfaceTileY - tileMinY
		local surfaceIndex = computeTileIndex(localX, localSurfaceY, width)
		local surfaceTileId = tiles[surfaceIndex]
		if surfaceTileId == self.tileId.AIR then
			continue
		end
		if not hasSurfaceSupportTile(worldTileX, surfaceTileY, column) then
			continue
		end

		local canSupportTree = isTreePlacementSupported(worldTileX, surfaceTileY, column, surfaceTileId)
		local hasAirClearance = canSupportTree and self:HasTreeAirClearance(column, worldTileX, surfaceTileY)
		local treeVariantIndex = if canSupportTree
			then self:GetTreeTemplateIndex(worldTileX, surfaceTileY, column.biomeType, column.biomeId)
			else nil
		local canSpawnTree = treeVariantIndex ~= nil and hasAirClearance
		local didSpawnTree = false
		if canSpawnTree and column.biomeId == self.biomeId.SNOW and column.biomeType == self.biomeType.NORMAL then
			local snowTreeChance = clampNumber(snowDecorationSettings.TreeChance, 0, 1, 0.38)
			local snowTreeEdgeBuffer = coerceInteger(snowDecorationSettings.TreeEdgeBufferTiles, 0, 48, 8)
			if
				not self:IsWithinBiomeTransitionBuffer(
					getColumnProfileForBlend,
					worldTileX,
					self.biomeId.SNOW,
					self.biomeType.NORMAL,
					snowTreeEdgeBuffer
				)
			then
				canSpawnTree = false
			else
				local snowTreeRoll =
					deterministicUnitInterval(self.seed, worldTileX, surfaceTileY, treeVariantIndex :: number, 1549)
				canSpawnTree = snowTreeRoll <= snowTreeChance
			end
		end
		if canSpawnTree then
			local treeSeed = computeProceduralTreeSeed(self.seed, worldTileX, surfaceTileY, treeVariantIndex)
			table.insert(trees, {
				tileX = worldTileX,
				tileY = surfaceTileY,
				variantIndex = treeVariantIndex,
				seed = treeSeed,
				biomeType = column.biomeType,
				biomeId = column.biomeId,
				templateIndex = treeVariantIndex,
			})
			didSpawnTree = true
		end

		if not didSpawnTree and column.biomeId == self.biomeId.SNOW and column.biomeType == self.biomeType.NORMAL then
			local isSnowSurfaceTile = surfaceTileId == self.tileId.SNOW or surfaceTileId == self.tileId.ICE
			if isSnowSurfaceTile then
				local propEdgeBuffer = coerceInteger(snowDecorationSettings.PropEdgeBufferTiles, 0, 48, 6)
				local propStructureBuffer = coerceInteger(snowDecorationSettings.PropStructureBufferTiles, 0, 48, 10)
				local _propAirClearance = coerceInteger(snowDecorationSettings.PropAirClearanceTiles, 1, 24, 5)
				if
					self:IsWithinBiomeTransitionBuffer(
						getColumnProfileForBlend,
						worldTileX,
						self.biomeId.SNOW,
						self.biomeType.NORMAL,
						propEdgeBuffer
					) and not hasReservedSurfaceTileNear(worldTileX, propStructureBuffer)
				then
					local snowPileChance = clampNumber(snowDecorationSettings.SnowPileChance, 0, 1, 0.24)
					local snowPileSpacing = coerceInteger(snowDecorationSettings.SnowPileSpacingTiles, 4, 64, 11)
					if self:IsSurfaceAnchorTile(worldTileX, snowPileSpacing, SNOW_PILE_SLOT_NOISE_FREQUENCY, 1223) then
						local snowPileRoll =
							deterministicUnitInterval(self.seed, worldTileX, surfaceTileY, self.propId.SNOW_PILE, 2179)
						if snowPileRoll <= snowPileChance then
							local variantIndex = self:GetDesertPropVariantIndex(worldTileX, surfaceTileY, 3)
							props[#props + 1] = {
								tileX = worldTileX,
								tileY = surfaceTileY,
								propId = self.propId.SNOW_PILE,
								variantIndex = variantIndex,
								seed = computeProceduralTreeSeed(
									self.seed + self.propId.SNOW_PILE * 97,
									worldTileX,
									surfaceTileY,
									variantIndex
								),
								biomeType = column.biomeType,
								biomeId = column.biomeId,
							}
						end
					end
				end
			end
		end

		if column.biomeId ~= self.biomeId.DESERT or column.biomeType ~= self.biomeType.NORMAL then
			continue
		end
		if surfaceTileId ~= self.tileId.SAND and surfaceTileId ~= self.tileId.SANDSTONE then
			continue
		end

		local cactusEdgeBuffer = coerceInteger(desertDecorationSettings.CactusEdgeBufferTiles, 0, 48, 7)
		local cactusStructureBuffer = coerceInteger(desertDecorationSettings.CactusStructureBufferTiles, 0, 48, 10)
		if
			not self:IsWithinBiomeTransitionBuffer(
				getColumnProfileForBlend,
				worldTileX,
				self.biomeId.DESERT,
				self.biomeType.NORMAL,
				cactusEdgeBuffer
			)
		then
			continue
		end
		if hasReservedSurfaceTileNear(worldTileX, cactusStructureBuffer) then
			continue
		end

		local cactusChance = clampNumber(desertDecorationSettings.CactusChance, 0, 1, 0.68)
		local cactusSpacing = coerceInteger(desertDecorationSettings.CactusSpacingTiles, 4, 64, 11)
		local cactusAirClearance = coerceInteger(desertDecorationSettings.CactusAirClearanceTiles, 3, 32, 14)
		local rockChance = clampNumber(desertDecorationSettings.RockChance, 0, 1, 0.12)
		local rockSpacing = coerceInteger(desertDecorationSettings.RockSpacingTiles, 4, 64, 16)
		local didSpawnDesertProp = false

		if
			self:IsSurfaceAnchorTile(worldTileX, cactusSpacing, DESERT_CACTUS_SLOT_NOISE_FREQUENCY, 211)
			and self:HasAirClearance(column, worldTileX, surfaceTileY, cactusAirClearance)
		then
			local cactusRoll =
				deterministicUnitInterval(self.seed, worldTileX, surfaceTileY, self.propId.DESERT_CACTUS, 617)
			if cactusRoll <= cactusChance then
				local variantIndex = self:GetDesertPropVariantIndex(worldTileX, surfaceTileY, 4)
				local propSeed = computeProceduralTreeSeed(
					self.seed + self.propId.DESERT_CACTUS * 97,
					worldTileX,
					surfaceTileY,
					variantIndex
				)
				props[#props + 1] = {
					tileX = worldTileX,
					tileY = surfaceTileY,
					propId = self.propId.DESERT_CACTUS,
					variantIndex = variantIndex,
					seed = propSeed,
					biomeType = column.biomeType,
					biomeId = column.biomeId,
				}
				didSpawnDesertProp = true
			end
		end

		if didSpawnDesertProp then
			continue
		end

		if self:IsSurfaceAnchorTile(worldTileX, rockSpacing, DESERT_ROCK_SLOT_NOISE_FREQUENCY, 487) then
			local rockRoll =
				deterministicUnitInterval(self.seed, worldTileX, surfaceTileY, self.propId.DESERT_ROCK, 1181)
			if rockRoll <= rockChance then
				local variantIndex = self:GetDesertPropVariantIndex(worldTileX, surfaceTileY, 2)
				props[#props + 1] = {
					tileX = worldTileX,
					tileY = surfaceTileY,
					propId = self.propId.DESERT_ROCK,
					variantIndex = variantIndex,
					seed = computeProceduralTreeSeed(
						self.seed + self.propId.DESERT_ROCK * 97,
						worldTileX,
						surfaceTileY,
						variantIndex
					),
					biomeType = column.biomeType,
					biomeId = column.biomeId,
				}
			end
		end
	end

	tiles = select(1, self:RepairIntersectingTileMetadata(tiles, width, height))

	local dominantBiomeType = getDominantBiomeType(biomeTypes, self.biomeType.NORMAL)
	local dominantBiomeId = getDominantBiomeId(biomeIds, self.biomeId.FOREST)
	local liquids = if self.liquidGenerator ~= nil
		then self.liquidGenerator:GenerateChunkLiquids({
			seed = self.seed,
			chunkX = chunkX,
			chunkY = chunkY,
			tileMinX = tileMinX,
			tileMinY = tileMinY,
			width = width,
			height = height,
			tiles = tiles,
			depthBelowSurface = depthBelowSurface,
			biomeIds = biomeIds,
			biomeTypes = biomeTypes,
			dominantBiomeId = dominantBiomeId,
			dominantBiomeType = dominantBiomeType,
			columnProfiles = columnProfiles,
			scanColumnProfiles = backgroundColumnProfiles,
			scanColumnMinX = backgroundTileMinX,
		})
		else Sift.Array.create(width * height, 0)

	local now = os.clock()
	local generated = {
		key = packChunkKey(chunkX, chunkY),
		chunkX = chunkX,
		chunkY = chunkY,
		tileMinX = tileMinX,
		tileMinY = tileMinY,
		width = width,
		height = height,
		tiles = tiles,
		walls = walls,
		liquids = liquids,
		depthLayers = depthLayers,
		depthBelowSurface = depthBelowSurface,
		biomeIds = biomeIds,
		surfaceBiomeIds = surfaceBiomeIds,
		biomeTypes = biomeTypes,
		dominantBiomeId = dominantBiomeId,
		dominantBiomeType = dominantBiomeType,
		backgroundLayers = backgroundLayers,
		trees = trees,
		props = props,
		generatedAt = now,
		lastAccessedAt = now,
	}
	local generatedRaw = generated :: any
	generatedRaw._metadataValidated = true
	generatedRaw._wallsValidated = true
	generatedRaw._liquidValidated = true
	generatedRaw._tileMetadataOverlapRepaired = false
	self:RepairChunkTileMetadataOverlaps(generated, true)
	return generated
end

function WorldGeneration.GetOrGenerateChunkData(self: WorldGeneration, chunkX: number, chunkY: number): ChunkData
	local key = packChunkKey(chunkX, chunkY)
	local cache = self.cache
	local cached = if cache then cache:GetChunkData(key) :: ChunkData? else nil
	if cached then
		local repairedOverlapCount = self:RepairChunkTileMetadataOverlaps(cached)
		if repairedOverlapCount > 0 then
			(cached :: any)._liquidValidated = false
		end
		ensureChunkBiomeMetadata(self, cached)
		ensureChunkWallData(self, cached)
		ensureChunkLiquidData(self, cached)
		return cached
	end

	local generated = self:GenerateChunkData(chunkX, chunkY)
	ensureChunkBiomeMetadata(self, generated)
	ensureChunkWallData(self, generated)
	ensureChunkLiquidData(self, generated)
	local chunkOverrides = self.chunkOverrides[key]
	local tileOverridesApplied = false
	if chunkOverrides ~= nil then
		for tileIndex, overrideTileId in chunkOverrides do
			if tileIndex >= 1 and tileIndex <= #generated.tiles then
				generated.tiles[tileIndex] = overrideTileId
				tileOverridesApplied = true
			end
		end
	end

	local chunkWallOverrides = self.chunkWallOverrides[key]
	if chunkWallOverrides ~= nil then
		for tileIndex, overrideWallId in chunkWallOverrides do
			if tileIndex >= 1 and tileIndex <= #generated.walls then
				generated.walls[tileIndex] = overrideWallId
			end
		end
	end

	local chunkBiomeOverrides = self.chunkBiomeOverrides[key]
	local biomeOverridesApplied = false
	if chunkBiomeOverrides ~= nil then
		for tileIndex, overrideBiomeType in chunkBiomeOverrides do
			if tileIndex >= 1 and tileIndex <= #generated.biomeTypes then
				generated.biomeTypes[tileIndex] = overrideBiomeType
				generated.tiles[tileIndex] =
					self.biomeGenerator:ConvertTileToBiomeType(generated.tiles[tileIndex], overrideBiomeType)
				biomeOverridesApplied = true
			end
		end
		generated.dominantBiomeType = getDominantBiomeType(generated.biomeTypes, self.biomeType.NORMAL)
	end

	if tileOverridesApplied or biomeOverridesApplied then
		(generated :: any)._tileMetadataOverlapRepaired = false
	end
	local repairedOverlapCount =
		self:RepairChunkTileMetadataOverlaps(generated, tileOverridesApplied or biomeOverridesApplied)
	if repairedOverlapCount > 0 then
		(generated :: any)._liquidValidated = false
		ensureChunkLiquidData(self, generated)
	end

	local chunkLiquidOverrides = self.chunkLiquidOverrides[key]
	if chunkLiquidOverrides ~= nil then
		for tileIndex, overrideCell in chunkLiquidOverrides do
			if tileIndex >= 1 and tileIndex <= #generated.liquids then
				generated.liquids[tileIndex] = overrideCell
			end
		end
	end

	if cache then
		cache:SetChunkData(key, generated)
	end
	return generated
end

function WorldGeneration.BuildGreedyRectangles(
	_self: WorldGeneration,
	values: { number },
	width: number,
	height: number,
	shouldInclude: (value: number, index: number) -> boolean
): { GreedyRect }
	local rectangles: { GreedyRect } = {}
	local visited: { boolean } = Sift.Array.create(width * height, false)

	for localY = 0, height - 1 do
		for localX = 0, width - 1 do
			local index = computeTileIndex(localX, localY, width)
			if visited[index] then
				continue
			end

			local value = values[index]
			if not shouldInclude(value, index) then
				continue
			end

			local rectWidth = 1
			while localX + rectWidth < width do
				local scanIndex = computeTileIndex(localX + rectWidth, localY, width)
				if visited[scanIndex] then
					break
				end
				local scanValue = values[scanIndex]
				if scanValue ~= value or not shouldInclude(scanValue, scanIndex) then
					break
				end
				rectWidth += 1
			end

			local rectHeight = 1
			local canExtend = true
			while canExtend and localY + rectHeight < height do
				for scanX = 0, rectWidth - 1 do
					local scanIndex = computeTileIndex(localX + scanX, localY + rectHeight, width)
					if visited[scanIndex] then
						canExtend = false
						break
					end
					local scanValue = values[scanIndex]
					if scanValue ~= value or not shouldInclude(scanValue, scanIndex) then
						canExtend = false
						break
					end
				end
				if canExtend then
					rectHeight += 1
				end
			end

			for markY = 0, rectHeight - 1 do
				for markX = 0, rectWidth - 1 do
					visited[computeTileIndex(localX + markX, localY + markY, width)] = true
				end
			end

			table.insert(rectangles, {
				x = localX,
				y = localY,
				width = rectWidth,
				height = rectHeight,
				value = value,
			})
		end
	end

	return rectangles
end

function WorldGeneration.BuildChunkVisual(self: WorldGeneration, chunkData: ChunkData): ChunkVisual
	local collisionChunksFolder = self.collisionChunksFolder
	if collisionChunksFolder == nil then
		self:CreateFolders()
		collisionChunksFolder = self.collisionChunksFolder :: Folder
	end

	local model = TileComponent.CreateModel({
		name = createRuntimeInstanceName(),
		attributes = {
			ChunkX = chunkData.chunkX,
			ChunkY = chunkData.chunkY,
			ChunkKey = chunkData.key,
			ChunkRevision = self.chunkRevisions[chunkData.key] or 0,
			DominantBiomeId = chunkData.dominantBiomeId,
			DominantBiomeType = chunkData.dominantBiomeType,
			IsCorruptionChunk = chunkData.dominantBiomeType == self.biomeType.CORRUPTION,
			ChunkCollisionReady = false,
			[SKIP_WORLD_ANIMATOR_ATTRIBUTE] = true,
			[WORLD_ANIMATOR_CHUNK_ATTRIBUTE] = false,
		},
	})
	TagBinder.applyTag(model, TagBinder.Tags.Chunk, CollectionService)

	local terrainFolder: Folder? = nil

	local parts: { BasePart } = {}
	local collisionRects = self:BuildGreedyRectangles(
		chunkData.tiles,
		chunkData.width,
		chunkData.height,
		function(value: number): boolean
			return value ~= self.tileId.AIR
		end
	)

	for rectIndex, rect in collisionRects do
		if #parts >= self.maxCollisionPartsPerChunk then
			break
		end

		local centerTileX = chunkData.tileMinX + rect.x + rect.width * 0.5
		local centerTileY = chunkData.tileMinY + rect.y + rect.height * 0.5
		local part = self:AcquirePart()
		part.Name = createRuntimeInstanceName()
		part.Anchored = true
		part.Locked = true
		part.Transparency = 1
		part.Color = Color3.new(0, 0, 0)
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.CastShadow = false
		part.Size = Vector3.new(self.tileDepth, self.tileSize * rect.height, self.tileSize * rect.width)
		part.CFrame = CFrame.new(self:ComputeTileCenterPosition(centerTileX, centerTileY, 0))
		if terrainFolder == nil then
			terrainFolder = TileComponent.CreateFolder({
				name = "Terrain",
				parent = model,
			} :: any)
			WorkspaceFolders.ManageFolder(terrainFolder, model)
		end
		part.Parent = terrainFolder
		table.insert(parts, part)

		if rectIndex % self.meshingRectsPerYield == 0 then
			task.wait()
		end
	end

	model.Parent = collisionChunksFolder

	local now = os.clock()
	return {
		key = chunkData.key,
		chunkX = chunkData.chunkX,
		chunkY = chunkData.chunkY,
		model = model,
		terrainFolder = terrainFolder,
		backgroundFolder = nil,
		treesFolder = nil,
		parts = parts,
		loadedAt = now,
		lastAccessedAt = now,
	}
end

function WorldGeneration.AttachChunkVisual(self: WorldGeneration, visual: ChunkVisual)
	local collisionChunksFolder = self.collisionChunksFolder
	if collisionChunksFolder == nil then
		self:CreateFolders()
		collisionChunksFolder = self.collisionChunksFolder :: Folder
	end

	visual.model.Parent = collisionChunksFolder
	visual.model:SetAttribute("ChunkCollisionReady", true)
	local now = os.clock()
	visual.loadedAt = now
	visual.lastAccessedAt = now
end

function WorldGeneration.TakeCachedChunkVisual(self: WorldGeneration, chunkKey: string): ChunkVisual?
	local cachedVisual = self.cachedChunkVisuals[chunkKey]
	if cachedVisual == nil then
		return nil
	end

	self.cachedChunkVisuals[chunkKey] = nil
	self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
	cachedVisual.lastAccessedAt = os.clock()
	return cachedVisual
end

function WorldGeneration.PruneCachedChunkVisuals(self: WorldGeneration)
	while self.cachedChunkVisualCount > self.maxCachedChunkVisuals do
		local evictionKey: string? = nil
		local oldestAccess = math.huge

		for chunkKey, cachedVisual in self.cachedChunkVisuals do
			if cachedVisual.lastAccessedAt < oldestAccess then
				oldestAccess = cachedVisual.lastAccessedAt
				evictionKey = chunkKey
			end
		end

		if evictionKey == nil then
			break
		end

		local visual = self.cachedChunkVisuals[evictionKey]
		self.cachedChunkVisuals[evictionKey] = nil
		self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
		if visual ~= nil then
			self:ReleaseChunkVisual(visual)
		end
	end
end

function WorldGeneration.CacheChunkVisual(self: WorldGeneration, chunkKey: string, visual: ChunkVisual)
	if self.maxCachedChunkVisuals <= 0 then
		self:ReleaseChunkVisual(visual)
		return
	end

	if visual.model.Parent ~= nil then
		visual.model.Parent = nil
	end
	visual.model:SetAttribute("ChunkCollisionReady", false)
	visual.lastAccessedAt = os.clock()

	local existing = self.cachedChunkVisuals[chunkKey]
	if existing == visual then
		return
	end
	if existing ~= nil and existing ~= visual then
		self:ReleaseChunkVisual(existing)
	else
		self.cachedChunkVisualCount += 1
	end
	self.cachedChunkVisuals[chunkKey] = visual
	self:PruneCachedChunkVisuals()
end

function WorldGeneration.ReleaseChunkVisual(self: WorldGeneration, visual: ChunkVisual)
	for _, part in visual.parts do
		if part.Parent ~= nil then
			part.Parent = nil
		end
		self:ReleasePart(part)
	end
	table.clear(visual.parts)
	visual.model:SetAttribute("ChunkCollisionReady", false)
	visual.model:Destroy()
end

function WorldGeneration.UnloadChunkByKey(self: WorldGeneration, chunkKey: string)
	local visual = self.loadedChunkVisuals[chunkKey]
	if visual == nil then
		return
	end

	self.loadedChunkVisuals[chunkKey] = nil
	self.loadedChunkCount = math.max(0, self.loadedChunkCount - 1)
	self:CacheChunkVisual(chunkKey, visual)
	self:NotifyChunkCollisionUnloaded(chunkKey, {
		reason = "unloaded",
	})
end

function WorldGeneration.LoadChunkByKey(self: WorldGeneration, chunkKey: string, contextRaw: any?)
	if self.loadedChunkVisuals[chunkKey] ~= nil then
		return
	end

	local context = if typeof(contextRaw) == "table" then contextRaw :: { [string]: any } else {} :: any
	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return
	end

	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return
	end

	local cachedVisual = self:TakeCachedChunkVisual(chunkKey)
	if cachedVisual ~= nil then
		if (self.chunkDemand[chunkKey] or 0) > 0 then
			self:AttachChunkVisual(cachedVisual)
			cachedVisual.model:SetAttribute("ChunkRevision", self.chunkRevisions[chunkKey] or 0)
			self.loadedChunkVisuals[chunkKey] = cachedVisual
			self.loadedChunkCount += 1
			self:NotifyChunkCollisionReady(chunkKey, {
				reason = if typeof(context.reason) == "string" then context.reason else "loaded",
				fromCache = true,
			})
		else
			self:CacheChunkVisual(chunkKey, cachedVisual)
		end
		return
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	if (self.chunkDemand[chunkKey] or 0) <= 0 then
		return
	end

	if self.loadedChunkVisuals[chunkKey] ~= nil then
		return
	end

	local visual = self:BuildChunkVisual(chunkData)
	if (self.chunkDemand[chunkKey] or 0) <= 0 then
		self:ReleaseChunkVisual(visual)
		return
	end

	self:AttachChunkVisual(visual)
	self.loadedChunkVisuals[chunkKey] = visual
	self.loadedChunkCount += 1
	visual.model:SetAttribute("ChunkRevision", self.chunkRevisions[chunkKey] or 0)
	self:NotifyChunkCollisionReady(chunkKey, {
		reason = if typeof(context.reason) == "string" then context.reason else "loaded",
		fromCache = false,
	})
end

function WorldGeneration.ProcessUnloadQueue(self: WorldGeneration)
	local queueDepth = self.unloadQueue:GetCount()
	local unloadBudget = self.maxChunkUnloadsPerHeartbeat
	if queueDepth > unloadBudget then
		unloadBudget = math.min(256, math.max(unloadBudget, math.ceil(queueDepth * 0.35)))
	end

	local processed = 0
	while processed < unloadBudget do
		local chunkKey = self:DequeueUnloadKey()
		if chunkKey == nil then
			break
		end

		self.pendingUnloadLookup[chunkKey] = nil
		if (self.chunkDemand[chunkKey] or 0) > 0 then
			continue
		end

		self:UnloadChunkByKey(chunkKey)
		processed += 1
	end

	if processed > 0 then
		self:PulseStatsChanged()
	end
end

function WorldGeneration.PumpLoadQueue(self: WorldGeneration)
	while self.activeLoadWorkers < self.maxConcurrentChunkLoads do
		local chunkKey = self:DequeueLoadKey()
		if chunkKey == nil then
			break
		end

		self.pendingLoadLookup[chunkKey] = nil
		if (self.chunkDemand[chunkKey] or 0) <= 0 then
			continue
		end
		if self.loadedChunkVisuals[chunkKey] ~= nil then
			continue
		end
		if self.loadingLookup[chunkKey] then
			continue
		end

		self.loadingLookup[chunkKey] = true
		self.activeLoadWorkers += 1
		self:PulseStatsChanged()

		task.spawn(function()
			local ok, loaderror = pcall(function()
				self:LoadChunkByKey(chunkKey)
			end)
			self.loadingLookup[chunkKey] = nil
			self.activeLoadWorkers = math.max(0, self.activeLoadWorkers - 1)
			if not ok and (self.chunkDemand[chunkKey] or 0) > 0 then
				warn(`WorldGeneration failed to load collision chunk {chunkKey}: {loaderror}`)
				self:EnqueueLoadByKey(chunkKey)
			end
			self:PulseStatsChanged()
		end)
	end
end

function WorldGeneration.PruneChunkDataCache(self: WorldGeneration, deltaTime: number)
	self.cachePruneAccumulator += deltaTime
	if self.cachePruneAccumulator < 0.9 then
		return
	end
	self.cachePruneAccumulator = 0

	local cache = self.cache
	if cache == nil then
		return
	end

	cache:PruneChunkData(function(chunkKey: string): boolean
		if self.loadedChunkVisuals[chunkKey] ~= nil then
			return true
		end
		if (self.chunkDemand[chunkKey] or 0) > 0 then
			return true
		end
		if self.loadingLookup[chunkKey] then
			return true
		end
		return false
	end)
end

function WorldGeneration.GetTileAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): (number, number)
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return self.tileId.AIR, self.wallId.NONE
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	if tileY < self.minTileY or tileY > self.maxTileY then
		return self.tileId.AIR, self.wallId.NONE
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return self.tileId.AIR, self.wallId.NONE
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()

	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return self.tileId.AIR, self.wallId.NONE
	end

	local index = computeTileIndex(localX, localY, chunkData.width)
	return chunkData.tiles[index], chunkData.walls[index] or self.wallId.NONE
end

function WorldGeneration.GetWallAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): number
	local _, wallId = self:GetTileAt(tileXRaw, tileYRaw)
	return wallId
end

function WorldGeneration.GetBiomeTypeAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): number
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return self.biomeType.NORMAL
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	if tileY < self.minTileY or tileY > self.maxTileY then
		return self.biomeType.NORMAL
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return self.biomeType.NORMAL
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return chunkData.dominantBiomeType
	end

	local index = computeTileIndex(localX, localY, chunkData.width)
	return chunkData.biomeTypes[index] or chunkData.dominantBiomeType
end

function WorldGeneration.GetBiomeIdAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): number
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return self.biomeId.FOREST
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	if tileY < self.minTileY or tileY > self.maxTileY then
		return self.biomeId.FOREST
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return self.biomeId.FOREST
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return chunkData.dominantBiomeId
	end

	local index = computeTileIndex(localX, localY, chunkData.width)
	return chunkData.biomeIds[index] or chunkData.dominantBiomeId
end

function WorldGeneration.GetTileAtWorldPosition(self: WorldGeneration, worldPosition: Vector3): (number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:GetTileAt(tileX, tileY)
end

function WorldGeneration.GetBiomeTypeAtWorldPosition(self: WorldGeneration, worldPosition: Vector3): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:GetBiomeTypeAt(tileX, tileY)
end

function WorldGeneration.GetBiomeIdAtWorldPosition(self: WorldGeneration, worldPosition: Vector3): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:GetBiomeIdAt(tileX, tileY)
end

function WorldGeneration.GetChunkData(self: WorldGeneration, chunkXRaw: any, chunkYRaw: any): ChunkData?
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return nil
	end

	local chunkX = math.floor(chunkXRaw :: number)
	local chunkY = math.floor(chunkYRaw :: number)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return nil
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	return chunkData
end

function WorldGeneration.GetChunkDataByKey(self: WorldGeneration, chunkKeyRaw: any): ChunkData?
	if typeof(chunkKeyRaw) ~= "string" then
		return nil
	end

	local chunkX, chunkY = unpackChunkKey(chunkKeyRaw)
	if chunkX == nil or chunkY == nil then
		return nil
	end
	return self:GetChunkData(chunkX, chunkY)
end

function WorldGeneration.GetChunkDominantBiomeTypeByKey(self: WorldGeneration, chunkKeyRaw: any): number
	local chunkData = self:GetChunkDataByKey(chunkKeyRaw)
	if chunkData == nil then
		return self.biomeType.NORMAL
	end
	return chunkData.dominantBiomeType
end

local function copyBackgroundLayerSnapshotWithinChunkBounds(
	self: WorldGeneration,
	chunkData: ChunkData,
	layerData: BackgroundLayerData
): { [string]: any }
	local snapshotTiles = Sift.Array.create(chunkData.width * chunkData.height, self.tileId.AIR)
	for localY = 0, chunkData.height - 1 do
		local worldTileY = chunkData.tileMinY + localY
		local sourceLocalY = worldTileY - layerData.tileMinY
		if sourceLocalY < 0 or sourceLocalY >= layerData.height then
			continue
		end

		for localX = 0, chunkData.width - 1 do
			local worldTileX = chunkData.tileMinX + localX
			local sourceLocalX = worldTileX - layerData.tileMinX
			if sourceLocalX < 0 or sourceLocalX >= layerData.width then
				continue
			end

			local sourceIndex = computeTileIndex(sourceLocalX, sourceLocalY, layerData.width)
			local targetIndex = computeTileIndex(localX, localY, chunkData.width)
			snapshotTiles[targetIndex] = getTileMetadataId(self, layerData.tiles[sourceIndex])
		end
	end

	return {
		layerIndex = layerData.layerIndex,
		tileMinX = chunkData.tileMinX,
		tileMinY = chunkData.tileMinY,
		width = chunkData.width,
		height = chunkData.height,
		tiles = snapshotTiles,
	}
end

function WorldGeneration.GetChunkSnapshotByKey(self: WorldGeneration, chunkKeyRaw: any): { [string]: any }?
	local chunkData = self:GetChunkDataByKey(chunkKeyRaw)
	if chunkData == nil then
		return nil
	end

	self:RepairChunkTileMetadataOverlaps(chunkData)

	local backgroundLayersSnapshot = Sift.Array.create(#chunkData.backgroundLayers)
	for layerIndex, layerData in chunkData.backgroundLayers do
		backgroundLayersSnapshot[layerIndex] = copyBackgroundLayerSnapshotWithinChunkBounds(self, chunkData, layerData)
	end

	local treesSnapshot = Sift.Array.create(#chunkData.trees)
	for treeIndex, treeData in chunkData.trees do
		treesSnapshot[treeIndex] = {
			tileX = treeData.tileX,
			tileY = treeData.tileY,
			variantIndex = treeData.variantIndex,
			seed = treeData.seed,
			biomeType = treeData.biomeType,
			biomeId = treeData.biomeId,
			templateIndex = treeData.templateIndex or treeData.variantIndex,
		}
	end

	local propsSnapshot = Sift.Array.create(#chunkData.props)
	for propIndex, propData in chunkData.props do
		propsSnapshot[propIndex] = {
			tileX = propData.tileX,
			tileY = propData.tileY,
			propId = propData.propId,
			variantIndex = propData.variantIndex,
			seed = propData.seed,
			biomeType = propData.biomeType,
			biomeId = propData.biomeId,
		}
	end

	return {
		key = chunkData.key,
		chunkX = chunkData.chunkX,
		chunkY = chunkData.chunkY,
		tileMinX = chunkData.tileMinX,
		tileMinY = chunkData.tileMinY,
		width = chunkData.width,
		height = chunkData.height,
		tiles = Sift.Dictionary.copy(chunkData.tiles),
		walls = Sift.Dictionary.copy(chunkData.walls),
		depthLayers = Sift.Dictionary.copy(chunkData.depthLayers),
		depthBelowSurface = Sift.Dictionary.copy(chunkData.depthBelowSurface),
		biomeIds = Sift.Dictionary.copy(chunkData.biomeIds),
		surfaceBiomeIds = Sift.Dictionary.copy(chunkData.surfaceBiomeIds),
		biomeTypes = Sift.Dictionary.copy(chunkData.biomeTypes),
		dominantBiomeId = chunkData.dominantBiomeId,
		dominantBiomeType = chunkData.dominantBiomeType,
		backgroundLayers = backgroundLayersSnapshot,
		trees = treesSnapshot,
		props = propsSnapshot,
		revision = self:GetChunkRevisionByKey(chunkData.key),
	}
end

function WorldGeneration.GetLiquidChunkSnapshotByKey(self: WorldGeneration, chunkKeyRaw: any): { [string]: any }?
	local chunkData = self:GetChunkDataByKey(chunkKeyRaw)
	if chunkData == nil then
		return nil
	end

	return {
		key = chunkData.key,
		chunkX = chunkData.chunkX,
		chunkY = chunkData.chunkY,
		tileMinX = chunkData.tileMinX,
		tileMinY = chunkData.tileMinY,
		width = chunkData.width,
		height = chunkData.height,
		cells = Sift.Dictionary.copy(chunkData.liquids),
		updatedAt = os.clock(),
	}
end

function WorldGeneration.GetLiquidCellAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): number
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return 0
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	if tileY < self.minTileY or tileY > self.maxTileY then
		return 0
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return 0
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return 0
	end

	return chunkData.liquids[computeTileIndex(localX, localY, chunkData.width)] or 0
end

function WorldGeneration.SetLiquidCellAt(
	self: WorldGeneration,
	tileXRaw: any,
	tileYRaw: any,
	packedCellRaw: any
): (boolean, number, number)
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return false, 0, 0
	end
	if not isFiniteNumber(packedCellRaw) then
		return false, 0, 0
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	local nextPackedCell = math.max(0, math.floor(packedCellRaw :: number))
	if tileY < self.minTileY or tileY > self.maxTileY then
		return false, 0, 0
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return false, 0, 0
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return false, 0, 0
	end

	local tileIndex = computeTileIndex(localX, localY, chunkData.width)
	local previousPackedCell = chunkData.liquids[tileIndex] or 0
	if previousPackedCell == nextPackedCell then
		return false, previousPackedCell, nextPackedCell
	end

	chunkData.liquids[tileIndex] = nextPackedCell
	local liquidOverrides = self.chunkLiquidOverrides[chunkData.key]
	if liquidOverrides == nil then
		liquidOverrides = {}
		self.chunkLiquidOverrides[chunkData.key] = liquidOverrides
	end
	liquidOverrides[tileIndex] = nextPackedCell

	return true, previousPackedCell, nextPackedCell
end

function WorldGeneration.SetTileAt(
	self: WorldGeneration,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any
): (boolean, number, number)
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return false, self.tileId.AIR, self.tileId.AIR
	end
	if not isFiniteNumber(tileIdRaw) then
		return false, self.tileId.AIR, self.tileId.AIR
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	local nextTileId = math.floor(tileIdRaw :: number)

	if tileY < self.minTileY or tileY > self.maxTileY then
		return false, self.tileId.AIR, self.tileId.AIR
	end
	if nextTileId < self.tileId.AIR or nextTileId > MAX_TILE_ID then
		return false, self.tileId.AIR, self.tileId.AIR
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return false, self.tileId.AIR, self.tileId.AIR
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()

	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return false, self.tileId.AIR, self.tileId.AIR
	end

	local tileIndex = computeTileIndex(localX, localY, chunkData.width)
	local previousTileId = chunkData.tiles[tileIndex]
	if previousTileId == nextTileId then
		return false, previousTileId, nextTileId
	end

	chunkData.tiles[tileIndex] = nextTileId
	local chunkOverrides = self.chunkOverrides[chunkData.key]
	if chunkOverrides == nil then
		chunkOverrides = {}
		self.chunkOverrides[chunkData.key] = chunkOverrides
	end
	chunkOverrides[tileIndex] = nextTileId

	local touchedChunkKeys: { [string]: boolean } = {}
	local touchedChunkBounds: { [string]: ChunkDirtyBounds } = {}
	local function touchChunk(chunkKey: string, dirtyBounds: ChunkDirtyBounds)
		if touchedChunkKeys[chunkKey] then
			return
		end
		touchedChunkKeys[chunkKey] = true
		touchedChunkBounds[chunkKey] = dirtyBounds
		self:BumpChunkRevisionByKey(chunkKey)
		self:MarkChunkDirtyByKey(chunkKey)

		local cachedVisual = self.cachedChunkVisuals[chunkKey]
		if cachedVisual ~= nil then
			self.cachedChunkVisuals[chunkKey] = nil
			self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
			self:ReleaseChunkVisual(cachedVisual)
		end
	end

	touchChunk(chunkData.key, {
		minTileX = tileX,
		minTileY = tileY,
		maxTileX = tileX,
		maxTileY = tileY,
	})
	if localX == 0 then
		local neighborChunkX = chunkX - 1
		touchChunk(packChunkKey(neighborChunkX, chunkY), {
			minTileX = neighborChunkX * self.chunkSize + self.chunkSize - 1,
			minTileY = tileY,
			maxTileX = neighborChunkX * self.chunkSize + self.chunkSize - 1,
			maxTileY = tileY,
		})
	elseif localX == chunkData.width - 1 then
		local neighborChunkX = chunkX + 1
		touchChunk(packChunkKey(neighborChunkX, chunkY), {
			minTileX = neighborChunkX * self.chunkSize,
			minTileY = tileY,
			maxTileX = neighborChunkX * self.chunkSize,
			maxTileY = tileY,
		})
	end
	if localY == 0 then
		local belowChunkY = chunkY - 1
		if self:IsChunkYWithinWorldBounds(belowChunkY) then
			touchChunk(packChunkKey(chunkX, belowChunkY), {
				minTileX = tileX,
				minTileY = belowChunkY * self.chunkSize + self.chunkSize - 1,
				maxTileX = tileX,
				maxTileY = belowChunkY * self.chunkSize + self.chunkSize - 1,
			})
		end
	elseif localY == chunkData.height - 1 then
		local aboveChunkY = chunkY + 1
		if self:IsChunkYWithinWorldBounds(aboveChunkY) then
			touchChunk(packChunkKey(chunkX, aboveChunkY), {
				minTileX = tileX,
				minTileY = aboveChunkY * self.chunkSize,
				maxTileX = tileX,
				maxTileY = aboveChunkY * self.chunkSize,
			})
		end
	end

	for touchedChunkKey, dirtyBounds in touchedChunkBounds do
		self:NotifyChunkTerrainChanged(touchedChunkKey, dirtyBounds, {
			reason = "setTileAt",
			sourceTileX = tileX,
			sourceTileY = tileY,
			previousTileId = previousTileId,
			nextTileId = nextTileId,
			sourceChunkKey = chunkData.key,
			targetChunkKey = touchedChunkKey,
		})
	end

	return true, previousTileId, nextTileId
end

function WorldGeneration.SetWallAt(
	self: WorldGeneration,
	tileXRaw: any,
	tileYRaw: any,
	wallIdRaw: any
): (boolean, number, number)
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) or not isFiniteNumber(wallIdRaw) then
		return false, self.wallId.NONE, self.wallId.NONE
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	local nextWallId = math.floor(wallIdRaw :: number)
	if tileY < self.minTileY or tileY > self.maxTileY then
		return false, self.wallId.NONE, self.wallId.NONE
	end
	if nextWallId < self.wallId.NONE or nextWallId > MAX_WALL_ID then
		return false, self.wallId.NONE, self.wallId.NONE
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return false, self.wallId.NONE, self.wallId.NONE
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return false, self.wallId.NONE, self.wallId.NONE
	end

	local tileIndex = computeTileIndex(localX, localY, chunkData.width)
	local previousWallId = chunkData.walls[tileIndex] or self.wallId.NONE
	if previousWallId == nextWallId then
		return false, previousWallId, nextWallId
	end

	chunkData.walls[tileIndex] = nextWallId
	local chunkOverrides = self.chunkWallOverrides[chunkData.key]
	if chunkOverrides == nil then
		chunkOverrides = {}
		self.chunkWallOverrides[chunkData.key] = chunkOverrides
	end
	chunkOverrides[tileIndex] = nextWallId

	self:BumpChunkRevisionByKey(chunkData.key)
	self:NotifyChunkWallChanged(chunkData.key, {
		minTileX = tileX,
		minTileY = tileY,
		maxTileX = tileX,
		maxTileY = tileY,
	}, {
		reason = "setWallAt",
		sourceTileX = tileX,
		sourceTileY = tileY,
		previousWallId = previousWallId,
		nextWallId = nextWallId,
	})

	return true, previousWallId, nextWallId
end

function WorldGeneration.SetBiomeTypeAt(
	self: WorldGeneration,
	tileXRaw: any,
	tileYRaw: any,
	biomeTypeRaw: any
): (boolean, number, number)
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return false, self.biomeType.NORMAL, self.biomeType.NORMAL
	end
	if not isFiniteNumber(biomeTypeRaw) then
		return false, self.biomeType.NORMAL, self.biomeType.NORMAL
	end

	local tileX = math.floor(tileXRaw :: number)
	local tileY = math.floor(tileYRaw :: number)
	local nextBiomeType = math.floor(biomeTypeRaw :: number)
	if nextBiomeType ~= self.biomeType.NORMAL and nextBiomeType ~= self.biomeType.CORRUPTION then
		return false, self.biomeType.NORMAL, self.biomeType.NORMAL
	end

	if tileY < self.minTileY or tileY > self.maxTileY then
		return false, self.biomeType.NORMAL, self.biomeType.NORMAL
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:IsChunkYWithinWorldBounds(chunkY) then
		return false, self.biomeType.NORMAL, self.biomeType.NORMAL
	end

	local chunkData = self:GetOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return false, self.biomeType.NORMAL, self.biomeType.NORMAL
	end

	local tileIndex = computeTileIndex(localX, localY, chunkData.width)
	local previousBiomeType = chunkData.biomeTypes[tileIndex]
	if previousBiomeType == nextBiomeType then
		return false, previousBiomeType, nextBiomeType
	end

	chunkData.biomeTypes[tileIndex] = nextBiomeType
	chunkData.tiles[tileIndex] = self.biomeGenerator:ConvertTileToBiomeType(chunkData.tiles[tileIndex], nextBiomeType)
	chunkData.dominantBiomeType = getDominantBiomeType(chunkData.biomeTypes, self.biomeType.NORMAL)

	local chunkBiomeOverrides = self.chunkBiomeOverrides[chunkData.key]
	if chunkBiomeOverrides == nil then
		chunkBiomeOverrides = {}
		self.chunkBiomeOverrides[chunkData.key] = chunkBiomeOverrides
	end
	chunkBiomeOverrides[tileIndex] = nextBiomeType

	local touchedChunkKeys: { [string]: boolean } = {}
	local function touchChunk(chunkKey: string)
		if touchedChunkKeys[chunkKey] then
			return
		end
		touchedChunkKeys[chunkKey] = true
		self:BumpChunkRevisionByKey(chunkKey)
		self:MarkChunkDirtyByKey(chunkKey)

		local cachedVisual = self.cachedChunkVisuals[chunkKey]
		if cachedVisual ~= nil then
			self.cachedChunkVisuals[chunkKey] = nil
			self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
			self:ReleaseChunkVisual(cachedVisual)
		end
	end

	touchChunk(chunkData.key)
	if localX == 0 then
		touchChunk(packChunkKey(chunkX - 1, chunkY))
	elseif localX == chunkData.width - 1 then
		touchChunk(packChunkKey(chunkX + 1, chunkY))
	end
	if localY == 0 then
		local belowChunkY = chunkY - 1
		if self:IsChunkYWithinWorldBounds(belowChunkY) then
			touchChunk(packChunkKey(chunkX, belowChunkY))
		end
	elseif localY == chunkData.height - 1 then
		local aboveChunkY = chunkY + 1
		if self:IsChunkYWithinWorldBounds(aboveChunkY) then
			touchChunk(packChunkKey(chunkX, aboveChunkY))
		end
	end

	return true, previousBiomeType, nextBiomeType
end

function WorldGeneration.SetTileAtWorldPosition(
	self: WorldGeneration,
	worldPosition: Vector3,
	tileIdRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:SetTileAt(tileX, tileY, tileIdRaw)
end

function WorldGeneration.SetWallAtWorldPosition(
	self: WorldGeneration,
	worldPosition: Vector3,
	wallIdRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:SetWallAt(tileX, tileY, wallIdRaw)
end

function WorldGeneration.SetBiomeTypeAtWorldPosition(
	self: WorldGeneration,
	worldPosition: Vector3,
	biomeTypeRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:SetBiomeTypeAt(tileX, tileY, biomeTypeRaw)
end

function WorldGeneration.ForceRefreshAllPlayers(self: WorldGeneration)
	for _, runtime in self.playerRuntimes do
		runtime.forceRefresh = true
		runtime.refreshAccumulator = self.playerRefreshInterval
	end
end

function WorldGeneration.GetStats(self: WorldGeneration): { [string]: any }
	local demandedChunks = 0
	for _ in self.chunkDemand do
		demandedChunks += 1
	end
	local focusedPlayers = countLookupEntries(self.playerFocusNodes)
	local interestIndexedChunks = countLookupEntries(self.chunkInterestPlayers)

	return {
		seed = self.seed,
		chunkSize = self.chunkSize,
		tileSize = self.tileSize,
		tileDepth = self.tileDepth,
		horizonDepthBlocks = self.horizonDepthBlocks,
		backgroundLayerCount = self.backgroundLayerCount,
		backgroundLayerThicknessBlocks = self.backgroundLayerThicknessBlocks,
		maxCollisionPartsPerChunk = self.maxCollisionPartsPerChunk,
		loadedChunks = self.loadedChunkCount,
		cachedChunkData = if self.cache then self.cache:GetCachedChunkCount() else 0,
		cachedChunkVisuals = self.cachedChunkVisualCount,
		demandedChunks = demandedChunks,
		pooledParts = if self.cache then self.cache:GetPooledPartCount() else 0,
		activeLoadWorkers = self.activeLoadWorkers,
		queuedLoads = math.max(0, self.loadQueueTail - self.loadQueueHead + 1),
		queuedUnloads = self.unloadQueue:GetCount(),
		queuedDirtyChunks = self.dirtyChunkQueue:GetCount(),
		queuedChunkRebuilds = self.chunkRebuildQueue:GetCount(),
		focusedPlayers = focusedPlayers,
		interestIndexedChunks = interestIndexedChunks,
		maxTrackedRenderDistanceChunks = self.maxTrackedRenderDistanceChunks,
		maxTrackedVerticalRenderDistanceChunks = self.maxTrackedVerticalRenderDistanceChunks,
		treeVariants = #self.treeVariantConfigs,
		trackedPlayers = #self:GetTrackedPlayers(),
		minTileY = self.minTileY,
		maxTileY = self.maxTileY,
	}
end

function WorldGeneration.GetTrackedPlayers(self: WorldGeneration): { Player }
	local players: { Player } = {}
	for player in self.playerRuntimes do
		table.insert(players, player)
	end
	return players
end

function WorldGeneration.Destroy(self: WorldGeneration)
	local trackedPlayers = self:GetTrackedPlayers()
	for _, player in trackedPlayers do
		self:UntrackPlayer(player)
	end

	local loadedChunkKeys = {}
	for chunkKey in self.loadedChunkVisuals do
		table.insert(loadedChunkKeys, chunkKey)
	end
	for _, chunkKey in loadedChunkKeys do
		self:UnloadChunkByKey(chunkKey)
	end

	for chunkKey, visual in self.cachedChunkVisuals do
		self.cachedChunkVisuals[chunkKey] = nil
		self:ReleaseChunkVisual(visual)
	end
	self.cachedChunkVisualCount = 0

	if self.cache then
		self.cache:Destroy()
		self.cache = nil
	end

	table.clear(self.pendingLoadLookup)
	table.clear(self.pendingUnloadLookup)
	table.clear(self.pendingRebuildLookup)
	table.clear(self.dirtyChunkLookup)
	table.clear(self.loadingLookup)
	table.clear(self.chunkDemand)
	table.clear(self.chunkInterestPlayers)
	table.clear(self.playerFocusNodes)
	table.clear(self.chunkRevisions)
	table.clear(self.chunkOverrides)
	table.clear(self.chunkWallOverrides)
	table.clear(self.chunkBiomeOverrides)
	table.clear(self.chunkLiquidOverrides)
	table.clear(self.chunkLifecycleObservers)
	table.clear(self.loadQueue)
	self.unloadQueue = Queue.new() :: QueueClass<string>
	self.dirtyChunkQueue = Queue.new() :: QueueClass<string>
	self.chunkRebuildQueue = Queue.new() :: QueueClass<string>
	self.loadQueueHead = 1
	self.loadQueueTail = 0

	if self.worldFolder then
		self.worldFolder:Destroy()
		self.worldFolder = nil
		self.chunksFolder = nil
		self.collisionChunksFolder = nil
	end

	if self.maid ~= nil then
		self.maid:Destroy()
	end
	self.heartbeatConnection = nil
	self.initialized = false
end
return WorldGeneration
