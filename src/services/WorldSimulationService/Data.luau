--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Config = require(script.Parent.Config)
local Net = require(script.Parent.Net)
local Shared = require(script.Parent.Shared)
local State = require(script.Parent.State)

local Data = {}

export type SimulationConfig = Config.SimulationConfig

export type ChunkEntityBuffer = {
	count: number,
	capacity: number,
	ids: { number },
	kinds: { number },
	flags: { number },
	posX: { number },
	posY: { number },
	posZ: { number },
	velX: { number },
	velY: { number },
	velZ: { number },
	health: { number },
}

export type ChunkData = {
	key: string,
	chunkX: number,
	chunkY: number,
	chunkZ: number,
	revision: number,
	sourceRevision: number,
	flags: number,
	tileCountX: number,
	tileCountY: number,
	tileCountZ: number,
	clusterCountX: number,
	clusterCountY: number,
	clusterCountZ: number,
	tileIds: { number },
	biomeIds: { number },
	corruptionLevels: { number },
	clusterPrimaryBiomeIds: { number },
	clusterSecondaryBiomeIds: { number },
	clusterChosenBiomeIds: { number },
	clusterBlendWeights: { number },
	clusterSolidMask: { number },
	clusterSurfaceY: { number },
	entities: ChunkEntityBuffer,
}

export type WorldData = {
	seed: number,
	config: SimulationConfig,
	tick: number,
	nextEntityId: number,
	systemFlags: number,
	chunksByKey: { [string]: ChunkData },
	chunkKeys: { string },
	chunkDemand: { [string]: number },
	activeChunkLookup: { [string]: boolean },
	activeChunkKeys: { string },
}

local LEGACY_BIOME_TYPE_CORRUPTION = 2
local WG_TILE_ID = {
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

local function createEntityBuffer(capacity: number): ChunkEntityBuffer
	return {
		count = 0,
		capacity = capacity,
		ids = Sift.Array.create(capacity, 0),
		kinds = Sift.Array.create(capacity, Shared.ENTITY_KIND.NONE),
		flags = Sift.Array.create(capacity, 0),
		posX = Sift.Array.create(capacity, 0),
		posY = Sift.Array.create(capacity, 0),
		posZ = Sift.Array.create(capacity, 0),
		velX = Sift.Array.create(capacity, 0),
		velY = Sift.Array.create(capacity, 0),
		velZ = Sift.Array.create(capacity, 0),
		health = Sift.Array.create(capacity, 100),
	}
end

local function createChunk(
	config: SimulationConfig,
	chunkX: number,
	chunkY: number,
	chunkZ: number,
	tileCountX: number,
	tileCountY: number,
	tileCountZ: number,
	clusterCountX: number,
	clusterCountY: number,
	clusterCountZ: number
): ChunkData
	local tileVolume = tileCountX * tileCountY * tileCountZ
	local clusterVolume = clusterCountX * clusterCountY * clusterCountZ
	return {
		key = Shared.packChunkKey(chunkX, chunkY, chunkZ),
		chunkX = chunkX,
		chunkY = chunkY,
		chunkZ = chunkZ,
		revision = 0,
		sourceRevision = -1,
		flags = State.CHUNK_FLAGS.DORMANT,
		tileCountX = tileCountX,
		tileCountY = tileCountY,
		tileCountZ = tileCountZ,
		clusterCountX = clusterCountX,
		clusterCountY = clusterCountY,
		clusterCountZ = clusterCountZ,
		tileIds = Sift.Array.create(tileVolume, Shared.TILE_ID.AIR),
		biomeIds = Sift.Array.create(tileVolume, Shared.BIOME_ID.FOREST),
		corruptionLevels = Sift.Array.create(tileVolume, 0),
		clusterPrimaryBiomeIds = Sift.Array.create(clusterVolume, Shared.BIOME_ID.FOREST),
		clusterSecondaryBiomeIds = Sift.Array.create(clusterVolume, Shared.BIOME_ID.FOREST),
		clusterChosenBiomeIds = Sift.Array.create(clusterVolume, Shared.BIOME_ID.FOREST),
		clusterBlendWeights = Sift.Array.create(clusterVolume, 0),
		clusterSolidMask = Sift.Array.create(clusterVolume, 0),
		clusterSurfaceY = Sift.Array.create(clusterVolume, 0),
		entities = createEntityBuffer(config.entityCapacityPerChunk),
	}
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function mapWorldGenerationTileIdToSimulation(tileIdRaw: any): number
	local tileId = sanitizeInteger(tileIdRaw, 0, 65535, WG_TILE_ID.AIR)
	if tileId == WG_TILE_ID.AIR then
		return Shared.TILE_ID.AIR
	end
	if tileId == WG_TILE_ID.GRASS or tileId == WG_TILE_ID.JUNGLE_GRASS then
		return Shared.TILE_ID.GRASS
	end
	if tileId == WG_TILE_ID.DIRT or tileId == WG_TILE_ID.CLAY then
		return Shared.TILE_ID.DIRT
	end
	if tileId == WG_TILE_ID.WOOD then
		return Shared.TILE_ID.DIRT
	end
	if tileId == WG_TILE_ID.STONE
		or tileId == WG_TILE_ID.SANDSTONE
		or tileId == WG_TILE_ID.COPPER_ORE
		or tileId == WG_TILE_ID.IRON_ORE
		or tileId == WG_TILE_ID.SILVER_ORE
		or tileId == WG_TILE_ID.GOLD_ORE
	then
		return Shared.TILE_ID.STONE
	end
	if tileId == WG_TILE_ID.SAND then
		return Shared.TILE_ID.SAND
	end
	if tileId == WG_TILE_ID.SNOW or tileId == WG_TILE_ID.ICE then
		return Shared.TILE_ID.SNOW
	end
	if tileId == WG_TILE_ID.MUD then
		return Shared.TILE_ID.MUD
	end
	if tileId == WG_TILE_ID.CORRUPT_GRASS or tileId == WG_TILE_ID.CORRUPT_SOIL then
		return Shared.TILE_ID.CORRUPT_SOIL
	end
	if tileId == WG_TILE_ID.CORRUPT_STONE then
		return Shared.TILE_ID.CORRUPT_STONE
	end
	return Shared.TILE_ID.STONE
end

local function sanitizeWorldGenerationBiomeId(biomeIdRaw: any, biomeTypeRaw: any, fallback: number): number
	local biomeId = sanitizeInteger(biomeIdRaw, Shared.BIOME_ID.FOREST, Shared.BIOME_ID.CORRUPTION, fallback)
	if biomeId == Shared.BIOME_ID.FOREST
		or biomeId == Shared.BIOME_ID.DESERT
		or biomeId == Shared.BIOME_ID.SNOW
		or biomeId == Shared.BIOME_ID.JUNGLE
		or biomeId == Shared.BIOME_ID.CORRUPTION
	then
		if sanitizeInteger(biomeTypeRaw, 1, 2, 1) == LEGACY_BIOME_TYPE_CORRUPTION then
			return Shared.BIOME_ID.CORRUPTION
		end
		return biomeId
	end
	if sanitizeInteger(biomeTypeRaw, 1, 2, 1) == LEGACY_BIOME_TYPE_CORRUPTION then
		return Shared.BIOME_ID.CORRUPTION
	end
	return fallback
end

local function resolveChunkFlagsFromContent(chunk: ChunkData, currentFlags: number): number
	local isCorrupted = false
	for clusterIndex = 1, #chunk.clusterChosenBiomeIds do
		if chunk.clusterChosenBiomeIds[clusterIndex] == Shared.BIOME_ID.CORRUPTION then
			isCorrupted = true
			break
		end
	end
	local flags = State.markChunkCorrupted(currentFlags, isCorrupted)
	flags = State.markChunkDirty(flags, true)
	return flags
end

local function copyEntitySlice(destination: { number }, sourceRaw: any, count: number)
	if typeof(sourceRaw) ~= "table" then
		for index = 1, count do
			destination[index] = 0
		end
		return
	end
	local source = sourceRaw :: { any }
	for index = 1, count do
		local value = source[index]
		destination[index] = if isFiniteNumber(value) then value else 0
	end
end

local function resetEntityTail(buffer: ChunkEntityBuffer)
	for index = buffer.count + 1, buffer.capacity do
		buffer.ids[index] = 0
		buffer.kinds[index] = Shared.ENTITY_KIND.NONE
		buffer.flags[index] = 0
		buffer.posX[index] = 0
		buffer.posY[index] = 0
		buffer.posZ[index] = 0
		buffer.velX[index] = 0
		buffer.velY[index] = 0
		buffer.velZ[index] = 0
		buffer.health[index] = 0
	end
end

function Data.createWorldData(configRaw: any): WorldData
	local config = Config.sanitize(configRaw, nil)
	return {
		seed = config.seed,
		config = config,
		tick = 0,
		nextEntityId = 1,
		systemFlags = State.createSystemFlags(config.enableDebug),
		chunksByKey = {},
		chunkKeys = {},
		chunkDemand = {},
		activeChunkLookup = {},
		activeChunkKeys = {},
	}
end

function Data.getChunk(world: WorldData, chunkX: number, chunkY: number, chunkZ: number): ChunkData?
	return world.chunksByKey[Shared.packChunkKey(chunkX, chunkY, chunkZ)]
end

function Data.getChunkByKey(world: WorldData, chunkKeyRaw: any): ChunkData?
	if typeof(chunkKeyRaw) ~= "string" then
		return nil
	end
	return world.chunksByKey[chunkKeyRaw]
end

function Data.getOrCreateChunk(_: WorldData, _: number, _: number, _: number): ChunkData
	error("[WorldSimulationService] getOrCreateChunk is forbidden; ingest chunks from WorldGenerationService snapshots only")
end

function Data.setChunkDemandByKey(world: WorldData, chunkKey: string, delta: number)
	local previous = world.chunkDemand[chunkKey] or 0
	local nextDemand = math.max(0, previous + delta)
	world.chunkDemand[chunkKey] = nextDemand

	if nextDemand > 0 then
		local chunk = world.chunksByKey[chunkKey]
		if chunk ~= nil then
			if not world.activeChunkLookup[chunkKey] then
				world.activeChunkLookup[chunkKey] = true
				world.activeChunkKeys[#world.activeChunkKeys + 1] = chunkKey
			end
			chunk.flags = State.markChunkActive(chunk.flags, true)
		end
		return
	end

	world.activeChunkLookup[chunkKey] = nil
	local chunk = world.chunksByKey[chunkKey]
	if chunk ~= nil then
		chunk.flags = State.markChunkActive(chunk.flags, false)
	end
end

function Data.ingestWorldGenerationChunkSnapshot(
	world: WorldData,
	chunkSnapshotRaw: any,
	chunkZRaw: any?
): ChunkData?
	local decoded = Net.decodeLegacyChunkTransitional(chunkSnapshotRaw)
	if decoded == nil then
		return nil
	end

	local config = world.config
	local clusterSize = math.max(1, config.clusterSize)
	local chunkX = sanitizeInteger(decoded.chunkX, -1000000, 1000000, 0)
	local chunkY = sanitizeInteger(decoded.chunkY, -1000000, 1000000, 0)
	local chunkZ = sanitizeInteger(chunkZRaw, -1000000, 1000000, sanitizeInteger(decoded.chunkZ, -1000000, 1000000, 0))
	local key = Shared.packChunkKey(chunkX, chunkY, chunkZ)
	local sourceRevision = sanitizeInteger(decoded.revision, 0, 1000000000, 0)
	local chunk = world.chunksByKey[key]
	local hadExistingChunk = chunk ~= nil

	if chunk ~= nil and chunk.sourceRevision == sourceRevision then
		return chunk
	end

	local clusterCountX = sanitizeInteger(decoded.clusterCountX, 1, 512, 1)
	local clusterCountY = sanitizeInteger(decoded.clusterCountY, 1, 512, 1)
	local clusterCountZ = sanitizeInteger(decoded.clusterCountZ, 1, 512, 1)
	local tileCountX = math.max(clusterSize, clusterCountX * clusterSize)
	local tileCountY = math.max(clusterSize, clusterCountY * clusterSize)
	local tileCountZ = math.max(clusterSize, clusterCountZ * clusterSize)
	local requiredClusterVolume = clusterCountX * clusterCountY * clusterCountZ
	local requiredTileVolume = tileCountX * tileCountY * tileCountZ
	local needsRecreate = false

	if chunk == nil then
		needsRecreate = true
	else
		if chunk.tileCountX ~= tileCountX or chunk.tileCountY ~= tileCountY or chunk.tileCountZ ~= tileCountZ then
			needsRecreate = true
		end
		if chunk.clusterCountX ~= clusterCountX or chunk.clusterCountY ~= clusterCountY or chunk.clusterCountZ ~= clusterCountZ then
			needsRecreate = true
		end
	end

	if needsRecreate then
		local existingFlags = if chunk ~= nil then chunk.flags else State.CHUNK_FLAGS.DORMANT
		chunk = createChunk(
			config,
			chunkX,
			chunkY,
			chunkZ,
			tileCountX,
			tileCountY,
			tileCountZ,
			clusterCountX,
			clusterCountY,
			clusterCountZ
		)
		chunk.flags = existingFlags
		world.chunksByKey[key] = chunk
		if world.activeChunkLookup[key] then
			chunk.flags = State.markChunkActive(chunk.flags, true)
		end
		if not hadExistingChunk then
			world.chunkKeys[#world.chunkKeys + 1] = key
		end
	end

	if chunk == nil then
		return nil
	end

	table.clear(chunk.tileIds)
	table.clear(chunk.biomeIds)
	table.clear(chunk.corruptionLevels)
	table.clear(chunk.clusterPrimaryBiomeIds)
	table.clear(chunk.clusterSecondaryBiomeIds)
	table.clear(chunk.clusterChosenBiomeIds)
	table.clear(chunk.clusterBlendWeights)
	table.clear(chunk.clusterSolidMask)
	table.clear(chunk.clusterSurfaceY)
	for tileIndex = 1, requiredTileVolume do
		chunk.tileIds[tileIndex] = Shared.TILE_ID.AIR
		chunk.biomeIds[tileIndex] = Shared.BIOME_ID.FOREST
		chunk.corruptionLevels[tileIndex] = 0
	end
	for clusterIndex = 1, requiredClusterVolume do
		chunk.clusterPrimaryBiomeIds[clusterIndex] = Shared.BIOME_ID.FOREST
		chunk.clusterSecondaryBiomeIds[clusterIndex] = Shared.BIOME_ID.FOREST
		chunk.clusterChosenBiomeIds[clusterIndex] = Shared.BIOME_ID.FOREST
		chunk.clusterBlendWeights[clusterIndex] = 0
		chunk.clusterSolidMask[clusterIndex] = 0
		chunk.clusterSurfaceY[clusterIndex] = chunkY * tileCountY
	end

	local chunkSnapshot = if typeof(chunkSnapshotRaw) == "table" then (chunkSnapshotRaw :: { [string]: any }) else {}
	local sourceTiles = if typeof(chunkSnapshot.tiles) == "table" then (chunkSnapshot.tiles :: { any }) else {}
	local sourceBiomeIds = if typeof(chunkSnapshot.biomeIds) == "table" then (chunkSnapshot.biomeIds :: { any }) else {}
	local sourceBiomeTypes = if typeof(chunkSnapshot.biomeTypes) == "table" then (chunkSnapshot.biomeTypes :: { any }) else {}
	local sourceTileMinY = sanitizeInteger(chunkSnapshot.tileMinY, -1000000, 1000000, chunkY * tileCountY)
	local sourceWidth = sanitizeInteger(chunkSnapshot.width, 1, tileCountX, tileCountX)
	local sourceHeight = sanitizeInteger(chunkSnapshot.height, 1, tileCountY, tileCountY)
	local dominantBiomeId = sanitizeWorldGenerationBiomeId(
		chunkSnapshot.dominantBiomeId,
		chunkSnapshot.dominantBiomeType,
		Shared.BIOME_ID.FOREST
	)

	for clusterLocalZ = 0, clusterCountZ - 1 do
		for clusterLocalY = 0, clusterCountY - 1 do
			for clusterLocalX = 0, clusterCountX - 1 do
				local clusterIndex = Shared.computeClusterIndex(
					clusterLocalX,
					clusterLocalY,
					clusterLocalZ,
					clusterCountX,
					clusterCountY
				)
				local clusterMinTileX, clusterMinTileY, clusterMinTileZ, clusterMaxTileX, clusterMaxTileY, clusterMaxTileZ = State.resolveClusterBounds(
					clusterLocalX,
					clusterLocalY,
					clusterLocalZ,
					clusterSize,
					tileCountX,
					tileCountY,
					tileCountZ
				)

				local solidMask = 0
				local highestSolidLocalY = -1
				local biomeCounts = {
					[Shared.BIOME_ID.FOREST] = 0,
					[Shared.BIOME_ID.DESERT] = 0,
					[Shared.BIOME_ID.SNOW] = 0,
					[Shared.BIOME_ID.JUNGLE] = 0,
					[Shared.BIOME_ID.CORRUPTION] = 0,
				}

				for localTileY = clusterMinTileY, clusterMaxTileY do
					if localTileY >= sourceHeight then
						continue
					end
					for localTileX = clusterMinTileX, clusterMaxTileX do
						if localTileX >= sourceWidth then
							continue
						end
						local sourceIndex = localTileY * sourceWidth + localTileX + 1
						local sourceBiome = sanitizeWorldGenerationBiomeId(
							sourceBiomeIds[sourceIndex],
							sourceBiomeTypes[sourceIndex],
							dominantBiomeId
						)
						local mappedTileId = mapWorldGenerationTileIdToSimulation(sourceTiles[sourceIndex])
						biomeCounts[sourceBiome] = (biomeCounts[sourceBiome] or 0) + 1
						if mappedTileId ~= Shared.TILE_ID.AIR then
							solidMask = 1
							if localTileY > highestSolidLocalY then
								highestSolidLocalY = localTileY
							end
						end

						for localTileZ = clusterMinTileZ, clusterMaxTileZ do
							local tileIndex = Shared.computeTileIndex(localTileX, localTileY, localTileZ, tileCountX, tileCountY)
							chunk.tileIds[tileIndex] = mappedTileId
							chunk.biomeIds[tileIndex] = sourceBiome
							chunk.corruptionLevels[tileIndex] = if sourceBiome == Shared.BIOME_ID.CORRUPTION then 1 else 0
						end
					end
				end

				local chosenBiome = dominantBiomeId
				local bestCount = -1
				for biomeId, count in biomeCounts do
					if count > bestCount then
						bestCount = count
						chosenBiome = biomeId
					end
				end

				chunk.clusterPrimaryBiomeIds[clusterIndex] = chosenBiome
				chunk.clusterSecondaryBiomeIds[clusterIndex] = chosenBiome
				chunk.clusterChosenBiomeIds[clusterIndex] = chosenBiome
				chunk.clusterBlendWeights[clusterIndex] = sanitizeInteger(
					(if typeof(decoded.clusterBlendWeights) == "table" then (decoded.clusterBlendWeights :: { any })[clusterIndex] else nil),
					0,
					255,
					0
				)
				chunk.clusterSolidMask[clusterIndex] = solidMask
				chunk.clusterSurfaceY[clusterIndex] = if highestSolidLocalY >= 0
					then sourceTileMinY + highestSolidLocalY
					else sourceTileMinY + clusterMaxTileY
			end
		end
	end

	chunk.sourceRevision = sourceRevision
	local existingRevision = chunk.revision
	chunk.revision = math.max(sourceRevision, existingRevision + 1)
	chunk.flags = resolveChunkFlagsFromContent(chunk, chunk.flags)
	if (world.chunkDemand[key] or 0) > 0 then
		if not world.activeChunkLookup[key] then
			world.activeChunkLookup[key] = true
			world.activeChunkKeys[#world.activeChunkKeys + 1] = key
		end
		chunk.flags = State.markChunkActive(chunk.flags, true)
	else
		chunk.flags = State.markChunkActive(chunk.flags, false)
	end

	local entities = chunk.entities
	local entityCount = sanitizeInteger(decoded.entityCount, 0, entities.capacity, 0)
	entities.count = entityCount
	copyEntitySlice(entities.ids, decoded.entityIds, entityCount)
	copyEntitySlice(entities.kinds, decoded.entityKinds, entityCount)
	copyEntitySlice(entities.flags, decoded.entityFlags, entityCount)
	copyEntitySlice(entities.posX, decoded.entityPosX, entityCount)
	copyEntitySlice(entities.posY, decoded.entityPosY, entityCount)
	copyEntitySlice(entities.posZ, decoded.entityPosZ, entityCount)
	for index = 1, entityCount do
		entities.velX[index] = 0
		entities.velY[index] = 0
		entities.velZ[index] = 0
		entities.health[index] = 100
	end
	resetEntityTail(entities)

	return chunk
end

function Data.compactActiveChunkKeys(world: WorldData)
	local nextKeys = Sift.Array.create(#world.activeChunkKeys)
	for _, key in world.activeChunkKeys do
		if world.activeChunkLookup[key] then
			nextKeys[#nextKeys + 1] = key
		end
	end
	world.activeChunkKeys = nextKeys
end

function Data.bumpChunkRevision(chunk: ChunkData)
	chunk.revision += 1
	chunk.flags = State.markChunkDirty(chunk.flags, true)
end

function Data.clearChunkDirty(chunk: ChunkData)
	chunk.flags = State.markChunkDirty(chunk.flags, false)
end

function Data.addEntityToChunk(
	world: WorldData,
	chunk: ChunkData,
	kind: number,
	spawnX: number,
	spawnY: number,
	spawnZ: number,
	flags: number,
	health: number
): number?
	local entities = chunk.entities
	if entities.count >= entities.capacity then
		return nil
	end

	local slot = entities.count + 1
	entities.count = slot
	local entityId = world.nextEntityId
	world.nextEntityId += 1

	entities.ids[slot] = entityId
	entities.kinds[slot] = kind
	entities.flags[slot] = flags
	entities.posX[slot] = spawnX
	entities.posY[slot] = spawnY
	entities.posZ[slot] = spawnZ
	entities.velX[slot] = 0
	entities.velY[slot] = 0
	entities.velZ[slot] = 0
	entities.health[slot] = health

	return entityId
end

function Data.removeEntitySlot(chunk: ChunkData, slotRaw: any): boolean
	local entities = chunk.entities
	if typeof(slotRaw) ~= "number" then
		return false
	end
	local slot = math.floor(slotRaw)
	if slot < 1 or slot > entities.count then
		return false
	end

	local last = entities.count
	if slot ~= last then
		entities.ids[slot] = entities.ids[last]
		entities.kinds[slot] = entities.kinds[last]
		entities.flags[slot] = entities.flags[last]
		entities.posX[slot] = entities.posX[last]
		entities.posY[slot] = entities.posY[last]
		entities.posZ[slot] = entities.posZ[last]
		entities.velX[slot] = entities.velX[last]
		entities.velY[slot] = entities.velY[last]
		entities.velZ[slot] = entities.velZ[last]
		entities.health[slot] = entities.health[last]
	end

	entities.ids[last] = 0
	entities.kinds[last] = Shared.ENTITY_KIND.NONE
	entities.flags[last] = 0
	entities.posX[last] = 0
	entities.posY[last] = 0
	entities.posZ[last] = 0
	entities.velX[last] = 0
	entities.velY[last] = 0
	entities.velZ[last] = 0
	entities.health[last] = 0
	entities.count = last - 1
	return true
end

function Data.forEachEntity(chunk: ChunkData, callback: (slot: number, entityId: number) -> ())
	local entities = chunk.entities
	for slot = 1, entities.count do
		callback(slot, entities.ids[slot])
	end
end

function Data.getStats(world: WorldData): { [string]: number }
	return {
		chunks = #world.chunkKeys,
		activeChunks = #world.activeChunkKeys,
		nextEntityId = world.nextEntityId,
		tick = world.tick,
	}
end

return Data
