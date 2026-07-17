local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldGeneration = require("WorldGeneration")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")
local WorldGenerationServiceUtils = require("WorldGenerationServiceUtils")

local Maid = require("Maid")
local TagBinder = require("TagBinder")

local REQUIRED_TILE_TEMPLATE_NAMES = {
	"Stone",
	"Dirt",
	"Grass",
	"JungleGrass",
	"Wood",
	"CorruptStone",
	"CorruptSoil",
	"CorruptGrass",
}

local function computeTileIndex(localX: number, localY: number, width: number): number
	return localY * width + localX + 1
end

local function createTileAssetTemplates()
	local assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage

	local worldGeneration = Instance.new("Folder")
	worldGeneration.Name = "WorldGeneration"
	worldGeneration.Parent = assets

	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = worldGeneration

	for _, tileName in REQUIRED_TILE_TEMPLATE_NAMES do
		local tile = Instance.new("Part")
		tile.Name = tileName
		tile.Parent = tiles
	end

	return assets
end

return function()
	describe("WorldGeneration Nevermore integrations", function()
		it("defaults terrain generation to one background layer and 2-stud tiles", function()
			local config = WorldGenerationServiceUtils.CreateDefaultConfig()
			local state = WorldGenerationServiceUtils.CreateDefaultState()

			expect(config.backgroundLayerCount).to.equal(1)
			expect(config.tileSize).to.equal(2)
			expect(state.tileSize).to.equal(2)
		end)

		it("builds chunk visuals when prop templates are unavailable", function()
			local client = setmetatable({
				state = WorldGenerationServiceUtils.CreateDefaultState(),
				worldOrigin = Vector3.zero,
				basePlaneX = 0,
				treeVariantDefinitions = {},
				propTemplatesByPropId = {},
			}, {
				__index = WorldGenerationServiceClient,
			})

			local snapshot = {
				key = "missing-prop-template",
				chunkX = 0,
				chunkY = 0,
				tileMinX = 0,
				tileMinY = 0,
				width = 1,
				height = 1,
				tiles = { 0 },
				depthLayers = { 0 },
				depthBelowSurface = { 0 },
				biomeIds = { 2 },
				surfaceBiomeIds = { 2 },
				biomeTypes = { 1 },
				dominantBiomeId = 2,
				dominantBiomeType = 1,
				backgroundLayers = {},
				trees = {},
				props = {
					{
						tileX = 0,
						tileY = 0,
						propId = 4,
						variantIndex = 1,
						seed = 1,
						biomeType = 1,
						biomeId = 2,
					},
				},
				revision = 1,
			}

			local model = nil
			local uncommittedJob = (WorldGenerationServiceClient :: any).CreateChunkVisualBuildJob(client, snapshot)
			expect(CollectionService:HasTag(uncommittedJob.model, TagBinder.Tags.Chunk)).to.equal(false)
			uncommittedJob.model:Destroy()
			local ok, err = pcall(function()
				model = (WorldGenerationServiceClient :: any).BuildChunkVisualModel(client, snapshot)
			end)

			local propCount = if model ~= nil then (model :: Model):GetAttribute("PropCount") else nil
			if model ~= nil then
				(model :: Model):Destroy()
			end

			expect(ok).to.equal(true)
			expect(err).to.equal(nil)
			expect(propCount).to.equal(1)
		end)

		it("computes client visual chunk bounds from tile and depth extents", function()
			local state = WorldGenerationServiceUtils.CreateDefaultState()
			local snapshot = {
				tileMinX = 32,
				tileMinY = -16,
				width = 32,
				height = 32,
				backgroundLayers = {
					{},
					{},
					{},
				},
			}

			local boundsCFrame, boundsSize = (WorldGenerationServiceClient :: any).ComputeChunkSnapshotVisualBounds(
				snapshot,
				state,
				Vector3.zero,
				0
			)

			expect(boundsCFrame.Position.Z).to.equal(192)
			expect(boundsCFrame.Position.Y).to.equal(0)
			expect(boundsSize.Z).to.equal(128)
			expect(boundsSize.Y).to.equal(128)
			expect(boundsSize.X).to.equal(16)
		end)

		it("does not build background terrain layers", function()
			local client = setmetatable({
				state = WorldGenerationServiceUtils.CreateDefaultState(),
				worldOrigin = Vector3.zero,
				basePlaneX = 0,
				terrainVisualPartPool = {},
				treeVariantDefinitions = {},
				propTemplatesByPropId = {},
			}, {
				__index = WorldGenerationServiceClient,
			})

			local snapshot = {
				key = "background-lighting",
				chunkX = 0,
				chunkY = 0,
				tileMinX = 0,
				tileMinY = 0,
				width = 1,
				height = 1,
				tiles = { 0 },
				depthLayers = { 0 },
				depthBelowSurface = { 0 },
				biomeIds = { 1 },
				surfaceBiomeIds = { 1 },
				biomeTypes = { 1 },
				dominantBiomeId = 1,
				dominantBiomeType = 1,
				backgroundLayers = {
					{
						layerIndex = 1,
						tileMinX = 0,
						tileMinY = 0,
						width = 1,
						height = 1,
						tiles = { 3 },
					},
					{
						layerIndex = 2,
						tileMinX = 0,
						tileMinY = 0,
						width = 1,
						height = 1,
						tiles = { 3 },
					},
				},
				trees = {},
				props = {},
				revision = 1,
			}

			local worldGenerationServiceClient = WorldGenerationServiceClient :: any
			local model, _partCount, _terrainHoverFolder, terrainParts, backgroundPartsByLayer =
				worldGenerationServiceClient.BuildChunkVisualModel(
				client,
				snapshot
				)
			worldGenerationServiceClient.ReleaseTerrainVisualParts(client, terrainParts)
			for _, backgroundParts in backgroundPartsByLayer do
				worldGenerationServiceClient.ReleaseTerrainVisualParts(client, backgroundParts)
			end
			worldGenerationServiceClient.ClearTerrainVisualPartPool(client)
			model:Destroy()

			expect(#backgroundPartsByLayer).to.equal(0)
		end)

		it("uses transparent anchors for autotiled foreground terrain", function()
			local client = setmetatable({
				state = WorldGenerationServiceUtils.CreateDefaultState(),
				worldOrigin = Vector3.zero,
				basePlaneX = 0,
				terrainVisualPartPool = {},
				treeVariantDefinitions = {},
				propTemplatesByPropId = {},
			}, {
				__index = WorldGenerationServiceClient,
			})

			local part = (WorldGenerationServiceClient :: any).CreateForegroundRectPart(
				client,
				0,
				0,
				1,
				1,
				WorldGeneration.TILE_ID.DIRT
			)

			expect(part.Transparency).to.equal(1)
			expect(part.Material).to.equal(Enum.Material.SmoothPlastic)
			expect(part.MaterialVariant).to.equal("")
			expect(part.CastShadow).to.equal(false)
			for _, child in part:GetChildren() do
				expect(child:IsA("Texture")).to.equal(false)
			end

			local worldGenerationServiceClient = WorldGenerationServiceClient :: any
			worldGenerationServiceClient.ReleaseTerrainVisualPart(client, part)
			worldGenerationServiceClient.ClearTerrainVisualPartPool(client)
		end)

		it("owns tree and cactus viewport surfaces under two-stud world anchors", function()
			local parent = Instance.new("Folder")
			parent.Name = "ViewportPropOwnershipSpec"
			parent.Parent = Workspace
			local client = setmetatable({}, {
				__index = WorldGenerationServiceClient,
			})
			local baseCFrame = CFrame.new(7, 11, -3)
			local runtime = (WorldGenerationServiceClient :: any).CreateViewportPropRuntime(
				client,
				parent,
				"CactusViewport",
				baseCFrame,
				2,
				"Prop"
			)

			expect(runtime.anchor.Size.X).to.equal(2)
			expect(runtime.surfaceGui.Parent).to.equal(runtime.anchor)
			expect(runtime.surfaceGui.Adornee).to.equal(nil)

			local content = Instance.new("Model")
			local part = Instance.new("Part")
			part.Anchored = true
			part.Size = Vector3.new(2, 4, 6)
			part.CFrame = CFrame.new(0, 2, 0)
			part.Parent = content
			local finalized = (WorldGenerationServiceClient :: any).FinalizeViewportPropRuntime(client, runtime, content)

			expect(finalized).to.equal(true)
			expect(runtime.anchor.Size.X).to.equal(2)
			expect(runtime.anchor.CFrame.Position.X).to.equal(baseCFrame.Position.X)
			expect(runtime.anchor.CFrame.Position.X + runtime.anchor.Size.X * 0.5).to.equal(
				baseCFrame.Position.X + 1
			)
			expect(runtime.surfaceGui.Parent).to.equal(runtime.anchor)

			local surfaceGui = runtime.surfaceGui
			runtime.container:Destroy()
			expect(surfaceGui.Parent).to.equal(nil)
			parent:Destroy()
		end)

		it("keeps non-surface autotile definitions on transparent foreground terrain", function()
			local client = setmetatable({
				state = WorldGenerationServiceUtils.CreateDefaultState(),
				worldOrigin = Vector3.zero,
				basePlaneX = 0,
				terrainVisualPartPool = {},
				treeVariantDefinitions = {},
				propTemplatesByPropId = {},
			}, {
				__index = WorldGenerationServiceClient,
			})

			local part = (WorldGenerationServiceClient :: any).CreateForegroundRectPart(
				client,
				0,
				0,
				1,
				1,
				WorldGeneration.TILE_ID.STONE
			)

			expect(part.Transparency).to.equal(1)
			expect(part.Material).to.equal(Enum.Material.SmoothPlastic)
			expect(part.MaterialVariant).to.equal("")
			for _, child in part:GetChildren() do
				expect(child:IsA("Texture")).to.equal(false)
			end

			local worldGenerationServiceClient = WorldGenerationServiceClient :: any
			worldGenerationServiceClient.ReleaseTerrainVisualPart(client, part)
			worldGenerationServiceClient.ClearTerrainVisualPartPool(client)
		end)

		it("preserves background depth layers that share terrain tile coordinates", function()
			local tileId = WorldGeneration.TILE_ID
			local generator = setmetatable({
				chunkSize = 2,
				tileId = tileId,
			}, {
				__index = WorldGeneration,
			})
			local function createLayerTiles(width: number, height: number): { number }
				local tiles = {}
				for tileIndex = 1, width * height do
					tiles[tileIndex] = tileId.AIR
				end
				return tiles
			end
			local function setLayerTile(layerData: any, worldTileX: number, worldTileY: number, value: number)
				local localX = worldTileX - layerData.tileMinX
				local localY = worldTileY - layerData.tileMinY
				layerData.tiles[computeTileIndex(localX, localY, layerData.width)] = value
			end

			local layerOne = {
				layerIndex = 1,
				tileMinX = 9,
				tileMinY = 19,
				width = 4,
				height = 4,
				tiles = createLayerTiles(4, 4),
			}
			local layerTwo = {
				layerIndex = 2,
				tileMinX = 9,
				tileMinY = 19,
				width = 4,
				height = 4,
				tiles = createLayerTiles(4, 4),
			}
			setLayerTile(layerOne, 10, 20, tileId.DIRT)
			setLayerTile(layerOne, 11, 20, tileId.STONE)
			setLayerTile(layerTwo, 11, 20, tileId.DIRT)
			setLayerTile(layerTwo, 10, 20, tileId.STONE)
			local chunkData = {
				key = "overlap-regression",
				chunkX = 0,
				chunkY = 0,
				tileMinX = 10,
				tileMinY = 20,
				width = 2,
				height = 2,
				tiles = {
					tileId.STONE,
					tileId.AIR,
					tileId.AIR,
					tileId.AIR,
				},
				backgroundLayers = {
					layerOne,
					layerTwo,
				},
			}

			local overlapCount = (WorldGeneration :: any).RepairChunkTileMetadataOverlaps(generator, chunkData, true)

			expect(overlapCount).to.equal(0)
			expect(chunkData.tiles[computeTileIndex(0, 0, chunkData.width)]).to.equal(tileId.STONE)
			expect(layerOne.tiles[computeTileIndex(1, 1, layerOne.width)]).to.equal(tileId.DIRT)
			expect(layerOne.tiles[computeTileIndex(2, 1, layerOne.width)]).to.equal(tileId.STONE)
			expect(layerTwo.tiles[computeTileIndex(2, 1, layerTwo.width)]).to.equal(tileId.DIRT)
			expect(layerTwo.tiles[computeTileIndex(1, 1, layerTwo.width)]).to.equal(tileId.STONE)
		end)

		it("clips background layer snapshots to the owning chunk bounds", function()
			local tileId = WorldGeneration.TILE_ID
			local layerTiles = {
				tileId.STONE,
				tileId.DIRT,
				tileId.AIR,
				tileId.AIR,
				tileId.AIR,
				tileId.AIR,
				tileId.AIR,
				tileId.AIR,
			}
			local chunkData = {
				key = "background-snapshot-ownership",
				chunkX = 0,
				chunkY = 0,
				tileMinX = 0,
				tileMinY = 0,
				width = 2,
				height = 2,
				tiles = {
					tileId.AIR,
					tileId.AIR,
					tileId.AIR,
					tileId.AIR,
				},
				depthLayers = { 0, 0, 0, 0 },
				depthBelowSurface = { 0, 0, 0, 0 },
				biomeIds = { 1, 1, 1, 1 },
				surfaceBiomeIds = { 1, 1 },
				biomeTypes = { 1, 1, 1, 1 },
				dominantBiomeId = 1,
				dominantBiomeType = 1,
				backgroundLayers = {
					{
						layerIndex = 1,
						tileMinX = -1,
						tileMinY = 0,
						width = 4,
						height = 2,
						tiles = layerTiles,
					},
				},
				trees = {},
				props = {},
			}
			local generator = setmetatable({
				chunkSize = 2,
				tileId = tileId,
				getChunkDataByKey = function()
					return chunkData
				end,
				getChunkRevisionByKey = function()
					return 1
				end,
			}, {
				__index = WorldGeneration,
			})

			local snapshot = (WorldGeneration :: any).GetChunkSnapshotByKey(generator, chunkData.key)
			local snapshotLayer = snapshot.backgroundLayers[1]

			expect(snapshotLayer.tileMinX).to.equal(chunkData.tileMinX)
			expect(snapshotLayer.tileMinY).to.equal(chunkData.tileMinY)
			expect(snapshotLayer.width).to.equal(chunkData.width)
			expect(snapshotLayer.height).to.equal(chunkData.height)
			expect(snapshotLayer.tiles[computeTileIndex(0, 0, snapshotLayer.width)]).to.equal(tileId.DIRT)
			expect(snapshotLayer.tiles[computeTileIndex(1, 0, snapshotLayer.width)]).to.equal(tileId.AIR)
			expect(#snapshotLayer.tiles).to.equal(chunkData.width * chunkData.height)
		end)

		it("only binds terrain parts that need tile binder behavior", function()
			expect((WorldGenerationServiceClient :: any).ShouldBindTerrainTile(10)).to.equal(true)
			expect((WorldGenerationServiceClient :: any).ShouldBindTerrainTile(3)).to.equal(false)
			expect((WorldGenerationServiceClient :: any).ShouldBindTerrainTile(1)).to.equal(false)
		end)

		it("keeps greedy terrain rects intact while hovering a tile inside them", function()
			local model = Instance.new("Model")
			model.Name = "TerrainHoverRuntimeSpec"
			model.Parent = Workspace

			local state = WorldGenerationServiceUtils.CreateDefaultState()

			local snapshot = {
				key = "0:0",
				chunkX = 0,
				chunkY = 0,
				tileMinX = 0,
				tileMinY = 0,
				width = 8,
				height = 8,
			}
			local part = Instance.new("Part")
			part.Name = "GreedyTerrainRect"
			part.Transparency = 0.35
			part.Parent = model
			local rectRuntime = {
				part = part,
				tileMinX = 1,
				tileMinY = 2,
				width = 4,
				height = 3,
				tileId = 10,
			}
			part.Size =
				Vector3.new(state.tileDepth, state.tileSize * rectRuntime.height, state.tileSize * rectRuntime.width)

			local hoveredTileX = 3
			local hoveredTileY = 4
			local rectByLocalTileIndex = {}
			rectByLocalTileIndex[computeTileIndex(hoveredTileX, hoveredTileY, snapshot.width)] = 1
			local client = setmetatable({
				state = state,
				chunkSnapshots = {
					["0:0"] = snapshot,
				},
				chunkVisuals = {
					["0:0"] = {
						model = model,
						partCount = 1,
						revision = 1,
						builtAt = 0,
						treeSignature = "",
						propSignature = "",
						terrainHoverFolder = nil,
						terrainLayerModel = nil,
						backgroundLayerModelsByLayer = {},
						terrainParts = { part },
						terrainRects = { rectRuntime },
						terrainRectByLocalTileIndex = rectByLocalTileIndex,
						treeModels = {},
						propModels = {},
					},
				},
				hoveredTerrainTileX = hoveredTileX,
				hoveredTerrainTileY = hoveredTileY,
				hoveredTerrainChunkKey = "0:0",
				createForegroundRectPart = function()
					error("hovering a greedy terrain rect should not split it into replacement parts")
				end,
			}, {
				__index = WorldGenerationServiceClient,
			})

			local ok, err = pcall(function()
				(WorldGenerationServiceClient :: any).ApplyHoveredTerrainTileRuntime(client)
			end)

			local runtime = (client :: any).hoveredTerrainRuntime
			local hoverProxyPart = runtime.hoverProxyPart
			local clearHoveredTerrainTileRuntime = (WorldGenerationServiceClient :: any).ClearHoveredTerrainTileRuntime
			clearHoveredTerrainTileRuntime(client)
			model:Destroy()

			expect(ok).to.equal(true)
			expect(err).to.equal(nil)
			expect(runtime.hoverPart).to.equal(part)
			expect(runtime.localTileX).to.equal(2)
			expect(runtime.localTileY).to.equal(2)
			expect(runtime.width).to.equal(4)
			expect(runtime.height).to.equal(3)
			expect(runtime.highlight:IsA("SelectionBox")).to.equal(true)
			expect(runtime.highlight.Adornee).to.equal(hoverProxyPart)
			expect(runtime.highlight.SurfaceTransparency).to.equal(1)
			expect(hoverProxyPart.Transparency).to.equal(1)
			expect(hoverProxyPart.CanQuery).to.equal(false)
			expect(hoverProxyPart.Size.Y).to.equal(state.tileSize)
			expect(hoverProxyPart.Size.Z).to.equal(state.tileSize)
			expect(hoverProxyPart.CFrame).to.equal(part.CFrame * CFrame.new(0, state.tileSize, state.tileSize * 0.5))
			expect(#runtime.replacementParts).to.equal(0)
			expect(part.Transparency).to.equal(0.35)
		end)

		it("preserves unchanged prop folders when replacing chunk visuals", function()
			local foregroundFolder = Instance.new("Folder")
			foregroundFolder.Name = "WorldGenerationPropPreserveForegroundSpec"
			foregroundFolder.Parent = Workspace

			local existingModel = Instance.new("Model")
			existingModel.Name = "0:0"
			existingModel.Parent = foregroundFolder

			local existingPropsFolder = Instance.new("Folder")
			existingPropsFolder.Name = "Props"
			existingPropsFolder.Parent = existingModel

			local existingAutotileLayer = Instance.new("Folder")
			existingAutotileLayer.Name = "AutotileLayer"
			existingAutotileLayer.Parent = existingModel

			local existingCactus = Instance.new("Model")
			existingCactus.Name = "Cactus_0_0_1"
			existingCactus.Parent = existingPropsFolder

			local existingCactusSegment = Instance.new("Part")
			existingCactusSegment.Name = "Segment"
			existingCactusSegment.Parent = existingCactus

			local rebuiltModel = Instance.new("Model")
			rebuiltModel.Name = "0:0"

			local propSignature = "4:5:2:3:12345:1:7"
			local snapshot = {
				key = "0:0",
				chunkX = 0,
				chunkY = 0,
				tileMinX = 0,
				tileMinY = 0,
				width = 8,
				height = 8,
				tiles = {},
				depthLayers = {},
				depthBelowSurface = {},
				biomeIds = {},
				surfaceBiomeIds = {},
				biomeTypes = {},
				dominantBiomeId = 7,
				dominantBiomeType = 1,
				backgroundLayers = {},
				trees = {},
				props = {
					{
						tileX = 4,
						tileY = 5,
						propId = 2,
						variantIndex = 3,
						seed = 12345,
						biomeType = 1,
						biomeId = 7,
					},
				},
				revision = 2,
			}
			local client = setmetatable({
				visibleChunkKeys = {
					["0:0"] = true,
				},
				chunkVisuals = {
					["0:0"] = {
						model = existingModel,
						partCount = 1,
						revision = 1,
						builtAt = 0,
						treeSignature = "",
						propSignature = propSignature,
						terrainHoverFolder = nil,
						terrainLayerModel = nil,
						backgroundLayerModelsByLayer = {},
						terrainParts = {},
						backgroundPartsByLayer = {},
						terrainRects = {},
						terrainRectByLocalTileIndex = {},
					},
				},
				dirtyChunkLookup = {
					["0:0"] = true,
				},
				totalVisualPartCount = 1,
				lastChunkBuildAt = {},
				chunkAnimationSkipUntil = {},
				GetForegroundTerrainFolder = function()
					return foregroundFolder
				end,
				GetBackgroundLayerFolder = function()
					return nil
				end,
				releaseTerrainVisualParts = function() end,
			}, {
				__index = WorldGenerationServiceClient,
			})

			local didCommit = (WorldGenerationServiceClient :: any).CommitChunkVisualBuildResult(
				client,
				snapshot,
				rebuiltModel,
				0,
				nil,
				{},
				{},
				{},
				{},
				1
			)

			expect(didCommit).to.equal(true)
			expect(existingPropsFolder.Parent).to.equal(existingModel)
			expect(existingAutotileLayer.Parent).to.equal(existingModel)
			expect(existingCactus.Parent).to.equal(existingPropsFolder)
			expect(existingCactusSegment.Parent).to.equal(existingCactus)
			expect(rebuiltModel.Parent).to.equal(nil)
			expect((client :: any).chunkVisuals["0:0"].partCount).to.equal(1)
			expect((client :: any).chunkVisuals["0:0"].propSignature).to.equal(propSignature)

			foregroundFolder:Destroy()
		end)

		it("uses generated tile templates when asset templates are unavailable", function()
			local existingAssets = ReplicatedStorage:FindFirstChild("Assets")
			local existingAssetsParent = if existingAssets ~= nil then existingAssets.Parent else nil
			if existingAssets ~= nil then
				existingAssets.Parent = nil
			end

			local parent = Instance.new("Folder")
			parent.Name = "WorldGenerationMissingAssetsSpec"
			parent.Parent = Workspace

			local world = nil
			local ok, err = pcall(function()
				world = (WorldGeneration.New :: any)({
					parent = parent,
					maxCachedChunkVisuals = 0,
					maxConcurrentChunkLoads = 1,
					maxChunkUnloadsPerHeartbeat = 1,
				})
			end)

			local stoneTemplate = if ok and world ~= nil
				then (world :: any):GetTerrainTileTemplate(WorldGeneration.TILE_ID.STONE)
				else nil

			if world ~= nil then
				(world :: any):Destroy()
			end
			parent:Destroy()
			if existingAssets ~= nil then
				existingAssets.Parent = existingAssetsParent
			end

			expect(ok).to.equal(true)
			expect(stoneTemplate ~= nil).to.equal(true)
			expect((stoneTemplate :: Instance):IsA("BasePart")).to.equal(true)
			expect(err).to.equal(nil)
		end)

		it("publishes chunk demand, lifecycle, and stats changes reactively", function()
			local parent = Instance.new("Folder")
			parent.Name = "WorldGenerationNevermoreSpec"
			parent.Parent = Workspace

			local assetTemplates = createTileAssetTemplates()
			local maid = Maid.new()
			local world = (WorldGeneration.New :: any)({
				parent = parent,
				maxCachedChunkVisuals = 0,
				maxConcurrentChunkLoads = 1,
				maxChunkUnloadsPerHeartbeat = 1,
			})
			local demandEvents = {}
			local readyEvents = {}
			local unloadedEvents = {}
			local statsSnapshots = {}

			maid:GiveTask(world:ObserveChunkDemand():Subscribe(function(event)
				demandEvents[#demandEvents + 1] = event
			end))
			maid:GiveTask(world:ObserveChunkCollisionReady():Subscribe(function(event)
				readyEvents[#readyEvents + 1] = event
			end))
			maid:GiveTask(world:ObserveChunkCollisionUnloaded():Subscribe(function(event)
				unloadedEvents[#unloadedEvents + 1] = event
			end))
			maid:GiveTask(world:ObserveStats():Subscribe(function(stats)
				statsSnapshots[#statsSnapshots + 1] = stats
			end))

			world:Init()
			world:AdjustChunkDemand("0:0", 1)
			world:LoadChunkByKey("0:0", {
				reason = "spec",
			})
			world:AdjustChunkDemand("0:0", -1)
			world:UnloadChunkByKey("0:0")
			task.wait()

			expect(#demandEvents).to.equal(2)
			expect(demandEvents[1].chunkKey).to.equal("0:0")
			expect(demandEvents[1].nextDemand).to.equal(1)
			expect(demandEvents[2].nextDemand).to.equal(0)
			expect(#readyEvents).to.equal(1)
			expect(readyEvents[1].chunkKey).to.equal("0:0")
			expect(#unloadedEvents).to.equal(1)
			expect(unloadedEvents[1].chunkKey).to.equal("0:0")
			expect(#statsSnapshots >= 1).to.equal(true)
			expect(statsSnapshots[#statsSnapshots].demandedChunks).to.equal(0)

			world:Destroy()
			maid:Destroy()
			assetTemplates:Destroy()
			parent:Destroy()
		end)
	end)
end
