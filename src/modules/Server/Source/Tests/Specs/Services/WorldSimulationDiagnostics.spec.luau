local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

-- selene: allow(undefined_variable)

local Config = require("SimulationConfig")
local Data = require("SimulationData")
local Diagnostics = require("Diagnostics")
local Net = require("Net")
local Runtime = require("SimulationRuntime")
local Shared = require("Shared")
local State = require("SimulationState")

local function createChunkSnapshot(): { [string]: any }
	return {
		key = "0:0:0",
		chunkX = 0,
		chunkY = 0,
		chunkZ = 0,
		revision = 1,
		width = 2,
		height = 2,
		tileCountX = 2,
		tileCountY = 2,
		tileCountZ = 1,
		clusterCountX = 1,
		clusterCountY = 1,
		clusterCountZ = 1,
		tileMinY = 0,
		tiles = {
			Shared.TILE_ID.GRASS,
			Shared.TILE_ID.GRASS,
			Shared.TILE_ID.DIRT,
			Shared.TILE_ID.DIRT,
		},
		biomeIds = {
			Shared.BIOME_ID.FOREST,
			Shared.BIOME_ID.FOREST,
			Shared.BIOME_ID.FOREST,
			Shared.BIOME_ID.FOREST,
		},
		biomeTypes = { 1, 1, 1, 1 },
		dominantBiomeId = Shared.BIOME_ID.FOREST,
		dominantBiomeType = 1,
	}
end

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

		it("mirrors chunk entity buffers through jecs without changing chunk deltas", function()
			local config = Config.CreateDefault()
			config.entityCapacityPerChunk = 16
			config.maxChunksPerRuntimeTick = 1
			config.runtimeEntitySlice = 16
			config.budgetAiEntitiesPerTick = 16
			config.budgetPhysicsEntitiesPerTick = 16

			local world = Data.CreateWorldData(config)
			local chunk = Data.IngestWorldGenerationChunkSnapshot(world, createChunkSnapshot(), 0)
			expect(chunk ~= nil).to.equal(true)
			Data.SetChunkDemandByKey(world, (chunk :: Data.ChunkData).key, 1)

			local entityId = Data.AddEntityToChunk(
				world,
				chunk :: Data.ChunkData,
				Shared.ENTITY_KIND.CREATURE,
				0,
				200,
				0,
				State.ENTITY_FLAGS.ACTIVE,
				30
			)
			expect(entityId ~= nil).to.equal(true)

			local ecsWorld = Data.GetEcsWorld(world)
			local components = Data.GetEcsComponents(world)
			local ecsEntity = Data.GetEcsEntityByRuntimeId(world, entityId :: number)
			expect(ecsEntity ~= nil).to.equal(true)

			local runtimeId = ecsWorld:get(ecsEntity, components.runtimeId)
			local chunkKey = ecsWorld:get(ecsEntity, components.chunkKey)
			local kind = ecsWorld:get(ecsEntity, components.kind)
			local flags = ecsWorld:get(ecsEntity, components.flags)
			local position = ecsWorld:get(ecsEntity, components.position)
			local health = ecsWorld:get(ecsEntity, components.health)

			expect(runtimeId).to.equal(entityId)
			expect(chunkKey).to.equal((chunk :: Data.ChunkData).key)
			expect(kind).to.equal(Shared.ENTITY_KIND.CREATURE)
			expect(flags).to.equal(State.ENTITY_FLAGS.ACTIVE)
			expect(position.X).to.equal(0)
			expect(position.Y).to.equal(200)
			expect(position.Z).to.equal(0)
			expect(health).to.equal(30)

			local runtime = Runtime.New(world, nil)
			runtime:Tick(1 / 30)

			local movedPosition = ecsWorld:get(ecsEntity, components.position)
			expect(typeof(movedPosition)).to.equal("Vector3")
			expect((movedPosition :: Vector3).Y < 200).to.equal(true)

			local delta = Net.BuildChunkDelta(chunk :: Data.ChunkData, nil)
			expect(delta ~= nil).to.equal(true)
			expect((delta :: Net.ChunkDelta).entityCount).to.equal(1)
			expect((delta :: Net.ChunkDelta).entityIds[1]).to.equal(entityId)
			expect((delta :: Net.ChunkDelta).entityKinds[1]).to.equal(Shared.ENTITY_KIND.CREATURE)
			expect((delta :: Net.ChunkDelta).entityPosY[1]).to.equal((movedPosition :: Vector3).Y)

			runtime:Destroy()
		end)
	end)
end
