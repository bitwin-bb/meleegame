local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Sift = require(ReplicatedStorage.Packages.Sift)

local Config = require("SimulationConfig")
local Net = require("Net")
local Shared = require("Shared")
local State = require("SimulationState")

local Data = {}

export type SimulationConfig = Config.SimulationConfig
export type EcsComponents = {
	runtimeId: any,
	chunkKey: any,
	slot: any,
	kind: any,
	flags: any,
	position: any,
	velocity: any,
	health: any,
}

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
	ecsEntitiesByRuntimeId: { [number]: any },
}

export type WorldData = {
	seed: number,
	config: SimulationConfig,
	tick: number,
	nextEntityId: number,
	systemFlags: number,
	ecsWorld: any,
	ecsComponents: EcsComponents,
	ecsEntityByRuntimeId: { [number]: any },
	entityChunkByRuntimeId: { [number]: ChunkData },
	entitySlotByRuntimeId: { [number]: number },
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

local function createEcsComponent(ecsWorld: any, name: string): any
	local component = ecsWorld:component()
	ecsWorld:set(component, Jecs.Name, name)
	return component
end

local function createEcsComponents(ecsWorld: any): EcsComponents
	return {
		runtimeId = createEcsComponent(ecsWorld, "WorldSimulation.RuntimeId"),
		chunkKey = createEcsComponent(ecsWorld, "WorldSimulation.ChunkKey"),
		slot = createEcsComponent(ecsWorld, "WorldSimulation.Slot"),
		kind = createEcsComponent(ecsWorld, "WorldSimulation.Kind"),
		flags = createEcsComponent(ecsWorld, "WorldSimulation.Flags"),
		position = createEcsComponent(ecsWorld, "WorldSimulation.Position"),
		velocity = createEcsComponent(ecsWorld, "WorldSimulation.Velocity"),
		health = createEcsComponent(ecsWorld, "WorldSimulation.Health"),
	}
end

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
		key = Shared.PackChunkKey(chunkX, chunkY, chunkZ),
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
		ecsEntitiesByRuntimeId = {},
	}
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function CoerceInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function mapWorldGenerationTileIdToSimulation(tileIdRaw: any): number
	local tileId = CoerceInteger(tileIdRaw, 0, 65535, WG_TILE_ID.AIR)
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
	if
		tileId == WG_TILE_ID.STONE
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

local function CoerceWorldGenerationBiomeId(biomeIdRaw: any, biomeTypeRaw: any, fallback: number): number
	local biomeId = CoerceInteger(biomeIdRaw, Shared.BIOME_ID.FOREST, Shared.BIOME_ID.CORRUPTION, fallback)
	if
		biomeId == Shared.BIOME_ID.FOREST
		or biomeId == Shared.BIOME_ID.DESERT
		or biomeId == Shared.BIOME_ID.SNOW
		or biomeId == Shared.BIOME_ID.JUNGLE
		or biomeId == Shared.BIOME_ID.CORRUPTION
	then
		if CoerceInteger(biomeTypeRaw, 1, 2, 1) == LEGACY_BIOME_TYPE_CORRUPTION then
			return Shared.BIOME_ID.CORRUPTION
		end
		return biomeId
	end
	if CoerceInteger(biomeTypeRaw, 1, 2, 1) == LEGACY_BIOME_TYPE_CORRUPTION then
		return Shared.BIOME_ID.CORRUPTION
	end
	return fallback
end

local function GetChunkFlagsFromContent(chunk: ChunkData, currentFlags: number): number
	local isCorrupted = false
	for clusterIndex = 1, #chunk.clusterChosenBiomeIds do
		if chunk.clusterChosenBiomeIds[clusterIndex] == Shared.BIOME_ID.CORRUPTION then
			isCorrupted = true
			break
		end
	end
	local flags = State.MarkChunkCorrupted(currentFlags, isCorrupted)
	flags = State.MarkChunkDirty(flags, true)
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

local function getEntitySlot(entities: ChunkEntityBuffer, slotRaw: any): number?
	if typeof(slotRaw) ~= "number" then
		return nil
	end
	local slot = math.floor(slotRaw)
	if slot < 1 or slot > entities.count then
		return nil
	end
	return slot
end

local function clearEcsEntity(world: WorldData, chunk: ChunkData, entityId: number)
	local ecsEntity = chunk.ecsEntitiesByRuntimeId[entityId] or world.ecsEntityByRuntimeId[entityId]
	if ecsEntity ~= nil and world.ecsWorld:contains(ecsEntity) then
		world.ecsWorld:delete(ecsEntity)
	end
	chunk.ecsEntitiesByRuntimeId[entityId] = nil
	world.ecsEntityByRuntimeId[entityId] = nil
	world.entityChunkByRuntimeId[entityId] = nil
	world.entitySlotByRuntimeId[entityId] = nil
end

local function clearChunkEntitiesFromEcs(world: WorldData, chunk: ChunkData)
	local entityIds = {}
	for entityId in chunk.ecsEntitiesByRuntimeId do
		entityIds[#entityIds + 1] = entityId
	end
	for _, entityId in entityIds do
		clearEcsEntity(world, chunk, entityId)
	end
	table.clear(chunk.ecsEntitiesByRuntimeId)
end

local function syncEntitySlotToEcs(world: WorldData, chunk: ChunkData, slot: number): any?
	local entities = chunk.entities
	local entityId = entities.ids[slot]
	if entityId == nil or entityId <= 0 then
		return nil
	end

	local previousChunk = world.entityChunkByRuntimeId[entityId]
	if previousChunk ~= nil and previousChunk ~= chunk then
		previousChunk.ecsEntitiesByRuntimeId[entityId] = nil
	end

	local ecsWorld = world.ecsWorld
	local ecsEntity = world.ecsEntityByRuntimeId[entityId]
	if ecsEntity == nil or not ecsWorld:contains(ecsEntity) then
		ecsEntity = ecsWorld:entity()
		world.ecsEntityByRuntimeId[entityId] = ecsEntity
	end

	chunk.ecsEntitiesByRuntimeId[entityId] = ecsEntity
	world.entityChunkByRuntimeId[entityId] = chunk
	world.entitySlotByRuntimeId[entityId] = slot

	local components = world.ecsComponents
	ecsWorld:set(ecsEntity, components.runtimeId, entityId)
	ecsWorld:set(ecsEntity, components.chunkKey, chunk.key)
	ecsWorld:set(ecsEntity, components.slot, slot)
	ecsWorld:set(ecsEntity, components.kind, entities.kinds[slot])
	ecsWorld:set(ecsEntity, components.flags, entities.flags[slot])
	ecsWorld:set(ecsEntity, components.position, Vector3.new(entities.posX[slot], entities.posY[slot], entities.posZ[slot]))
	ecsWorld:set(ecsEntity, components.velocity, Vector3.new(entities.velX[slot], entities.velY[slot], entities.velZ[slot]))
	ecsWorld:set(ecsEntity, components.health, entities.health[slot])
	return ecsEntity
end

local function syncEntitySlotFromEcs(world: WorldData, chunk: ChunkData, slot: number): boolean
	local entities = chunk.entities
	local entityId = entities.ids[slot]
	local ecsEntity = world.ecsEntityByRuntimeId[entityId]
	if ecsEntity == nil or not world.ecsWorld:contains(ecsEntity) then
		return false
	end

	local components = world.ecsComponents
	local ecsWorld = world.ecsWorld
	local kind = ecsWorld:get(ecsEntity, components.kind)
	local flags = ecsWorld:get(ecsEntity, components.flags)
	local position = ecsWorld:get(ecsEntity, components.position)
	local velocity = ecsWorld:get(ecsEntity, components.velocity)
	local health = ecsWorld:get(ecsEntity, components.health)
	local changed = false

	if isFiniteNumber(kind) and entities.kinds[slot] ~= kind then
		entities.kinds[slot] = kind
		changed = true
	end
	if isFiniteNumber(flags) and entities.flags[slot] ~= flags then
		entities.flags[slot] = flags
		changed = true
	end
	if typeof(position) == "Vector3" then
		if entities.posX[slot] ~= position.X or entities.posY[slot] ~= position.Y or entities.posZ[slot] ~= position.Z then
			entities.posX[slot] = position.X
			entities.posY[slot] = position.Y
			entities.posZ[slot] = position.Z
			changed = true
		end
	end
	if typeof(velocity) == "Vector3" then
		if entities.velX[slot] ~= velocity.X or entities.velY[slot] ~= velocity.Y or entities.velZ[slot] ~= velocity.Z then
			entities.velX[slot] = velocity.X
			entities.velY[slot] = velocity.Y
			entities.velZ[slot] = velocity.Z
			changed = true
		end
	end
	if isFiniteNumber(health) and entities.health[slot] ~= health then
		entities.health[slot] = health
		changed = true
	end

	return changed
end

function Data.CreateWorldData(configRaw: any): WorldData
	local config = Config.Coerce(configRaw, nil)
	local ecsWorld = Jecs.world()
	return {
		seed = config.seed,
		config = config,
		tick = 0,
		nextEntityId = 1,
		systemFlags = State.CreateSystemFlags(config.enableDebug),
		ecsWorld = ecsWorld,
		ecsComponents = createEcsComponents(ecsWorld),
		ecsEntityByRuntimeId = {},
		entityChunkByRuntimeId = {},
		entitySlotByRuntimeId = {},
		chunksByKey = {},
		chunkKeys = {},
		chunkDemand = {},
		activeChunkLookup = {},
		activeChunkKeys = {},
	}
end

function Data.GetChunk(world: WorldData, chunkX: number, chunkY: number, chunkZ: number): ChunkData?
	return world.chunksByKey[Shared.PackChunkKey(chunkX, chunkY, chunkZ)]
end

function Data.GetChunkByKey(world: WorldData, chunkKeyRaw: any): ChunkData?
	if typeof(chunkKeyRaw) ~= "string" then
		return nil
	end
	return world.chunksByKey[chunkKeyRaw]
end

function Data.GetOrCreateChunk(_: WorldData, _: number, _: number, _: number): ChunkData
	error(
		"[WorldSimulationService] getOrCreateChunk is forbidden; ingest chunks from WorldGenerationService snapshots only"
	)
end

function Data.SetChunkDemandByKey(world: WorldData, chunkKey: string, delta: number)
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
			chunk.flags = State.MarkChunkActive(chunk.flags, true)
		end
		return
	end

	world.activeChunkLookup[chunkKey] = nil
	local chunk = world.chunksByKey[chunkKey]
	if chunk ~= nil then
		chunk.flags = State.MarkChunkActive(chunk.flags, false)
	end
end

function Data.IngestWorldGenerationChunkSnapshot(world: WorldData, chunkSnapshotRaw: any, chunkZRaw: any?): ChunkData?
	local decoded = Net.DecodeLegacyChunkTransitional(chunkSnapshotRaw)
	if decoded == nil then
		return nil
	end

	local config = world.config
	local clusterSize = math.max(1, config.clusterSize)
	local chunkX = CoerceInteger(decoded.chunkX, -1000000, 1000000, 0)
	local chunkY = CoerceInteger(decoded.chunkY, -1000000, 1000000, 0)
	local chunkZ = CoerceInteger(chunkZRaw, -1000000, 1000000, CoerceInteger(decoded.chunkZ, -1000000, 1000000, 0))
	local key = Shared.PackChunkKey(chunkX, chunkY, chunkZ)
	local sourceRevision = CoerceInteger(decoded.revision, 0, 1000000000, 0)
	local chunk = world.chunksByKey[key]
	local hadExistingChunk = chunk ~= nil

	if chunk ~= nil and chunk.sourceRevision == sourceRevision then
		return chunk
	end

	local clusterCountX = CoerceInteger(decoded.clusterCountX, 1, 512, 1)
	local clusterCountY = CoerceInteger(decoded.clusterCountY, 1, 512, 1)
	local clusterCountZ = CoerceInteger(decoded.clusterCountZ, 1, 512, 1)
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
		if
			chunk.clusterCountX ~= clusterCountX
			or chunk.clusterCountY ~= clusterCountY
			or chunk.clusterCountZ ~= clusterCountZ
		then
			needsRecreate = true
		end
	end

	if needsRecreate then
		if chunk ~= nil then
			clearChunkEntitiesFromEcs(world, chunk)
		end
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
			chunk.flags = State.MarkChunkActive(chunk.flags, true)
		end
		if not hadExistingChunk then
			world.chunkKeys[#world.chunkKeys + 1] = key
		end
	end

	if chunk == nil then
		return nil
	end
	clearChunkEntitiesFromEcs(world, chunk)

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

	local chunkSnapshot = if typeof(chunkSnapshotRaw) == "table"
		then chunkSnapshotRaw :: { [string]: any }
		else {} :: any
	local sourceTiles = if typeof(chunkSnapshot.tiles) == "table" then chunkSnapshot.tiles :: { any } else {} :: any
	local sourceBiomeIds = if typeof(chunkSnapshot.biomeIds) == "table"
		then chunkSnapshot.biomeIds :: { any }
		else {} :: any
	local sourceBiomeTypes = if typeof(chunkSnapshot.biomeTypes) == "table"
		then chunkSnapshot.biomeTypes :: { any }
		else {} :: any
	local sourceTileMinY = CoerceInteger(chunkSnapshot.tileMinY, -1000000, 1000000, chunkY * tileCountY)
	local sourceWidth = CoerceInteger(chunkSnapshot.width, 1, tileCountX, tileCountX)
	local sourceHeight = CoerceInteger(chunkSnapshot.height, 1, tileCountY, tileCountY)
	local dominantBiomeId = CoerceWorldGenerationBiomeId(
		chunkSnapshot.dominantBiomeId,
		chunkSnapshot.dominantBiomeType,
		Shared.BIOME_ID.FOREST
	)

	for clusterLocalZ = 0, clusterCountZ - 1 do
		for clusterLocalY = 0, clusterCountY - 1 do
			for clusterLocalX = 0, clusterCountX - 1 do
				local clusterIndex = Shared.ComputeClusterIndex(
					clusterLocalX,
					clusterLocalY,
					clusterLocalZ,
					clusterCountX,
					clusterCountY
				)
				local clusterMinTileX, clusterMinTileY, clusterMinTileZ, clusterMaxTileX, clusterMaxTileY, clusterMaxTileZ =
					State.GetClusterBounds(
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
						local sourceBiome = CoerceWorldGenerationBiomeId(
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
							local tileIndex =
								Shared.ComputeTileIndex(localTileX, localTileY, localTileZ, tileCountX, tileCountY)
							chunk.tileIds[tileIndex] = mappedTileId
							chunk.biomeIds[tileIndex] = sourceBiome
							chunk.corruptionLevels[tileIndex] = if sourceBiome == Shared.BIOME_ID.CORRUPTION
								then 1
								else 0
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
				chunk.clusterBlendWeights[clusterIndex] = CoerceInteger(
					(
						if typeof(decoded.clusterBlendWeights) == "table"
							then (decoded.clusterBlendWeights :: { any })[clusterIndex]
							else nil
					),
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
	chunk.flags = GetChunkFlagsFromContent(chunk, chunk.flags)
	if (world.chunkDemand[key] or 0) > 0 then
		if not world.activeChunkLookup[key] then
			world.activeChunkLookup[key] = true
			world.activeChunkKeys[#world.activeChunkKeys + 1] = key
		end
		chunk.flags = State.MarkChunkActive(chunk.flags, true)
	else
		chunk.flags = State.MarkChunkActive(chunk.flags, false)
	end

	local entities = chunk.entities
	local entityCount = CoerceInteger(decoded.entityCount, 0, entities.capacity, 0)
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
		if entities.ids[index] >= world.nextEntityId then
			world.nextEntityId = entities.ids[index] + 1
		end
		syncEntitySlotToEcs(world, chunk, index)
	end
	resetEntityTail(entities)

	return chunk
end

function Data.CompactActiveChunkKeys(world: WorldData)
	local nextKeys = Sift.Array.create(#world.activeChunkKeys)
	for _, key in world.activeChunkKeys do
		if world.activeChunkLookup[key] then
			nextKeys[#nextKeys + 1] = key
		end
	end
	world.activeChunkKeys = nextKeys
end

function Data.BumpChunkRevision(chunk: ChunkData)
	chunk.revision += 1
	chunk.flags = State.MarkChunkDirty(chunk.flags, true)
end

function Data.ClearChunkDirty(chunk: ChunkData)
	chunk.flags = State.MarkChunkDirty(chunk.flags, false)
end

function Data.AddEntityToChunk(
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
	syncEntitySlotToEcs(world, chunk, slot)

	return entityId
end

function Data.RemoveEntitySlot(chunk: ChunkData, slotRaw: any, world: WorldData?): boolean
	local entities = chunk.entities
	local slot = getEntitySlot(entities, slotRaw)
	if slot == nil then
		return false
	end

	local last = entities.count
	local removedEntityId = entities.ids[slot]
	local movedEntityId = if slot ~= last then entities.ids[last] else nil
	if world ~= nil then
		clearEcsEntity(world, chunk, removedEntityId)
	end
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
	if world ~= nil and movedEntityId ~= nil then
		syncEntitySlotToEcs(world, chunk, slot)
	end
	return true
end

function Data.GetEcsWorld(world: WorldData): any
	return world.ecsWorld
end

function Data.GetEcsComponents(world: WorldData): EcsComponents
	return world.ecsComponents
end

function Data.GetEcsEntityByRuntimeId(world: WorldData, runtimeIdRaw: any): any?
	if typeof(runtimeIdRaw) ~= "number" then
		return nil
	end
	local runtimeId = math.floor(runtimeIdRaw)
	local ecsEntity = world.ecsEntityByRuntimeId[runtimeId]
	if ecsEntity == nil or not world.ecsWorld:contains(ecsEntity) then
		world.ecsEntityByRuntimeId[runtimeId] = nil
		return nil
	end
	return ecsEntity
end

function Data.GetEntityLocationByRuntimeId(world: WorldData, runtimeIdRaw: any): (ChunkData?, number?)
	if typeof(runtimeIdRaw) ~= "number" then
		return nil, nil
	end
	local runtimeId = math.floor(runtimeIdRaw)
	local chunk = world.entityChunkByRuntimeId[runtimeId]
	local slot = world.entitySlotByRuntimeId[runtimeId]
	if chunk == nil or slot == nil then
		return nil, nil
	end
	if slot < 1 or slot > chunk.entities.count or chunk.entities.ids[slot] ~= runtimeId then
		world.entityChunkByRuntimeId[runtimeId] = nil
		world.entitySlotByRuntimeId[runtimeId] = nil
		return nil, nil
	end
	return chunk, slot
end

function Data.SyncEntitySlotToEcs(world: WorldData, chunk: ChunkData, slotRaw: any): any?
	local slot = getEntitySlot(chunk.entities, slotRaw)
	if slot == nil then
		return nil
	end
	return syncEntitySlotToEcs(world, chunk, slot)
end

function Data.SyncEntitySlotFromEcs(world: WorldData, chunk: ChunkData, slotRaw: any): boolean
	local slot = getEntitySlot(chunk.entities, slotRaw)
	if slot == nil then
		return false
	end
	return syncEntitySlotFromEcs(world, chunk, slot)
end

function Data.ForEachEntity(chunk: ChunkData, callback: (slot: number, entityId: number) -> ())
	local entities = chunk.entities
	for slot = 1, entities.count do
		callback(slot, entities.ids[slot])
	end
end

function Data.GetStats(world: WorldData): { [string]: number }
	return {
		chunks = #world.chunkKeys,
		activeChunks = #world.activeChunkKeys,
		nextEntityId = world.nextEntityId,
		tick = world.tick,
	}
end
return Data
