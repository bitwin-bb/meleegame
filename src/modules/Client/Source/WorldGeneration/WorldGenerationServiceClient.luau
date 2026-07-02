local require = require(script.Parent.loader).load(script)

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BuildServiceUtils = require("BuildServiceUtils")
local Configs = require("CoreConfigs")
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local WorldGenerationServicePackets = require("NetPacketsShared").WorldGenerationService

local function sendPacket(methodName: string, ...: any)
	local packet = WorldGenerationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldGenerationService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = WorldGenerationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for WorldGenerationService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyState")
	bindPacket(self, "onChunkSnapshot")
	bindPacket(self, "onChunkUnloaded")
	bindPacket(self, "requestSync")
	bindPacket(self, "setRenderDistance")
end

local OreRegistry = require("Ores")
local PlantRegistry = require("Plants")
local ProceduralCactus = require("WorldGenerationCactus")
local ProceduralTree = require("WorldGenerationTree")
local Queue = require("Queue")
local Signal = require("Signal")
local TagBinder = require("TagBinder")
local TileComponent = require("Tile")
local TileMaterial = require("TileMaterial")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationColor = require("WorldGenerationColor")
local WorldGenerationServiceUtils = require("WorldGenerationServiceUtils")

type WorldGenerationServiceState = WorldGenerationServiceUtils.WorldGenerationServiceState
type ProceduralTreeConfig = ProceduralTree.ProceduralTreeConfig

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type QueueClass<T> = {
	GetCount: (self: QueueClass<T>) -> number,
	IsEmpty: (self: QueueClass<T>) -> boolean,
	PushRight: (self: QueueClass<T>, value: T) -> (),
	PopLeft: (self: QueueClass<T>) -> T,
}

type ChunkLayerSnapshot = {
	layerIndex: number,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tiles: { number },
}

type TreeSpawnSnapshot = {
	tileX: number,
	tileY: number,
	variantIndex: number,
	seed: number,
	biomeType: number?,
	biomeId: number?,
	templateIndex: number?,
}

type PropSpawnSnapshot = {
	tileX: number,
	tileY: number,
	propId: number,
	variantIndex: number,
	seed: number,
	biomeType: number?,
	biomeId: number?,
}

type ChunkSnapshot = {
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
	surfaceBiomeIds: { number },
	biomeTypes: { number },
	dominantBiomeId: number,
	dominantBiomeType: number,
	backgroundLayers: { ChunkLayerSnapshot },
	trees: { TreeSpawnSnapshot },
	props: { PropSpawnSnapshot },
	revision: number,
}

type TileVisual = {
	name: string,
	color: Color3,
	material: Enum.Material,
	transparency: number,
}

type GreedyRect = {
	x: number,
	y: number,
	width: number,
	height: number,
	value: number,
}

type TerrainRectRuntime = {
	part: Part,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tileId: number,
}

type TerrainHoverRuntime = {
	chunkKey: string,
	tileX: number,
	tileY: number,
	localTileX: number,
	localTileY: number,
	width: number,
	height: number,
	originalPart: Part,
	originalPartTransparency: number,
	hoverPart: Part,
	highlight: SelectionBox,
	hoverProxyPart: Part,
	replacementParts: { BasePart },
}

type ChunkVisualRuntime = {
	model: Model,
	partCount: number,
	revision: number,
	builtAt: number,
	treeSignature: string,
	propSignature: string,
	terrainHoverFolder: Folder?,
	terrainLayerModel: Model?,
	backgroundLayerModelsByLayer: { Model },
	terrainParts: { BasePart },
	backgroundPartsByLayer: { { BasePart } },
	terrainRects: { TerrainRectRuntime },
	terrainRectByLocalTileIndex: { number },
}

type ChunkVisualBuildJob = {
	chunkKey: string,
	snapshot: ChunkSnapshot,
	model: Model,
	partCount: number,
	terrainParts: { BasePart },
	backgroundPartsByLayer: { { BasePart } },
	terrainRects: { TerrainRectRuntime },
	terrainRectByLocalTileIndex: { number },
	terrainGreedyRects: { GreedyRect },
	terrainRectIndex: number,
	backgroundLayerIndex: number,
	backgroundRects: { GreedyRect }?,
	backgroundRectIndex: number,
	treeIndex: number,
	treeCount: number,
	treesFolder: Folder?,
	propIndex: number,
	propCount: number,
	propsFolder: Folder?,
	stage: "terrain" | "background" | "trees" | "props" | "done",
}

type TreeVariantDefinition = {
	config: ProceduralTreeConfig,
	estimatedPartCount: number,
}

type GrassTextureFaceDefinition = {
	color: string?,
	normal: string?,
}

type GrassTextureDefinition = {
	top: (string | GrassTextureFaceDefinition)?,
	side: (string | GrassTextureFaceDefinition)?,
}

local WorldGenerationServiceClient = {}
local ENABLE_CLIENT_VISUALS = true

local WORLD_FOLDER_NAME = "WorldGeneration"
local CHUNKS_FOLDER_NAME = "Chunks"
local TERRAIN_FOLDER_NAME = "Terrain"
local FOREGROUND_TERRAIN_LAYER_FOLDER_NAME = "0"
local LEGACY_BACKGROUND_DEPTH_FOLDER_NAME = "BackgroundDepth"
local TILES_FOLDER_NAME = "Tiles"
local DEFAULT_BASE_PLANE_X = 0
local DEFAULT_WORLD_ORIGIN = Vector3.zero
local MAX_VISUAL_PARTS_TOTAL = 35000
local MAX_VISUAL_PARTS_PER_CHUNK = 2800
local MIN_SECONDS_BETWEEN_REBUILDS_PER_CHUNK = 0.02
local VISIBILITY_REFRESH_INTERVAL = 0.03
local MAX_REBUILD_QUEUE_LENGTH = 2048
local DEFAULT_CLIENT_VISUAL_PRELOAD_MARGIN_PIXELS = 96
local DEFAULT_CLIENT_VISUAL_BUILD_TIME_BUDGET_SECONDS = 0.0035
local DEFAULT_CLIENT_VISUAL_UNLOAD_TIME_BUDGET_SECONDS = 0.002
local DEFAULT_MAX_POOLED_VISUAL_PARTS = 6000
local DEFAULT_CHUNK_ANIMATION_SKIP_SECONDS = 1.5
local MAX_CHUNK_ANIMATION_SKIP_SECONDS = 8
local FOREGROUND_TILE_AIR_ID = 0
local TREE_PLANE_DEPTH_ALPHA = 0.5
local TREE_SURFACE_OFFSET_Y_TILES = 1
local SKIP_WORLD_ANIMATOR_ATTRIBUTE = "SkipWorldAnimator"
local WORLD_ANIMATOR_CHUNK_ATTRIBUTE = "WorldAnimatorChunk"
local ANIMATING_WORLD_ANIMATOR_ATTRIBUTE = "WorldAnimatorAnimating"
local MIN_INT32 = -2147483648
local MAX_INT32 = 2147483647
local BIOME_TYPE_NORMAL = 1
local BIOME_TYPE_CORRUPTION = 2
local BIOME_ID_FOREST = 1
local BIOME_ID_DESERT = 2
local BIOME_ID_SNOW = 3
local BIOME_ID_JUNGLE = 4
local PROP_ID_CORRUPTION_SPIKE = 1
local PROP_ID_DESERT_CACTUS = 2
local PROP_ID_DEAD_BUSH = 3
local PROP_ID_DESERT_ROCK = 4
local PROP_ID_SNOW_PILE = 5
local DEPTH_LAYER_CODE_SKY = 0
local DEPTH_LAYER_CODE_UNDERGROUND = 2
local MIN_DEPTH_LAYER_CODE = 0
local MAX_DEPTH_LAYER_CODE = 4
local MIN_DEPTH_BELOW_SURFACE = -8192
local MAX_DEPTH_BELOW_SURFACE = 8192
local TERRAIN_HOVER_OUTLINE_NAME = "TerrainHoverOutline"
local TERRAIN_HOVER_OUTLINE_PROXY_NAME = "TerrainHoverOutlineProxy"
local TERRAIN_HOVER_OUTLINE_COLOR = Color3.fromRGB(255, 221, 64)
local TERRAIN_HOVER_OUTLINE_THICKNESS = 0.04
local TERRAIN_HOVER_DEPTH_PADDING = 0.04
local GRASS_TILE_ID = 1
local STONE_TILE_ID = 3
local CORRUPT_GRASS_TILE_ID = 14
local JUNGLE_GRASS_TILE_ID = 17
local ORE_TEXTURE_NAME = "OreTexture"
local GRASS_TEXTURE_NAME = "GrassTexture"
local TILE_BINDER_TAG_NAME = "Tile"
local MISSING_ASSET_ERROR = "no asset found!"
local ORE_TEXTURE_FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}
local ORE_ASSET_KEYS_BY_TILE_ID = {
	[10] = { "CopperOre", "Copper" },
	[11] = { "IronOre", "Iron" },
	[12] = { "SilverOre", "Silver" },
	[13] = { "GoldOre", "Gold" },
}
local GRASS_TEXTURE_KEYS_BY_TILE_ID = {
	[GRASS_TILE_ID] = "overworld",
	[CORRUPT_GRASS_TILE_ID] = "corruption",
	[JUNGLE_GRASS_TILE_ID] = "jungle",
}
local GRASS_SIDE_TEXTURE_FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
}
local CAMERA_VIEW_MIN_HALF_SIZE = 0.001
local TERRAIN_TILE_ATTRIBUTE_NAMES = {
	"TileId",
	"TileName",
	"TileMinX",
	"TileMinY",
	"TileWidth",
	"TileHeight",
	"TileIsOre",
}

local TILE_VISUALS: { [number]: TileVisual } = WorldGenerationColor.TILE_VISUALS
local GRASS_TEXTURES: { [string]: GrassTextureDefinition } = PlantRegistry :: any
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

local function applyTileStudSurfaces(part: BasePart)
	TileMaterial.ApplyStudSurfaces(part)
end

local function applyTileSmoothSurfaces(part: BasePart)
	TileMaterial.ApplySmoothSurfaces(part)
end

local function clearTerrainVisualPartState(part: Part)
	for _, child in part:GetChildren() do
		if child:IsA("Texture") then
			child:Destroy()
		end
	end
	for _, attributeName in TERRAIN_TILE_ATTRIBUTE_NAMES do
		part:SetAttribute(attributeName, nil)
	end
	if CollectionService:HasTag(part, TILE_BINDER_TAG_NAME) then
		CollectionService:RemoveTag(part, TILE_BINDER_TAG_NAME)
	end
	part.Parent = nil
	part.Name = "Part"
	part.Shape = Enum.PartType.Block
	part.Anchored = true
	part.Locked = true
	part.Massless = false
	part.CastShadow = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0
	part.LocalTransparencyModifier = 0
	part.Color = Color3.new(1, 1, 1)
	part.Material = Enum.Material.Plastic
	part.MaterialVariant = ""
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new()
	applyTileStudSurfaces(part)
end

local function createTerrainVisualPart(): Part
	local part = Instance.new("Part")
	clearTerrainVisualPartState(part)
	return part
end

local function createChunkVisualModel(snapshot: ChunkSnapshot): Model
	local model = Instance.new("Model")
	model.Name = snapshot.key
	model:SetAttribute("ChunkX", snapshot.chunkX)
	model:SetAttribute("ChunkY", snapshot.chunkY)
	model:SetAttribute("ChunkKey", snapshot.key)
	model:SetAttribute("ChunkRevision", snapshot.revision)
	model:SetAttribute("DominantBiomeId", snapshot.dominantBiomeId)
	model:SetAttribute("DominantBiomeType", snapshot.dominantBiomeType)
	model:SetAttribute("IsCorruptionChunk", snapshot.dominantBiomeType == BIOME_TYPE_CORRUPTION)
	model:SetAttribute(SKIP_WORLD_ANIMATOR_ATTRIBUTE, true)
	model:SetAttribute(WORLD_ANIMATOR_CHUNK_ATTRIBUTE, false)
	return model
end

local function shouldUseSmoothTextureSurfaces(tileId: number): boolean
	return GRASS_TEXTURE_KEYS_BY_TILE_ID[tileId] ~= nil
end

local assignCreatedTileMaterial = TileMaterial.ApplyTileMaterial

local function createTreeVariantDefinitions(): { TreeVariantDefinition }
	return {
		{
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
			estimatedPartCount = 60,
		},
		{
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
			estimatedPartCount = 78,
		},
		{
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
			estimatedPartCount = 96,
		},
		{
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
			estimatedPartCount = 118,
		},
		{
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
			estimatedPartCount = 86,
		},
		{
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
			estimatedPartCount = 104,
		},
		{
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
			estimatedPartCount = 192,
		},
		{
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
			estimatedPartCount = 228,
		},
		{
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
			estimatedPartCount = 88,
		},
		{
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
			estimatedPartCount = 102,
		},
	}
end

local function GetTreeVariantDefinition(
	variantDefinitions: { TreeVariantDefinition },
	variantIndexRaw: any
): TreeVariantDefinition
	local count = #variantDefinitions
	if count <= 0 then
		error("WorldGenerationServiceClient tree variants are not configured")
	end

	local variantIndex = if typeof(variantIndexRaw) == "number"
			and variantIndexRaw == variantIndexRaw
			and variantIndexRaw ~= math.huge
			and variantIndexRaw ~= -math.huge
		then math.floor(variantIndexRaw)
		else 1
	if variantIndex < 1 then
		variantIndex = 1
	end
	local normalizedIndex = ((variantIndex - 1) % count) + 1
	return variantDefinitions[normalizedIndex]
end

local function countBaseParts(instance: Instance): number
	local total = 0
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			total += 1
		end
	end
	return total
end

local function computeBasePartBottomY(part: BasePart): number
	local halfSize = part.Size * 0.5
	local cframe = part.CFrame
	local worldHalfY = math.abs(cframe.RightVector.Y) * halfSize.X
		+ math.abs(cframe.UpVector.Y) * halfSize.Y
		+ math.abs(cframe.LookVector.Y) * halfSize.Z
	return cframe.Position.Y - worldHalfY
end

local function alignInstanceBottomToY(instance: Instance, targetBottomY: number)
	local bottomY: number?
	if instance:IsA("Model") then
		local boundsCFrame, boundsSize = instance:GetBoundingBox()
		bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	elseif instance:IsA("BasePart") then
		bottomY = computeBasePartBottomY(instance)
	end

	if bottomY == nil then
		return
	end

	local offsetY = targetBottomY - bottomY
	if math.abs(offsetY) <= 0.0001 then
		return
	end

	if instance:IsA("Model") then
		instance:PivotTo(instance:GetPivot() + Vector3.new(0, offsetY, 0))
	elseif instance:IsA("BasePart") then
		instance.CFrame = instance.CFrame + Vector3.new(0, offsetY, 0)
	end
end

local function computeTreeSignature(snapshot: ChunkSnapshot): string
	local trees = snapshot.trees
	if #trees <= 0 then
		return ""
	end

	local chunks = Sift.Array.create(#trees)
	for index, tree in trees do
		chunks[index] = table.concat({
			tostring(tree.tileX),
			tostring(tree.tileY),
			tostring(tree.variantIndex),
			tostring(tree.seed),
			tostring(tree.biomeType),
			tostring(tree.biomeId),
			tostring(tree.templateIndex),
		}, ":")
	end
	return table.concat(chunks, "|")
end

local function computePropSignature(snapshot: ChunkSnapshot): string
	local props = snapshot.props
	if #props <= 0 then
		return ""
	end

	local chunks = Sift.Array.create(#props)
	for index, prop in props do
		chunks[index] = table.concat({
			tostring(prop.tileX),
			tostring(prop.tileY),
			tostring(prop.propId),
			tostring(prop.variantIndex),
			tostring(prop.seed),
			tostring(prop.biomeType),
			tostring(prop.biomeId),
		}, ":")
	end
	return table.concat(chunks, "|")
end

local function pruneTreesFolderToSnapshot(treesFolder: Instance?, snapshot: ChunkSnapshot)
	if treesFolder == nil or not treesFolder:IsA("Folder") then
		return
	end

	local nextTreeIds = {}
	for _, tree in snapshot.trees do
		nextTreeIds[BuildServiceUtils.ComputeTreeId(tree.tileX, tree.tileY, tree.seed)] = true
	end

	for _, child in treesFolder:GetChildren() do
		local treeId = child:GetAttribute("BuildTreeId")
		if typeof(treeId) ~= "string" or nextTreeIds[treeId] ~= true then
			child:Destroy()
		end
	end
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function CoerceInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw :: number), minimum, maximum)
end

local function CoerceNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw :: number, minimum, maximum)
end

local function packChunkKey(chunkX: number, chunkY: number): string
	return `{chunkX}:{chunkY}`
end

local function computeTileIndex(localX: number, localY: number, width: number): number
	return localY * width + localX + 1
end

local function toTileCoordinate(worldAxis: number, tileSize: number): number
	return math.floor(worldAxis / tileSize)
end

local function toChunkCoordinate(tile: number, chunkSize: number): number
	return math.floor(tile / chunkSize)
end

local function GetWorldGenerationConfigSource(): { [string]: any }
	if typeof(Configs) ~= "table" then
		return {}
	end
	local worldGenerationConfig = (Configs :: any).worldGeneration
	return if typeof(worldGenerationConfig) == "table" then worldGenerationConfig else {} :: any
end

local function GetClientVisualSettings(): (number, number, number, number)
	local source = GetWorldGenerationConfigSource()
	return CoerceInteger(source.clientVisualPreloadMarginPixels, 0, 1024, DEFAULT_CLIENT_VISUAL_PRELOAD_MARGIN_PIXELS),
		CoerceNumber(
			source.clientVisualBuildTimeBudgetSeconds,
			0.001,
			0.03,
			DEFAULT_CLIENT_VISUAL_BUILD_TIME_BUDGET_SECONDS
		),
		CoerceNumber(
			source.clientVisualUnloadTimeBudgetSeconds,
			0.001,
			0.03,
			DEFAULT_CLIENT_VISUAL_UNLOAD_TIME_BUDGET_SECONDS
		),
		CoerceInteger(source.maxPooledVisualParts, 0, 50000, DEFAULT_MAX_POOLED_VISUAL_PARTS)
end

local function computeChunkSnapshotVisualBounds(
	snapshotRaw: any,
	stateRaw: any,
	worldOriginRaw: any,
	basePlaneXRaw: any
): (CFrame, Vector3)
	local snapshot = if typeof(snapshotRaw) == "table" then snapshotRaw :: { [string]: any } else {} :: any
	local state = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else {} :: any
	local tileSize = CoerceNumber(state.tileSize, 1, 64, WorldGenerationServiceUtils.CreateDefaultState().tileSize)
	local tileDepth =
		CoerceNumber(state.tileDepth, 0.5, 64, WorldGenerationServiceUtils.CreateDefaultState().tileDepth)
	local tileMinX = CoerceInteger(snapshot.tileMinX, -10000000, 10000000, 0)
	local tileMinY = CoerceInteger(snapshot.tileMinY, -10000000, 10000000, 0)
	local width = CoerceInteger(snapshot.width, 1, 512, CoerceInteger(state.chunkSize, 1, 512, 32))
	local height = CoerceInteger(snapshot.height, 1, 512, CoerceInteger(state.chunkSize, 1, 512, 32))
	local backgroundLayerCount = if typeof(snapshot.backgroundLayers) == "table" then #snapshot.backgroundLayers else 0
	local worldOrigin = if typeof(worldOriginRaw) == "Vector3" then worldOriginRaw :: Vector3 else DEFAULT_WORLD_ORIGIN
	local basePlaneX = if isFiniteNumber(basePlaneXRaw) then basePlaneXRaw :: number else DEFAULT_BASE_PLANE_X

	local minPlaneOffset = -(math.max(0, backgroundLayerCount) * tileDepth)
	local minX = worldOrigin.X + basePlaneX + minPlaneOffset - tileDepth * 0.5
	local maxX = worldOrigin.X + basePlaneX + tileDepth * 0.5
	local minY = worldOrigin.Y + tileMinY * tileSize
	local maxY = worldOrigin.Y + (tileMinY + height) * tileSize
	local minZ = worldOrigin.Z + tileMinX * tileSize
	local maxZ = worldOrigin.Z + (tileMinX + width) * tileSize

	return CFrame.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5),
		Vector3.new(math.max(tileDepth, maxX - minX), math.max(tileSize, maxY - minY), math.max(tileSize, maxZ - minZ))
end

local function isBoundsInCameraView(
	camera: Camera,
	boundsCFrame: CFrame,
	boundsSize: Vector3,
	preloadMarginPixels: number
): boolean
	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return true
	end

	local halfSize = Vector3.new(
		math.max(math.abs(boundsSize.X) * 0.5, CAMERA_VIEW_MIN_HALF_SIZE),
		math.max(math.abs(boundsSize.Y) * 0.5, CAMERA_VIEW_MIN_HALF_SIZE),
		math.max(math.abs(boundsSize.Z) * 0.5, CAMERA_VIEW_MIN_HALF_SIZE)
	)

	local cameraLocalPosition = boundsCFrame:PointToObjectSpace(camera.CFrame.Position)
	if
		math.abs(cameraLocalPosition.X) <= halfSize.X
		and math.abs(cameraLocalPosition.Y) <= halfSize.Y
		and math.abs(cameraLocalPosition.Z) <= halfSize.Z
	then
		return true
	end

	local minViewportX = math.huge
	local minViewportY = math.huge
	local maxViewportX = -math.huge
	local maxViewportY = -math.huge
	local hasProjectedPoint = false

	for xIndex = 1, 2 do
		local x = if xIndex == 1 then -halfSize.X else halfSize.X
		for yIndex = 1, 2 do
			local y = if yIndex == 1 then -halfSize.Y else halfSize.Y
			for zIndex = 1, 2 do
				local z = if zIndex == 1 then -halfSize.Z else halfSize.Z
				local viewportPoint, isOnScreen =
					camera:WorldToViewportPoint(boundsCFrame:PointToWorldSpace(Vector3.new(x, y, z)))
				if viewportPoint.Z > 0 then
					hasProjectedPoint = true
					if isOnScreen then
						return true
					end
					minViewportX = math.min(minViewportX, viewportPoint.X)
					minViewportY = math.min(minViewportY, viewportPoint.Y)
					maxViewportX = math.max(maxViewportX, viewportPoint.X)
					maxViewportY = math.max(maxViewportY, viewportPoint.Y)
				end
			end
		end
	end

	if not hasProjectedPoint then
		return false
	end

	return maxViewportX >= -preloadMarginPixels
		and minViewportX <= viewportSize.X + preloadMarginPixels
		and maxViewportY >= -preloadMarginPixels
		and minViewportY <= viewportSize.Y + preloadMarginPixels
end

local function isChunkSnapshotInCameraView(
	snapshot: ChunkSnapshot,
	state: WorldGenerationServiceState,
	worldOrigin: Vector3,
	basePlaneX: number,
	camera: Camera?,
	preloadMarginPixels: number
): boolean
	if camera == nil then
		return true
	end

	local boundsCFrame, boundsSize = computeChunkSnapshotVisualBounds(snapshot, state, worldOrigin, basePlaneX)
	return isBoundsInCameraView(camera, boundsCFrame, boundsSize, preloadMarginPixels)
end

local function GetWorldGenerationAssetsFolder(): Folder?
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

local function GetPropsTemplateFolder(): Folder?
	local worldGeneration = GetWorldGenerationAssetsFolder()
	if worldGeneration == nil then
		return nil
	end
	local props = worldGeneration:FindFirstChild("Props")
	if props ~= nil and props:IsA("Folder") then
		return props
	end
	return nil
end

local function collectTemplateInstances(sourceFolder: Folder?): { Instance }
	local instances: { Instance } = {}
	if sourceFolder == nil then
		return instances
	end
	for _, child in sourceFolder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			instances[#instances + 1] = child
		end
	end
	table.sort(instances, function(a: Instance, b: Instance): boolean
		return a.Name < b.Name
	end)
	return instances
end

local function GetPropTemplatesByPropId(): { [number]: { Instance } }
	local templatesByPropId: { [number]: { Instance } } = {}
	local propsFolder = GetPropsTemplateFolder()
	if propsFolder == nil then
		return templatesByPropId
	end

	local spikeFolder = propsFolder:FindFirstChild("CorruptionSpike")
	if spikeFolder ~= nil then
		if spikeFolder:IsA("Folder") then
			templatesByPropId[PROP_ID_CORRUPTION_SPIKE] = collectTemplateInstances(spikeFolder)
		elseif spikeFolder:IsA("Model") or spikeFolder:IsA("BasePart") then
			templatesByPropId[PROP_ID_CORRUPTION_SPIKE] = { spikeFolder }
		end
	end

	local snowPileFolder = propsFolder:FindFirstChild("SnowPile")
	if snowPileFolder ~= nil then
		if snowPileFolder:IsA("Folder") then
			templatesByPropId[PROP_ID_SNOW_PILE] = collectTemplateInstances(snowPileFolder)
		elseif snowPileFolder:IsA("Model") or snowPileFolder:IsA("BasePart") then
			templatesByPropId[PROP_ID_SNOW_PILE] = { snowPileFolder }
		end
	end

	local desertRockFolder = propsFolder:FindFirstChild("DesertRock")
	if desertRockFolder ~= nil then
		if desertRockFolder:IsA("Folder") then
			templatesByPropId[PROP_ID_DESERT_ROCK] = collectTemplateInstances(desertRockFolder)
		elseif desertRockFolder:IsA("Model") or desertRockFolder:IsA("BasePart") then
			templatesByPropId[PROP_ID_DESERT_ROCK] = { desertRockFolder }
		end
	end

	return templatesByPropId
end

local function cloneTemplateByVariant(templates: { Instance }, variantIndexRaw: any): Instance?
	local count = #templates
	if count <= 0 then
		return nil
	end
	local variantIndex = 1
	if
		typeof(variantIndexRaw) == "number"
		and variantIndexRaw == variantIndexRaw
		and variantIndexRaw ~= math.huge
		and variantIndexRaw ~= -math.huge
	then
		variantIndex = math.max(1, math.floor(variantIndexRaw))
	end
	local normalizedIndex = ((variantIndex - 1) % count) + 1
	local source = templates[normalizedIndex] :: Instance?
	if source == nil then
		return nil
	end
	if source:IsA("Model") or source:IsA("BasePart") then
		return source:Clone()
	end
	return nil
end

local function createFallbackPropTemplate(propId: number, variantIndexRaw: any): BasePart?
	local variantIndex = CoerceInteger(variantIndexRaw, 1, 12, 1)
	local sizeScale = 0.85 + (variantIndex % 4) * 0.1
	local part: BasePart

	if propId == PROP_ID_CORRUPTION_SPIKE then
		part = TileComponent.CreateWedgePart({
			size = Vector3.new(1.1 * sizeScale, 3.6 * sizeScale, 1.1 * sizeScale),
			color = Color3.fromRGB(94, 49, 125),
			material = Enum.Material.Slate,
		})
	elseif propId == PROP_ID_DESERT_ROCK then
		part = TileComponent.CreatePart({
			shape = Enum.PartType.Ball,
			size = Vector3.new(1.6 * sizeScale, 0.9 * sizeScale, 1.9 * sizeScale),
			color = Color3.fromRGB(154, 125, 88),
			material = Enum.Material.Rock,
		})
	elseif propId == PROP_ID_SNOW_PILE then
		part = TileComponent.CreatePart({
			shape = Enum.PartType.Ball,
			size = Vector3.new(2.2 * sizeScale, 0.45 * sizeScale, 1.7 * sizeScale),
			color = Color3.fromRGB(235, 241, 245),
			material = Enum.Material.Snow,
		})
	else
		return nil
	end

	part.Name = `GeneratedProp_{propId}`
	return part
end

local function clonePropTemplateById(
	templatesByPropId: { [number]: { Instance } },
	propId: number,
	variantIndexRaw: any
): Instance?
	local templates = templatesByPropId[propId]
	if templates ~= nil then
		local clone = cloneTemplateByVariant(templates, variantIndexRaw)
		if clone ~= nil then
			return clone
		end
	end
	return createFallbackPropTemplate(propId, variantIndexRaw)
end

local function buildGreedyRectangles(
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

local function styleForegroundPart(part: BasePart, tileId: number): boolean
	local visualTileId = if ORE_ASSET_KEYS_BY_TILE_ID[tileId] ~= nil then STONE_TILE_ID else tileId
	local style = TILE_VISUALS[visualTileId] or TILE_VISUALS[STONE_TILE_ID]
	part.Name = HttpService:GenerateGUID(false)
	part.Color = style.color
	part.Material = style.material
	part.Transparency = style.transparency
	part.CastShadow = false
	applyTileStudSurfaces(part)
	if shouldUseSmoothTextureSurfaces(tileId) then
		assignCreatedTileMaterial(part, visualTileId)
		applyTileSmoothSurfaces(part)
		return false
	end
	if assignCreatedTileMaterial(part, visualTileId) then
		return true
	end
	return false
end

local function GetGrassTextureDefinition(tileId: number): GrassTextureDefinition?
	local biomeKey = GRASS_TEXTURE_KEYS_BY_TILE_ID[tileId]
	if biomeKey == nil then
		return nil
	end

	local definition = GRASS_TEXTURES[biomeKey]
	if typeof(definition) ~= "table" then
		return nil
	end

	return definition
end

local function GetOreTextureAsset(tileId: number): string?
	local assetKeys = ORE_ASSET_KEYS_BY_TILE_ID[tileId]
	if assetKeys == nil or typeof(OreRegistry) ~= "table" then
		return nil
	end

	local oreRegistry = OreRegistry :: { [string]: any }
	for _, assetKey in assetKeys do
		local entry = oreRegistry[assetKey]
		if typeof(entry) == "string" and entry ~= "" then
			return entry
		end
		if typeof(entry) ~= "table" then
			continue
		end

		local asset = entry.asset or entry.texture or entry.id
		if typeof(asset) == "string" and asset ~= "" then
			return asset
		end
	end

	return nil
end

local function clearTexturesByName(part: BasePart, textureName: string)
	for _, child in part:GetChildren() do
		if child:IsA("Texture") and child.Name == textureName then
			child:Destroy()
		end
	end
end

local function GetOreTextureScale(face: Enum.NormalId, tileSize: number, tileDepth: number): (number, number)
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return tileDepth, tileSize
	end
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return tileSize, tileDepth
	end
	return tileSize, tileSize
end

local function applyOreTextures(part: BasePart, tileId: number, tileSize: number, tileDepth: number)
	clearTexturesByName(part, ORE_TEXTURE_NAME)

	local textureAsset = GetOreTextureAsset(tileId)
	if textureAsset == nil then
		return
	end

	local safeTileSize = math.max(0.01, tileSize)
	local safeTileDepth = math.max(0.01, tileDepth)
	for _, face in ORE_TEXTURE_FACES do
		local studsPerTileU, studsPerTileV = GetOreTextureScale(face, safeTileSize, safeTileDepth)
		local texture = Instance.new("Texture")
		texture.Name = ORE_TEXTURE_NAME
		texture.Face = face
		texture.Texture = textureAsset
		texture.StudsPerTileU = studsPerTileU
		texture.StudsPerTileV = studsPerTileV
		texture.Parent = part
	end
end

local function isOreTileId(tileId: number): boolean
	return ORE_ASSET_KEYS_BY_TILE_ID[tileId] ~= nil
end

local function shouldBindTerrainTile(tileId: number): boolean
	return isOreTileId(tileId)
end

function WorldGenerationServiceClient.ShouldBindTerrainTile(tileIdRaw: any): boolean
	if not isFiniteNumber(tileIdRaw) then
		return false
	end
	return shouldBindTerrainTile(math.floor(tileIdRaw :: number))
end

function WorldGenerationServiceClient.ComputeChunkSnapshotVisualBounds(
	snapshotRaw: any,
	stateRaw: any,
	worldOriginRaw: any,
	basePlaneXRaw: any
): (CFrame, Vector3)
	return computeChunkSnapshotVisualBounds(snapshotRaw, stateRaw, worldOriginRaw, basePlaneXRaw)
end

local function GetTileName(tileId: number): string
	local tileRule = BuildServiceUtils.GetTileRule(tileId)
	if typeof(tileRule) == "table" and typeof(tileRule.name) == "string" then
		return tileRule.name
	end
	return tostring(tileId)
end

local function applyTileBinderMetadata(
	part: BasePart,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tileId: number
)
	part:SetAttribute("TileId", tileId)
	part:SetAttribute("TileName", GetTileName(tileId))
	part:SetAttribute("TileMinX", tileMinX)
	part:SetAttribute("TileMinY", tileMinY)
	part:SetAttribute("TileWidth", width)
	part:SetAttribute("TileHeight", height)
	part:SetAttribute("TileIsOre", isOreTileId(tileId))
	local shouldBindTile = shouldBindTerrainTile(tileId)
	if shouldBindTile and not CollectionService:HasTag(part, TILE_BINDER_TAG_NAME) then
		CollectionService:AddTag(part, TILE_BINDER_TAG_NAME)
	elseif not shouldBindTile and CollectionService:HasTag(part, TILE_BINDER_TAG_NAME) then
		CollectionService:RemoveTag(part, TILE_BINDER_TAG_NAME)
	end
end

local function GetGrassTextureScale(face: Enum.NormalId, tileSize: number, tileDepth: number): (number, number)
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return tileSize, tileSize
	end
	return tileDepth, tileSize
end

local function GetTextureColorAsset(definitionRaw: any): string?
	if typeof(definitionRaw) == "string" then
		return if definitionRaw ~= "" then definitionRaw else nil
	end
	if typeof(definitionRaw) ~= "table" then
		return nil
	end

	local colorAsset = definitionRaw.color
		or definitionRaw.ColorMapContent
		or definitionRaw.texture
		or definitionRaw.Texture
	if typeof(colorAsset) == "string" and colorAsset ~= "" then
		return colorAsset
	end

	return nil
end

local function GetTextureNormalAsset(definitionRaw: any): string?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end

	local normalAsset = definitionRaw.normal
		or definitionRaw.NormalMap
		or definitionRaw.NormalMapContent
		or definitionRaw.normalMap
	if typeof(normalAsset) == "string" and normalAsset ~= "" then
		return normalAsset
	end

	return nil
end

local function GetTextureContent(asset: string): any?
	local ok, content = pcall(function()
		return Content.fromUri(asset)
	end)
	if ok then
		return content
	end

	return nil
end

local function assignTextureProperty(texture: Texture, propertyName: string, value: any): boolean
	local ok = pcall(function()
		(texture :: any)[propertyName] = value
	end)
	return ok
end

local function assignTextureContent(texture: Texture, colorAsset: string, normalAsset: string?)
	texture.Texture = colorAsset
	assignTextureProperty(texture, "ColorMap", colorAsset)
	assignTextureProperty(texture, "TextureContent", colorAsset)
	assignTextureProperty(texture, "ColorMapContent", colorAsset)

	local colorContent = GetTextureContent(colorAsset)
	if colorContent ~= nil then
		assignTextureProperty(texture, "TextureContent", colorContent)
		assignTextureProperty(texture, "ColorMapContent", colorContent)
	end

	if normalAsset ~= nil then
		assignTextureProperty(texture, "NormalMap", normalAsset)
		assignTextureProperty(texture, "NormalMapContent", normalAsset)

		local normalContent = GetTextureContent(normalAsset)
		if normalContent ~= nil then
			assignTextureProperty(texture, "NormalMapContent", normalContent)
		end
	end
end

local function createGrassTexture(
	part: BasePart,
	face: Enum.NormalId,
	definitionRaw: any,
	tileSize: number,
	tileDepth: number,
	tint: Color3
)
	local colorAsset = GetTextureColorAsset(definitionRaw)
	if colorAsset == nil then
		return
	end

	local studsPerTileU, studsPerTileV = GetGrassTextureScale(face, tileSize, tileDepth)
	local texture = Instance.new("Texture")
	texture.Name = GRASS_TEXTURE_NAME
	texture.Face = face
	texture.Texture = colorAsset
	assignTextureContent(texture, colorAsset, GetTextureNormalAsset(definitionRaw))
	texture.Color3 = tint
	texture.StudsPerTileU = studsPerTileU
	texture.StudsPerTileV = studsPerTileV
	texture.Parent = part
end

local function applyGrassTextures(
	part: BasePart,
	tileId: number,
	tileSize: number,
	tileDepth: number,
	textureTint: Color3?
)
	clearTexturesByName(part, GRASS_TEXTURE_NAME)

	local textureDefinition = GetGrassTextureDefinition(tileId)
	if textureDefinition == nil then
		return
	end

	local safeTileSize = math.max(0.01, tileSize)
	local safeTileDepth = math.max(0.01, tileDepth)
	local tint = if textureTint ~= nil then textureTint else Color3.new(1, 1, 1)
	createGrassTexture(part, Enum.NormalId.Top, textureDefinition.top, safeTileSize, safeTileDepth, tint)

	if GetTextureColorAsset(textureDefinition.side) == nil then
		return
	end

	for _, face in GRASS_SIDE_TEXTURE_FACES do
		createGrassTexture(part, face, textureDefinition.side, safeTileSize, safeTileDepth, tint)
	end
end

local function styleBackgroundPart(part: BasePart, tileId: number): boolean
	local style = TILE_VISUALS[tileId] or TILE_VISUALS[3]
	part.Name = HttpService:GenerateGUID(false)
	part.Color = style.color
	part.Material = style.material
	part.Transparency = 0
	part.CastShadow = false
	applyTileStudSurfaces(part)
	if shouldUseSmoothTextureSurfaces(tileId) then
		assignCreatedTileMaterial(part, tileId)
		applyTileSmoothSurfaces(part)
		return false
	end
	if assignCreatedTileMaterial(part, tileId) then
		return true
	end
	return false
end

local function CoerceTileCoordinate(valueRaw: any): number?
	if not isFiniteNumber(valueRaw) then
		return nil
	end
	return math.floor(valueRaw)
end

local function createTerrainHoverOutline(
	targetPart: BasePart,
	localTileX: number,
	localTileY: number,
	width: number,
	height: number,
	tileSize: number
): (SelectionBox, Part)
	local hoverProxyPart = Instance.new("Part")
	hoverProxyPart.Name = TERRAIN_HOVER_OUTLINE_PROXY_NAME
	hoverProxyPart.Anchored = true
	hoverProxyPart.CanCollide = false
	hoverProxyPart.CanQuery = false
	hoverProxyPart.CanTouch = false
	hoverProxyPart.CastShadow = false
	hoverProxyPart.Transparency = 1
	hoverProxyPart.Size = Vector3.new(targetPart.Size.X + TERRAIN_HOVER_DEPTH_PADDING, tileSize, tileSize)
	hoverProxyPart.CFrame = targetPart.CFrame
		* CFrame.new(0, (localTileY + 0.5 - height * 0.5) * tileSize, (localTileX + 0.5 - width * 0.5) * tileSize)
	hoverProxyPart.Parent = targetPart

	local outline = Instance.new("SelectionBox")
	outline.Name = TERRAIN_HOVER_OUTLINE_NAME
	outline.Adornee = hoverProxyPart
	outline.Color3 = TERRAIN_HOVER_OUTLINE_COLOR
	outline.LineThickness = TERRAIN_HOVER_OUTLINE_THICKNESS
	outline.SurfaceTransparency = 1
	outline.Parent = hoverProxyPart
	return outline, hoverProxyPart
end

function WorldGenerationServiceClient.GetWorldFolder(self: WorldGenerationServiceClient): Folder?
	local existing = WorkspaceFolders.FindFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		self.worldFolder = existing
		return existing
	end

	self.worldFolder = nil
	self.chunksFolder = nil
	return nil
end

function WorldGenerationServiceClient.GetChunksFolder(self: WorldGenerationServiceClient): Folder?
	local worldFolder = self:GetWorldFolder()
	if worldFolder == nil then
		return nil
	end

	local existing = worldFolder:FindFirstChild(CHUNKS_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		local folder = WorkspaceFolders.ManageFolder(existing, worldFolder) or existing
		self.chunksFolder = folder
		return folder
	end

	if self.chunksFolder ~= nil and self.chunksFolder.Parent == nil then
		local folder = WorkspaceFolders.ManageFolder(self.chunksFolder, worldFolder) or self.chunksFolder
		self.chunksFolder = folder
		return folder
	end

	local folder = TileComponent.CreateFolder({
		name = CHUNKS_FOLDER_NAME,
		parent = worldFolder,
	} :: any)
	WorkspaceFolders.ManageFolder(folder, worldFolder)
	self.chunksFolder = folder
	return folder
end

local function getOrCreateChildFolder(parent: Instance, folderName: string): Folder
	local existing = parent:FindFirstChild(folderName)
	if existing ~= nil and existing:IsA("Folder") then
		return WorkspaceFolders.ManageFolder(existing, parent) or existing
	end
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = TileComponent.CreateFolder({
		name = folderName,
		parent = parent,
	})
	return WorkspaceFolders.ManageFolder(folder, parent) or folder
end

local function destroyFolderIfEmpty(folder: Folder?)
	if folder ~= nil and folder.Parent ~= nil and #folder:GetChildren() <= 0 then
		folder:Destroy()
	end
end

local function destroyFolderAndParentIfEmpty(folder: Folder?)
	if folder == nil or folder.Parent == nil then
		return
	end
	local parent = folder.Parent
	destroyFolderIfEmpty(folder)
	if parent:IsA("Folder") then
		destroyFolderIfEmpty(parent)
	end
end

local function hasVisibleChunkChildren(model: Model): boolean
	for _, child in model:GetChildren() do
		if child:IsA("Folder") and #child:GetChildren() <= 0 then
			continue
		end
		return true
	end
	return false
end

local function pruneEmptyChildFolders(instance: Instance)
	for _, child in instance:GetChildren() do
		if child:IsA("Folder") then
			destroyFolderIfEmpty(child)
		end
	end
end

local function getOrCreateChunkLayerModel(
	parent: Instance,
	snapshot: ChunkSnapshot,
	_skipWorldAnimation: boolean
): Model
	local existing = parent:FindFirstChild(snapshot.key)
	if existing ~= nil and existing:IsA("Model") then
		existing:SetAttribute(SKIP_WORLD_ANIMATOR_ATTRIBUTE, true)
		existing:SetAttribute(WORLD_ANIMATOR_CHUNK_ATTRIBUTE, false)
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end

	local model = TileComponent.CreateModel({
		name = snapshot.key,
		parent = parent,
		attributes = {
			ChunkX = snapshot.chunkX,
			ChunkY = snapshot.chunkY,
			ChunkKey = snapshot.key,
			[SKIP_WORLD_ANIMATOR_ATTRIBUTE] = true,
			[WORLD_ANIMATOR_CHUNK_ATTRIBUTE] = false,
		},
	})
	TagBinder.applyTag(model, TagBinder.Tags.Chunk, CollectionService)
	return model
end

local function prepareChunkLayerModel(model: Model, snapshot: ChunkSnapshot, skipWorldAnimation: boolean)
	model.Name = snapshot.key
	model:SetAttribute("ChunkX", snapshot.chunkX)
	model:SetAttribute("ChunkY", snapshot.chunkY)
	model:SetAttribute("ChunkKey", snapshot.key)
	model:SetAttribute(SKIP_WORLD_ANIMATOR_ATTRIBUTE, skipWorldAnimation)
	model:SetAttribute(WORLD_ANIMATOR_CHUNK_ATTRIBUTE, not skipWorldAnimation)
	TagBinder.applyTag(model, TagBinder.Tags.Chunk, CollectionService)
end

function WorldGenerationServiceClient.GetSharedTerrainFolder(self: WorldGenerationServiceClient): Folder?
	local chunksFolder = self:GetChunksFolder()
	if chunksFolder == nil then
		return nil
	end

	local legacyBackgroundFolder = chunksFolder:FindFirstChild(LEGACY_BACKGROUND_DEPTH_FOLDER_NAME)
	if legacyBackgroundFolder ~= nil then
		legacyBackgroundFolder:Destroy()
	end

	return getOrCreateChildFolder(chunksFolder, TERRAIN_FOLDER_NAME)
end

function WorldGenerationServiceClient.GetForegroundTerrainFolder(self: WorldGenerationServiceClient): Folder?
	local terrainFolder = self:GetSharedTerrainFolder()
	if terrainFolder == nil then
		return nil
	end

	local foregroundFolder = getOrCreateChildFolder(terrainFolder, FOREGROUND_TERRAIN_LAYER_FOLDER_NAME)
	local chunksFolder = terrainFolder.Parent
	if chunksFolder ~= nil then
		for _, child in chunksFolder:GetChildren() do
			if child:IsA("Model") and typeof(child:GetAttribute("ChunkKey")) == "string" then
				local tileParts = {}
				for _, grandchild in child:GetChildren() do
					if grandchild:IsA("BasePart") then
						tileParts[#tileParts + 1] = grandchild
					end
				end
				if #tileParts > 0 then
					local tilesFolder = getOrCreateChildFolder(child, TILES_FOLDER_NAME)
					for _, part in tileParts do
						part.Parent = tilesFolder
					end
				end
				child.Parent = foregroundFolder
			end
		end
	end
	for _, child in terrainFolder:GetChildren() do
		if child:IsA("BasePart") then
			child.Parent = foregroundFolder
		end
	end

	return foregroundFolder
end

function WorldGenerationServiceClient.GetBackgroundLayerFolder(
	self: WorldGenerationServiceClient,
	layerIndex: number
): Folder?
	local terrainFolder = self:GetSharedTerrainFolder()
	if terrainFolder == nil then
		return nil
	end

	local layerFolder = getOrCreateChildFolder(terrainFolder, tostring(layerIndex))
	TagBinder.applyTag(layerFolder, TagBinder.Tags.Layer, CollectionService)
	return layerFolder
end

function WorldGenerationServiceClient.RefreshWorldAttributes(self: WorldGenerationServiceClient)
	local worldFolder = self:GetWorldFolder()
	if worldFolder == nil or worldFolder.Parent == nil then
		return
	end

	local originX = worldFolder:GetAttribute("WorldOriginX")
	local originY = worldFolder:GetAttribute("WorldOriginY")
	local originZ = worldFolder:GetAttribute("WorldOriginZ")
	self.worldOrigin = Vector3.new(
		if isFiniteNumber(originX) then originX :: number else DEFAULT_WORLD_ORIGIN.X,
		if isFiniteNumber(originY) then originY :: number else DEFAULT_WORLD_ORIGIN.Y,
		if isFiniteNumber(originZ) then originZ :: number else DEFAULT_WORLD_ORIGIN.Z
	)

	local basePlaneX = worldFolder:GetAttribute("BasePlaneX")
	self.basePlaneX = if isFiniteNumber(basePlaneX) then basePlaneX :: number else DEFAULT_BASE_PLANE_X
end

function WorldGenerationServiceClient.ComputeTileCenterPosition(
	self: WorldGenerationServiceClient,
	tileCenterX: number,
	tileCenterY: number,
	planeOffsetX: number
): Vector3
	return Vector3.new(
		self.worldOrigin.X + self.basePlaneX + planeOffsetX,
		self.worldOrigin.Y + tileCenterY * self.state.tileSize,
		self.worldOrigin.Z + tileCenterX * self.state.tileSize
	)
end

function WorldGenerationServiceClient.CreateForegroundRectPart(
	self: WorldGenerationServiceClient,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tileId: number
): Part
	local tileDepth = self.state.tileDepth
	local tileSize = self.state.tileSize
	local part = self:AcquireTerrainVisualPart()
	part.Size = Vector3.new(tileDepth, tileSize * height, tileSize * width)
	local hasTileMaterial = styleForegroundPart(part, tileId)
	applyOreTextures(part, tileId, tileSize, tileDepth)
	if not hasTileMaterial then
		applyGrassTextures(part, tileId, tileSize, tileDepth)
	end

	local centerTileX = tileMinX + width * 0.5
	local centerTileY = tileMinY + height * 0.5
	part.CFrame = CFrame.new(self:ComputeTileCenterPosition(centerTileX, centerTileY, 0))
	applyTileBinderMetadata(part, tileMinX, tileMinY, width, height, tileId)
	return part
end

function WorldGenerationServiceClient.ClearHoveredTerrainTileRuntime(self: WorldGenerationServiceClient)
	local activeRuntime = self.hoveredTerrainRuntime
	if activeRuntime == nil then
		return
	end

	if activeRuntime.highlight.Parent ~= nil then
		activeRuntime.highlight:Destroy()
	end

	if activeRuntime.hoverProxyPart.Parent ~= nil then
		activeRuntime.hoverProxyPart:Destroy()
	end

	for _, replacementPart in activeRuntime.replacementParts do
		if replacementPart.Parent ~= nil then
			replacementPart:Destroy()
		end
	end

	if activeRuntime.originalPart.Parent ~= nil then
		activeRuntime.originalPart.Transparency = activeRuntime.originalPartTransparency
	end

	local visual = self.chunkVisuals[activeRuntime.chunkKey]
	if visual ~= nil then
		destroyFolderIfEmpty(visual.terrainHoverFolder)
		if visual.terrainHoverFolder ~= nil and visual.terrainHoverFolder.Parent == nil then
			visual.terrainHoverFolder = nil
		end
	end

	self.hoveredTerrainRuntime = nil
end

function WorldGenerationServiceClient.GetTerrainRectRuntime(
	self: WorldGenerationServiceClient,
	tileX: number,
	tileY: number
): (ChunkVisualRuntime?, TerrainRectRuntime?)
	local chunkSize = math.max(1, math.floor(self.state.chunkSize))
	local chunkX = toChunkCoordinate(tileX, chunkSize)
	local chunkY = toChunkCoordinate(tileY, chunkSize)
	local chunkKey = packChunkKey(chunkX, chunkY)
	local visual = self.chunkVisuals[chunkKey]
	if visual == nil then
		return nil, nil
	end

	local snapshot = self.chunkSnapshots[chunkKey]
	if snapshot == nil then
		return nil, nil
	end

	local localX = tileX - snapshot.tileMinX
	local localY = tileY - snapshot.tileMinY
	if localX < 0 or localX >= snapshot.width or localY < 0 or localY >= snapshot.height then
		return nil, nil
	end

	local lookupIndex = computeTileIndex(localX, localY, snapshot.width)
	local rectIndex = visual.terrainRectByLocalTileIndex[lookupIndex]
	if rectIndex == nil or rectIndex <= 0 then
		return nil, nil
	end

	return visual, visual.terrainRects[rectIndex]
end

function WorldGenerationServiceClient.ApplyHoveredTerrainTileRuntime(self: WorldGenerationServiceClient)
	self:ClearHoveredTerrainTileRuntime()

	local tileX = self.hoveredTerrainTileX
	local tileY = self.hoveredTerrainTileY
	local hoveredChunkKey = self.hoveredTerrainChunkKey
	if tileX == nil or tileY == nil or hoveredChunkKey == nil then
		return
	end

	local _, rectRuntime = self:GetTerrainRectRuntime(tileX, tileY)
	if rectRuntime == nil then
		return
	end

	local localTileX = tileX - rectRuntime.tileMinX
	local localTileY = tileY - rectRuntime.tileMinY
	local originalPartTransparency = rectRuntime.part.Transparency

	local highlight, hoverProxyPart = createTerrainHoverOutline(
		rectRuntime.part,
		localTileX,
		localTileY,
		rectRuntime.width,
		rectRuntime.height,
		self.state.tileSize
	)
	self.hoveredTerrainRuntime = {
		chunkKey = hoveredChunkKey,
		tileX = tileX,
		tileY = tileY,
		localTileX = localTileX,
		localTileY = localTileY,
		width = rectRuntime.width,
		height = rectRuntime.height,
		originalPart = rectRuntime.part,
		originalPartTransparency = originalPartTransparency,
		hoverPart = rectRuntime.part,
		highlight = highlight,
		hoverProxyPart = hoverProxyPart,
		replacementParts = {},
	}
end

function WorldGenerationServiceClient.SetHoveredTerrainTile(
	self: WorldGenerationServiceClient,
	tileXRaw: any,
	tileYRaw: any
)
	local tileX = CoerceTileCoordinate(tileXRaw)
	local tileY = CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		self.hoveredTerrainTileX = nil
		self.hoveredTerrainTileY = nil
		self.hoveredTerrainChunkKey = nil
		self:ClearHoveredTerrainTileRuntime()
		return
	end

	local chunkSize = math.max(1, math.floor(self.state.chunkSize))
	local chunkKey = packChunkKey(toChunkCoordinate(tileX, chunkSize), toChunkCoordinate(tileY, chunkSize))
	local activeRuntime = self.hoveredTerrainRuntime
	if
		self.hoveredTerrainTileX == tileX
		and self.hoveredTerrainTileY == tileY
		and self.hoveredTerrainChunkKey == chunkKey
		and activeRuntime ~= nil
		and activeRuntime.tileX == tileX
		and activeRuntime.tileY == tileY
	then
		return
	end

	self.hoveredTerrainTileX = tileX
	self.hoveredTerrainTileY = tileY
	self.hoveredTerrainChunkKey = chunkKey
	self:ApplyHoveredTerrainTileRuntime()
end

function WorldGenerationServiceClient.ClearHoveredTerrainTile(self: WorldGenerationServiceClient)
	self.hoveredTerrainTileX = nil
	self.hoveredTerrainTileY = nil
	self.hoveredTerrainChunkKey = nil
	self:ClearHoveredTerrainTileRuntime()
end

function WorldGenerationServiceClient.EnqueueChunkRebuild(self: WorldGenerationServiceClient, chunkKey: string)
	if self.rebuildLookup[chunkKey] then
		return
	end
	if self.rebuildQueue:GetCount() >= MAX_REBUILD_QUEUE_LENGTH then
		return
	end

	self.rebuildLookup[chunkKey] = true
	self.rebuildQueue:PushRight(chunkKey)
end

function WorldGenerationServiceClient.DequeueChunkRebuild(self: WorldGenerationServiceClient): string?
	if self.rebuildQueue:IsEmpty() then
		return nil
	end

	local chunkKey = self.rebuildQueue:PopLeft()
	if chunkKey == nil then
		return nil
	end

	self.rebuildLookup[chunkKey] = nil
	return chunkKey
end

function WorldGenerationServiceClient.EnqueueChunkVisualUnload(self: WorldGenerationServiceClient, chunkKey: string)
	if self.unloadLookup[chunkKey] then
		return
	end

	self.unloadLookup[chunkKey] = true
	self.unloadQueue:PushRight(chunkKey)
end

function WorldGenerationServiceClient.CancelChunkVisualUnload(self: WorldGenerationServiceClient, chunkKey: string)
	self.unloadLookup[chunkKey] = nil
end

function WorldGenerationServiceClient.DequeueChunkVisualUnload(self: WorldGenerationServiceClient): string?
	while not self.unloadQueue:IsEmpty() do
		local chunkKey = self.unloadQueue:PopLeft()
		if chunkKey ~= nil and self.unloadLookup[chunkKey] == true then
			self.unloadLookup[chunkKey] = nil
			return chunkKey
		end
	end

	return nil
end

function WorldGenerationServiceClient.ClearChunkVisualUnloadQueue(self: WorldGenerationServiceClient)
	self.unloadQueue = Queue.new()
	table.clear(self.unloadLookup)
end

function WorldGenerationServiceClient.AcquireTerrainVisualPart(self: WorldGenerationServiceClient): Part
	local pool = self.terrainVisualPartPool
	if pool ~= nil then
		local count = #pool
		if count > 0 then
			local part = pool[count]
			pool[count] = nil
			clearTerrainVisualPartState(part)
			return part
		end
	end
	return createTerrainVisualPart()
end

function WorldGenerationServiceClient.ReleaseTerrainVisualPart(self: WorldGenerationServiceClient, part: BasePart)
	if not part:IsA("Part") then
		part:Destroy()
		return
	end

	clearTerrainVisualPartState(part)
	local pool = self.terrainVisualPartPool
	local maxPooledParts = self.maxPooledVisualParts or DEFAULT_MAX_POOLED_VISUAL_PARTS
	if pool ~= nil and #pool < maxPooledParts then
		table.insert(pool, part)
		return
	end
	part:Destroy()
end

function WorldGenerationServiceClient.ReleaseTerrainVisualParts(self: WorldGenerationServiceClient, parts: { BasePart })
	for _, part in parts do
		self:ReleaseTerrainVisualPart(part)
	end
	table.clear(parts)
end

function WorldGenerationServiceClient.ClearTerrainVisualPartPool(self: WorldGenerationServiceClient)
	local pool = self.terrainVisualPartPool
	if pool == nil then
		return
	end
	for _, part in pool do
		part:Destroy()
	end
	table.clear(pool)
end

function WorldGenerationServiceClient.DestroyChunkVisual(self: WorldGenerationServiceClient, chunkKey: string)
	local visual = self.chunkVisuals[chunkKey]
	if visual == nil then
		return
	end

	if self.hoveredTerrainChunkKey == chunkKey then
		self:ClearHoveredTerrainTileRuntime()
	end

	self.chunkVisuals[chunkKey] = nil
	self.totalVisualPartCount = math.max(0, self.totalVisualPartCount - visual.partCount)
	local terrainLayerFolder = if visual.terrainLayerModel ~= nil then visual.terrainLayerModel.Parent else nil
	local terrainFolder = if terrainLayerFolder ~= nil then terrainLayerFolder.Parent else nil
	self:ReleaseTerrainVisualParts(visual.terrainParts)
	for _, backgroundParts in visual.backgroundPartsByLayer do
		self:ReleaseTerrainVisualParts(backgroundParts)
	end
	local destroyedTerrainLayerModel = false
	if visual.terrainLayerModel ~= nil and visual.terrainLayerModel.Parent ~= nil then
		visual.terrainLayerModel:Destroy()
		destroyedTerrainLayerModel = true
	end
	for _, layerModel in visual.backgroundLayerModelsByLayer do
		local layerFolder = layerModel.Parent
		if layerFolder ~= nil then
			layerModel:Destroy()
			if layerFolder:IsA("Folder") then
				destroyFolderAndParentIfEmpty(layerFolder)
			end
		end
	end
	if visual.model ~= visual.terrainLayerModel or not destroyedTerrainLayerModel then
		visual.model:Destroy()
	end
	if terrainLayerFolder ~= nil and terrainLayerFolder:IsA("Folder") then
		destroyFolderIfEmpty(terrainLayerFolder)
	end
	if terrainFolder ~= nil and terrainFolder:IsA("Folder") then
		destroyFolderIfEmpty(terrainFolder)
	end
end

function WorldGenerationServiceClient.DestroyUncommittedChunkVisual(
	self: WorldGenerationServiceClient,
	model: Model,
	terrainParts: { BasePart },
	backgroundPartsByLayer: { { BasePart } }
)
	self:ReleaseTerrainVisualParts(terrainParts)
	for _, backgroundParts in backgroundPartsByLayer do
		self:ReleaseTerrainVisualParts(backgroundParts)
	end
	model:Destroy()
end

function WorldGenerationServiceClient.CancelActiveChunkBuildJob(
	self: WorldGenerationServiceClient,
	chunkKeyRaw: string?
)
	local activeJob = self.activeChunkBuildJob
	if activeJob == nil then
		return
	end
	if chunkKeyRaw ~= nil and activeJob.chunkKey ~= chunkKeyRaw then
		return
	end

	self.activeChunkBuildJob = nil
	self:DestroyUncommittedChunkVisual(activeJob.model, activeJob.terrainParts, activeJob.backgroundPartsByLayer)
end

function WorldGenerationServiceClient.ProcessChunkVisualUnloadQueue(self: WorldGenerationServiceClient)
	if self.unloadQueue:IsEmpty() then
		return
	end

	local deadline = os.clock() + self.visualUnloadTimeBudgetSeconds
	while true do
		local chunkKey = self:DequeueChunkVisualUnload()
		if chunkKey == nil then
			return
		end
		if self.visibleChunkKeys[chunkKey] == true then
			continue
		end

		self:CancelActiveChunkBuildJob(chunkKey)
		self:DestroyChunkVisual(chunkKey)
		if os.clock() >= deadline then
			return
		end
	end
end

function WorldGenerationServiceClient.CommitChunkVisualParts(
	self: WorldGenerationServiceClient,
	snapshot: ChunkSnapshot,
	foregroundModel: Model,
	terrainParts: { BasePart },
	backgroundPartsByLayer: { { BasePart } },
	skipWorldAnimation: boolean
): (boolean, Model, { Model })
	local backgroundLayerFolders = {} :: { Folder? }
	for layerIndex, backgroundParts in backgroundPartsByLayer do
		if #backgroundParts <= 0 then
			continue
		end
		local layerFolder = self:GetBackgroundLayerFolder(layerIndex)
		if layerFolder == nil then
			return false, foregroundModel, {}
		end
		backgroundLayerFolders[layerIndex] = layerFolder
	end

	prepareChunkLayerModel(foregroundModel, snapshot, skipWorldAnimation)
	pruneEmptyChildFolders(foregroundModel)
	local foregroundHasContent = #terrainParts > 0 or hasVisibleChunkChildren(foregroundModel)
	if foregroundHasContent then
		local foregroundFolder = self:GetForegroundTerrainFolder()
		if foregroundFolder == nil then
			return false, foregroundModel, {}
		end
		local existingForeground = foregroundFolder:FindFirstChild(snapshot.key)
		if existingForeground ~= nil and existingForeground ~= foregroundModel then
			existingForeground:Destroy()
		end
		foregroundModel.Parent = foregroundFolder
	else
		local previousForegroundFolder = foregroundModel.Parent
		foregroundModel.Parent = nil
		if previousForegroundFolder ~= nil and previousForegroundFolder:IsA("Folder") then
			destroyFolderAndParentIfEmpty(previousForegroundFolder)
		end
	end

	local terrainTilesFolder: Folder? = nil
	if #terrainParts > 0 then
		terrainTilesFolder = getOrCreateChildFolder(foregroundModel, TILES_FOLDER_NAME)
	end
	local backgroundLayerModelsByLayer = {} :: { Model? }
	for layerIndex, backgroundParts in backgroundPartsByLayer do
		if #backgroundParts <= 0 then
			continue
		end

		local layerFolder = backgroundLayerFolders[layerIndex] :: Folder?
		if layerFolder ~= nil then
			backgroundLayerModelsByLayer[layerIndex] = getOrCreateChunkLayerModel(layerFolder, snapshot, true)
		end
	end

	if terrainTilesFolder ~= nil then
		for _, part in terrainParts do
			part.Parent = terrainTilesFolder
		end
	end
	for layerIndex, backgroundParts in backgroundPartsByLayer do
		local layerModel = backgroundLayerModelsByLayer[layerIndex] :: Model?
		if layerModel == nil then
			continue
		end
		local tilesFolder = getOrCreateChildFolder(layerModel, TILES_FOLDER_NAME)
		for _, part in backgroundParts do
			part.Parent = tilesFolder
		end
	end

	return true, foregroundModel, backgroundLayerModelsByLayer :: any
end

function WorldGenerationServiceClient.CommitChunkVisualBuildResult(
	self: WorldGenerationServiceClient,
	snapshot: ChunkSnapshot,
	model: Model,
	partCount: number,
	terrainHoverFolder: Folder?,
	terrainParts: { BasePart },
	backgroundPartsByLayer: { { BasePart } },
	terrainRects: { TerrainRectRuntime },
	terrainRectByLocalTileIndex: { number },
	now: number
): boolean
	local chunkKey = snapshot.key
	if self.visibleChunkKeys[chunkKey] ~= true then
		self:DestroyUncommittedChunkVisual(model, terrainParts, backgroundPartsByLayer)
		return false
	end

	local existing = self.chunkVisuals[chunkKey]
	if existing ~= nil and existing.revision == snapshot.revision and self.dirtyChunkLookup[chunkKey] ~= true then
		self:DestroyUncommittedChunkVisual(model, terrainParts, backgroundPartsByLayer)
		return false
	end

	local nextTreeSignature = computeTreeSignature(snapshot)
	local nextPropSignature = computePropSignature(snapshot)
	local shouldPreservePropsFolder = false
	local adjustedPartCount = partCount
	if existing ~= nil and nextPropSignature ~= "" and existing.propSignature == nextPropSignature then
		local existingPropsFolder = existing.model:FindFirstChild("Props")
		if existingPropsFolder ~= nil then
			shouldPreservePropsFolder = true
			local rebuiltPropsFolder = model:FindFirstChild("Props")
			local rebuiltPropPartCount = if rebuiltPropsFolder ~= nil then countBaseParts(rebuiltPropsFolder) else 0
			adjustedPartCount = math.max(0, adjustedPartCount - rebuiltPropPartCount)
				+ countBaseParts(existingPropsFolder)
		end
	end
	local existingPartCount = if existing ~= nil then existing.partCount else 0
	local projectedPartTotal = self.totalVisualPartCount - existingPartCount + adjustedPartCount
	if projectedPartTotal > MAX_VISUAL_PARTS_TOTAL then
		self:DestroyUncommittedChunkVisual(model, terrainParts, backgroundPartsByLayer)
		return false
	end

	local shouldSkipChunkAnimation = self:ShouldSkipChunkAnimationForKey(chunkKey, now)
	local visualModel = model
	if existing ~= nil then
		if self.hoveredTerrainChunkKey == chunkKey then
			self:ClearHoveredTerrainTileRuntime()
		end
		self:ReleaseTerrainVisualParts(existing.terrainParts)
		for _, backgroundParts in existing.backgroundPartsByLayer do
			self:ReleaseTerrainVisualParts(backgroundParts)
		end
		if
			existing.terrainHoverFolder ~= nil
			and existing.terrainHoverFolder ~= terrainHoverFolder
			and existing.terrainHoverFolder.Parent ~= nil
		then
			existing.terrainHoverFolder:Destroy()
		end
		for _, layerModel in existing.backgroundLayerModelsByLayer do
			local layerFolder = layerModel.Parent
			if layerFolder ~= nil then
				layerModel:Destroy()
				if layerFolder:IsA("Folder") then
					destroyFolderAndParentIfEmpty(layerFolder)
				end
			end
		end
		shouldSkipChunkAnimation = true

		local preservedChildNames = {} :: { [string]: boolean }
		local existingTreesFolder = existing.model:FindFirstChild("Trees")
		if existing.treeSignature == nextTreeSignature or (nextTreeSignature ~= "" and existingTreesFolder ~= nil) then
			preservedChildNames.Trees = true
		end
		local existingPropsFolder = existing.model:FindFirstChild("Props")
		if shouldPreservePropsFolder and existingPropsFolder ~= nil then
			preservedChildNames.Props = true
		end
		self:ReplaceChunkVisualContents(existing.model, model, preservedChildNames)
		if preservedChildNames.Trees then
			pruneTreesFolderToSnapshot(existingTreesFolder, snapshot)
		end
		visualModel = existing.model
	end

	local didCommit, terrainLayerModel, backgroundLayerModelsByLayer = self:CommitChunkVisualParts(
		snapshot,
		visualModel,
		terrainParts,
		backgroundPartsByLayer,
		shouldSkipChunkAnimation
	)
	if not didCommit then
		self:DestroyUncommittedChunkVisual(model, terrainParts, backgroundPartsByLayer)
		return false
	end

	for _, layerModel in backgroundLayerModelsByLayer do
		layerModel:SetAttribute(SKIP_WORLD_ANIMATOR_ATTRIBUTE, true)
		layerModel:SetAttribute(WORLD_ANIMATOR_CHUNK_ATTRIBUTE, false)
	end

	self.chunkVisuals[chunkKey] = {
		model = visualModel,
		partCount = adjustedPartCount,
		revision = snapshot.revision,
		builtAt = now,
		treeSignature = nextTreeSignature,
		propSignature = nextPropSignature,
		terrainHoverFolder = terrainHoverFolder,
		terrainLayerModel = terrainLayerModel,
		backgroundLayerModelsByLayer = backgroundLayerModelsByLayer,
		terrainParts = terrainParts,
		backgroundPartsByLayer = backgroundPartsByLayer,
		terrainRects = terrainRects,
		terrainRectByLocalTileIndex = terrainRectByLocalTileIndex,
	}
	self.lastChunkBuildAt[chunkKey] = now
	self.totalVisualPartCount = projectedPartTotal
	self.dirtyChunkLookup[chunkKey] = nil
	if self.hoveredTerrainChunkKey == chunkKey then
		self:ApplyHoveredTerrainTileRuntime()
	end

	return true
end

function WorldGenerationServiceClient.ReplaceChunkVisualContents(
	_self: WorldGenerationServiceClient,
	targetModel: Model,
	rebuiltModel: Model,
	preservedChildNamesRaw: { [string]: boolean }?
)
	if targetModel == rebuiltModel then
		return
	end

	local targetAttributes = targetModel:GetAttributes()
	for attributeName in targetAttributes do
		targetModel:SetAttribute(attributeName, nil)
	end

	local rebuiltAttributes = rebuiltModel:GetAttributes()
	for attributeName, attributeValue in rebuiltAttributes do
		targetModel:SetAttribute(attributeName, attributeValue)
	end

	targetModel.Name = rebuiltModel.Name
	local preservedChildNames = if typeof(preservedChildNamesRaw) == "table"
		then preservedChildNamesRaw
		else {} :: { [string]: boolean }
	local preservedChildren = {} :: { [string]: Instance? }
	for _, child in targetModel:GetChildren() do
		if preservedChildNames[child.Name] == true then
			preservedChildren[child.Name] = child
		else
			child:Destroy()
		end
	end

	for _, child in rebuiltModel:GetChildren() do
		if preservedChildren[child.Name] ~= nil then
			child:Destroy()
		else
			local ok = pcall(function()
				child.Parent = targetModel
			end)
			if not ok then
				child:Destroy()
			end
		end
	end
	rebuiltModel:Destroy()
end

function WorldGenerationServiceClient.SuppressChunkAnimationForChunkKey(
	self: WorldGenerationServiceClient,
	chunkKeyRaw: any,
	durationRaw: any?
)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end

	local duration = if isFiniteNumber(durationRaw)
		then math.clamp(durationRaw :: number, 0.05, MAX_CHUNK_ANIMATION_SKIP_SECONDS)
		else DEFAULT_CHUNK_ANIMATION_SKIP_SECONDS
	local now = os.clock()
	local skipUntil = now + duration
	local previousSkipUntil = self.chunkAnimationSkipUntil[chunkKeyRaw]
	if previousSkipUntil ~= nil and previousSkipUntil > skipUntil then
		skipUntil = previousSkipUntil
	end
	self.chunkAnimationSkipUntil[chunkKeyRaw] = skipUntil
end

function WorldGenerationServiceClient.SuppressChunkAnimationForTile(
	self: WorldGenerationServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	durationRaw: any?
)
	if not isFiniteNumber(tileXRaw) or not isFiniteNumber(tileYRaw) then
		return
	end

	local chunkSize = math.max(1, math.floor(self.state.chunkSize))
	local tileX = math.floor(tileXRaw)
	local tileY = math.floor(tileYRaw)
	local chunkX = toChunkCoordinate(tileX, chunkSize)
	local chunkY = toChunkCoordinate(tileY, chunkSize)
	local localTileX = tileX - chunkX * chunkSize
	local localTileY = tileY - chunkY * chunkSize

	self:SuppressChunkAnimationForChunkKey(packChunkKey(chunkX, chunkY), durationRaw)

	if localTileX == 0 then
		self:SuppressChunkAnimationForChunkKey(packChunkKey(chunkX - 1, chunkY), durationRaw)
	elseif localTileX == chunkSize - 1 then
		self:SuppressChunkAnimationForChunkKey(packChunkKey(chunkX + 1, chunkY), durationRaw)
	end

	if localTileY == 0 then
		self:SuppressChunkAnimationForChunkKey(packChunkKey(chunkX, chunkY - 1), durationRaw)
	elseif localTileY == chunkSize - 1 then
		self:SuppressChunkAnimationForChunkKey(packChunkKey(chunkX, chunkY + 1), durationRaw)
	end
end

function WorldGenerationServiceClient.ShouldSkipChunkAnimationForKey(
	self: WorldGenerationServiceClient,
	chunkKey: string,
	now: number
): boolean
	local skipUntil = self.chunkAnimationSkipUntil[chunkKey]
	if skipUntil == nil then
		return false
	end
	if now <= skipUntil then
		return true
	end
	self.chunkAnimationSkipUntil[chunkKey] = nil
	return false
end

function WorldGenerationServiceClient.CoerceChunkSnapshot(
	self: WorldGenerationServiceClient,
	snapshotRaw: any
): ChunkSnapshot?
	if typeof(snapshotRaw) ~= "table" then
		return nil
	end

	local source = snapshotRaw :: { [string]: any }
	if not isFiniteNumber(source.chunkX) or not isFiniteNumber(source.chunkY) then
		return nil
	end

	local chunkX = math.floor(source.chunkX)
	local chunkY = math.floor(source.chunkY)
	local width = CoerceInteger(source.width, 1, 256, self.state.chunkSize)
	local height = CoerceInteger(source.height, 1, 256, self.state.chunkSize)
	local tileMinX = CoerceInteger(source.tileMinX, -10000000, 10000000, chunkX * width)
	local tileMinY = CoerceInteger(source.tileMinY, -10000000, 10000000, chunkY * height)
	local key = if typeof(source.key) == "string" and source.key ~= "" then source.key else packChunkKey(chunkX, chunkY)
	local revision = CoerceInteger(source.revision, 0, 2147483646, 0)

	local totalTiles = width * height
	local tiles = Sift.Array.create(totalTiles, FOREGROUND_TILE_AIR_ID)
	local tilesRaw = if typeof(source.tiles) == "table" then source.tiles :: { any } else {} :: any
	for tileIndex = 1, totalTiles do
		local rawTileId = tilesRaw[tileIndex]
		if isFiniteNumber(rawTileId) then
			tiles[tileIndex] = math.floor(rawTileId)
		end
	end
	local depthLayers = Sift.Array.create(totalTiles, DEPTH_LAYER_CODE_UNDERGROUND)
	local depthLayersRaw = if typeof(source.depthLayers) == "table" then source.depthLayers :: { any } else {} :: any
	for tileIndex = 1, totalTiles do
		local rawDepthLayerCode = depthLayersRaw[tileIndex]
		if isFiniteNumber(rawDepthLayerCode) then
			depthLayers[tileIndex] = CoerceInteger(
				rawDepthLayerCode,
				MIN_DEPTH_LAYER_CODE,
				MAX_DEPTH_LAYER_CODE,
				DEPTH_LAYER_CODE_UNDERGROUND
			)
		elseif tiles[tileIndex] == FOREGROUND_TILE_AIR_ID then
			depthLayers[tileIndex] = DEPTH_LAYER_CODE_SKY
		end
	end
	local depthBelowSurface = Sift.Array.create(totalTiles, 0)
	local depthBelowSurfaceRaw = if typeof(source.depthBelowSurface) == "table"
		then source.depthBelowSurface :: { any }
		else {} :: any
	for tileIndex = 1, totalTiles do
		local rawDepthBelowSurface = depthBelowSurfaceRaw[tileIndex]
		if isFiniteNumber(rawDepthBelowSurface) then
			depthBelowSurface[tileIndex] =
				CoerceInteger(rawDepthBelowSurface, MIN_DEPTH_BELOW_SURFACE, MAX_DEPTH_BELOW_SURFACE, 0)
		elseif depthLayers[tileIndex] == DEPTH_LAYER_CODE_SKY then
			depthBelowSurface[tileIndex] = -1
		end
	end

	local dominantBiomeId = CoerceInteger(source.dominantBiomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, BIOME_ID_FOREST)
	local biomeIds = Sift.Array.create(totalTiles, dominantBiomeId)
	local biomeIdsRaw = if typeof(source.biomeIds) == "table" then source.biomeIds :: { any } else {} :: any
	for tileIndex = 1, totalTiles do
		local rawBiomeId = biomeIdsRaw[tileIndex]
		if isFiniteNumber(rawBiomeId) then
			biomeIds[tileIndex] = CoerceInteger(rawBiomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, dominantBiomeId)
		end
	end
	local hasSurfaceBiomeIds = typeof(source.surfaceBiomeIds) == "table"
	local surfaceBiomeIds = Sift.Array.create(width, if hasSurfaceBiomeIds then dominantBiomeId else BIOME_ID_FOREST)
	local surfaceBiomeIdsRaw = if hasSurfaceBiomeIds then source.surfaceBiomeIds :: { any } else {} :: any
	for localX = 0, width - 1 do
		local rawBiomeId = surfaceBiomeIdsRaw[localX + 1]
		if isFiniteNumber(rawBiomeId) then
			surfaceBiomeIds[localX + 1] = CoerceInteger(rawBiomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, dominantBiomeId)
		elseif hasSurfaceBiomeIds then
			surfaceBiomeIds[localX + 1] = dominantBiomeId
		end
	end

	local dominantBiomeType =
		CoerceInteger(source.dominantBiomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, BIOME_TYPE_NORMAL)
	local biomeTypes = Sift.Array.create(totalTiles, dominantBiomeType)
	local biomeTypesRaw = if typeof(source.biomeTypes) == "table" then source.biomeTypes :: { any } else {} :: any
	for tileIndex = 1, totalTiles do
		local rawBiomeType = biomeTypesRaw[tileIndex]
		if isFiniteNumber(rawBiomeType) then
			biomeTypes[tileIndex] =
				CoerceInteger(rawBiomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, dominantBiomeType)
		end
	end

	local backgroundLayers: { ChunkLayerSnapshot } = {}
	local layersRaw = if typeof(source.backgroundLayers) == "table"
		then source.backgroundLayers :: { any }
		else {} :: any
	for _, layerRaw in layersRaw do
		if typeof(layerRaw) ~= "table" then
			continue
		end

		local layer = layerRaw :: { [string]: any }
		local layerWidth = CoerceInteger(layer.width, 1, 512, width)
		local layerHeight = CoerceInteger(layer.height, 1, 512, height)
		local layerTileMinX = CoerceInteger(layer.tileMinX, -10000000, 10000000, tileMinX)
		local layerTileMinY = CoerceInteger(layer.tileMinY, -10000000, 10000000, tileMinY)
		local layerIndex = CoerceInteger(layer.layerIndex, 1, 64, #backgroundLayers + 1)
		local layerTotalTiles = layerWidth * layerHeight
		local layerTiles = Sift.Array.create(layerTotalTiles, FOREGROUND_TILE_AIR_ID)
		local layerTilesRaw = if typeof(layer.tiles) == "table" then layer.tiles :: { any } else {} :: any
		for tileIndex = 1, layerTotalTiles do
			local rawTileId = layerTilesRaw[tileIndex]
			if isFiniteNumber(rawTileId) then
				layerTiles[tileIndex] = math.floor(rawTileId)
			end
		end

		table.insert(backgroundLayers, {
			layerIndex = layerIndex,
			tileMinX = layerTileMinX,
			tileMinY = layerTileMinY,
			width = layerWidth,
			height = layerHeight,
			tiles = layerTiles,
		})
	end

	local trees: { TreeSpawnSnapshot } = {}
	local treesRaw = if typeof(source.trees) == "table" then source.trees :: { any } else {} :: any
	for _, treeRaw in treesRaw do
		if typeof(treeRaw) ~= "table" then
			continue
		end

		local tree = treeRaw :: { [string]: any }
		if not isFiniteNumber(tree.tileX) or not isFiniteNumber(tree.tileY) then
			continue
		end

		local tileX = math.floor(tree.tileX)
		local tileY = math.floor(tree.tileY)
		local fallbackVariantIndex = CoerceInteger(tree.templateIndex, 1, 128, 1)
		local variantIndex = CoerceInteger(tree.variantIndex, 1, 128, fallbackVariantIndex)
		local fallbackSeed =
			CoerceInteger(tileX * 92821 + tileY * 68917 + variantIndex * 193 + 1337, MIN_INT32, MAX_INT32, 1337)

		table.insert(trees, {
			tileX = tileX,
			tileY = tileY,
			variantIndex = variantIndex,
			seed = CoerceInteger(tree.seed, MIN_INT32, MAX_INT32, fallbackSeed),
			biomeType = if isFiniteNumber(tree.biomeType)
				then CoerceInteger(tree.biomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, dominantBiomeType)
				else nil,
			biomeId = if isFiniteNumber(tree.biomeId)
				then CoerceInteger(tree.biomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, dominantBiomeId)
				else nil,
			templateIndex = if isFiniteNumber(tree.templateIndex)
				then CoerceInteger(tree.templateIndex, 1, 128, variantIndex)
				else nil,
		})
	end

	local props: { PropSpawnSnapshot } = {}
	local propsRaw = if typeof(source.props) == "table" then source.props :: { any } else {} :: any
	for _, propRaw in propsRaw do
		if typeof(propRaw) ~= "table" then
			continue
		end

		local prop = propRaw :: { [string]: any }
		if not isFiniteNumber(prop.tileX) or not isFiniteNumber(prop.tileY) or not isFiniteNumber(prop.propId) then
			continue
		end

		local propId = CoerceInteger(prop.propId, 1, 1024, PROP_ID_CORRUPTION_SPIKE)
		local variantIndex = CoerceInteger(prop.variantIndex, 1, 32, 1)
		local tileX = math.floor(prop.tileX)
		local tileY = math.floor(prop.tileY)
		local fallbackSeed = CoerceInteger(
			tileX * 71341 + tileY * 19753 + propId * 181 + variantIndex * 97 + 1933,
			MIN_INT32,
			MAX_INT32,
			1933
		)

		props[#props + 1] = {
			tileX = tileX,
			tileY = tileY,
			propId = propId,
			variantIndex = variantIndex,
			seed = CoerceInteger(prop.seed, MIN_INT32, MAX_INT32, fallbackSeed),
			biomeType = if isFiniteNumber(prop.biomeType)
				then CoerceInteger(prop.biomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, dominantBiomeType)
				else nil,
			biomeId = if isFiniteNumber(prop.biomeId)
				then CoerceInteger(prop.biomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, dominantBiomeId)
				else nil,
		}
	end

	return {
		key = key,
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
		surfaceBiomeIds = surfaceBiomeIds,
		biomeTypes = biomeTypes,
		dominantBiomeId = dominantBiomeId,
		dominantBiomeType = dominantBiomeType,
		backgroundLayers = backgroundLayers,
		trees = trees,
		props = props,
		revision = revision,
	}
end

function WorldGenerationServiceClient.OnChunkSnapshot(self: WorldGenerationServiceClient, snapshotRaw: any)
	local snapshot = self:CoerceChunkSnapshot(snapshotRaw)
	if snapshot == nil then
		return
	end

	local existingVisual = self.chunkVisuals[snapshot.key]
	local wasAlreadyCurrentRevision = existingVisual ~= nil and existingVisual.revision == snapshot.revision
	self.chunkSnapshots[snapshot.key] = snapshot
	self.chunkSnapshotsChanged:Fire(snapshot.key)
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	if wasAlreadyCurrentRevision and self.dirtyChunkLookup[snapshot.key] ~= true then
		return
	end
	self.dirtyChunkLookup[snapshot.key] = true
	if
		self.visibleChunkKeys[snapshot.key] == true
		and isChunkSnapshotInCameraView(
			snapshot,
			self.state,
			self.worldOrigin,
			self.basePlaneX,
			Workspace.CurrentCamera,
			self.visualPreloadMarginPixels
		)
	then
		self:CancelChunkVisualUnload(snapshot.key)
		self:EnqueueChunkRebuild(snapshot.key)
	end
end

function WorldGenerationServiceClient.OnChunkUnloaded(self: WorldGenerationServiceClient, chunkKeyRaw: any)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end

	self.chunkSnapshots[chunkKeyRaw] = nil
	self.chunkSnapshotsChanged:Fire(chunkKeyRaw)
	self.visibleChunkKeys[chunkKeyRaw] = nil
	self.dirtyChunkLookup[chunkKeyRaw] = nil
	self.rebuildLookup[chunkKeyRaw] = nil
	self.lastChunkBuildAt[chunkKeyRaw] = nil
	self.chunkAnimationSkipUntil[chunkKeyRaw] = nil
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	self:CancelActiveChunkBuildJob(chunkKeyRaw)
	self:EnqueueChunkVisualUnload(chunkKeyRaw)
end

function WorldGenerationServiceClient.CreateChunkVisualBuildJob(
	_self: WorldGenerationServiceClient,
	snapshot: ChunkSnapshot
): ChunkVisualBuildJob
	local model = createChunkVisualModel(snapshot)
	TagBinder.applyTag(model, TagBinder.Tags.Chunk, CollectionService)

	local terrainGreedyRects = buildGreedyRectangles(
		snapshot.tiles,
		snapshot.width,
		snapshot.height,
		function(value: number): boolean
			return value ~= FOREGROUND_TILE_AIR_ID
		end
	)

	return {
		chunkKey = snapshot.key,
		snapshot = snapshot,
		model = model,
		partCount = 0,
		terrainParts = {},
		backgroundPartsByLayer = {},
		terrainRects = {},
		terrainRectByLocalTileIndex = Sift.Array.create(snapshot.width * snapshot.height, 0) :: { number },
		terrainGreedyRects = terrainGreedyRects,
		terrainRectIndex = 1,
		backgroundLayerIndex = 1,
		backgroundRects = nil,
		backgroundRectIndex = 1,
		treeIndex = 1,
		treeCount = 0,
		treesFolder = nil,
		propIndex = 1,
		propCount = 0,
		propsFolder = nil,
		stage = "terrain",
	}
end

function WorldGenerationServiceClient.StepChunkVisualBuildJob(
	self: WorldGenerationServiceClient,
	job: ChunkVisualBuildJob,
	deadline: number
): boolean
	local snapshot = job.snapshot
	local tileDepth = self.state.tileDepth
	local tileSize = self.state.tileSize

	while job.stage == "terrain" do
		if job.partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			job.stage = "done"
			break
		end
		local rect = job.terrainGreedyRects[job.terrainRectIndex]
		if rect == nil then
			job.stage = "background"
			break
		end

		local absoluteTileMinX = snapshot.tileMinX + rect.x
		local absoluteTileMinY = snapshot.tileMinY + rect.y
		local part =
			self:CreateForegroundRectPart(absoluteTileMinX, absoluteTileMinY, rect.width, rect.height, rect.value)
		job.terrainParts[#job.terrainParts + 1] = part
		job.partCount += 1

		local runtimeRectIndex = #job.terrainRects + 1
		job.terrainRects[runtimeRectIndex] = {
			part = part,
			tileMinX = absoluteTileMinX,
			tileMinY = absoluteTileMinY,
			width = rect.width,
			height = rect.height,
			tileId = rect.value,
		}
		for localRectY = 0, rect.height - 1 do
			for localRectX = 0, rect.width - 1 do
				local lookupIndex = computeTileIndex(rect.x + localRectX, rect.y + localRectY, snapshot.width)
				job.terrainRectByLocalTileIndex[lookupIndex] = runtimeRectIndex
			end
		end

		job.terrainRectIndex += 1
		if os.clock() >= deadline then
			return false
		end
	end

	while job.stage == "background" do
		if job.partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			job.stage = "done"
			break
		end

		local layerListIndex = job.backgroundLayerIndex
		local layerData = snapshot.backgroundLayers[layerListIndex]
		if layerData == nil then
			job.stage = "trees"
			break
		end

		if job.backgroundRects == nil then
			job.backgroundRects = buildGreedyRectangles(
				layerData.tiles,
				layerData.width,
				layerData.height,
				function(value: number): boolean
					return value ~= FOREGROUND_TILE_AIR_ID
				end
			)
			job.backgroundRectIndex = 1
			job.backgroundPartsByLayer[layerListIndex] = {}
		end

		local planeOffset = -(layerListIndex * tileDepth)
		local backgroundParts = job.backgroundPartsByLayer[layerListIndex]
		while true do
			if job.partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
				job.stage = "done"
				break
			end

			local rect = (job.backgroundRects :: { GreedyRect })[job.backgroundRectIndex]
			if rect == nil then
				job.backgroundRects = nil
				job.backgroundLayerIndex += 1
				break
			end

			local part = self:AcquireTerrainVisualPart()
			part.Size = Vector3.new(tileDepth, tileSize * rect.height, tileSize * rect.width)
			local hasTileMaterial = styleBackgroundPart(part, rect.value)
			if not hasTileMaterial then
				applyGrassTextures(part, rect.value, tileSize, tileDepth)
			end

			local centerTileX = layerData.tileMinX + rect.x + rect.width * 0.5
			local centerTileY = layerData.tileMinY + rect.y + rect.height * 0.5
			part.CFrame = CFrame.new(self:ComputeTileCenterPosition(centerTileX, centerTileY, planeOffset))
			backgroundParts[#backgroundParts + 1] = part
			job.partCount += 1

			job.backgroundRectIndex += 1
			if os.clock() >= deadline then
				return false
			end
		end
	end

	while job.stage == "trees" do
		if job.partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			job.stage = "done"
			break
		end

		local treeSpawnData = snapshot.trees[job.treeIndex]
		if treeSpawnData == nil then
			job.stage = "props"
			break
		end

		local furthestBackgroundOffset = -math.max(1, #snapshot.backgroundLayers) * tileDepth
		local treePlaneOffset = furthestBackgroundOffset * TREE_PLANE_DEPTH_ALPHA
		local treeVariantDefinitions = self.treeVariantDefinitions
		local variantDefinition = GetTreeVariantDefinition(treeVariantDefinitions, treeSpawnData.variantIndex)
		if job.partCount + variantDefinition.estimatedPartCount > MAX_VISUAL_PARTS_PER_CHUNK then
			job.stage = "props"
			break
		end

		local centerTileX = treeSpawnData.tileX + 0.5
		local centerTileY = treeSpawnData.tileY + TREE_SURFACE_OFFSET_Y_TILES
		local position = self:ComputeTileCenterPosition(centerTileX, centerTileY, treePlaneOffset)

		local treeConfig = Sift.Dictionary.copy(variantDefinition.config) :: { [string]: any }
		treeConfig.Seed = treeSpawnData.seed
		treeConfig.ModelName = `Tree_{snapshot.chunkX}_{snapshot.chunkY}_{job.treeCount + 1}`

		local proceduralTree = ProceduralTree.New(treeConfig)
		job.treesFolder = job.treesFolder or getOrCreateChildFolder(job.model, "Trees")
		local generatedTreeModel = proceduralTree:Generate(job.treesFolder, CFrame.new(position))
		generatedTreeModel:SetAttribute(
			"BuildTreeId",
			BuildServiceUtils.ComputeTreeId(treeSpawnData.tileX, treeSpawnData.tileY, treeSpawnData.seed)
		)
		generatedTreeModel:SetAttribute("BuildTreeRootTileX", treeSpawnData.tileX)
		generatedTreeModel:SetAttribute("BuildTreeRootTileY", treeSpawnData.tileY)
		generatedTreeModel:SetAttribute("VariantIndex", treeSpawnData.variantIndex)
		generatedTreeModel:SetAttribute("TreeSeed", treeSpawnData.seed)
		for _, descendant in generatedTreeModel:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CastShadow = false
			end
		end

		local generatedPartCount = countBaseParts(generatedTreeModel)
		if job.partCount + generatedPartCount > MAX_VISUAL_PARTS_PER_CHUNK then
			generatedTreeModel:Destroy()
			destroyFolderIfEmpty(job.treesFolder)
			if job.treesFolder ~= nil and job.treesFolder.Parent == nil then
				job.treesFolder = nil
			end
			job.stage = "props"
			break
		end

		job.partCount += generatedPartCount
		job.treeCount += 1
		job.treeIndex += 1
		if os.clock() >= deadline then
			return false
		end
	end

	while job.stage == "props" do
		if job.partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			job.stage = "done"
			break
		end

		local propSpawnData = snapshot.props[job.propIndex]
		if propSpawnData == nil then
			job.stage = "done"
			break
		end

		local furthestBackgroundOffset = -math.max(1, #snapshot.backgroundLayers) * tileDepth
		local treePlaneOffset = furthestBackgroundOffset * TREE_PLANE_DEPTH_ALPHA
		local centerTileX = propSpawnData.tileX + 0.5
		local centerTileY = propSpawnData.tileY + TREE_SURFACE_OFFSET_Y_TILES
		if
			propSpawnData.propId == PROP_ID_DEAD_BUSH
			or propSpawnData.propId == PROP_ID_DESERT_ROCK
			or propSpawnData.propId == PROP_ID_SNOW_PILE
		then
			centerTileY = propSpawnData.tileY + 0.5
		end
		local position = self:ComputeTileCenterPosition(centerTileX, centerTileY, treePlaneOffset)
		local propInstance: Instance?
		local useGeneratedBoundsPlacement = false
		if
			propSpawnData.propId == PROP_ID_CORRUPTION_SPIKE
			or propSpawnData.propId == PROP_ID_DESERT_ROCK
			or propSpawnData.propId == PROP_ID_SNOW_PILE
		then
			propInstance =
				clonePropTemplateById(self.propTemplatesByPropId, propSpawnData.propId, propSpawnData.variantIndex)
		elseif propSpawnData.propId == PROP_ID_DESERT_CACTUS then
			local cactusColor = if propSpawnData.biomeId == BIOME_ID_DESERT
				then Color3.fromRGB(90, 147, 78)
				else Color3.fromRGB(82, 136, 74)
			local cactusComplexity = math.clamp(propSpawnData.variantIndex, 1, 4)
			job.propsFolder = job.propsFolder or getOrCreateChildFolder(job.model, "Props")
			local cactusGenerator = ProceduralCactus.New({
				Seed = propSpawnData.seed,
				Parent = job.propsFolder,
				ModelName = `Cactus_{snapshot.chunkX}_{snapshot.chunkY}_{job.propCount + 1}`,
				Iterations = 6 + cactusComplexity,
				StepLength = 3.05 + cactusComplexity * 0.25,
				BaseThickness = 1.25 + cactusComplexity * 0.18,
				AngleDegrees = 24 + cactusComplexity * 2.5,
				MinBranchHeight = 3.5 + cactusComplexity * 0.75,
				MaxBranches = 2 + math.clamp(cactusComplexity, 0, 3),
				BranchChance = math.clamp(0.48 + cactusComplexity * 0.07, 0, 0.82),
				BranchStartIteration = 2,
				Curvature = 11 + cactusComplexity * 1.8,
				TrunkWobbleDegrees = 1.2 + cactusComplexity * 0.2,
				ArmThicknessScale = 0.74,
				MinimumThickness = 0.48,
				SegmentMaterial = Enum.Material.SmoothPlastic,
				SegmentColor = cactusColor,
				UseWelds = true,
				SegmentCanCollide = false,
			} :: any)
			propInstance = cactusGenerator:Generate(position)
			useGeneratedBoundsPlacement = true
		else
			job.propIndex += 1
			continue
		end

		if propInstance == nil then
			error(MISSING_ASSET_ERROR, 0)
		end

		local generatedPartCount = 0
		if propInstance:IsA("Model") then
			if not useGeneratedBoundsPlacement then
				local existingPivot = propInstance:GetPivot()
				local preservedRotation = existingPivot - existingPivot.Position
				propInstance:PivotTo(CFrame.new(position) * preservedRotation)
			end
			alignInstanceBottomToY(propInstance, position.Y)

			generatedPartCount = countBaseParts(propInstance)
			for _, descendant in propInstance:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.CastShadow = false
				end
			end
		elseif propInstance:IsA("BasePart") then
			propInstance.CFrame = CFrame.new(position)
			alignInstanceBottomToY(propInstance, position.Y)
			propInstance.Anchored = true
			propInstance.CanCollide = false
			propInstance.CanQuery = false
			propInstance.CanTouch = false
			propInstance.CastShadow = false
			generatedPartCount = 1
		end

		if job.partCount + generatedPartCount > MAX_VISUAL_PARTS_PER_CHUNK then
			propInstance:Destroy()
			destroyFolderIfEmpty(job.propsFolder)
			if job.propsFolder ~= nil and job.propsFolder.Parent == nil then
				job.propsFolder = nil
			end
			job.stage = "done"
			break
		end

		job.partCount += generatedPartCount
		job.propCount += 1
		job.propsFolder = job.propsFolder or getOrCreateChildFolder(job.model, "Props")
		propInstance.Parent = job.propsFolder
		job.propIndex += 1
		if os.clock() >= deadline then
			return false
		end
	end

	if job.stage == "done" then
		job.model:SetAttribute("TreeCount", job.treeCount)
		job.model:SetAttribute("PropCount", job.propCount)
		return true
	end

	return false
end

function WorldGenerationServiceClient.FinishChunkVisualBuildJob(
	_self: WorldGenerationServiceClient,
	job: ChunkVisualBuildJob
): (
	Model,
	number,
	Folder?,
	{ BasePart },
	{ { BasePart } },
	{ TerrainRectRuntime },
	{ number }
)
	job.model:SetAttribute("TreeCount", job.treeCount)
	job.model:SetAttribute("PropCount", job.propCount)
	return job.model,
		job.partCount,
		nil,
		job.terrainParts,
		job.backgroundPartsByLayer,
		job.terrainRects,
		job.terrainRectByLocalTileIndex
end

function WorldGenerationServiceClient.BuildChunkVisualModel(
	self: WorldGenerationServiceClient,
	snapshot: ChunkSnapshot
): (
	Model,
	number,
	Folder?,
	{ BasePart },
	{ { BasePart } },
	{ TerrainRectRuntime },
	{ number }
)
	local job = self:CreateChunkVisualBuildJob(snapshot)
	local isComplete = false
	while not isComplete do
		isComplete = self:StepChunkVisualBuildJob(job, math.huge)
	end
	return self:FinishChunkVisualBuildJob(job)
end

function WorldGenerationServiceClient.ShouldBuildChunkSnapshotVisualNow(
	self: WorldGenerationServiceClient,
	snapshot: ChunkSnapshot,
	camera: Camera?
): boolean
	return self.visibleChunkKeys[snapshot.key] == true
		and isChunkSnapshotInCameraView(
			snapshot,
			self.state,
			self.worldOrigin,
			self.basePlaneX,
			camera,
			self.visualPreloadMarginPixels
		)
end

function WorldGenerationServiceClient.ProcessActiveChunkBuildJob(
	self: WorldGenerationServiceClient,
	deadline: number,
	camera: Camera?
): boolean
	local activeJob = self.activeChunkBuildJob
	if activeJob == nil then
		return true
	end

	local chunkKey = activeJob.chunkKey
	local snapshot = self.chunkSnapshots[chunkKey]
	if snapshot ~= activeJob.snapshot then
		self:CancelActiveChunkBuildJob(chunkKey)
		if snapshot ~= nil then
			self:EnqueueChunkRebuild(chunkKey)
		end
		return true
	end
	if not self:ShouldBuildChunkSnapshotVisualNow(snapshot, camera) then
		self:CancelActiveChunkBuildJob(chunkKey)
		return true
	end

	local existing = self.chunkVisuals[chunkKey]
	if existing ~= nil and existing.model:GetAttribute(ANIMATING_WORLD_ANIMATOR_ATTRIBUTE) == true then
		self:CancelActiveChunkBuildJob(chunkKey)
		self:EnqueueChunkRebuild(chunkKey)
		return true
	end
	if existing ~= nil and existing.revision == snapshot.revision and self.dirtyChunkLookup[chunkKey] ~= true then
		self:CancelActiveChunkBuildJob(chunkKey)
		return true
	end

	local isComplete = self:StepChunkVisualBuildJob(activeJob, deadline)
	if not isComplete then
		return false
	end

	self.activeChunkBuildJob = nil
	local model, partCount, terrainHoverFolder, terrainParts, backgroundPartsByLayer, terrainRects, terrainRectByLocalTileIndex =
		self:FinishChunkVisualBuildJob(activeJob)
	self:CommitChunkVisualBuildResult(
		snapshot,
		model,
		partCount,
		terrainHoverFolder,
		terrainParts,
		backgroundPartsByLayer,
		terrainRects,
		terrainRectByLocalTileIndex,
		os.clock()
	)
	return true
end

function WorldGenerationServiceClient.ProcessChunkRebuildQueue(self: WorldGenerationServiceClient)
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	if self.isProcessingRebuildQueue then
		return
	end
	if self.activeChunkBuildJob == nil and self.rebuildQueue:IsEmpty() then
		return
	end

	self.isProcessingRebuildQueue = true
	local ok, result = (pcall :: any)(function()
		local chunksFolder = self:GetChunksFolder()
		if chunksFolder == nil then
			return
		end

		local camera = Workspace.CurrentCamera
		local deadline = os.clock() + self.visualBuildTimeBudgetSeconds
		if not self:ProcessActiveChunkBuildJob(deadline, camera) then
			return
		end

		local inspected = 0
		local maxInspections = math.max(1, self.rebuildQueue:GetCount())
		while inspected < maxInspections and os.clock() < deadline do
			local chunkKey = self:DequeueChunkRebuild()
			if chunkKey == nil then
				break
			end
			inspected += 1

			local snapshot = self.chunkSnapshots[chunkKey]
			if snapshot == nil or not self:ShouldBuildChunkSnapshotVisualNow(snapshot, camera) then
				continue
			end

			local existing = self.chunkVisuals[chunkKey]
			if
				existing ~= nil
				and existing.revision == snapshot.revision
				and self.dirtyChunkLookup[chunkKey] ~= true
			then
				continue
			end
			if existing ~= nil and existing.model:GetAttribute(ANIMATING_WORLD_ANIMATOR_ATTRIBUTE) == true then
				self:EnqueueChunkRebuild(chunkKey)
				continue
			end

			local now = os.clock()
			local lastBuiltAt = self.lastChunkBuildAt[chunkKey] or 0
			if now - lastBuiltAt < MIN_SECONDS_BETWEEN_REBUILDS_PER_CHUNK then
				self:EnqueueChunkRebuild(chunkKey)
				continue
			end

			self:CancelChunkVisualUnload(chunkKey)
			self.activeChunkBuildJob = self:CreateChunkVisualBuildJob(snapshot)
			if not self:ProcessActiveChunkBuildJob(deadline, camera) then
				return
			end
		end
	end)
	self.isProcessingRebuildQueue = false
	if not ok then
		error(result, 0)
	end
end

function WorldGenerationServiceClient.RefreshVisibleChunks(self: WorldGenerationServiceClient)
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	self:RefreshWorldAttributes()

	local nextVisible: { [string]: boolean } = {}
	for chunkKey, snapshot in self.chunkSnapshots do
		if
			not isChunkSnapshotInCameraView(
				snapshot,
				self.state,
				self.worldOrigin,
				self.basePlaneX,
				camera,
				self.visualPreloadMarginPixels
			)
		then
			continue
		end

		nextVisible[chunkKey] = true
		self:CancelChunkVisualUnload(chunkKey)
		local existingVisual = self.chunkVisuals[chunkKey]
		if
			existingVisual == nil
			or existingVisual.revision ~= snapshot.revision
			or self.dirtyChunkLookup[chunkKey] == true
		then
			self:EnqueueChunkRebuild(chunkKey)
		end
	end

	for chunkKey in pairs(self.chunkVisuals) do
		if nextVisible[chunkKey] then
			continue
		end
		self:CancelActiveChunkBuildJob(chunkKey)
		self:EnqueueChunkVisualUnload(chunkKey)
	end

	self.visibleChunkKeys = nextVisible
end

function WorldGenerationServiceClient.OnHeartbeat(self: WorldGenerationServiceClient, deltaTime: number)
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	self.visibilityRefreshAccumulator += deltaTime
	if self.visibilityRefreshAccumulator >= VISIBILITY_REFRESH_INTERVAL then
		self.visibilityRefreshAccumulator = 0
		self:RefreshVisibleChunks()
	end

	self:ProcessChunkVisualUnloadQueue()
	self:ProcessChunkRebuildQueue()
end

function WorldGenerationServiceClient.ResetActiveWorldState(self: WorldGenerationServiceClient)
	self:ClearHoveredTerrainTile()
	self:CancelActiveChunkBuildJob(nil)
	for chunkKey in pairs(self.chunkVisuals) do
		self:DestroyChunkVisual(chunkKey)
	end

	table.clear(self.chunkSnapshots)
	table.clear(self.visibleChunkKeys)
	table.clear(self.dirtyChunkLookup)
	table.clear(self.rebuildLookup)
	table.clear(self.lastChunkBuildAt)
	table.clear(self.chunkAnimationSkipUntil)
	self.rebuildQueue = Queue.new()
	self:ClearChunkVisualUnloadQueue()
	self.totalVisualPartCount = 0
	self.visibilityRefreshAccumulator = VISIBILITY_REFRESH_INTERVAL
end

function WorldGenerationServiceClient.ApplyState(self: WorldGenerationServiceClient, stateRaw: any)
	local previousState = self.state
	local nextState = WorldGenerationServiceUtils.CreateState(stateRaw, previousState)
	local shouldResetActiveWorld = previousState ~= nil
		and (
			previousState.seed ~= nextState.seed
			or previousState.chunkSize ~= nextState.chunkSize
			or previousState.minTileY ~= nextState.minTileY
			or previousState.maxTileY ~= nextState.maxTileY
		)
	if shouldResetActiveWorld then
		self:ResetActiveWorldState()
	end
	self.state = nextState
	self.stateChanged:Fire(WorldGenerationServiceUtils.CloneState(self.state))
end

function WorldGenerationServiceClient.RequestSync(self: WorldGenerationServiceClient)
	sendPacket(WorldGenerationServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function WorldGenerationServiceClient.SetRenderDistance(
	self: WorldGenerationServiceClient,
	renderDistanceRaw: any,
	verticalRenderDistanceRaw: any?
)
	sendPacket(
		WorldGenerationServiceUtils.NETWORK_METHOD_SET_RENDER_DISTANCE,
		renderDistanceRaw,
		verticalRenderDistanceRaw
	)
end

function WorldGenerationServiceClient.GetState(self: WorldGenerationServiceClient): WorldGenerationServiceState
	return WorldGenerationServiceUtils.CloneState(self.state)
end

function WorldGenerationServiceClient.GetRenderDistance(self: WorldGenerationServiceClient): (number, number)
	return self.state.renderDistanceChunks, self.state.verticalRenderDistanceChunks
end

function WorldGenerationServiceClient.GetBiomeTypeAtWorldPosition(
	self: WorldGenerationServiceClient,
	worldPosition: Vector3
): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.state.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.state.tileSize)
	local chunkX = toChunkCoordinate(tileX, self.state.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.state.chunkSize)
	local snapshot = self.chunkSnapshots[packChunkKey(chunkX, chunkY)]
	if snapshot == nil then
		return BIOME_TYPE_NORMAL
	end

	local localX = tileX - snapshot.tileMinX
	local localY = tileY - snapshot.tileMinY
	if localX < 0 or localX >= snapshot.width or localY < 0 or localY >= snapshot.height then
		return snapshot.dominantBiomeType
	end
	local index = computeTileIndex(localX, localY, snapshot.width)
	return snapshot.biomeTypes[index] or snapshot.dominantBiomeType
end

function WorldGenerationServiceClient.GetBiomeIdAtWorldPosition(
	self: WorldGenerationServiceClient,
	worldPosition: Vector3
): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.state.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.state.tileSize)
	local chunkX = toChunkCoordinate(tileX, self.state.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.state.chunkSize)
	local snapshot = self.chunkSnapshots[packChunkKey(chunkX, chunkY)]
	if snapshot == nil then
		return BIOME_ID_FOREST
	end

	local localX = tileX - snapshot.tileMinX
	local localY = tileY - snapshot.tileMinY
	if localX < 0 or localX >= snapshot.width or localY < 0 or localY >= snapshot.height then
		return snapshot.dominantBiomeId
	end
	local index = computeTileIndex(localX, localY, snapshot.width)
	return snapshot.biomeIds[index] or snapshot.dominantBiomeId
end

function WorldGenerationServiceClient.GetSurfaceBiomeIdAtWorldPosition(
	self: WorldGenerationServiceClient,
	worldPosition: Vector3
): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.state.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.state.tileSize)
	local chunkX = toChunkCoordinate(tileX, self.state.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.state.chunkSize)
	local snapshot = self.chunkSnapshots[packChunkKey(chunkX, chunkY)]
	local fallbackBiomeId = if snapshot ~= nil then snapshot.dominantBiomeId else BIOME_ID_FOREST

	if snapshot ~= nil then
		local localX = tileX - snapshot.tileMinX
		if localX >= 0 and localX < snapshot.width then
			local surfaceBiomeId = snapshot.surfaceBiomeIds[localX + 1]
			if typeof(surfaceBiomeId) == "number" then
				local CoerceDSurfaceBiomeId =
					CoerceInteger(surfaceBiomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, fallbackBiomeId)
				if CoerceDSurfaceBiomeId == BIOME_ID_SNOW then
					return BIOME_ID_SNOW
				end
				fallbackBiomeId = CoerceDSurfaceBiomeId
			end
		end
	end

	for _, candidateSnapshot in self.chunkSnapshots do
		if candidateSnapshot.chunkX ~= chunkX then
			continue
		end

		local localX = tileX - candidateSnapshot.tileMinX
		if localX < 0 or localX >= candidateSnapshot.width then
			continue
		end

		local surfaceBiomeId = candidateSnapshot.surfaceBiomeIds[localX + 1]
		if typeof(surfaceBiomeId) ~= "number" then
			continue
		end

		local CoerceDSurfaceBiomeId =
			CoerceInteger(surfaceBiomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, candidateSnapshot.dominantBiomeId)
		if CoerceDSurfaceBiomeId == BIOME_ID_SNOW then
			return BIOME_ID_SNOW
		end
		fallbackBiomeId = CoerceDSurfaceBiomeId
	end

	return fallbackBiomeId
end

function WorldGenerationServiceClient.GetDepthLayerAtWorldPosition(
	self: WorldGenerationServiceClient,
	worldPosition: Vector3
): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.state.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.state.tileSize)
	local chunkX = toChunkCoordinate(tileX, self.state.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.state.chunkSize)
	local snapshot = self.chunkSnapshots[packChunkKey(chunkX, chunkY)]
	if snapshot == nil then
		return DEPTH_LAYER_CODE_SKY
	end

	local localX = tileX - snapshot.tileMinX
	local localY = tileY - snapshot.tileMinY
	if localX < 0 or localX >= snapshot.width or localY < 0 or localY >= snapshot.height then
		return DEPTH_LAYER_CODE_SKY
	end
	local index = computeTileIndex(localX, localY, snapshot.width)
	return snapshot.depthLayers[index] or DEPTH_LAYER_CODE_SKY
end

function WorldGenerationServiceClient.GetDepthBelowSurfaceAtWorldPosition(
	self: WorldGenerationServiceClient,
	worldPosition: Vector3
): number
	local tileX = toTileCoordinate(worldPosition.Z - self.worldOrigin.Z, self.state.tileSize)
	local tileY = toTileCoordinate(worldPosition.Y - self.worldOrigin.Y, self.state.tileSize)
	local chunkX = toChunkCoordinate(tileX, self.state.chunkSize)
	local chunkY = toChunkCoordinate(tileY, self.state.chunkSize)
	local snapshot = self.chunkSnapshots[packChunkKey(chunkX, chunkY)]
	if snapshot == nil then
		return -1
	end

	local localX = tileX - snapshot.tileMinX
	local localY = tileY - snapshot.tileMinY
	if localX < 0 or localX >= snapshot.width or localY < 0 or localY >= snapshot.height then
		return -1
	end
	local index = computeTileIndex(localX, localY, snapshot.width)
	return snapshot.depthBelowSurface[index] or -1
end

function WorldGenerationServiceClient.Init(self: WorldGenerationServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = WorldGenerationServiceUtils.CreateDefaultState()
	self.stateChanged = Signal.new()
	self.chunkSnapshotsChanged = Signal.new()
	local visualPreloadMarginPixels, visualBuildTimeBudgetSeconds, visualUnloadTimeBudgetSeconds, maxPooledVisualParts =
		GetClientVisualSettings()

	self.worldFolder = nil :: Folder?
	self.chunksFolder = nil :: Folder?
	self.worldOrigin = DEFAULT_WORLD_ORIGIN
	self.basePlaneX = DEFAULT_BASE_PLANE_X
	self.treeVariantDefinitions = createTreeVariantDefinitions()
	self.propTemplatesByPropId = GetPropTemplatesByPropId()
	self.chunkSnapshots = {} :: { [string]: ChunkSnapshot }
	self.chunkVisuals = {} :: { [string]: ChunkVisualRuntime }
	self.visibleChunkKeys = {} :: { [string]: boolean }
	self.dirtyChunkLookup = {} :: { [string]: boolean }
	self.rebuildQueue = Queue.new()
	self.rebuildLookup = {} :: { [string]: boolean }
	self.unloadQueue = Queue.new()
	self.unloadLookup = {} :: { [string]: boolean }
	self.lastChunkBuildAt = {} :: { [string]: number }
	self.chunkAnimationSkipUntil = {} :: { [string]: number }
	self.totalVisualPartCount = 0
	self.visualPreloadMarginPixels = visualPreloadMarginPixels
	self.visualBuildTimeBudgetSeconds = visualBuildTimeBudgetSeconds
	self.visualUnloadTimeBudgetSeconds = visualUnloadTimeBudgetSeconds
	self.maxPooledVisualParts = maxPooledVisualParts
	self.terrainVisualPartPool = {} :: { Part }
	self.activeChunkBuildJob = nil :: ChunkVisualBuildJob?
	self.isProcessingRebuildQueue = false
	self.visibilityRefreshAccumulator = VISIBILITY_REFRESH_INTERVAL
	self.hoveredTerrainTileX = nil :: number?
	self.hoveredTerrainTileY = nil :: number?
	self.hoveredTerrainChunkKey = nil :: string?
	self.hoveredTerrainRuntime = nil :: TerrainHoverRuntime?

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)
	self.janitor:GiveChore(function()
		self.chunkSnapshotsChanged:Destroy()
	end)
	self.janitor:GiveChore(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:OnHeartbeat(deltaTime)
	end))

	if ENABLE_CLIENT_VISUALS then
		self:GetChunksFolder()
	end
	self:RefreshWorldAttributes()
	self:RequestSync()
end

function WorldGenerationServiceClient.Destroy(self: WorldGenerationServiceClient)
	self:ClearHoveredTerrainTile()
	self:CancelActiveChunkBuildJob(nil)
	local chunkVisuals = self.chunkVisuals :: { [string]: any }
	for chunkKey in pairs(chunkVisuals) do
		self:DestroyChunkVisual(chunkKey)
	end
	table.clear(self.chunkSnapshots)
	table.clear(self.visibleChunkKeys)
	table.clear(self.dirtyChunkLookup)
	table.clear(self.rebuildLookup)
	table.clear(self.lastChunkBuildAt)
	table.clear(self.chunkAnimationSkipUntil)
	self.rebuildQueue = Queue.new()
	self:ClearChunkVisualUnloadQueue()
	self:ClearTerrainVisualPartPool()

	if self.janitor then
		self.janitor:Destroy()
	end
end

type WorldGenerationServiceClient = typeof(WorldGenerationServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass,
	state: WorldGenerationServiceState,
	stateChanged: SignalObject,
	chunkSnapshotsChanged: SignalObject,
	worldFolder: Folder?,
	chunksFolder: Folder?,
	worldOrigin: Vector3,
	basePlaneX: number,
	treeVariantDefinitions: { TreeVariantDefinition },
	propTemplatesByPropId: { [number]: { Instance } },
	chunkSnapshots: { [string]: ChunkSnapshot },
	chunkVisuals: { [string]: ChunkVisualRuntime },
	visibleChunkKeys: { [string]: boolean },
	dirtyChunkLookup: { [string]: boolean },
	rebuildQueue: QueueClass<string>,
	rebuildLookup: { [string]: boolean },
	unloadQueue: QueueClass<string>,
	unloadLookup: { [string]: boolean },
	lastChunkBuildAt: { [string]: number },
	chunkAnimationSkipUntil: { [string]: number },
	totalVisualPartCount: number,
	visualPreloadMarginPixels: number,
	visualBuildTimeBudgetSeconds: number,
	visualUnloadTimeBudgetSeconds: number,
	maxPooledVisualParts: number,
	terrainVisualPartPool: { Part },
	activeChunkBuildJob: ChunkVisualBuildJob?,
	isProcessingRebuildQueue: boolean,
	visibilityRefreshAccumulator: number,
	hoveredTerrainTileX: number?,
	hoveredTerrainTileY: number?,
	hoveredTerrainChunkKey: string?,
	hoveredTerrainRuntime: TerrainHoverRuntime?,
}

return WorldGenerationServiceClient :: WorldGenerationServiceClient
