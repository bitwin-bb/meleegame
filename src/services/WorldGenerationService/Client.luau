--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)
local ProceduralTree = require(ReplicatedStorage.Shared.Classes.WorldGeneration.Tree)
local WorldGenerationServiceUtils = require(ReplicatedStorage.Shared.Services.WorldGenerationService.WorldGenerationServiceUtils)

type WorldGenerationServiceState = WorldGenerationServiceUtils.WorldGenerationServiceState
type ProceduralTreeConfig = ProceduralTree.ProceduralTreeConfig

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: WorldGenerationServiceState) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: WorldGenerationServiceState) -> (),
	Destroy: (self: SignalObject) -> (),
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
	biomeTypes: { number },
	dominantBiomeId: number,
	dominantBiomeType: number,
	backgroundLayers: { ChunkLayerSnapshot },
	trees: { TreeSpawnSnapshot },
	props: { PropSpawnSnapshot },
	revision: number,
}

type ChunkVisualRuntime = {
	model: Model,
	partCount: number,
	revision: number,
	builtAt: number,
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

type TreeVariantDefinition = {
	config: ProceduralTreeConfig,
	estimatedPartCount: number,
}

local WorldGenerationServiceClient = {}
local ENABLE_CLIENT_VISUALS = true

local WORLD_FOLDER_NAME = "WorldGeneration"
local CHUNKS_FOLDER_NAME = "Chunks"
local DEFAULT_BASE_PLANE_X = 0
local DEFAULT_WORLD_ORIGIN = Vector3.zero
local MAX_CHUNK_REBUILDS_PER_HEARTBEAT = 2
local MAX_VISUAL_PARTS_TOTAL = 35000
local MAX_VISUAL_PARTS_PER_CHUNK = 2800
local MIN_SECONDS_BETWEEN_REBUILDS_PER_CHUNK = 0.08
local VISIBILITY_REFRESH_INTERVAL = 0.1
local MAX_REBUILD_QUEUE_LENGTH = 2048
local DEFAULT_CHUNK_ANIMATION_SKIP_SECONDS = 1.5
local MAX_CHUNK_ANIMATION_SKIP_SECONDS = 8
local FOREGROUND_TILE_AIR_ID = 0
local TREE_PLANE_DEPTH_ALPHA = 0.5
local TREE_SURFACE_OFFSET_Y_TILES = 1
local SKIP_WORLD_ANIMATOR_ATTRIBUTE = "SkipWorldAnimator"
local ANIMATING_WORLD_ANIMATOR_ATTRIBUTE = "WorldAnimatorAnimating"
local MIN_INT32 = -2147483648
local MAX_INT32 = 2147483647
local BIOME_TYPE_NORMAL = 1
local BIOME_TYPE_CORRUPTION = 2
local BIOME_ID_FOREST = 1
local BIOME_ID_JUNGLE = 4
local PROP_ID_CORRUPTION_SPIKE = 1
local DEPTH_LAYER_CODE_SKY = 0
local DEPTH_LAYER_CODE_UNDERGROUND = 2
local MIN_DEPTH_LAYER_CODE = 0
local MAX_DEPTH_LAYER_CODE = 4
local MIN_DEPTH_BELOW_SURFACE = -8192
local MAX_DEPTH_BELOW_SURFACE = 8192

local TILE_VISUALS: { [number]: TileVisual } = {
	[1] = {
		name = "Grass",
		color = Color3.fromRGB(95, 159, 53),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[17] = {
		name = "JungleGrass",
		color = Color3.fromRGB(113, 186, 72),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[2] = {
		name = "Dirt",
		color = Color3.fromRGB(108, 78, 52),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[3] = {
		name = "Stone",
		color = Color3.fromRGB(108, 113, 122),
		material = Enum.Material.Slate,
		transparency = 0,
	},
	[4] = {
		name = "Sand",
		color = Color3.fromRGB(225, 206, 136),
		material = Enum.Material.Sand,
		transparency = 0,
	},
	[5] = {
		name = "Sandstone",
		color = Color3.fromRGB(183, 154, 109),
		material = Enum.Material.Sandstone,
		transparency = 0,
	},
	[6] = {
		name = "Snow",
		color = Color3.fromRGB(232, 240, 255),
		material = Enum.Material.Snow,
		transparency = 0,
	},
	[7] = {
		name = "Ice",
		color = Color3.fromRGB(178, 214, 255),
		material = Enum.Material.Glacier,
		transparency = 0,
	},
	[8] = {
		name = "Mud",
		color = Color3.fromRGB(112, 90, 61),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[9] = {
		name = "Clay",
		color = Color3.fromRGB(135, 98, 73),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[10] = {
		name = "CopperOre",
		color = Color3.fromRGB(189, 118, 63),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[11] = {
		name = "IronOre",
		color = Color3.fromRGB(141, 134, 116),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[12] = {
		name = "SilverOre",
		color = Color3.fromRGB(177, 177, 185),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[13] = {
		name = "GoldOre",
		color = Color3.fromRGB(214, 186, 62),
		material = Enum.Material.Metal,
		transparency = 0,
	},
	[14] = {
		name = "CorruptGrass",
		color = Color3.fromRGB(131, 84, 193),
		material = Enum.Material.Grass,
		transparency = 0,
	},
	[15] = {
		name = "CorruptSoil",
		color = Color3.fromRGB(116, 84, 88),
		material = Enum.Material.Ground,
		transparency = 0,
	},
	[16] = {
		name = "CorruptStone",
		color = Color3.fromRGB(126, 104, 160),
		material = Enum.Material.Rock,
		transparency = 0,
	},
}

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
				BranchColor = Color3.fromRGB(56, 39, 89),
				LeafColor = Color3.fromRGB(153, 92, 210),
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
				BranchColor = Color3.fromRGB(49, 33, 81),
				LeafColor = Color3.fromRGB(171, 101, 231),
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
				BranchColor = Color3.fromRGB(88, 65, 42),
				LeafColor = Color3.fromRGB(67, 178, 86),
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
				BranchColor = Color3.fromRGB(82, 60, 39),
				LeafColor = Color3.fromRGB(74, 192, 96),
				UseWelds = true,
				BranchCanCollide = false,
				ModelName = "ProceduralTree_Jungle2",
			},
			estimatedPartCount = 228,
		},
	}
end

local function resolveTreeVariantDefinition(
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

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw :: number), minimum, maximum)
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

local function resolvePropsTemplateFolder(): Folder?
	local worldGeneration = resolveWorldGenerationAssetsFolder()
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

local function resolvePropTemplatesByPropId(): { [number]: { Instance } }
	local templatesByPropId: { [number]: { Instance } } = {}
	local propsFolder = resolvePropsTemplateFolder()
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

	return templatesByPropId
end

local function cloneTemplateByVariant(templates: { Instance }, variantIndexRaw: any): Instance?
	local count = #templates
	if count <= 0 then
		return nil
	end
	local variantIndex = 1
	if typeof(variantIndexRaw) == "number"
		and variantIndexRaw == variantIndexRaw
		and variantIndexRaw ~= math.huge
		and variantIndexRaw ~= -math.huge
	then
		variantIndex = math.max(1, math.floor(variantIndexRaw))
	end
	local normalizedIndex = ((variantIndex - 1) % count) + 1
	local source = templates[normalizedIndex]
	if source == nil then
		return nil
	end
	if source:IsA("Model") or source:IsA("BasePart") then
		return source:Clone()
	end
	return nil
end

local function createCorruptionSpikeFallbackModel(variantIndex: number, seed: number): Model
	local randomObject = Random.new(seed)
	local model = Instance.new("Model")
	model.Name = "CorruptionSpike"

	local segmentCount = if variantIndex % 2 == 0 then 2 else 1
	for segment = 1, segmentCount do
		local wedge = Instance.new("WedgePart")
		wedge.Name = `Spike_{segment}`
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.Material = Enum.Material.Slate
		wedge.Color = Color3.fromRGB(
			76 + randomObject:NextInteger(-6, 6),
			56 + randomObject:NextInteger(-5, 5),
			122 + randomObject:NextInteger(-8, 8)
		)
		local height = if segment == 1 then randomObject:NextNumber(3.2, 4.4) else randomObject:NextNumber(2.1, 3.1)
		local width = randomObject:NextNumber(0.7, 1.1)
		local depth = randomObject:NextNumber(0.9, 1.4)
		wedge.Size = Vector3.new(width, height, depth)
		local yaw = math.rad(randomObject:NextNumber(0, 360))
		local yOffset = if segment == 1 then height * 0.5 else height * 0.5 + 1.3
		wedge.CFrame = CFrame.new(0, yOffset, 0) * CFrame.Angles(0, yaw, 0)
		wedge.Parent = model
	end

	return model
end

local function resolvePlayerRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local rootCandidate = character:FindFirstChild("HumanoidRootPart")
	if rootCandidate ~= nil and rootCandidate:IsA("BasePart") then
		return rootCandidate
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function buildGreedyRectangles(
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

local function styleForegroundPart(part: BasePart, tileId: number)
	local style = TILE_VISUALS[tileId] or TILE_VISUALS[3]
	part.Name = style.name
	part.Color = style.color
	part.Material = style.material
	part.Transparency = style.transparency
	part.CastShadow = true
end

local function styleBackgroundPart(part: BasePart, tileId: number, layerIndex: number, layerCount: number)
	local style = TILE_VISUALS[tileId] or TILE_VISUALS[3]
	local alpha = if layerCount > 1 then (layerIndex - 1) / (layerCount - 1) else 0
	part.Name = `{style.name}Background_{layerIndex}`
	part.Color = style.color:Lerp(Color3.new(0, 0, 0), 0.28 + alpha * 0.26)
	part.Material = style.material
	part.Transparency = 0
	part.CastShadow = false
end

function WorldGenerationServiceClient.resolveWorldFolder(self: WorldGenerationServiceClient): Folder?
	local existing = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		self.worldFolder = existing
		return existing
	end

	self.worldFolder = nil
	self.chunksFolder = nil
	return nil
end

function WorldGenerationServiceClient.resolveChunksFolder(self: WorldGenerationServiceClient): Folder?
	local worldFolder = self:resolveWorldFolder()
	if worldFolder == nil then
		return nil
	end

	local existing = worldFolder:FindFirstChild(CHUNKS_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		self.chunksFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = CHUNKS_FOLDER_NAME
	folder.Parent = worldFolder
	self.chunksFolder = folder
	return folder
end

function WorldGenerationServiceClient.refreshWorldAttributes(self: WorldGenerationServiceClient)
	local worldFolder = self:resolveWorldFolder()
	if worldFolder == nil or worldFolder.Parent == nil then
		return
	end

	local originX = worldFolder:GetAttribute("WorldOriginX")
	local originY = worldFolder:GetAttribute("WorldOriginY")
	local originZ = worldFolder:GetAttribute("WorldOriginZ")
	self.worldOrigin = Vector3.new(
		if isFiniteNumber(originX) then originX else DEFAULT_WORLD_ORIGIN.X,
		if isFiniteNumber(originY) then originY else DEFAULT_WORLD_ORIGIN.Y,
		if isFiniteNumber(originZ) then originZ else DEFAULT_WORLD_ORIGIN.Z
	)

	local basePlaneX = worldFolder:GetAttribute("BasePlaneX")
	self.basePlaneX = if isFiniteNumber(basePlaneX) then basePlaneX else DEFAULT_BASE_PLANE_X
end

function WorldGenerationServiceClient.computeTileCenterPosition(
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

function WorldGenerationServiceClient.enqueueChunkRebuild(self: WorldGenerationServiceClient, chunkKey: string)
	if self.rebuildLookup[chunkKey] then
		return
	end
	if self.rebuildQueueTail - self.rebuildQueueHead + 1 >= MAX_REBUILD_QUEUE_LENGTH then
		return
	end

	self.rebuildLookup[chunkKey] = true
	self.rebuildQueueTail += 1
	self.rebuildQueue[self.rebuildQueueTail] = chunkKey
end

function WorldGenerationServiceClient.dequeueChunkRebuild(self: WorldGenerationServiceClient): string?
	if self.rebuildQueueHead > self.rebuildQueueTail then
		if self.rebuildQueueHead ~= 1 or self.rebuildQueueTail ~= 0 then
			table.clear(self.rebuildQueue)
			self.rebuildQueueHead = 1
			self.rebuildQueueTail = 0
		end
		return nil
	end

	local chunkKey = self.rebuildQueue[self.rebuildQueueHead]
	if chunkKey == nil then
		return nil
	end

	self.rebuildQueue[self.rebuildQueueHead] = nil
	self.rebuildQueueHead += 1
	if self.rebuildQueueHead > self.rebuildQueueTail then
		table.clear(self.rebuildQueue)
		self.rebuildQueueHead = 1
		self.rebuildQueueTail = 0
	end

	self.rebuildLookup[chunkKey] = nil
	return chunkKey
end

function WorldGenerationServiceClient.destroyChunkVisual(self: WorldGenerationServiceClient, chunkKey: string)
	local visual = self.chunkVisuals[chunkKey]
	if visual == nil then
		return
	end

	self.chunkVisuals[chunkKey] = nil
	self.totalVisualPartCount = math.max(0, self.totalVisualPartCount - visual.partCount)
	visual.model:Destroy()
end

function WorldGenerationServiceClient.replaceChunkVisualContents(
	self: WorldGenerationServiceClient,
	targetModel: Model,
	rebuiltModel: Model
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
	for _, child in targetModel:GetChildren() do
		child:Destroy()
	end

	for _, child in rebuiltModel:GetChildren() do
		child.Parent = targetModel
	end
	rebuiltModel:Destroy()
end

function WorldGenerationServiceClient.suppressChunkAnimationForChunkKey(
	self: WorldGenerationServiceClient,
	chunkKeyRaw: any,
	durationRaw: any?
)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end

	local duration = if isFiniteNumber(durationRaw)
		then math.clamp(durationRaw, 0.05, MAX_CHUNK_ANIMATION_SKIP_SECONDS)
		else DEFAULT_CHUNK_ANIMATION_SKIP_SECONDS
	local now = os.clock()
	local skipUntil = now + duration
	local previousSkipUntil = self.chunkAnimationSkipUntil[chunkKeyRaw]
	if previousSkipUntil ~= nil and previousSkipUntil > skipUntil then
		skipUntil = previousSkipUntil
	end
	self.chunkAnimationSkipUntil[chunkKeyRaw] = skipUntil
end

function WorldGenerationServiceClient.suppressChunkAnimationForTile(
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

	self:suppressChunkAnimationForChunkKey(packChunkKey(chunkX, chunkY), durationRaw)

	if localTileX == 0 then
		self:suppressChunkAnimationForChunkKey(packChunkKey(chunkX - 1, chunkY), durationRaw)
	elseif localTileX == chunkSize - 1 then
		self:suppressChunkAnimationForChunkKey(packChunkKey(chunkX + 1, chunkY), durationRaw)
	end

	if localTileY == 0 then
		self:suppressChunkAnimationForChunkKey(packChunkKey(chunkX, chunkY - 1), durationRaw)
	elseif localTileY == chunkSize - 1 then
		self:suppressChunkAnimationForChunkKey(packChunkKey(chunkX, chunkY + 1), durationRaw)
	end
end

function WorldGenerationServiceClient.shouldSkipChunkAnimationForKey(
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

function WorldGenerationServiceClient.sanitizeChunkSnapshot(
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
	local width = sanitizeInteger(source.width, 1, 256, self.state.chunkSize)
	local height = sanitizeInteger(source.height, 1, 256, self.state.chunkSize)
	local tileMinX = sanitizeInteger(source.tileMinX, -10000000, 10000000, chunkX * width)
	local tileMinY = sanitizeInteger(source.tileMinY, -10000000, 10000000, chunkY * height)
	local key = if typeof(source.key) == "string" and source.key ~= "" then source.key else packChunkKey(chunkX, chunkY)
	local revision = sanitizeInteger(source.revision, 0, 2147483646, 0)

	local totalTiles = width * height
	local tiles = table.create(totalTiles, FOREGROUND_TILE_AIR_ID)
	local tilesRaw = if typeof(source.tiles) == "table" then (source.tiles :: { any }) else {}
	for tileIndex = 1, totalTiles do
		local rawTileId = tilesRaw[tileIndex]
		if isFiniteNumber(rawTileId) then
			tiles[tileIndex] = math.floor(rawTileId)
		end
	end
	local depthLayers = table.create(totalTiles, DEPTH_LAYER_CODE_UNDERGROUND)
	local depthLayersRaw = if typeof(source.depthLayers) == "table" then (source.depthLayers :: { any }) else {}
	for tileIndex = 1, totalTiles do
		local rawDepthLayerCode = depthLayersRaw[tileIndex]
		if isFiniteNumber(rawDepthLayerCode) then
			depthLayers[tileIndex] = sanitizeInteger(
				rawDepthLayerCode,
				MIN_DEPTH_LAYER_CODE,
				MAX_DEPTH_LAYER_CODE,
				DEPTH_LAYER_CODE_UNDERGROUND
			)
		elseif tiles[tileIndex] == FOREGROUND_TILE_AIR_ID then
			depthLayers[tileIndex] = DEPTH_LAYER_CODE_SKY
		end
	end
	local depthBelowSurface = table.create(totalTiles, 0)
	local depthBelowSurfaceRaw = if typeof(source.depthBelowSurface) == "table"
		then (source.depthBelowSurface :: { any })
		else {}
	for tileIndex = 1, totalTiles do
		local rawDepthBelowSurface = depthBelowSurfaceRaw[tileIndex]
		if isFiniteNumber(rawDepthBelowSurface) then
			depthBelowSurface[tileIndex] = sanitizeInteger(
				rawDepthBelowSurface,
				MIN_DEPTH_BELOW_SURFACE,
				MAX_DEPTH_BELOW_SURFACE,
				0
			)
		elseif depthLayers[tileIndex] == DEPTH_LAYER_CODE_SKY then
			depthBelowSurface[tileIndex] = -1
		end
	end

	local dominantBiomeId = sanitizeInteger(source.dominantBiomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, BIOME_ID_FOREST)
	local biomeIds = table.create(totalTiles, dominantBiomeId)
	local biomeIdsRaw = if typeof(source.biomeIds) == "table" then (source.biomeIds :: { any }) else {}
	for tileIndex = 1, totalTiles do
		local rawBiomeId = biomeIdsRaw[tileIndex]
		if isFiniteNumber(rawBiomeId) then
			biomeIds[tileIndex] = sanitizeInteger(rawBiomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, dominantBiomeId)
		end
	end

	local dominantBiomeType =
		sanitizeInteger(source.dominantBiomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, BIOME_TYPE_NORMAL)
	local biomeTypes = table.create(totalTiles, dominantBiomeType)
	local biomeTypesRaw = if typeof(source.biomeTypes) == "table" then (source.biomeTypes :: { any }) else {}
	for tileIndex = 1, totalTiles do
		local rawBiomeType = biomeTypesRaw[tileIndex]
		if isFiniteNumber(rawBiomeType) then
			biomeTypes[tileIndex] = sanitizeInteger(rawBiomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, dominantBiomeType)
		end
	end

	local backgroundLayers: { ChunkLayerSnapshot } = {}
	local layersRaw = if typeof(source.backgroundLayers) == "table" then (source.backgroundLayers :: { any }) else {}
	for _, layerRaw in layersRaw do
		if typeof(layerRaw) ~= "table" then
			continue
		end

		local layer = layerRaw :: { [string]: any }
		local layerWidth = sanitizeInteger(layer.width, 1, 512, width)
		local layerHeight = sanitizeInteger(layer.height, 1, 512, height)
		local layerTileMinX = sanitizeInteger(layer.tileMinX, -10000000, 10000000, tileMinX)
		local layerTileMinY = sanitizeInteger(layer.tileMinY, -10000000, 10000000, tileMinY)
		local layerIndex = sanitizeInteger(layer.layerIndex, 1, 64, #backgroundLayers + 1)
		local layerTotalTiles = layerWidth * layerHeight
		local layerTiles = table.create(layerTotalTiles, FOREGROUND_TILE_AIR_ID)
		local layerTilesRaw = if typeof(layer.tiles) == "table" then (layer.tiles :: { any }) else {}
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
	local treesRaw = if typeof(source.trees) == "table" then (source.trees :: { any }) else {}
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
		local fallbackVariantIndex = sanitizeInteger(tree.templateIndex, 1, 128, 1)
		local variantIndex = sanitizeInteger(tree.variantIndex, 1, 128, fallbackVariantIndex)
		local fallbackSeed = sanitizeInteger(
			tileX * 92821 + tileY * 68917 + variantIndex * 193 + 1337,
			MIN_INT32,
			MAX_INT32,
			1337
		)

		table.insert(trees, {
			tileX = tileX,
			tileY = tileY,
			variantIndex = variantIndex,
			seed = sanitizeInteger(tree.seed, MIN_INT32, MAX_INT32, fallbackSeed),
			biomeType = if isFiniteNumber(tree.biomeType)
				then sanitizeInteger(tree.biomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, dominantBiomeType)
				else nil,
			biomeId = if isFiniteNumber(tree.biomeId)
				then sanitizeInteger(tree.biomeId, BIOME_ID_FOREST, BIOME_ID_JUNGLE, dominantBiomeId)
				else nil,
			templateIndex = if isFiniteNumber(tree.templateIndex)
				then sanitizeInteger(tree.templateIndex, 1, 128, variantIndex)
				else nil,
		})
	end

	local props: { PropSpawnSnapshot } = {}
	local propsRaw = if typeof(source.props) == "table" then (source.props :: { any }) else {}
	for _, propRaw in propsRaw do
		if typeof(propRaw) ~= "table" then
			continue
		end

		local prop = propRaw :: { [string]: any }
		if not isFiniteNumber(prop.tileX) or not isFiniteNumber(prop.tileY) or not isFiniteNumber(prop.propId) then
			continue
		end

		local propId = sanitizeInteger(prop.propId, 1, 1024, PROP_ID_CORRUPTION_SPIKE)
		if propId == PROP_ID_CORRUPTION_SPIKE then
			continue
		end
		local variantIndex = sanitizeInteger(prop.variantIndex, 1, 32, 1)
		local tileX = math.floor(prop.tileX)
		local tileY = math.floor(prop.tileY)
		local fallbackSeed = sanitizeInteger(
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
			seed = sanitizeInteger(prop.seed, MIN_INT32, MAX_INT32, fallbackSeed),
			biomeType = if isFiniteNumber(prop.biomeType)
				then sanitizeInteger(prop.biomeType, BIOME_TYPE_NORMAL, BIOME_TYPE_CORRUPTION, dominantBiomeType)
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
		biomeTypes = biomeTypes,
		dominantBiomeId = dominantBiomeId,
		dominantBiomeType = dominantBiomeType,
		backgroundLayers = backgroundLayers,
		trees = trees,
		props = props,
		revision = revision,
	}
end

function WorldGenerationServiceClient.onChunkSnapshot(self: WorldGenerationServiceClient, snapshotRaw: any)
	local snapshot = self:sanitizeChunkSnapshot(snapshotRaw)
	if snapshot == nil then
		return
	end

	local existingVisual = self.chunkVisuals[snapshot.key]
	local wasAlreadyCurrentRevision = existingVisual ~= nil and existingVisual.revision == snapshot.revision
	self.chunkSnapshots[snapshot.key] = snapshot
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	if wasAlreadyCurrentRevision and self.dirtyChunkLookup[snapshot.key] ~= true then
		return
	end
	self.dirtyChunkLookup[snapshot.key] = true
	self:enqueueChunkRebuild(snapshot.key)
end

function WorldGenerationServiceClient.onChunkUnloaded(self: WorldGenerationServiceClient, chunkKeyRaw: any)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end

	self.chunkSnapshots[chunkKeyRaw] = nil
	self.visibleChunkKeys[chunkKeyRaw] = nil
	self.dirtyChunkLookup[chunkKeyRaw] = nil
	self.rebuildLookup[chunkKeyRaw] = nil
	self.lastChunkBuildAt[chunkKeyRaw] = nil
	self.chunkAnimationSkipUntil[chunkKeyRaw] = nil
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	self:destroyChunkVisual(chunkKeyRaw)
end

function WorldGenerationServiceClient.buildChunkVisualModel(
	self: WorldGenerationServiceClient,
	snapshot: ChunkSnapshot
): (Model, number)
	local model = Instance.new("Model")
	model.Name = `Chunk_{snapshot.chunkX}_{snapshot.chunkY}`
	model:SetAttribute("ChunkX", snapshot.chunkX)
	model:SetAttribute("ChunkY", snapshot.chunkY)
	model:SetAttribute("ChunkKey", snapshot.key)
	model:SetAttribute("ChunkRevision", snapshot.revision)
	model:SetAttribute("DominantBiomeId", snapshot.dominantBiomeId)
	model:SetAttribute("DominantBiomeType", snapshot.dominantBiomeType)
	model:SetAttribute("IsCorruptionChunk", snapshot.dominantBiomeType == BIOME_TYPE_CORRUPTION)

	local terrainFolder = Instance.new("Folder")
	terrainFolder.Name = "Terrain"
	terrainFolder.Parent = model

	local backgroundFolder = Instance.new("Folder")
	backgroundFolder.Name = "BackgroundDepth"
	backgroundFolder.Parent = model

	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder.Parent = model

	local propsFolder = Instance.new("Folder")
	propsFolder.Name = "Props"
	propsFolder.Parent = model

	local tileDepth = self.state.tileDepth
	local tileSize = self.state.tileSize
	local partCount = 0

	local terrainRects = buildGreedyRectangles(
		snapshot.tiles,
		snapshot.width,
		snapshot.height,
		function(value: number): boolean
			return value ~= FOREGROUND_TILE_AIR_ID
		end
	)

	for rectIndex, rect in terrainRects do
		if partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			break
		end

		local part = Instance.new("Part")
		part.Anchored = true
		part.Locked = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Size = Vector3.new(tileDepth, tileSize * rect.height, tileSize * rect.width)
		styleForegroundPart(part, rect.value)

		local centerTileX = snapshot.tileMinX + rect.x + rect.width * 0.5
		local centerTileY = snapshot.tileMinY + rect.y + rect.height * 0.5
		part.CFrame = CFrame.new(self:computeTileCenterPosition(centerTileX, centerTileY, 0))
		part.Parent = terrainFolder
		partCount += 1

		if rectIndex % 128 == 0 then
			task.wait()
		end
	end

	local layerCount = #snapshot.backgroundLayers
	for layerListIndex = 1, layerCount do
		if partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			break
		end

		local layerData = snapshot.backgroundLayers[layerListIndex]
		local layerRects = buildGreedyRectangles(
			layerData.tiles,
			layerData.width,
			layerData.height,
			function(value: number): boolean
				return value ~= FOREGROUND_TILE_AIR_ID
			end
		)

		local planeOffset = -(layerListIndex * tileDepth)
		for rectIndex, rect in layerRects do
			if partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
				break
			end

			local part = Instance.new("Part")
			part.Anchored = true
			part.Locked = true
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Size = Vector3.new(tileDepth, tileSize * rect.height, tileSize * rect.width)
			styleBackgroundPart(part, rect.value, layerListIndex, layerCount)

			local centerTileX = layerData.tileMinX + rect.x + rect.width * 0.5
			local centerTileY = layerData.tileMinY + rect.y + rect.height * 0.5
			part.CFrame = CFrame.new(self:computeTileCenterPosition(centerTileX, centerTileY, planeOffset))
			part.Parent = backgroundFolder
			partCount += 1

			if rectIndex % 128 == 0 then
				task.wait()
			end
		end
	end

	local treeCount = 0
	local furthestBackgroundOffset = -math.max(1, #snapshot.backgroundLayers) * tileDepth
	local treePlaneOffset = furthestBackgroundOffset * TREE_PLANE_DEPTH_ALPHA
	local treeVariantDefinitions = self.treeVariantDefinitions
	for _, treeSpawnData in snapshot.trees do
		if partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			break
		end

		local variantDefinition = resolveTreeVariantDefinition(treeVariantDefinitions, treeSpawnData.variantIndex)
		if partCount + variantDefinition.estimatedPartCount > MAX_VISUAL_PARTS_PER_CHUNK then
			break
		end

		local centerTileX = treeSpawnData.tileX + 0.5
		local centerTileY = treeSpawnData.tileY + TREE_SURFACE_OFFSET_Y_TILES
		local position = self:computeTileCenterPosition(centerTileX, centerTileY, treePlaneOffset)

		local treeConfig = table.clone(variantDefinition.config) :: { [string]: any }
		treeConfig.Seed = treeSpawnData.seed
		treeConfig.ModelName = `Tree_{snapshot.chunkX}_{snapshot.chunkY}_{treeCount + 1}`

		local proceduralTree = ProceduralTree.new(treeConfig)
		local generatedTreeModel = proceduralTree:generate(treesFolder, CFrame.new(position))
		generatedTreeModel:SetAttribute("VariantIndex", treeSpawnData.variantIndex)
		generatedTreeModel:SetAttribute("TreeSeed", treeSpawnData.seed)

		local generatedPartCount = countBaseParts(generatedTreeModel)
		if partCount + generatedPartCount > MAX_VISUAL_PARTS_PER_CHUNK then
			generatedTreeModel:Destroy()
			break
		end

		partCount += generatedPartCount
		treeCount += 1
	end

	local propCount = 0
	for _, propSpawnData in snapshot.props do
		if partCount >= MAX_VISUAL_PARTS_PER_CHUNK then
			break
		end

		if propSpawnData.propId ~= PROP_ID_CORRUPTION_SPIKE then
			continue
		end

		local templates = self.propTemplatesByPropId[propSpawnData.propId]
		local propInstance = if templates ~= nil
			then cloneTemplateByVariant(templates, propSpawnData.variantIndex)
			else nil
		if propInstance == nil then
			propInstance = createCorruptionSpikeFallbackModel(propSpawnData.variantIndex, propSpawnData.seed)
		end

		local centerTileX = propSpawnData.tileX + 0.5
		local centerTileY = propSpawnData.tileY + TREE_SURFACE_OFFSET_Y_TILES
		local position = self:computeTileCenterPosition(centerTileX, centerTileY, treePlaneOffset)
		local generatedPartCount = 0
		if propInstance:IsA("Model") then
			propInstance:PivotTo(CFrame.new(position))
			local boundsCFrame, boundsSize = propInstance:GetBoundingBox()
			local boundsBottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
			local bottomOffset = position.Y - boundsBottomY
			if math.abs(bottomOffset) > 0.0001 then
				propInstance:PivotTo(propInstance:GetPivot() + Vector3.new(0, bottomOffset, 0))
			end

			generatedPartCount = countBaseParts(propInstance)
			for _, descendant in propInstance:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
				end
			end
		elseif propInstance:IsA("BasePart") then
			propInstance.CFrame = CFrame.new(position + Vector3.new(0, propInstance.Size.Y * 0.5, 0))
			propInstance.Anchored = true
			propInstance.CanCollide = false
			propInstance.CanQuery = false
			propInstance.CanTouch = false
			generatedPartCount = 1
		end

		if partCount + generatedPartCount > MAX_VISUAL_PARTS_PER_CHUNK then
			propInstance:Destroy()
			break
		end

		partCount += generatedPartCount
		propCount += 1
		propInstance.Parent = propsFolder
	end

	model:SetAttribute("TreeCount", treeCount)
	model:SetAttribute("PropCount", propCount)
	return model, partCount
end

function WorldGenerationServiceClient.processChunkRebuildQueue(self: WorldGenerationServiceClient)
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	if self.rebuildQueueHead > self.rebuildQueueTail then
		return
	end

	local chunksFolder = self:resolveChunksFolder()
	if chunksFolder == nil then
		return
	end
	local now = os.clock()
	local processed = 0
	local inspected = 0
	local maxInspections = math.max(1, self.rebuildQueueTail - self.rebuildQueueHead + 1)
	while processed < MAX_CHUNK_REBUILDS_PER_HEARTBEAT and inspected < maxInspections do
		local chunkKey = self:dequeueChunkRebuild()
		if chunkKey == nil then
			break
		end
		inspected += 1

		if self.visibleChunkKeys[chunkKey] == nil then
			continue
		end

		local snapshot = self.chunkSnapshots[chunkKey]
		if snapshot == nil then
			continue
		end

		local existing = self.chunkVisuals[chunkKey]
		if existing ~= nil and existing.revision == snapshot.revision and self.dirtyChunkLookup[chunkKey] ~= true then
			continue
		end
		if existing ~= nil and existing.model:GetAttribute(ANIMATING_WORLD_ANIMATOR_ATTRIBUTE) == true then
			self:enqueueChunkRebuild(chunkKey)
			continue
		end

		local lastBuiltAt = self.lastChunkBuildAt[chunkKey] or 0
		if now - lastBuiltAt < MIN_SECONDS_BETWEEN_REBUILDS_PER_CHUNK then
			self:enqueueChunkRebuild(chunkKey)
			continue
		end

		local model, partCount = self:buildChunkVisualModel(snapshot)
		local existingPartCount = if existing ~= nil then existing.partCount else 0
		local projectedPartTotal = self.totalVisualPartCount - existingPartCount + partCount
		if projectedPartTotal > MAX_VISUAL_PARTS_TOTAL then
			model:Destroy()
			continue
		end

		local shouldSkipChunkAnimation = self:shouldSkipChunkAnimationForKey(chunkKey, now)
		local visualModel = model
		if existing ~= nil then
			shouldSkipChunkAnimation = true
			self:replaceChunkVisualContents(existing.model, model)
			visualModel = existing.model
		end

		visualModel:SetAttribute(SKIP_WORLD_ANIMATOR_ATTRIBUTE, shouldSkipChunkAnimation)
		if visualModel.Parent == nil then
			visualModel.Parent = chunksFolder
		end

		self.chunkVisuals[chunkKey] = {
			model = visualModel,
			partCount = partCount,
			revision = snapshot.revision,
			builtAt = now,
		}
		self.lastChunkBuildAt[chunkKey] = now
		self.totalVisualPartCount = projectedPartTotal
		self.dirtyChunkLookup[chunkKey] = nil
		processed += 1
	end
end

function WorldGenerationServiceClient.refreshVisibleChunks(self: WorldGenerationServiceClient)
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	local rootPart = resolvePlayerRootPart(self.localPlayer)
	if rootPart == nil then
		for chunkKey in self.chunkVisuals do
			self:destroyChunkVisual(chunkKey)
		end
		table.clear(self.visibleChunkKeys)
		return
	end

	self:refreshWorldAttributes()

	local tileX = toTileCoordinate(rootPart.Position.Z - self.worldOrigin.Z, self.state.tileSize)
	local tileY = toTileCoordinate(rootPart.Position.Y - self.worldOrigin.Y, self.state.tileSize)
	local centerChunkX = toChunkCoordinate(tileX, self.state.chunkSize)
	local centerChunkY = toChunkCoordinate(tileY, self.state.chunkSize)
	local renderDistance = sanitizeInteger(
		self.state.renderDistanceChunks,
		1,
		WorldGenerationServiceUtils.MAX_RENDER_DISTANCE_CHUNKS,
		WorldGenerationServiceUtils.DEFAULT_RENDER_DISTANCE_CHUNKS
	)
	local verticalRenderDistance = sanitizeInteger(
		self.state.verticalRenderDistanceChunks,
		1,
		WorldGenerationServiceUtils.MAX_RENDER_DISTANCE_CHUNKS,
		WorldGenerationServiceUtils.DEFAULT_VERTICAL_RENDER_DISTANCE_CHUNKS
	)
	local radiusSquared = renderDistance * renderDistance

	local nextVisible: { [string]: boolean } = {}
	for chunkKey, snapshot in self.chunkSnapshots do
		local deltaX = snapshot.chunkX - centerChunkX
		local deltaY = snapshot.chunkY - centerChunkY
		if math.abs(deltaY) > verticalRenderDistance then
			continue
		end
		if deltaX * deltaX + deltaY * deltaY > radiusSquared then
			continue
		end

		nextVisible[chunkKey] = true
		local existingVisual = self.chunkVisuals[chunkKey]
		if existingVisual == nil or existingVisual.revision ~= snapshot.revision or self.dirtyChunkLookup[chunkKey] == true then
			self:enqueueChunkRebuild(chunkKey)
		end
	end

	for chunkKey in self.chunkVisuals do
		if nextVisible[chunkKey] then
			continue
		end
		self:destroyChunkVisual(chunkKey)
	end

	self.visibleChunkKeys = nextVisible
end

function WorldGenerationServiceClient.onHeartbeat(self: WorldGenerationServiceClient, deltaTime: number)
	if not ENABLE_CLIENT_VISUALS then
		return
	end
	self.visibilityRefreshAccumulator += deltaTime
	if self.visibilityRefreshAccumulator >= VISIBILITY_REFRESH_INTERVAL then
		self.visibilityRefreshAccumulator = 0
		self:refreshVisibleChunks()
	end

	self:processChunkRebuildQueue()
end

function WorldGenerationServiceClient.applyState(self: WorldGenerationServiceClient, stateRaw: any)
	self.state = WorldGenerationServiceUtils.createState(stateRaw, self.state)
	self.stateChanged:Fire(WorldGenerationServiceUtils.cloneState(self.state))
end

function WorldGenerationServiceClient.requestSync(self: WorldGenerationServiceClient)
	self.networker:fire(WorldGenerationServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function WorldGenerationServiceClient.setRenderDistance(
	self: WorldGenerationServiceClient,
	renderDistanceRaw: any,
	verticalRenderDistanceRaw: any?
)
	self.networker:fire(
		WorldGenerationServiceUtils.NETWORK_METHOD_SET_RENDER_DISTANCE,
		renderDistanceRaw,
		verticalRenderDistanceRaw
	)
end

function WorldGenerationServiceClient.getState(self: WorldGenerationServiceClient): WorldGenerationServiceState
	return WorldGenerationServiceUtils.cloneState(self.state)
end

function WorldGenerationServiceClient.getRenderDistance(self: WorldGenerationServiceClient): (number, number)
	return self.state.renderDistanceChunks, self.state.verticalRenderDistanceChunks
end

function WorldGenerationServiceClient.getBiomeTypeAtWorldPosition(
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

function WorldGenerationServiceClient.getBiomeIdAtWorldPosition(
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

function WorldGenerationServiceClient.getDepthLayerAtWorldPosition(
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

function WorldGenerationServiceClient.getDepthBelowSurfaceAtWorldPosition(
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

function WorldGenerationServiceClient.init(self: WorldGenerationServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("WorldGenerationService", self)
	self.janitor = Janitor.new()
	self.state = WorldGenerationServiceUtils.createDefaultState()
	self.stateChanged = Signal.new()

	self.worldFolder = nil :: Folder?
	self.chunksFolder = nil :: Folder?
	self.worldOrigin = DEFAULT_WORLD_ORIGIN
	self.basePlaneX = DEFAULT_BASE_PLANE_X
	self.treeVariantDefinitions = createTreeVariantDefinitions()
	self.propTemplatesByPropId = resolvePropTemplatesByPropId()
	self.chunkSnapshots = {} :: { [string]: ChunkSnapshot }
	self.chunkVisuals = {} :: { [string]: ChunkVisualRuntime }
	self.visibleChunkKeys = {} :: { [string]: boolean }
	self.dirtyChunkLookup = {} :: { [string]: boolean }
	self.rebuildQueue = {} :: { string }
	self.rebuildQueueHead = 1
	self.rebuildQueueTail = 0
	self.rebuildLookup = {} :: { [string]: boolean }
	self.lastChunkBuildAt = {} :: { [string]: number }
	self.chunkAnimationSkipUntil = {} :: { [string]: number }
	self.totalVisualPartCount = 0
	self.visibilityRefreshAccumulator = VISIBILITY_REFRESH_INTERVAL

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)
	self.janitor:GiveChore(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:onHeartbeat(deltaTime)
	end))

	if ENABLE_CLIENT_VISUALS then
		self:resolveChunksFolder()
	end
	self:refreshWorldAttributes()
	self:requestSync()
end

function WorldGenerationServiceClient.destroy(self: WorldGenerationServiceClient)
	for chunkKey in self.chunkVisuals do
		self:destroyChunkVisual(chunkKey)
	end
	table.clear(self.chunkSnapshots)
	table.clear(self.visibleChunkKeys)
	table.clear(self.dirtyChunkLookup)
	table.clear(self.rebuildLookup)
	table.clear(self.lastChunkBuildAt)
	table.clear(self.chunkAnimationSkipUntil)
	table.clear(self.rebuildQueue)
	self.rebuildQueueHead = 1
	self.rebuildQueueTail = 0

	if self.janitor then
		self.janitor:Destroy()
	end
end

type WorldGenerationServiceClient = typeof(WorldGenerationServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	state: WorldGenerationServiceState,
	stateChanged: SignalObject,
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
	rebuildQueue: { string },
	rebuildQueueHead: number,
	rebuildQueueTail: number,
	rebuildLookup: { [string]: boolean },
	lastChunkBuildAt: { [string]: number },
	chunkAnimationSkipUntil: { [string]: number },
	totalVisualPartCount: number,
	visibilityRefreshAccumulator: number,
}

return WorldGenerationServiceClient :: WorldGenerationServiceClient
