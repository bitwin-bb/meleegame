--!strict

local require = require(script.Parent.loader).load(assert(script:FindFirstAncestor("AquariaBackup"), "Missing AquariaBackup package root"))

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldGeneration = require("WorldGeneration")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")
local WorldGenerationServiceUtils = require("WorldGenerationServiceUtils")

local Maid = require("Maid")

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
		it("builds chunk visuals when prop templates are unavailable", function()
			local client = setmetatable({
				state = WorldGenerationServiceUtils.createDefaultState(),
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
			local state = WorldGenerationServiceUtils.createDefaultState()
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

		it("only binds terrain parts that need tile binder behavior", function()
			expect((WorldGenerationServiceClient :: any).ShouldBindTerrainTile(10)).to.equal(true)
			expect((WorldGenerationServiceClient :: any).ShouldBindTerrainTile(3)).to.equal(false)
			expect((WorldGenerationServiceClient :: any).ShouldBindTerrainTile(1)).to.equal(false)
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
				world = (WorldGeneration.new :: any)({
					parent = parent,
					maxCachedChunkVisuals = 0,
					maxConcurrentChunkLoads = 1,
					maxChunkUnloadsPerHeartbeat = 1,
				})
			end)

			local stoneTemplate = if ok and world ~= nil
				then (world :: any):getTerrainTileTemplate(WorldGeneration.TILE_ID.STONE)
				else nil

			if world ~= nil then
				(world :: any):destroy()
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
			local world = (WorldGeneration.new :: any)({
				parent = parent,
				maxCachedChunkVisuals = 0,
				maxConcurrentChunkLoads = 1,
				maxChunkUnloadsPerHeartbeat = 1,
			})
			local demandEvents = {}
			local readyEvents = {}
			local unloadedEvents = {}
			local statsSnapshots = {}

			maid:GiveTask(world:observeChunkDemand():Subscribe(function(event)
				demandEvents[#demandEvents + 1] = event
			end))
			maid:GiveTask(world:observeChunkCollisionReady():Subscribe(function(event)
				readyEvents[#readyEvents + 1] = event
			end))
			maid:GiveTask(world:observeChunkCollisionUnloaded():Subscribe(function(event)
				unloadedEvents[#unloadedEvents + 1] = event
			end))
			maid:GiveTask(world:observeStats():Subscribe(function(stats)
				statsSnapshots[#statsSnapshots + 1] = stats
			end))

			world:init()
			world:adjustChunkDemand("0:0", 1)
			world:loadChunkByKey("0:0", {
				reason = "spec",
			})
			world:adjustChunkDemand("0:0", -1)
			world:unloadChunkByKey("0:0")
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

			world:destroy()
			maid:Destroy()
			assetTemplates:Destroy()
			parent:Destroy()
		end)
	end)
end
