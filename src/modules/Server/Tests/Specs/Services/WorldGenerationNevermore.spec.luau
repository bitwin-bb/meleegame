--!strict

local Workspace = game:GetService("Workspace")

local WorldGeneration = require(script:FindFirstAncestor("game").Shared.Classes.WorldGeneration)

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Maid = loader("Maid")

return function()
	describe("WorldGeneration Nevermore integrations", function()
		it("publishes chunk demand, lifecycle, and stats changes reactively", function()
			local parent = Instance.new("Folder")
			parent.Name = "WorldGenerationNevermoreSpec"
			parent.Parent = Workspace

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
			parent:Destroy()
		end)
	end)
end
