--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldGeneration = require(script:FindFirstAncestor("game").Shared.Classes.WorldGeneration)

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Maid = loader("Maid")

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
				world = WorldGeneration.new({
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
			local world = WorldGeneration.new({
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
