--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Biome = require(script.Biome)
local Cave = require(script.Cave)
local Structures = require(script.Structures)
local ProceduralTree = require(script.Tree)
local Cache = require(script.Utils.Cache)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)

type BiomeClass = Biome.Biome
type CaveClass = Cave.Cave
type StructuresClass = Structures.Structures
type CacheClass = Cache.Cache
type ColumnProfile = Biome.ColumnProfile
type ProceduralTreeConfig = ProceduralTree.ProceduralTreeConfig

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
	depthLayers: { number },
	depthBelowSurface: { number },
	biomeIds: { number },
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
	terrainFolder: Folder,
	backgroundFolder: Folder?,
	treesFolder: Folder?,
	parts: { BasePart },
	loadedAt: number,
	lastAccessedAt: number,
}

type PlayerRuntime = {
	renderDistance: number,
	verticalRenderDistance: number,
	interestKeys: { [string]: boolean },
	refreshAccumulator: number,
	forceRefresh: boolean,
	lastChunkX: number?,
	lastChunkY: number?,
	connections: { RBXScriptConnection },
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
	parent: Instance?,
	debugLog: boolean?,
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
}

local WALL_ID: WallIdMap = {
	NONE = 0,
	DIRT = 1,
	STONE = 2,
	SANDSTONE = 3,
	SNOW = 4,
	MUD = 5,
}

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
}

local DEPTH_LAYER_CODE = {
	SKY = 0,
	SURFACE = 1,
	UNDERGROUND = 2,
	CAVERN = 3,
	DEEP = 4,
}

local TILE_VISUALS: { [number]: TileVisual } = {
	[TILE_ID.GRASS] = {
		name = "Grass",
		color = Color3.fromRGB(95, 159, 53),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[TILE_ID.JUNGLE_GRASS] = {
		name = "JungleGrass",
		color = Color3.fromRGB(113, 186, 72),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[TILE_ID.DIRT] = {
		name = "Dirt",
		color = Color3.fromRGB(108, 78, 52),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[TILE_ID.STONE] = {
		name = "Stone",
		color = Color3.fromRGB(108, 113, 122),
		material = Enum.Material.Slate,
		transparency = 0,
	},
	[TILE_ID.SAND] = {
		name = "Sand",
		color = Color3.fromRGB(225, 206, 136),
		material = Enum.Material.Sand,
		transparency = 0,
	},
	[TILE_ID.SANDSTONE] = {
		name = "Sandstone",
		color = Color3.fromRGB(183, 154, 109),
		material = Enum.Material.Sandstone,
		transparency = 0,
	},
	[TILE_ID.SNOW] = {
		name = "Snow",
		color = Color3.fromRGB(232, 240, 255),
		material = Enum.Material.Snow,
		transparency = 0,
	},
	[TILE_ID.ICE] = {
		name = "Ice",
		color = Color3.fromRGB(178, 214, 255),
		material = Enum.Material.Glacier,
		transparency = 0,
	},
	[TILE_ID.MUD] = {
		name = "Mud",
		color = Color3.fromRGB(112, 90, 61),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[TILE_ID.CLAY] = {
		name = "Clay",
		color = Color3.fromRGB(135, 98, 73),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[TILE_ID.COPPER_ORE] = {
		name = "CopperOre",
		color = Color3.fromRGB(189, 118, 63),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[TILE_ID.IRON_ORE] = {
		name = "IronOre",
		color = Color3.fromRGB(141, 134, 116),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[TILE_ID.SILVER_ORE] = {
		name = "SilverOre",
		color = Color3.fromRGB(177, 177, 185),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[TILE_ID.GOLD_ORE] = {
		name = "GoldOre",
		color = Color3.fromRGB(214, 186, 62),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[TILE_ID.CORRUPT_GRASS] = {
		name = "CorruptGrass",
		color = Color3.fromRGB(131, 84, 193),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[TILE_ID.CORRUPT_SOIL] = {
		name = "CorruptSoil",
		color = Color3.fromRGB(116, 84, 88),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[TILE_ID.CORRUPT_STONE] = {
		name = "CorruptStone",
		color = Color3.fromRGB(126, 104, 160),
		material = Enum.Material.Rock,
		transparency = 0,
	},
}

local DEFAULT_SEED = 93847583
local DEFAULT_CHUNK_SIZE = 32
local DEFAULT_TILE_SIZE = 2
local DEFAULT_TILE_DEPTH = 2
local DEFAULT_BASE_PLANE_X = 0
local DEFAULT_WALL_PLANE_OFFSET = 1.65
local DEFAULT_HORIZON_DEPTH_BLOCKS = 10
local DEFAULT_BACKGROUND_LAYER_COUNT = 3
local DEFAULT_BACKGROUND_LAYER_THICKNESS_BLOCKS = 1
local DEFAULT_MIN_TILE_Y = -360
local DEFAULT_MAX_TILE_Y = 180
local DEFAULT_BEDROCK_THICKNESS = 4
local DEFAULT_RENDER_DISTANCE_CHUNKS = 4
local DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS = 2
local DEFAULT_PLAYER_REFRESH_INTERVAL = 0.1
local DEFAULT_MAX_CONCURRENT_CHUNK_LOADS = 3
local DEFAULT_MAX_CHUNK_UNLOADS_PER_HEARTBEAT = 12
local DEFAULT_GENERATION_ROWS_PER_YIELD = 8
local DEFAULT_MESHING_RECTS_PER_YIELD = 16
local DEFAULT_MAX_CACHED_CHUNK_DATA = 1200
local DEFAULT_MAX_CACHED_CHUNK_VISUALS = 0
local DEFAULT_POOL_SIZE = 9000
local FIXED_TILE_SIZE_STUDS = 2
local FIXED_TILE_DEPTH_STUDS = 2
local DEFAULT_WORLD_FOLDER_NAME = "WorldGeneration"
local DEFAULT_WORLD_CHUNKS_FOLDER_NAME = "Chunks"
local DEFAULT_WORLD_COLLISION_FOLDER_NAME = "CollisionChunks"
local BACKGROUND_LAYER_BOUNDS_PADDING_TILES = 5

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
local TREE_PLANE_DEPTH_ALPHA = 0.5
local TREE_SURFACE_OFFSET_Y_TILES = 1
local TREE_SLOT_NOISE_FREQUENCY = 0.739
local TREE_VARIANT_NOISE_FREQUENCY_X = 0.413
local TREE_VARIANT_NOISE_FREQUENCY_Y = 0.217
local UINT32_MAX = 0xFFFFFFFF
local INT32_SIGN_BIT = 0x80000000
local UINT32_WRAP = 4294967296
local DEBUG_JUNGLE_SCAN_RADIUS_TILES = 5000
local DEBUG_JUNGLE_SCAN_STEP_TILES = 1
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
local BIOME_BLEND_NEAR_SURFACE_DEPTH = 10
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

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	local value = math.floor(valueRaw :: number)
	return math.clamp(value, minimum, maximum)
end

local function packChunkKey(chunkX: number, chunkY: number): string
	return `{chunkX}:{chunkY}`
end

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

local function hasNonAirNeighborOrSelf(values: { number }, width: number, height: number, localX: number, localY: number): boolean
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

local function createPartTemplate(): Part
	local part = Instance.new("Part")
	part.Name = "WorldTile"
	part.Anchored = true
	part.Locked = true
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = nil
	return part
end

local function resolveWorldGenerationAssetsFolder(): Folder?
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

local function resolveTilesTemplateFolder(): Folder?
	local worldGeneration = resolveWorldGenerationAssetsFolder()
	if worldGeneration == nil then
		return nil
	end
	local tiles = worldGeneration:FindFirstChild("Tiles")
	if tiles ~= nil and tiles:IsA("Folder") then
		return tiles
	end
	return nil
end

local function resolveTreesTemplateFolder(): Folder?
	local worldGeneration = resolveWorldGenerationAssetsFolder()
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

local function collectTemplateInstances(sourceFolder: Folder?): { Instance }
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
				BranchColor = Color3.fromRGB(56, 39, 89),
				LeafColor = Color3.fromRGB(153, 92, 210),
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
				BranchColor = Color3.fromRGB(49, 33, 81),
				LeafColor = Color3.fromRGB(171, 101, 231),
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
				BranchColor = Color3.fromRGB(88, 65, 42),
				LeafColor = Color3.fromRGB(67, 178, 86),
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
				BranchColor = Color3.fromRGB(82, 60, 39),
				LeafColor = Color3.fromRGB(74, 192, 96),
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Jungle2",
			},
		},
	}
end

local function resolveTreeVariantIndexByAlpha(treeVariantCount: number, alpha: number): number
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

local function resolveDominantBiomeType(biomeTypes: { number }, fallbackBiomeType: number): number
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

local function resolveDominantBiomeId(biomeIds: { number }, fallbackBiomeId: number): number
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
	local biomeIdByColumn = table.create(chunkData.width, self.biomeId.FOREST)
	for localX = 0, chunkData.width - 1 do
		local worldTileX = chunkData.tileMinX + localX
		local column = self.biomeGenerator:getColumnProfile(worldTileX)
		biomeIdByColumn[localX + 1] = column.biomeId
	end

	for localY = 0, chunkData.height - 1 do
		for localX = 0, chunkData.width - 1 do
			local tileIndex = computeTileIndex(localX, localY, chunkData.width)
			biomeIds[tileIndex] = biomeIdByColumn[localX + 1]
		end
	end
end

local function debugPrintJungleSides(self: WorldGeneration)
	local leftJungleX: number? = nil
	local rightJungleX: number? = nil
	local forestCount = 0
	local desertCount = 0
	local snowCount = 0
	local jungleCount = 0

	for tileX = -DEBUG_JUNGLE_SCAN_RADIUS_TILES, DEBUG_JUNGLE_SCAN_RADIUS_TILES, DEBUG_JUNGLE_SCAN_STEP_TILES do
		local column = self.biomeGenerator:getColumnProfile(tileX)
		if column.biomeId == self.biomeId.FOREST then
			forestCount += 1
		elseif column.biomeId == self.biomeId.DESERT then
			desertCount += 1
		elseif column.biomeId == self.biomeId.SNOW then
			snowCount += 1
		elseif column.biomeId == self.biomeId.JUNGLE then
			jungleCount += 1
			if tileX < 0 then
				if leftJungleX == nil or math.abs(tileX) < math.abs(leftJungleX) then
					leftJungleX = tileX
				end
			else
				if rightJungleX == nil or tileX < rightJungleX then
					rightJungleX = tileX
				end
			end
		end
	end

	print(
		`[WorldGeneration] Debug biome distribution in x=[{-DEBUG_JUNGLE_SCAN_RADIUS_TILES},{DEBUG_JUNGLE_SCAN_RADIUS_TILES}] :: Forest={forestCount}, Desert={desertCount}, Snow={snowCount}, Jungle={jungleCount}`
	)
	print(
		`[WorldGeneration] Jungle placement config :: Side={(if self.biomeGenerator.junglePreferredSideSign < 0 then "LEFT" else "RIGHT")}, Mode={self.biomeGenerator.junglePlacementLabel}, AnchorDistance={self.biomeGenerator.jungleAnchorDistance}, BandHalfWidth={self.biomeGenerator.jungleBandHalfWidth}`
	)

	if leftJungleX ~= nil then
		print(`[WorldGeneration] Debug jungle scan: LEFT side jungle near tileX={leftJungleX}`)
	else
		print("[WorldGeneration] Debug jungle scan: LEFT side jungle not found in scan range")
	end

	if rightJungleX ~= nil then
		print(`[WorldGeneration] Debug jungle scan: RIGHT side jungle near tileX={rightJungleX}`)
	else
		print("[WorldGeneration] Debug jungle scan: RIGHT side jungle not found in scan range")
	end
end

local function ensureChunkBiomeMetadata(self, chunkData: ChunkData)
	local chunkDataRaw = chunkData :: any
	local totalTiles = chunkData.width * chunkData.height
	if typeof(chunkDataRaw.biomeTypes) ~= "table" then
		chunkDataRaw.biomeTypes = table.create(totalTiles, self.biomeType.NORMAL)
	end
	if typeof(chunkDataRaw.biomeIds) ~= "table" then
		chunkDataRaw.biomeIds = table.create(totalTiles, self.biomeId.FOREST)
		populateChunkBiomeIdsFromColumns(self, chunkData, chunkDataRaw.biomeIds)
	end
	if typeof(chunkDataRaw.depthLayers) ~= "table" then
		chunkDataRaw.depthLayers = table.create(totalTiles)
	end
	if typeof(chunkDataRaw.depthBelowSurface) ~= "table" then
		chunkDataRaw.depthBelowSurface = table.create(totalTiles)
	end
	if typeof(chunkDataRaw.props) ~= "table" then
		chunkDataRaw.props = {}
	end
	local propsRaw = chunkDataRaw.props
	if typeof(propsRaw) == "table" then
		local filteredProps = table.create(#propsRaw)
		for _, propData in propsRaw do
			if typeof(propData) ~= "table" then
				continue
			end
			if (propData :: any).propId == self.propId.CORRUPTION_SPIKE then
				continue
			end
			filteredProps[#filteredProps + 1] = propData
		end
		chunkDataRaw.props = filteredProps
	end

	local biomeTypes = chunkDataRaw.biomeTypes :: { number }
	local biomeIds = chunkDataRaw.biomeIds :: { number }
	local depthLayers = chunkDataRaw.depthLayers :: { number }
	local depthBelowSurface = chunkDataRaw.depthBelowSurface :: { number }
	for tileIndex = 1, totalTiles do
		local depthLayerCodeRaw = depthLayers[tileIndex]
		local hasDepthLayerCode = isFiniteNumber(depthLayerCodeRaw)
		if hasDepthLayerCode then
			depthLayers[tileIndex] = sanitizeInteger(
				depthLayerCodeRaw,
				DEPTH_LAYER_CODE.SKY,
				DEPTH_LAYER_CODE.DEEP,
				DEPTH_LAYER_CODE.UNDERGROUND
			)
		end

		local depthBelowSurfaceRaw = depthBelowSurface[tileIndex]
		local hasDepthBelowSurface = isFiniteNumber(depthBelowSurfaceRaw)
		if hasDepthBelowSurface then
			depthBelowSurface[tileIndex] = sanitizeInteger(depthBelowSurfaceRaw, -8192, 8192, 0)
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
		local column = self.biomeGenerator:getColumnProfile(worldTileX)
		local depthLayer, depthValue = self.caveGenerator:resolveDepthLayer(column.surfaceY, worldTileY)
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
		biomeTypes[tileIndex] = self.biomeType.NORMAL
	end
	for tileIndex = 1, totalTiles do
		local biomeId = biomeIds[tileIndex]
		if biomeId == self.biomeId.FOREST
			or biomeId == self.biomeId.DESERT
			or biomeId == self.biomeId.SNOW
			or biomeId == self.biomeId.JUNGLE
		then
			continue
		end
		biomeIds[tileIndex] = self.biomeId.FOREST
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

	chunkDataRaw.dominantBiomeType = resolveDominantBiomeType(biomeTypes, self.biomeType.NORMAL)
	chunkDataRaw.dominantBiomeId = resolveDominantBiomeId(biomeIds, self.biomeId.FOREST)
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
	local smoothingMask = table.create(width * height, false)
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
				(walker.y + CORRUPTION_CHASM_RADIUS_OFFSET_Y - stepIndex * 0.41) * CORRUPTION_CHASM_RADIUS_NOISE_FREQUENCY,
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

			if spawnedBranches < CORRUPTION_CHASM_MAX_BRANCHES
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
		local removals = table.create(totalTiles, false)
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

function WorldGeneration.new(configRaw: WorldGenerationConfig?): WorldGeneration
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local parent = if typeof((config :: any).parent) == "Instance"
		then (config :: any).parent :: Instance
		else WorkspaceFolders.getOrCreateGameFolder()

	local chunkSize = sanitizeInteger((config :: any).chunkSize, 8, 128, DEFAULT_CHUNK_SIZE)
	local minTileY = sanitizeInteger((config :: any).minTileY, -2048, 2048, DEFAULT_MIN_TILE_Y)
	local maxTileY = sanitizeInteger((config :: any).maxTileY, -2048, 2048, DEFAULT_MAX_TILE_Y)
	local seed = sanitizeInteger((config :: any).seed, -2147483648, 2147483647, DEFAULT_SEED)

	local self = setmetatable({
		seed = seed,
		chunkSize = chunkSize,
		tileSize = FIXED_TILE_SIZE_STUDS,
		tileDepth = FIXED_TILE_DEPTH_STUDS,
		basePlaneX = clampNumber((config :: any).basePlaneX, -4096, 4096, DEFAULT_BASE_PLANE_X),
		wallPlaneOffset = clampNumber((config :: any).wallPlaneOffset, 0.1, 64, DEFAULT_WALL_PLANE_OFFSET),
		horizonDepthBlocks = sanitizeInteger(
			(config :: any).horizonDepthBlocks,
			DEFAULT_HORIZON_DEPTH_BLOCKS,
			256,
			DEFAULT_HORIZON_DEPTH_BLOCKS
		),
		backgroundLayerCount = sanitizeInteger(
			(config :: any).backgroundLayerCount,
			3,
			3,
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
		bedrockThickness = sanitizeInteger((config :: any).bedrockThickness, 0, 32, DEFAULT_BEDROCK_THICKNESS),
		defaultRenderDistanceChunks = sanitizeInteger(
			(config :: any).defaultRenderDistanceChunks,
			1,
			24,
			DEFAULT_RENDER_DISTANCE_CHUNKS
		),
		defaultVerticalRenderDistanceChunks = sanitizeInteger(
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
		maxConcurrentChunkLoads = sanitizeInteger(
			(config :: any).maxConcurrentChunkLoads,
			1,
			16,
			DEFAULT_MAX_CONCURRENT_CHUNK_LOADS
		),
		maxChunkUnloadsPerHeartbeat = sanitizeInteger(
			(config :: any).maxChunkUnloadsPerHeartbeat,
			1,
			128,
			DEFAULT_MAX_CHUNK_UNLOADS_PER_HEARTBEAT
		),
		generationRowsPerYield = sanitizeInteger(
			(config :: any).generationRowsPerYield,
			1,
			64,
			DEFAULT_GENERATION_ROWS_PER_YIELD
		),
		meshingRectsPerYield = sanitizeInteger(
			(config :: any).meshingRowsPerYield,
			1,
			128,
			DEFAULT_MESHING_RECTS_PER_YIELD
		),
		maxCachedChunkData = sanitizeInteger(
			(config :: any).maxCachedChunkData,
			16,
			4096,
			DEFAULT_MAX_CACHED_CHUNK_DATA
		),
		maxCachedChunkVisuals = sanitizeInteger(
			(config :: any).maxCachedChunkVisuals,
			0,
			512,
			DEFAULT_MAX_CACHED_CHUNK_VISUALS
		),
		maxCollisionPartsPerChunk = sanitizeInteger((config :: any).maxCollisionPartsPerChunk, 64, 20000, 4096),
		maxPoolSize = sanitizeInteger((config :: any).maxPoolSize, 64, 200000, DEFAULT_POOL_SIZE),
		debugLog = if typeof((config :: any).debugLog) == "boolean" then (config :: any).debugLog else false,
		parent = parent,
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
		chunkDemand = {} :: { [string]: number },
		chunkRevisions = {} :: { [string]: number },
		chunkOverrides = {} :: { [string]: { [number]: number } },
		chunkBiomeOverrides = {} :: { [string]: { [number]: number } },
		dirtyChunkLookup = {} :: { [string]: boolean },
		dirtyChunkQueue = {} :: { string },
		dirtyChunkQueueHead = 1,
		dirtyChunkQueueTail = 0,
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
		unloadQueue = {} :: { string },
		unloadQueueHead = 1,
		unloadQueueTail = 0,
		pendingUnloadLookup = {} :: { [string]: boolean },
		chunkRebuildQueue = {} :: { string },
		chunkRebuildQueueHead = 1,
		chunkRebuildQueueTail = 0,
		pendingRebuildLookup = {} :: { [string]: boolean },
		maxChunkRebuildsPerHeartbeat = sanitizeInteger((config :: any).maxChunkRebuildsPerHeartbeat, 1, 64, 4),
		cachePruneAccumulator = 0,
		loadedChunkAuditAccumulator = 0,
		hasPrintedJungleSideLeft = false,
		hasPrintedJungleSideRight = false,
	}, WorldGeneration)

	self.backgroundLayerThicknessBlocks = 1
	local maxLayersByDepth = math.max(2, math.floor(self.horizonDepthBlocks))
	self.backgroundLayerCount = math.min(self.backgroundLayerCount, maxLayersByDepth)

	self.cache = Cache.new({
		maxPoolSize = self.maxPoolSize,
		maxCachedChunkData = self.maxCachedChunkData,
		createPart = createPartTemplate,
	})

	local tilesFolder = resolveTilesTemplateFolder()
	self.tileTemplatesByTileId = {
		[self.tileId.STONE] = if tilesFolder ~= nil then tilesFolder:FindFirstChild("Stone") else nil,
		[self.tileId.DIRT] = if tilesFolder ~= nil then tilesFolder:FindFirstChild("Dirt") else nil,
		[self.tileId.GRASS] = if tilesFolder ~= nil then tilesFolder:FindFirstChild("Grass") else nil,
		[self.tileId.JUNGLE_GRASS] = if tilesFolder ~= nil
			then (tilesFolder:FindFirstChild("JungleGrass") or tilesFolder:FindFirstChild("Grass"))
			else nil,
		[self.tileId.CORRUPT_STONE] = if tilesFolder ~= nil then tilesFolder:FindFirstChild("CorruptStone") else nil,
		[self.tileId.CORRUPT_SOIL] = if tilesFolder ~= nil then tilesFolder:FindFirstChild("CorruptSoil") else nil,
		[self.tileId.CORRUPT_GRASS] = if tilesFolder ~= nil then tilesFolder:FindFirstChild("CorruptGrass") else nil,
	}
	self.treeVariantConfigs = createProceduralTreeVariantConfigs()

	self.biomeGenerator = Biome.new({
		seed = self.seed,
		tileId = self.tileId,
		biomeId = self.biomeId,
		biomeType = self.biomeType,
	})
	debugPrintJungleSides(self)
	self.caveGenerator = Cave.new({
		seed = self.seed,
		tileId = {
			AIR = self.tileId.AIR,
		},
		wallId = self.wallId,
		biomeId = self.biomeId,
	})
	self.structuresGenerator = Structures.new({
		seed = self.seed,
		tileId = self.tileId,
	})

	return self
end

function WorldGeneration.log(self: WorldGeneration, ...: any)
	if not self.debugLog then
		return
	end
	warn("[WorldGeneration]", ...)
end

function WorldGeneration.createFolders(self: WorldGeneration)
	if self.worldFolder ~= nil and self.worldFolder.Parent ~= nil then
		return
	end

	local worldFolder = Instance.new("Folder")
	worldFolder.Name = DEFAULT_WORLD_FOLDER_NAME
	worldFolder:SetAttribute("Seed", self.seed)
	worldFolder:SetAttribute("ChunkSize", self.chunkSize)
	worldFolder:SetAttribute("TileSize", self.tileSize)
	worldFolder:SetAttribute("TileDepth", self.tileDepth)
	worldFolder:SetAttribute("BasePlaneX", self.basePlaneX)
	worldFolder:SetAttribute("WallPlaneOffset", self.wallPlaneOffset)
	worldFolder:SetAttribute("HorizonDepthBlocks", self.horizonDepthBlocks)
	worldFolder:SetAttribute("BackgroundLayerCount", self.backgroundLayerCount)
	worldFolder:SetAttribute("WorldOriginX", self.worldOrigin.X)
	worldFolder:SetAttribute("WorldOriginY", self.worldOrigin.Y)
	worldFolder:SetAttribute("WorldOriginZ", self.worldOrigin.Z)
	worldFolder.Parent = self.parent

	local chunksFolder = Instance.new("Folder")
	chunksFolder.Name = DEFAULT_WORLD_CHUNKS_FOLDER_NAME
	chunksFolder.Parent = worldFolder

	local collisionChunksFolder = Instance.new("Folder")
	collisionChunksFolder.Name = DEFAULT_WORLD_COLLISION_FOLDER_NAME
	collisionChunksFolder.Parent = worldFolder

	self.worldFolder = worldFolder
	self.chunksFolder = chunksFolder
	self.collisionChunksFolder = collisionChunksFolder
end

function WorldGeneration.init(self: WorldGeneration)
	if self.initialized then
		return
	end

	self:createFolders()
	self.initialized = true
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:onHeartbeat(deltaTime)
	end)
end

function WorldGeneration.onHeartbeat(self: WorldGeneration, deltaTime: number)
	self:updateTrackedPlayers(deltaTime)
	self:auditLoadedChunksForUnload(deltaTime)
	self:processDirtyChunkQueue()
	self:processUnloadQueue()
	self:pumpLoadQueue()
	self:processChunkRebuildQueue()
	self:pruneChunkDataCache(deltaTime)
	self:pruneCachedChunkVisuals()
end

function WorldGeneration.isChunkYWithinWorldBounds(self: WorldGeneration, chunkY: number): boolean
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

function WorldGeneration.enqueueLoadByKey(self: WorldGeneration, chunkKey: string)
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
end

function WorldGeneration.enqueueUnloadByKey(self: WorldGeneration, chunkKey: string)
	if self.pendingUnloadLookup[chunkKey] then
		return
	end

	self.pendingUnloadLookup[chunkKey] = true
	self.unloadQueueTail += 1
	self.unloadQueue[self.unloadQueueTail] = chunkKey
end

function WorldGeneration.dequeueLoadKey(self: WorldGeneration): string?
	if self.loadQueueHead > self.loadQueueTail then
		if self.loadQueueHead ~= 1 or self.loadQueueTail ~= 0 then
			table.clear(self.loadQueue)
			self.loadQueueHead = 1
			self.loadQueueTail = 0
		end
		return nil
	end

	local chunkKey = self.loadQueue[self.loadQueueHead]
	if chunkKey == nil then
		return nil
	end

	self.loadQueue[self.loadQueueHead] = nil
	self.loadQueueHead += 1
	if self.loadQueueHead > self.loadQueueTail then
		table.clear(self.loadQueue)
		self.loadQueueHead = 1
		self.loadQueueTail = 0
	end

	return chunkKey
end

function WorldGeneration.dequeueUnloadKey(self: WorldGeneration): string?
	if self.unloadQueueHead > self.unloadQueueTail then
		if self.unloadQueueHead ~= 1 or self.unloadQueueTail ~= 0 then
			table.clear(self.unloadQueue)
			self.unloadQueueHead = 1
			self.unloadQueueTail = 0
		end
		return nil
	end

	local chunkKey = self.unloadQueue[self.unloadQueueHead]
	if chunkKey == nil then
		return nil
	end

	self.unloadQueue[self.unloadQueueHead] = nil
	self.unloadQueueHead += 1
	if self.unloadQueueHead > self.unloadQueueTail then
		table.clear(self.unloadQueue)
		self.unloadQueueHead = 1
		self.unloadQueueTail = 0
	end

	return chunkKey
end

function WorldGeneration.markChunkDirtyByKey(self: WorldGeneration, chunkKey: string)
	if self.dirtyChunkLookup[chunkKey] then
		return
	end
	self.dirtyChunkLookup[chunkKey] = true
	self.dirtyChunkQueueTail += 1
	self.dirtyChunkQueue[self.dirtyChunkQueueTail] = chunkKey
end

function WorldGeneration.dequeueDirtyChunkKey(self: WorldGeneration): string?
	if self.dirtyChunkQueueHead > self.dirtyChunkQueueTail then
		if self.dirtyChunkQueueHead ~= 1 or self.dirtyChunkQueueTail ~= 0 then
			table.clear(self.dirtyChunkQueue)
			self.dirtyChunkQueueHead = 1
			self.dirtyChunkQueueTail = 0
		end
		return nil
	end

	local chunkKey = self.dirtyChunkQueue[self.dirtyChunkQueueHead]
	if chunkKey == nil then
		return nil
	end

	self.dirtyChunkQueue[self.dirtyChunkQueueHead] = nil
	self.dirtyChunkQueueHead += 1
	if self.dirtyChunkQueueHead > self.dirtyChunkQueueTail then
		table.clear(self.dirtyChunkQueue)
		self.dirtyChunkQueueHead = 1
		self.dirtyChunkQueueTail = 0
	end

	return chunkKey
end

function WorldGeneration.enqueueChunkRebuildByKey(self: WorldGeneration, chunkKey: string)
	if self.pendingRebuildLookup[chunkKey] then
		return
	end

	self.pendingRebuildLookup[chunkKey] = true
	self.chunkRebuildQueueTail += 1
	self.chunkRebuildQueue[self.chunkRebuildQueueTail] = chunkKey
end

function WorldGeneration.dequeueChunkRebuildKey(self: WorldGeneration): string?
	if self.chunkRebuildQueueHead > self.chunkRebuildQueueTail then
		if self.chunkRebuildQueueHead ~= 1 or self.chunkRebuildQueueTail ~= 0 then
			table.clear(self.chunkRebuildQueue)
			self.chunkRebuildQueueHead = 1
			self.chunkRebuildQueueTail = 0
		end
		return nil
	end

	local chunkKey = self.chunkRebuildQueue[self.chunkRebuildQueueHead]
	if chunkKey == nil then
		return nil
	end

	self.chunkRebuildQueue[self.chunkRebuildQueueHead] = nil
	self.chunkRebuildQueueHead += 1
	if self.chunkRebuildQueueHead > self.chunkRebuildQueueTail then
		table.clear(self.chunkRebuildQueue)
		self.chunkRebuildQueueHead = 1
		self.chunkRebuildQueueTail = 0
	end

	return chunkKey
end

function WorldGeneration.processDirtyChunkQueue(self: WorldGeneration)
	local processed = 0
	local maxProcessed = 256

	while processed < maxProcessed do
		local chunkKey = self:dequeueDirtyChunkKey()
		if chunkKey == nil then
			break
		end

		processed += 1
		self.dirtyChunkLookup[chunkKey] = nil
		if self.loadedChunkVisuals[chunkKey] ~= nil then
			self:enqueueChunkRebuildByKey(chunkKey)
		end
	end
end

function WorldGeneration.processChunkRebuildQueue(self: WorldGeneration)
	local processed = 0
	while processed < self.maxChunkRebuildsPerHeartbeat do
		local chunkKey = self:dequeueChunkRebuildKey()
		if chunkKey == nil then
			break
		end

		self.pendingRebuildLookup[chunkKey] = nil
		if self.loadedChunkVisuals[chunkKey] == nil then
			continue
		end
		if self.loadingLookup[chunkKey] then
			self:enqueueChunkRebuildByKey(chunkKey)
			continue
		end

		local loadedVisual = self.loadedChunkVisuals[chunkKey]
		if loadedVisual ~= nil then
			self.loadedChunkVisuals[chunkKey] = nil
			self.loadedChunkCount = math.max(0, self.loadedChunkCount - 1)
			self:releaseChunkVisual(loadedVisual)
		end

		local cachedVisual = self.cachedChunkVisuals[chunkKey]
		if cachedVisual ~= nil then
			self.cachedChunkVisuals[chunkKey] = nil
			self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
			self:releaseChunkVisual(cachedVisual)
		end

		self:loadChunkByKey(chunkKey)
		processed += 1
	end
end

function WorldGeneration.bumpChunkRevisionByKey(self: WorldGeneration, chunkKey: string): number
	local current = self.chunkRevisions[chunkKey] or 0
	local nextRevision = current + 1
	if nextRevision >= 2147483647 then
		nextRevision = 1
	end
	self.chunkRevisions[chunkKey] = nextRevision
	return nextRevision
end

function WorldGeneration.getChunkRevisionByKey(self: WorldGeneration, chunkKey: string): number
	return self.chunkRevisions[chunkKey] or 0
end

function WorldGeneration.auditLoadedChunksForUnload(self: WorldGeneration, deltaTime: number)
	self.loadedChunkAuditAccumulator += deltaTime
	if self.loadedChunkAuditAccumulator < 0.25 then
		return
	end
	self.loadedChunkAuditAccumulator = 0

	for chunkKey in self.loadedChunkVisuals do
		if (self.chunkDemand[chunkKey] or 0) <= 0 then
			self:enqueueUnloadByKey(chunkKey)
		end
	end
end

function WorldGeneration.adjustChunkDemand(self: WorldGeneration, chunkKey: string, delta: number)
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
			self:enqueueUnloadByKey(chunkKey)
		end
		return
	end

	self.chunkDemand[chunkKey] = nextDemand
	if current == 0 then
		self:enqueueLoadByKey(chunkKey)
	end
end

function WorldGeneration.clearPlayerInterest(self: WorldGeneration, runtime: PlayerRuntime)
	for chunkKey in runtime.interestKeys do
		self:adjustChunkDemand(chunkKey, -1)
	end
	runtime.interestKeys = {}
end

function WorldGeneration.trackPlayer(
	self: WorldGeneration,
	player: Player,
	renderDistanceRaw: any?,
	verticalRenderDistanceRaw: any?
)
	if self.playerRuntimes[player] then
		self:setPlayerRenderDistance(player, renderDistanceRaw, verticalRenderDistanceRaw)
		return
	end

	local renderDistance = sanitizeInteger(renderDistanceRaw, 1, 24, self.defaultRenderDistanceChunks)
	local verticalRenderDistance =
		sanitizeInteger(verticalRenderDistanceRaw, 1, 24, self.defaultVerticalRenderDistanceChunks)

	local runtime: PlayerRuntime = {
		renderDistance = renderDistance,
		verticalRenderDistance = verticalRenderDistance,
		interestKeys = {},
		refreshAccumulator = self.playerRefreshInterval,
		forceRefresh = true,
		lastChunkX = nil,
		lastChunkY = nil,
		connections = {},
	}

	runtime.connections[1] = player.CharacterAdded:Connect(function()
		runtime.forceRefresh = true
		runtime.refreshAccumulator = self.playerRefreshInterval
	end)
	runtime.connections[2] = player.CharacterRemoving:Connect(function()
		runtime.forceRefresh = true
		runtime.refreshAccumulator = self.playerRefreshInterval
	end)

	self.playerRuntimes[player] = runtime
	self:refreshPlayerInterest(player, runtime)
end
function WorldGeneration.untrackPlayer(self: WorldGeneration, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:clearPlayerInterest(runtime)
	for _, connection in runtime.connections do
		connection:Disconnect()
	end

	self.playerRuntimes[player] = nil
end

function WorldGeneration.setPlayerRenderDistance(
	self: WorldGeneration,
	player: Player,
	renderDistanceRaw: any,
	verticalRenderDistanceRaw: any?
)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:trackPlayer(player, renderDistanceRaw, verticalRenderDistanceRaw)
		return
	end

	local nextRenderDistance = sanitizeInteger(renderDistanceRaw, 1, 24, runtime.renderDistance)
	local nextVerticalRenderDistance = sanitizeInteger(verticalRenderDistanceRaw, 1, 24, runtime.verticalRenderDistance)

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
end

function WorldGeneration.getPlayerRenderDistance(self: WorldGeneration, player: Player): (number, number)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return self.defaultRenderDistanceChunks, self.defaultVerticalRenderDistanceChunks
	end

	return runtime.renderDistance, runtime.verticalRenderDistance
end

function WorldGeneration.getPlayerInterestKeys(self: WorldGeneration, player: Player): { [string]: boolean }
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

function WorldGeneration.getPlayerRootPart(player: Player): BasePart?
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

function WorldGeneration.getPlayerFocusPosition(self: WorldGeneration, player: Player): Vector3?
	local rootPart = WorldGeneration.getPlayerRootPart(player)
	if rootPart ~= nil then
		return rootPart.Position
	end

	local character = player.Character
	if character == nil then
		return nil
	end

	local ok, pivot = pcall(function(): CFrame
		return character:GetPivot()
	end)
	if ok then
		return (pivot :: CFrame).Position
	end

	return nil
end

function WorldGeneration.refreshPlayerInterest(self: WorldGeneration, player: Player, runtimeRaw: PlayerRuntime?)
	local runtime = if runtimeRaw then runtimeRaw else self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	local focusPosition = self:getPlayerFocusPosition(player)
	if focusPosition == nil then
		if next(runtime.interestKeys) ~= nil then
			self:clearPlayerInterest(runtime)
		end
		runtime.lastChunkX = nil
		runtime.lastChunkY = nil
		runtime.forceRefresh = false
		return
	end

	local tileX = toTileCoordinate(focusPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(focusPosition.Y - self.worldOrigin.Y, self.tileSize)
	local centerChunkX = toChunkCoordinate(tileX, self.chunkSize)
	local centerChunkY = toChunkCoordinate(tileY, self.chunkSize)
	local minChunkY = toChunkCoordinate(self.minTileY, self.chunkSize)
	local maxChunkY = toChunkCoordinate(self.maxTileY, self.chunkSize)
	centerChunkY = math.clamp(centerChunkY, minChunkY, maxChunkY)

	if not runtime.forceRefresh and runtime.lastChunkX == centerChunkX and runtime.lastChunkY == centerChunkY then
		return
	end

	local nextInterest: { [string]: boolean } = {}
	local radiusSquared = runtime.renderDistance * runtime.renderDistance

	for offsetY = -runtime.verticalRenderDistance, runtime.verticalRenderDistance do
		local chunkY = centerChunkY + offsetY
		if not self:isChunkYWithinWorldBounds(chunkY) then
			continue
		end

		for offsetX = -runtime.renderDistance, runtime.renderDistance do
			if offsetX * offsetX + offsetY * offsetY > radiusSquared then
				continue
			end

			local chunkX = centerChunkX + offsetX
			nextInterest[packChunkKey(chunkX, chunkY)] = true
		end
	end

	for chunkKey in nextInterest do
		if runtime.interestKeys[chunkKey] then
			continue
		end
		self:adjustChunkDemand(chunkKey, 1)
	end

	for chunkKey in runtime.interestKeys do
		if nextInterest[chunkKey] then
			continue
		end
		self:adjustChunkDemand(chunkKey, -1)
	end

	runtime.interestKeys = nextInterest
	runtime.lastChunkX = centerChunkX
	runtime.lastChunkY = centerChunkY
	runtime.forceRefresh = false
end

function WorldGeneration.updateTrackedPlayers(self: WorldGeneration, deltaTime: number)
	for player, runtime in self.playerRuntimes do
		runtime.refreshAccumulator += deltaTime
		if runtime.forceRefresh or runtime.refreshAccumulator >= self.playerRefreshInterval then
			runtime.refreshAccumulator = 0
			self:refreshPlayerInterest(player, runtime)
		end
	end
end

function WorldGeneration.acquirePart(self: WorldGeneration): BasePart
	local cache = self.cache
	if cache == nil then
		return createPartTemplate()
	end
	return cache:acquirePart()
end

function WorldGeneration.releasePart(self: WorldGeneration, part: BasePart)
	local cache = self.cache
	if cache == nil then
		part:Destroy()
		return
	end
	cache:releasePart(part)
end

function WorldGeneration.computeTileCenterPosition(
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

function WorldGeneration.styleTerrainPart(self: WorldGeneration, part: BasePart, tileId: number)
	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	part.Name = style.name
	part.Color = style.color
	part.Material = style.material
	part.Transparency = style.transparency
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = true
end

function WorldGeneration.getTerrainTileTemplate(self: WorldGeneration, tileId: number): Instance?
	local templatesByTileId = self.tileTemplatesByTileId
	if templatesByTileId == nil then
		return nil
	end
	return templatesByTileId[tileId]
end

function WorldGeneration.placeTerrainTileTemplate(
	self: WorldGeneration,
	tileTemplate: Instance,
	parent: Instance,
	position: Vector3,
	tileId: number
): boolean
	local cloned = cloneTileTemplate(tileTemplate)
	if cloned == nil then
		return false
	end

	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	cloned.Name = style.name
	local rotationFix = if shouldApplyGrassRotationFix(self, tileId) then GRASS_TEMPLATE_X_ROTATION_FIX else CFrame.identity
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
				descendant.CastShadow = true
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
		cloned.CastShadow = true
	end

	cloned.Parent = parent
	return true
end

function WorldGeneration.placeBackgroundTileTemplate(
	self: WorldGeneration,
	tileTemplate: Instance,
	parent: Instance,
	position: Vector3,
	tileId: number,
	layerIndex: number,
	totalLayers: number
): boolean
	local cloned = cloneTileTemplate(tileTemplate)
	if cloned == nil then
		return false
	end

	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	local layerCount = math.max(1, totalLayers)
	local layerAlpha = if layerCount > 1 then (layerIndex - 1) / (layerCount - 1) else 0
	local darkenAlpha = 0.28 + layerAlpha * 0.26
	local rotationFix = if shouldApplyGrassRotationFix(self, tileId) then GRASS_TEMPLATE_X_ROTATION_FIX else CFrame.identity
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
				descendant.Color = style.color:Lerp(Color3.new(0, 0, 0), darkenAlpha)
				descendant.Material = style.material
				descendant.Transparency = 0
			end
		end
	elseif cloned:IsA("BasePart") then
		cloned.CFrame = placementCFrame
		cloned.Anchored = true
		cloned.CanCollide = false
		cloned.CanQuery = false
		cloned.CanTouch = false
		cloned.CastShadow = false
		cloned.Color = style.color:Lerp(Color3.new(0, 0, 0), darkenAlpha)
		cloned.Material = style.material
		cloned.Transparency = 0
	end

	cloned.Parent = parent
	return true
end

function WorldGeneration.placeTreeTemplate(
	self: WorldGeneration,
	treeTemplate: Instance,
	parent: Instance,
	position: Vector3
): boolean
	local cloned = cloneTileTemplate(treeTemplate)
	if cloned == nil then
		return false
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

function WorldGeneration.styleBackgroundPart(
	self: WorldGeneration,
	part: BasePart,
	tileId: number,
	layerIndex: number?,
	totalLayers: number?
)
	local style = self.tileVisuals[tileId] or self.tileVisuals[self.tileId.STONE]
	local layer = if layerIndex then layerIndex else 1
	local layerCount = math.max(1, if totalLayers then totalLayers else 1)
	local layerAlpha = if layerCount > 1 then (layer - 1) / (layerCount - 1) else 0
	part.Name = `{style.name}Background_{layer}`
	part.Color = style.color:Lerp(Color3.new(0, 0, 0), 0.28 + layerAlpha * 0.26)
	part.Material = style.material
	part.Transparency = 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

function WorldGeneration.sampleSharedBackgroundDensity(self: WorldGeneration, tileX: number, tileY: number): number
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

function WorldGeneration.shouldFillBackgroundLayer(
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

	local layerAlpha = if self.backgroundLayerCount > 1
		then (layerIndex - 1) / (self.backgroundLayerCount - 1)
		else 0

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
	local crackNoise = math.abs(math.noise(
		(tileX + BG_CRACK_OFFSET_X + layerIndex * 83.5) * crackFrequency,
		(tileY + BG_CRACK_OFFSET_Y - layerIndex * 57.8) * crackFrequency,
		(layerZ + self.seed + layerIndex * 307) * BG_SEED_Y_MULTIPLIER
	))

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

function WorldGeneration.resolveBackgroundTileIdForLayer(
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
		return self.biomeGenerator:resolveTileForDepth(column, depthBelowSurface)
	end

	if not self:shouldFillBackgroundLayer(layerIndex, sharedDensity, tileX, tileY, depthLayer, depthBelowSurface) then
		return self.tileId.AIR
	end

	local backgroundDepth = depthBelowSurface + math.max(0, layerIndex - 1)
	if depthLayer == "Deep" then
		backgroundDepth += 1
	end
	backgroundDepth = math.max(soilDepthLimit + 1, backgroundDepth)
	return self.biomeGenerator:resolveTileForDepth(column, backgroundDepth)
end

function WorldGeneration.resolveForegroundTileAt(
	self: WorldGeneration,
	column: ColumnProfile,
	worldTileX: number,
	worldTileY: number
): (number, DepthLayer, number)
	local depthLayer, depthBelowSurface = self.caveGenerator:resolveDepthLayer(column.surfaceY, worldTileY)

	local tileId = self.tileId.AIR
	if depthBelowSurface >= 0 then
		local baseTileId = self.biomeGenerator:resolveTileForDepth(column, depthBelowSurface)
		local isBedrock = worldTileY <= self.minTileY + self.bedrockThickness
		if isBedrock then
			tileId = self.tileId.STONE
		else
			local shouldCarve = self.caveGenerator:shouldCarve(
				worldTileX,
				worldTileY,
				column.biomeId,
				depthLayer,
				depthBelowSurface
			)
			if shouldCarve then
				tileId = self.tileId.AIR
			else
				tileId = self.structuresGenerator:resolveOreTile(
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

function WorldGeneration.isTreeAnchorTile(self: WorldGeneration, worldTileX: number): boolean
	local treeCell = math.floor(worldTileX / TREE_SPACING_TILES)
	local slotAlpha = math.clamp(
		(math.noise(
			(treeCell + 0.5) * TREE_SLOT_NOISE_FREQUENCY,
			self.seed * BG_SEED_Y_MULTIPLIER,
			73.4
		) + 1)
			* 0.5,
		0,
		1
	)
	local slot = math.clamp(math.floor(slotAlpha * TREE_SPACING_TILES), 0, TREE_SPACING_TILES - 1)
	return worldTileX == treeCell * TREE_SPACING_TILES + slot
end

function WorldGeneration.resolveTreeTemplateIndex(
	self: WorldGeneration,
	worldTileX: number,
	surfaceTileY: number,
	biomeType: number,
	biomeId: number
): number?
	if not self:isTreeAnchorTile(worldTileX) then
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
		(math.noise(
			(worldTileX + 179.3) * TREE_VARIANT_NOISE_FREQUENCY_X,
			(surfaceTileY - 61.7) * TREE_VARIANT_NOISE_FREQUENCY_Y,
			self.seed * BG_SEED_X_MULTIPLIER
		) + 1)
			* 0.5,
		0,
		1
	)
	local variantSlot = resolveTreeVariantIndexByAlpha(#matchingVariants, variantAlpha)
	return matchingVariants[variantSlot]
end

function WorldGeneration.hasTreeAirClearance(
	self: WorldGeneration,
	column: ColumnProfile,
	worldTileX: number,
	surfaceTileY: number
): boolean
	for offset = 1, TREE_REQUIRED_AIR_CLEARANCE do
		local scanTileY = surfaceTileY + offset
		if scanTileY > self.maxTileY then
			continue
		end

		local scanTileId = self:resolveForegroundTileAt(column, worldTileX, scanTileY)
		if scanTileId ~= self.tileId.AIR then
			return false
		end
	end

	return true
end

function WorldGeneration.generateChunkData(self: WorldGeneration, chunkX: number, chunkY: number): ChunkData
	local width = self.chunkSize
	local height = self.chunkSize
	local tileMinX = chunkX * width
	local tileMinY = chunkY * height
	local tiles = table.create(width * height, self.tileId.AIR)
	local depthLayers = table.create(width * height, DEPTH_LAYER_CODE.SKY)
	local depthBelowSurface = table.create(width * height, -1)
	local biomeIds = table.create(width * height, self.biomeId.FOREST)
	local biomeTypes = table.create(width * height, self.biomeType.NORMAL)
	local backgroundPadding = BACKGROUND_LAYER_BOUNDS_PADDING_TILES
	local backgroundWidth = width + backgroundPadding * 2
	local backgroundHeight = height + backgroundPadding * 2
	local backgroundTileMinX = tileMinX - backgroundPadding
	local backgroundTileMinY = tileMinY - backgroundPadding
	local backgroundLayers: { BackgroundLayerData } = table.create(self.backgroundLayerCount)
	for layerIndex = 1, self.backgroundLayerCount do
		backgroundLayers[layerIndex] = {
			layerIndex = layerIndex,
			tileMinX = backgroundTileMinX,
			tileMinY = backgroundTileMinY,
			width = backgroundWidth,
			height = backgroundHeight,
			tiles = table.create(backgroundWidth * backgroundHeight, self.tileId.AIR),
		}
	end
	local backgroundColumnProfiles: { ColumnProfile } = table.create(backgroundWidth)
	local columnProfiles: { ColumnProfile } = table.create(width)
	local biomeBlendColumnCache = {} :: { [number]: ColumnProfile }
	local biomeBlendAxisCache = {} :: { [number]: BiomeBlendAxisData }
	local biomeBlendClusterCache = {} :: { [string]: ColumnProfile }

	local function getColumnProfileForBlend(worldTileX: number): ColumnProfile
		local cached = biomeBlendColumnCache[worldTileX]
		if cached ~= nil then
			return cached
		end

		local sampled = self.biomeGenerator:getColumnProfile(worldTileX)
		biomeBlendColumnCache[worldTileX] = sampled
		return sampled
	end

	local function resolveBiomeBlendAxisData(clusterX: number): BiomeBlendAxisData
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

	local function resolveClusterBlendedColumn(
		worldTileX: number,
		worldTileY: number,
		depthBelowSurface: number,
		baseColumn: ColumnProfile
	): ColumnProfile
		if depthBelowSurface < 0 or depthBelowSurface > BIOME_BLEND_NEAR_SURFACE_DEPTH then
			return baseColumn
		end

		local clusterX = math.floor(worldTileX / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterY = math.floor(worldTileY / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterZ = math.floor(depthBelowSurface / BIOME_BLEND_CLUSTER_SIZE_TILES)
		local clusterKey = `{clusterX}:{clusterY}:{clusterZ}`
		local cached = biomeBlendClusterCache[clusterKey]
		if cached ~= nil then
			return cached
		end

		local axisData = resolveBiomeBlendAxisData(clusterX)
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
			local blendFactor = math.clamp(
				distanceAlpha * (1 - BIOME_BLEND_NOISE_WEIGHT) + noiseAlpha * BIOME_BLEND_NOISE_WEIGHT,
				0,
				1
			)
			local secondaryChance = BIOME_BLEND_MIN_SECONDARY_CHANCE
				+ (BIOME_BLEND_MAX_SECONDARY_CHANCE - BIOME_BLEND_MIN_SECONDARY_CHANCE) * blendFactor
			local roll = deterministicUnitInterval(self.seed, clusterX, clusterY, clusterZ, BIOME_BLEND_CLUSTER_ROLL_SALT)
			if roll < secondaryChance then
				selectedColumn = secondaryColumn
			end
		end

		biomeBlendClusterCache[clusterKey] = selectedColumn
		return selectedColumn
	end

	for localX = 0, backgroundWidth - 1 do
		local worldTileX = backgroundTileMinX + localX
		local column = self.biomeGenerator:getColumnProfile(worldTileX)
		backgroundColumnProfiles[localX + 1] = column
		biomeBlendColumnCache[worldTileX] = column
		if column.biomeId == self.biomeId.JUNGLE then
			if worldTileX < 0 and not self.hasPrintedJungleSideLeft then
				self.hasPrintedJungleSideLeft = true
				print(`[WorldGeneration] Jungle detected on LEFT side (tileX={worldTileX})`)
			elseif worldTileX >= 0 and not self.hasPrintedJungleSideRight then
				self.hasPrintedJungleSideRight = true
				print(`[WorldGeneration] Jungle detected on RIGHT side (tileX={worldTileX})`)
			end
		end
	end

	for localX = 0, width - 1 do
		columnProfiles[localX + 1] = backgroundColumnProfiles[localX + backgroundPadding + 1]
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

			local _, blendDepthBelowSurface = self.caveGenerator:resolveDepthLayer(baseColumn.surfaceY, worldTileY)
			local column = resolveClusterBlendedColumn(worldTileX, worldTileY, blendDepthBelowSurface, baseColumn)
			biomeIds[index] = column.biomeId
			biomeTypes[index] = column.biomeType
			local tileId, depthLayer, tileDepthBelowSurface = self:resolveForegroundTileAt(column, worldTileX, worldTileY)
			tiles[index] = tileId
			depthLayers[index] = encodeDepthLayer(depthLayer)
			depthBelowSurface[index] = tileDepthBelowSurface
		end

		if localY > 0 and localY % self.generationRowsPerYield == 0 then
			task.wait()
		end
	end

	carveCorruptionChasmsForChunk(self, chunkX, chunkY, tileMinX, tileMinY, width, height, tiles, biomeTypes, columnProfiles)

	for localY = 0, backgroundHeight - 1 do
		local worldTileY = backgroundTileMinY + localY
		if worldTileY < self.minTileY or worldTileY > self.maxTileY then
			continue
		end

		for localX = 0, backgroundWidth - 1 do
			local worldTileX = backgroundTileMinX + localX
			local column = backgroundColumnProfiles[localX + 1]
			local _, depthLayer, depthBelowSurface = self:resolveForegroundTileAt(column, worldTileX, worldTileY)
			if depthBelowSurface < 0 then
				continue
			end

			local backgroundIndex = computeTileIndex(localX, localY, backgroundWidth)
			local sharedBackgroundDensity = self:sampleSharedBackgroundDensity(worldTileX, worldTileY)
			for layerIndex = 1, self.backgroundLayerCount do
				local layerData = backgroundLayers[layerIndex]
				local backgroundTileId = self:resolveBackgroundTileIdForLayer(
					layerIndex,
					column,
					sharedBackgroundDensity,
					worldTileX,
					worldTileY,
					depthLayer,
					depthBelowSurface
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

	local foregroundAnchorTiles = table.create(backgroundWidth * backgroundHeight, self.tileId.AIR)
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
				local column = backgroundColumnProfiles[localX + 1]
				local _, depthLayer, depthBelowSurface = self:resolveForegroundTileAt(column, worldTileX, worldTileY)
				if depthBelowSurface < 0 then
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

				local connectionDepth = math.max(0, depthBelowSurface + layerIndex - 1)
				currentTiles[index] = self.biomeGenerator:resolveTileForDepth(column, connectionDepth)
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
				local column = backgroundColumnProfiles[localX + 1]
				local _, _, depthBelowSurface = self:resolveForegroundTileAt(column, worldTileX, worldTileY)
				if depthBelowSurface < 0 then
					continue
				end

				lastLayerTiles[index] =
					self.biomeGenerator:resolveTileForDepth(column, depthBelowSurface + self.backgroundLayerCount)
			end

			if localY > 0 and localY % self.generationRowsPerYield == 0 then
				task.wait()
			end
		end
	end

	local trees: { TreeSpawnData } = {}
	local props: { PropSpawnData } = {}
	local chunkTileMaxY = tileMinY + height - 1
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

		local hasAirClearance = self:hasTreeAirClearance(column, worldTileX, surfaceTileY)
		local treeVariantIndex = self:resolveTreeTemplateIndex(worldTileX, surfaceTileY, column.biomeType, column.biomeId)
		if treeVariantIndex ~= nil and hasAirClearance then
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
		end
	end

	local dominantBiomeType = resolveDominantBiomeType(biomeTypes, self.biomeType.NORMAL)
	local dominantBiomeId = resolveDominantBiomeId(biomeIds, self.biomeId.FOREST)

	local now = os.clock()
	return {
		key = packChunkKey(chunkX, chunkY),
		chunkX = chunkX,
		chunkY = chunkY,
		tileMinX = tileMinX,
		tileMinY = tileMinY,
		width = width,
		height = height,
		tiles = tiles,
		depthLayers = depthLayers,
		depthBelowSurface = depthBelowSurface,
		biomeIds = biomeIds,
		biomeTypes = biomeTypes,
		dominantBiomeId = dominantBiomeId,
		dominantBiomeType = dominantBiomeType,
		backgroundLayers = backgroundLayers,
		trees = trees,
		props = props,
		generatedAt = now,
		lastAccessedAt = now,
	}
end

function WorldGeneration.getOrGenerateChunkData(self: WorldGeneration, chunkX: number, chunkY: number): ChunkData
	local key = packChunkKey(chunkX, chunkY)
	local cache = self.cache
	local cached = if cache then cache:getChunkData(key) :: ChunkData? else nil
	if cached then
		ensureChunkBiomeMetadata(self, cached)
		return cached
	end

	local generated = self:generateChunkData(chunkX, chunkY)
	ensureChunkBiomeMetadata(self, generated)
	local chunkOverrides = self.chunkOverrides[key]
	if chunkOverrides ~= nil then
		for tileIndex, overrideTileId in chunkOverrides do
			if tileIndex >= 1 and tileIndex <= #generated.tiles then
				generated.tiles[tileIndex] = overrideTileId
			end
		end
	end

	local chunkBiomeOverrides = self.chunkBiomeOverrides[key]
	if chunkBiomeOverrides ~= nil then
		for tileIndex, overrideBiomeType in chunkBiomeOverrides do
			if tileIndex >= 1 and tileIndex <= #generated.biomeTypes then
				generated.biomeTypes[tileIndex] = overrideBiomeType
				generated.tiles[tileIndex] = self.biomeGenerator:convertTileToBiomeType(
					generated.tiles[tileIndex],
					overrideBiomeType
				)
			end
		end
		generated.dominantBiomeType = resolveDominantBiomeType(generated.biomeTypes, self.biomeType.NORMAL)
	end

	if cache then
		cache:setChunkData(key, generated)
	end
	return generated
end

function WorldGeneration.buildGreedyRectangles(
	self: WorldGeneration,
	values: { number },
	width: number,
	height: number,
	shouldInclude: (value: number, index: number) -> boolean
): { GreedyRect }
	local rectangles: { GreedyRect } = {}
	local visited: { boolean } = table.create(width * height, false)

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

function WorldGeneration.buildChunkVisual(self: WorldGeneration, chunkData: ChunkData): ChunkVisual
	local collisionChunksFolder = self.collisionChunksFolder
	if collisionChunksFolder == nil then
		self:createFolders()
		collisionChunksFolder = self.collisionChunksFolder :: Folder
	end

	local model = Instance.new("Model")
	model.Name = `CollisionChunk_{chunkData.chunkX}_{chunkData.chunkY}`
	model:SetAttribute("ChunkX", chunkData.chunkX)
	model:SetAttribute("ChunkY", chunkData.chunkY)
	model:SetAttribute("ChunkKey", chunkData.key)
	model:SetAttribute("ChunkRevision", self.chunkRevisions[chunkData.key] or 0)
	model:SetAttribute("DominantBiomeId", chunkData.dominantBiomeId)
	model:SetAttribute("DominantBiomeType", chunkData.dominantBiomeType)
	model:SetAttribute("IsCorruptionChunk", chunkData.dominantBiomeType == self.biomeType.CORRUPTION)

	local terrainFolder = Instance.new("Folder")
	terrainFolder.Name = "Terrain"
	terrainFolder.Parent = model

	local parts: { BasePart } = {}
	local collisionRects = self:buildGreedyRectangles(
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
		local part = self:acquirePart()
		part.Name = "Collision"
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
		part.CFrame = CFrame.new(self:computeTileCenterPosition(centerTileX, centerTileY, 0))
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

function WorldGeneration.attachChunkVisual(self: WorldGeneration, visual: ChunkVisual)
	local collisionChunksFolder = self.collisionChunksFolder
	if collisionChunksFolder == nil then
		self:createFolders()
		collisionChunksFolder = self.collisionChunksFolder :: Folder
	end

	visual.model.Parent = collisionChunksFolder
	local now = os.clock()
	visual.loadedAt = now
	visual.lastAccessedAt = now
end

function WorldGeneration.takeCachedChunkVisual(self: WorldGeneration, chunkKey: string): ChunkVisual?
	local cachedVisual = self.cachedChunkVisuals[chunkKey]
	if cachedVisual == nil then
		return nil
	end

	self.cachedChunkVisuals[chunkKey] = nil
	self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
	cachedVisual.lastAccessedAt = os.clock()
	return cachedVisual
end

function WorldGeneration.pruneCachedChunkVisuals(self: WorldGeneration)
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
			self:releaseChunkVisual(visual)
		end
	end
end

function WorldGeneration.cacheChunkVisual(self: WorldGeneration, chunkKey: string, visual: ChunkVisual)
	if self.maxCachedChunkVisuals <= 0 then
		self:releaseChunkVisual(visual)
		return
	end

	if visual.model.Parent ~= nil then
		visual.model.Parent = nil
	end
	visual.lastAccessedAt = os.clock()

	local existing = self.cachedChunkVisuals[chunkKey]
	if existing == visual then
		return
	end
	if existing ~= nil and existing ~= visual then
		self:releaseChunkVisual(existing)
	else
		self.cachedChunkVisualCount += 1
	end
	self.cachedChunkVisuals[chunkKey] = visual
	self:pruneCachedChunkVisuals()
end

function WorldGeneration.releaseChunkVisual(self: WorldGeneration, visual: ChunkVisual)
	for _, part in visual.parts do
		if part.Parent ~= nil then
			part.Parent = nil
		end
		self:releasePart(part)
	end
	table.clear(visual.parts)
	visual.model:Destroy()
end

function WorldGeneration.unloadChunkByKey(self: WorldGeneration, chunkKey: string)
	local visual = self.loadedChunkVisuals[chunkKey]
	if visual == nil then
		return
	end

	self.loadedChunkVisuals[chunkKey] = nil
	self.loadedChunkCount = math.max(0, self.loadedChunkCount - 1)
	self:cacheChunkVisual(chunkKey, visual)
end

function WorldGeneration.loadChunkByKey(self: WorldGeneration, chunkKey: string)
	if self.loadedChunkVisuals[chunkKey] ~= nil then
		return
	end

	local chunkX, chunkY = unpackChunkKey(chunkKey)
	if chunkX == nil or chunkY == nil then
		return
	end

	if not self:isChunkYWithinWorldBounds(chunkY) then
		return
	end

	local cachedVisual = self:takeCachedChunkVisual(chunkKey)
	if cachedVisual ~= nil then
		if (self.chunkDemand[chunkKey] or 0) > 0 then
			self:attachChunkVisual(cachedVisual)
			self.loadedChunkVisuals[chunkKey] = cachedVisual
			self.loadedChunkCount += 1
		else
			self:cacheChunkVisual(chunkKey, cachedVisual)
		end
		return
	end

	local chunkData = self:getOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	if (self.chunkDemand[chunkKey] or 0) <= 0 then
		return
	end

	if self.loadedChunkVisuals[chunkKey] ~= nil then
		return
	end

	local visual = self:buildChunkVisual(chunkData)
	if (self.chunkDemand[chunkKey] or 0) <= 0 then
		self:releaseChunkVisual(visual)
		return
	end

	self.loadedChunkVisuals[chunkKey] = visual
	self.loadedChunkCount += 1
end

function WorldGeneration.processUnloadQueue(self: WorldGeneration)
	local queueDepth = math.max(0, self.unloadQueueTail - self.unloadQueueHead + 1)
	local unloadBudget = self.maxChunkUnloadsPerHeartbeat
	if queueDepth > unloadBudget then
		unloadBudget = math.min(256, math.max(unloadBudget, math.ceil(queueDepth * 0.35)))
	end

	local processed = 0
	while processed < unloadBudget do
		local chunkKey = self:dequeueUnloadKey()
		if chunkKey == nil then
			break
		end

		self.pendingUnloadLookup[chunkKey] = nil
		if (self.chunkDemand[chunkKey] or 0) > 0 then
			continue
		end

		self:unloadChunkByKey(chunkKey)
		processed += 1
	end
end

function WorldGeneration.pumpLoadQueue(self: WorldGeneration)
	while self.activeLoadWorkers < self.maxConcurrentChunkLoads do
		local chunkKey = self:dequeueLoadKey()
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

		task.spawn(function()
			local ok, err = pcall(function()
				self:loadChunkByKey(chunkKey)
			end)
			if not ok then
				warn("[WorldGeneration] Chunk load failed:", chunkKey, tostring(err))
			end
			self.loadingLookup[chunkKey] = nil
			self.activeLoadWorkers = math.max(0, self.activeLoadWorkers - 1)
		end)
	end
end

function WorldGeneration.pruneChunkDataCache(self: WorldGeneration, deltaTime: number)
	self.cachePruneAccumulator += deltaTime
	if self.cachePruneAccumulator < 0.9 then
		return
	end
	self.cachePruneAccumulator = 0

	local cache = self.cache
	if cache == nil then
		return
	end

	cache:pruneChunkData(function(chunkKey: string): boolean
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

function WorldGeneration.getTileAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): (number, number)
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
	if not self:isChunkYWithinWorldBounds(chunkY) then
		return self.tileId.AIR, self.wallId.NONE
	end

	local chunkData = self:getOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()

	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return self.tileId.AIR, self.wallId.NONE
	end

	local index = computeTileIndex(localX, localY, chunkData.width)
	return chunkData.tiles[index], self.wallId.NONE
end

function WorldGeneration.getBiomeTypeAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): number
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
	if not self:isChunkYWithinWorldBounds(chunkY) then
		return self.biomeType.NORMAL
	end

	local chunkData = self:getOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return chunkData.dominantBiomeType
	end

	local index = computeTileIndex(localX, localY, chunkData.width)
	return chunkData.biomeTypes[index] or chunkData.dominantBiomeType
end

function WorldGeneration.getBiomeIdAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any): number
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
	if not self:isChunkYWithinWorldBounds(chunkY) then
		return self.biomeId.FOREST
	end

	local chunkData = self:getOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	local localX = tileX - chunkData.tileMinX
	local localY = tileY - chunkData.tileMinY
	if localX < 0 or localX >= chunkData.width or localY < 0 or localY >= chunkData.height then
		return chunkData.dominantBiomeId
	end

	local index = computeTileIndex(localX, localY, chunkData.width)
	return chunkData.biomeIds[index] or chunkData.dominantBiomeId
end

function WorldGeneration.getTileAtWorldPosition(self: WorldGeneration, worldPosition: Vector3): (number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:getTileAt(tileX, tileY)
end

function WorldGeneration.getBiomeTypeAtWorldPosition(self: WorldGeneration, worldPosition: Vector3): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:getBiomeTypeAt(tileX, tileY)
end

function WorldGeneration.getBiomeIdAtWorldPosition(self: WorldGeneration, worldPosition: Vector3): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:getBiomeIdAt(tileX, tileY)
end

function WorldGeneration.getChunkData(self: WorldGeneration, chunkXRaw: any, chunkYRaw: any): ChunkData?
	if not isFiniteNumber(chunkXRaw) or not isFiniteNumber(chunkYRaw) then
		return nil
	end

	local chunkX = math.floor(chunkXRaw :: number)
	local chunkY = math.floor(chunkYRaw :: number)
	if not self:isChunkYWithinWorldBounds(chunkY) then
		return nil
	end

	local chunkData = self:getOrGenerateChunkData(chunkX, chunkY)
	chunkData.lastAccessedAt = os.clock()
	return chunkData
end

function WorldGeneration.getChunkDataByKey(self: WorldGeneration, chunkKeyRaw: any): ChunkData?
	if typeof(chunkKeyRaw) ~= "string" then
		return nil
	end

	local chunkX, chunkY = unpackChunkKey(chunkKeyRaw)
	if chunkX == nil or chunkY == nil then
		return nil
	end
	return self:getChunkData(chunkX, chunkY)
end

function WorldGeneration.getChunkDominantBiomeTypeByKey(self: WorldGeneration, chunkKeyRaw: any): number
	local chunkData = self:getChunkDataByKey(chunkKeyRaw)
	if chunkData == nil then
		return self.biomeType.NORMAL
	end
	return chunkData.dominantBiomeType
end

function WorldGeneration.getChunkSnapshotByKey(self: WorldGeneration, chunkKeyRaw: any): { [string]: any }?
	local chunkData = self:getChunkDataByKey(chunkKeyRaw)
	if chunkData == nil then
		return nil
	end

	local backgroundLayersSnapshot = table.create(#chunkData.backgroundLayers)
	for layerIndex, layerData in chunkData.backgroundLayers do
		backgroundLayersSnapshot[layerIndex] = {
			layerIndex = layerData.layerIndex,
			tileMinX = layerData.tileMinX,
			tileMinY = layerData.tileMinY,
			width = layerData.width,
			height = layerData.height,
			tiles = table.clone(layerData.tiles),
		}
	end

	local treesSnapshot = table.create(#chunkData.trees)
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

	local propsSnapshot = table.create(#chunkData.props)
	for propIndex, propData in chunkData.props do
		propsSnapshot[propIndex] = {
			tileX = propData.tileX,
			tileY = propData.tileY,
			propId = propData.propId,
			variantIndex = propData.variantIndex,
			seed = propData.seed,
			biomeType = propData.biomeType,
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
		tiles = table.clone(chunkData.tiles),
		depthLayers = table.clone(chunkData.depthLayers),
		depthBelowSurface = table.clone(chunkData.depthBelowSurface),
		biomeIds = table.clone(chunkData.biomeIds),
		biomeTypes = table.clone(chunkData.biomeTypes),
		dominantBiomeId = chunkData.dominantBiomeId,
		dominantBiomeType = chunkData.dominantBiomeType,
		backgroundLayers = backgroundLayersSnapshot,
		trees = treesSnapshot,
		props = propsSnapshot,
		revision = self:getChunkRevisionByKey(chunkData.key),
	}
end

function WorldGeneration.setTileAt(self: WorldGeneration, tileXRaw: any, tileYRaw: any, tileIdRaw: any): (boolean, number, number)
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
	if nextTileId < self.tileId.AIR or nextTileId > self.tileId.JUNGLE_GRASS then
		return false, self.tileId.AIR, self.tileId.AIR
	end

	local chunkX = toChunkCoordinate(tileX, self.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.chunkSize)
	if not self:isChunkYWithinWorldBounds(chunkY) then
		return false, self.tileId.AIR, self.tileId.AIR
	end

	local chunkData = self:getOrGenerateChunkData(chunkX, chunkY)
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
	local function touchChunk(chunkKey: string)
		if touchedChunkKeys[chunkKey] then
			return
		end
		touchedChunkKeys[chunkKey] = true
		self:bumpChunkRevisionByKey(chunkKey)
		self:markChunkDirtyByKey(chunkKey)

		local cachedVisual = self.cachedChunkVisuals[chunkKey]
		if cachedVisual ~= nil then
			self.cachedChunkVisuals[chunkKey] = nil
			self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
			self:releaseChunkVisual(cachedVisual)
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
		if self:isChunkYWithinWorldBounds(belowChunkY) then
			touchChunk(packChunkKey(chunkX, belowChunkY))
		end
	elseif localY == chunkData.height - 1 then
		local aboveChunkY = chunkY + 1
		if self:isChunkYWithinWorldBounds(aboveChunkY) then
			touchChunk(packChunkKey(chunkX, aboveChunkY))
		end
	end

	return true, previousTileId, nextTileId
end

function WorldGeneration.setBiomeTypeAt(
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
	if not self:isChunkYWithinWorldBounds(chunkY) then
		return false, self.biomeType.NORMAL, self.biomeType.NORMAL
	end

	local chunkData = self:getOrGenerateChunkData(chunkX, chunkY)
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
	chunkData.tiles[tileIndex] = self.biomeGenerator:convertTileToBiomeType(chunkData.tiles[tileIndex], nextBiomeType)
	chunkData.dominantBiomeType = resolveDominantBiomeType(chunkData.biomeTypes, self.biomeType.NORMAL)

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
		self:bumpChunkRevisionByKey(chunkKey)
		self:markChunkDirtyByKey(chunkKey)

		local cachedVisual = self.cachedChunkVisuals[chunkKey]
		if cachedVisual ~= nil then
			self.cachedChunkVisuals[chunkKey] = nil
			self.cachedChunkVisualCount = math.max(0, self.cachedChunkVisualCount - 1)
			self:releaseChunkVisual(cachedVisual)
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
		if self:isChunkYWithinWorldBounds(belowChunkY) then
			touchChunk(packChunkKey(chunkX, belowChunkY))
		end
	elseif localY == chunkData.height - 1 then
		local aboveChunkY = chunkY + 1
		if self:isChunkYWithinWorldBounds(aboveChunkY) then
			touchChunk(packChunkKey(chunkX, aboveChunkY))
		end
	end

	return true, previousBiomeType, nextBiomeType
end

function WorldGeneration.setTileAtWorldPosition(
	self: WorldGeneration,
	worldPosition: Vector3,
	tileIdRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:setTileAt(tileX, tileY, tileIdRaw)
end

function WorldGeneration.setBiomeTypeAtWorldPosition(
	self: WorldGeneration,
	worldPosition: Vector3,
	biomeTypeRaw: any
): (boolean, number, number)
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.tileSize)
	return self:setBiomeTypeAt(tileX, tileY, biomeTypeRaw)
end

function WorldGeneration.forceRefreshAllPlayers(self: WorldGeneration)
	for _, runtime in self.playerRuntimes do
		runtime.forceRefresh = true
		runtime.refreshAccumulator = self.playerRefreshInterval
	end
end

function WorldGeneration.getStats(self: WorldGeneration): { [string]: any }
	local demandedChunks = 0
	for _ in self.chunkDemand do
		demandedChunks += 1
	end

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
		cachedChunkData = if self.cache then self.cache:getCachedChunkCount() else 0,
		cachedChunkVisuals = self.cachedChunkVisualCount,
		demandedChunks = demandedChunks,
		pooledParts = if self.cache then self.cache:getPooledPartCount() else 0,
		activeLoadWorkers = self.activeLoadWorkers,
		queuedLoads = math.max(0, self.loadQueueTail - self.loadQueueHead + 1),
		queuedUnloads = math.max(0, self.unloadQueueTail - self.unloadQueueHead + 1),
		queuedDirtyChunks = math.max(0, self.dirtyChunkQueueTail - self.dirtyChunkQueueHead + 1),
		queuedChunkRebuilds = math.max(0, self.chunkRebuildQueueTail - self.chunkRebuildQueueHead + 1),
		treeVariants = #self.treeVariantConfigs,
		trackedPlayers = #self:getTrackedPlayers(),
		minTileY = self.minTileY,
		maxTileY = self.maxTileY,
	}
end

function WorldGeneration.getTrackedPlayers(self: WorldGeneration): { Player }
	local players: { Player } = {}
	for player in self.playerRuntimes do
		table.insert(players, player)
	end
	return players
end

function WorldGeneration.destroy(self: WorldGeneration)
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	local trackedPlayers = self:getTrackedPlayers()
	for _, player in trackedPlayers do
		self:untrackPlayer(player)
	end

	local loadedChunkKeys = {}
	for chunkKey in self.loadedChunkVisuals do
		table.insert(loadedChunkKeys, chunkKey)
	end
	for _, chunkKey in loadedChunkKeys do
		self:unloadChunkByKey(chunkKey)
	end

	for chunkKey, visual in self.cachedChunkVisuals do
		self.cachedChunkVisuals[chunkKey] = nil
		self:releaseChunkVisual(visual)
	end
	self.cachedChunkVisualCount = 0

	if self.cache then
		self.cache:destroy()
		self.cache = nil
	end

	table.clear(self.pendingLoadLookup)
	table.clear(self.pendingUnloadLookup)
	table.clear(self.pendingRebuildLookup)
	table.clear(self.dirtyChunkLookup)
	table.clear(self.loadingLookup)
	table.clear(self.chunkDemand)
	table.clear(self.chunkRevisions)
	table.clear(self.chunkOverrides)
	table.clear(self.chunkBiomeOverrides)
	table.clear(self.loadQueue)
	table.clear(self.unloadQueue)
	table.clear(self.dirtyChunkQueue)
	table.clear(self.chunkRebuildQueue)
	self.loadQueueHead = 1
	self.loadQueueTail = 0
	self.unloadQueueHead = 1
	self.unloadQueueTail = 0
	self.dirtyChunkQueueHead = 1
	self.dirtyChunkQueueTail = 0
	self.chunkRebuildQueueHead = 1
	self.chunkRebuildQueueTail = 0

	if self.worldFolder then
		self.worldFolder:Destroy()
		self.worldFolder = nil
		self.chunksFolder = nil
		self.collisionChunksFolder = nil
	end

	self.initialized = false
end

return WorldGeneration
