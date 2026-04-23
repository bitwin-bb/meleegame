--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(script:FindFirstAncestor("game").Shared.Services.Diagnostics)

local function createDebugStub()
	return {
		counters = {} :: { [string]: any },
		setCounter = function(self: any, name: string, valueRaw: any)
			self.counters[name] = valueRaw
		end,
	}
end

return function()
	describe("WorldSimulationService.Diagnostics", function()
		it("records runtime samples and rolling averages", function()
			local debug = createDebugStub()
			local diagnostics = Diagnostics.New(debug)

			diagnostics:Record({
				worldTick = 10,
				deltaTime = 1 / 60,
				elapsedSeconds = 0.001,
				activeChunkCount = 6,
				selectedChunkCount = 3,
				chunkBudget = 4,
				processedChunks = 3,
				processedCorruptionClusters = 12,
				processedBiomeClusters = 8,
				processedAiEntities = 6,
				processedPhysicsEntities = 4,
			})

			diagnostics:Record({
				worldTick = 11,
				deltaTime = 1 / 60,
				elapsedSeconds = 0.002,
				activeChunkCount = 8,
				selectedChunkCount = 5,
				chunkBudget = 6,
				processedChunks = 5,
				processedCorruptionClusters = 18,
				processedBiomeClusters = 10,
				processedAiEntities = 8,
				processedPhysicsEntities = 6,
			})

			local snapshot = diagnostics:GetSnapshot()
			expect(snapshot.sample.worldTick).to.equal(11)
			expect(snapshot.sample.selectedChunkCount).to.equal(5)
			expect(snapshot.rolling.sampleCount).to.equal(2)
			expect(snapshot.rolling.averageProcessedChunks).to.equal(4)
			expect(snapshot.rolling.averageSelectedChunks).to.equal(4)
			expect(debug.counters.runtime_active_chunks).to.equal(8)
			expect(debug.counters.runtime_chunks_processed_avg).to.equal(4)

			diagnostics:Destroy()
		end)
	end)
end
