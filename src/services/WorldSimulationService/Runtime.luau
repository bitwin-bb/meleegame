--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Data = require(script.Parent.Data)
local Shared = require(script.Parent.Shared)
local State = require(script.Parent.State)

local Runtime = {}
Runtime.__index = Runtime

export type Runtime = typeof(setmetatable({} :: any, Runtime))

local CORRUPTION_NEIGHBOR_OFFSETS = {
	{ -1, 0, 0 },
	{ 1, 0, 0 },
	{ 0, -1, 0 },
	{ 0, 1, 0 },
	{ 0, 0, -1 },
	{ 0, 0, 1 },
}

local function decodeClusterIndex(index: number, countX: number, countY: number): (number, number, number)
	local linear = index - 1
	local clusterX = linear % countX
	local layer = math.floor(linear / countX)
	local clusterY = layer % countY
	local clusterZ = math.floor(layer / countY)
	return clusterX, clusterY, clusterZ
end

local function encodeClusterIndex(clusterX: number, clusterY: number, clusterZ: number, countX: number, countY: number): number
	return Shared.computeClusterIndex(clusterX, clusterY, clusterZ, countX, countY)
end

local function convertTileToCorruption(tileId: number): number
	if tileId == Shared.TILE_ID.AIR then
		return tileId
	end
	if tileId == Shared.TILE_ID.STONE then
		return Shared.TILE_ID.CORRUPT_STONE
	end
	return Shared.TILE_ID.CORRUPT_SOIL
end

local function resolveSlicePerChunk(totalBudget: number, chunkCount: number, maxSlice: number): number
	if chunkCount <= 0 or totalBudget <= 0 then
		return 0
	end
	local perChunk = math.floor(totalBudget / chunkCount)
	if perChunk <= 0 then
		perChunk = 1
	end
	return math.max(1, math.min(maxSlice, perChunk))
end

local function processClusterSlice(
	chunk: Data.ChunkData,
	cursorMap: { [string]: number },
	sliceCount: number,
	handler: (clusterIndex: number) -> boolean
): (boolean, number)
	if sliceCount <= 0 then
		return false, 0
	end

	local totalClusters = chunk.clusterCountX * chunk.clusterCountY * chunk.clusterCountZ
	if totalClusters <= 0 then
		return false, 0
	end

	local cursor = cursorMap[chunk.key] or 1
	if cursor < 1 or cursor > totalClusters then
		cursor = 1
	end

	local limit = math.min(sliceCount, totalClusters)
	local changed = false
	for _ = 1, limit do
		local clusterIndex = cursor
		if handler(clusterIndex) then
			changed = true
		end
		cursor += 1
		if cursor > totalClusters then
			cursor = 1
		end
	end

	cursorMap[chunk.key] = cursor
	return changed, limit
end

local function processEntitySlice(
	chunk: Data.ChunkData,
	cursorMap: { [string]: number },
	sliceCount: number,
	handler: (slot: number, entityId: number) -> boolean
): (boolean, number)
	if sliceCount <= 0 then
		return false, 0
	end

	local entities = chunk.entities
	if entities.count <= 0 then
		return false, 0
	end

	local cursor = cursorMap[chunk.key] or 1
	if cursor < 1 or cursor > entities.count then
		cursor = 1
	end

	local limit = math.min(sliceCount, entities.count)
	local changed = false
	for _ = 1, limit do
		if cursor > entities.count then
			cursor = 1
		end
		local slot = cursor
		local entityId = entities.ids[slot]
		if handler(slot, entityId) then
			changed = true
		end
		cursor += 1
	end

	cursorMap[chunk.key] = cursor
	return changed, limit
end

function Runtime.applyBiomeToCluster(self: Runtime, chunk: Data.ChunkData, clusterIndex: number, biomeId: number): boolean
	if chunk.clusterChosenBiomeIds[clusterIndex] == biomeId then
		return false
	end

	chunk.clusterChosenBiomeIds[clusterIndex] = biomeId
	local clusterSize = math.max(1, self.config.clusterSize)
	local clusterX, clusterY, clusterZ = decodeClusterIndex(clusterIndex, chunk.clusterCountX, chunk.clusterCountY)
	local minTileX, minTileY, minTileZ, maxTileX, maxTileY, maxTileZ = State.resolveClusterBounds(
		clusterX,
		clusterY,
		clusterZ,
		clusterSize,
		chunk.tileCountX,
		chunk.tileCountY,
		chunk.tileCountZ
	)

	local solidMask = 0
	local clusterSurfaceY = chunk.clusterSurfaceY[clusterIndex] or (chunk.chunkY * chunk.tileCountY + minTileY)
	for tileZ = minTileZ, maxTileZ do
		for tileY = minTileY, maxTileY do
			for tileX = minTileX, maxTileX do
				local tileIndex = Shared.computeTileIndex(tileX, tileY, tileZ, chunk.tileCountX, chunk.tileCountY)
				local worldY = chunk.chunkY * chunk.tileCountY + tileY
				local depthBelowSurface = clusterSurfaceY - worldY
				local tileId = Shared.resolveTileIdForBiomeDepth(biomeId, depthBelowSurface)
				if biomeId == Shared.BIOME_ID.CORRUPTION then
					tileId = convertTileToCorruption(tileId)
				end
				chunk.tileIds[tileIndex] = tileId
				chunk.biomeIds[tileIndex] = biomeId
				chunk.corruptionLevels[tileIndex] = if biomeId == Shared.BIOME_ID.CORRUPTION then 1 else 0
				if tileId ~= Shared.TILE_ID.AIR then
					solidMask = 1
				end
			end
		end
	end

	chunk.clusterSolidMask[clusterIndex] = solidMask
	return true
end

function Runtime.stepCorruptionSlice(self: Runtime, chunk: Data.ChunkData, dt: number, sliceCount: number): (boolean, number)
	local spreadChance = math.clamp(self.config.corruptionSpreadRate * dt * 6, 0, 1)
	local decayChance = math.clamp(self.config.corruptionDecayRate * dt * 6, 0, 1)

	local changed, processed = processClusterSlice(chunk, self.corruptionClusterCursorByChunkKey, sliceCount, function(clusterIndex: number): boolean
		if chunk.clusterChosenBiomeIds[clusterIndex] ~= Shared.BIOME_ID.CORRUPTION then
			return false
		end

		local localChanged = false
		local clusterX, clusterY, clusterZ = decodeClusterIndex(clusterIndex, chunk.clusterCountX, chunk.clusterCountY)
		for _, offset in CORRUPTION_NEIGHBOR_OFFSETS do
			local nx = clusterX + offset[1]
			local ny = clusterY + offset[2]
			local nz = clusterZ + offset[3]
			if nx < 0 or nx >= chunk.clusterCountX or ny < 0 or ny >= chunk.clusterCountY or nz < 0 or nz >= chunk.clusterCountZ then
				continue
			end
			local neighborIndex = encodeClusterIndex(nx, ny, nz, chunk.clusterCountX, chunk.clusterCountY)
			if chunk.clusterChosenBiomeIds[neighborIndex] == Shared.BIOME_ID.CORRUPTION then
				continue
			end

			local roll = Shared.unitRandom(self.world.seed + self.world.tick, clusterIndex, neighborIndex, math.floor(dt * 1000), 991)
			if roll <= spreadChance then
				if self:applyBiomeToCluster(chunk, neighborIndex, Shared.BIOME_ID.CORRUPTION) then
					chunk.clusterBlendWeights[neighborIndex] = 255
					localChanged = true
				end
			end
		end

		if decayChance > 0 then
			local decayRoll = Shared.unitRandom(self.world.seed, chunk.chunkX, chunk.chunkY, chunk.chunkZ + clusterIndex, 421)
			if decayRoll < decayChance * 0.2 then
				local previous = chunk.clusterBlendWeights[clusterIndex]
				local nextValue = math.max(0, previous - 1)
				if nextValue ~= previous then
					chunk.clusterBlendWeights[clusterIndex] = nextValue
					localChanged = true
				end
			end
		end

		return localChanged
	end)

	if processed > 0 then
		local totalClusters = chunk.clusterCountX * chunk.clusterCountY * chunk.clusterCountZ
		local corrupted = 0
		for index = 1, totalClusters do
			if chunk.clusterChosenBiomeIds[index] == Shared.BIOME_ID.CORRUPTION then
				corrupted += 1
			end
		end
		chunk.flags = State.applyCorruptionFromWeight(
			chunk.flags,
			corrupted / math.max(1, totalClusters),
			self.config.corruptionActivationThreshold
		)
	end

	return changed, processed
end

function Runtime.stepBiomeSpreadSlice(self: Runtime, chunk: Data.ChunkData, dt: number, sliceCount: number): (boolean, number)
	local blendStep = math.max(1, math.floor(dt * 60 * 4))
	local clusterSize = math.max(1, self.config.clusterSize)

	return processClusterSlice(chunk, self.biomeClusterCursorByChunkKey, sliceCount, function(clusterIndex: number): boolean
		if chunk.clusterChosenBiomeIds[clusterIndex] == Shared.BIOME_ID.CORRUPTION then
			return false
		end

		local primary = chunk.clusterPrimaryBiomeIds[clusterIndex]
		local secondary = chunk.clusterSecondaryBiomeIds[clusterIndex]
		if primary == nil then
			return false
		end
		if secondary == nil or secondary == 0 then
			secondary = primary
		end

		local clusterX, clusterY, clusterZ = decodeClusterIndex(clusterIndex, chunk.clusterCountX, chunk.clusterCountY)
		local worldCenterY = chunk.chunkY * chunk.tileCountY + clusterY * clusterSize + math.floor(clusterSize * 0.5)
		local depthBelowSurface = (chunk.clusterSurfaceY[clusterIndex] or worldCenterY) - worldCenterY
		local targetWeight = 0
		if secondary ~= primary and depthBelowSurface >= 0 and depthBelowSurface <= self.config.nearSurfaceDepth then
			local worldCenterX = chunk.chunkX * chunk.tileCountX + clusterX * clusterSize + math.floor(clusterSize * 0.5)
			local worldCenterZ = chunk.chunkZ * chunk.tileCountZ + clusterZ * clusterSize + math.floor(clusterSize * 0.5)
			local edgeNoise = math.noise(
				(worldCenterX + 4123.77) * 0.141,
				(worldCenterZ + 5087.41) * 0.141,
				(self.world.seed + worldCenterY * 19) * 0.000371
			)
			targetWeight = math.floor(((edgeNoise + 1) * 0.5) * 255 + 0.5)
		end

		local previousWeight = chunk.clusterBlendWeights[clusterIndex] or 0
		local nextWeight = previousWeight
		if previousWeight < targetWeight then
			nextWeight = math.min(targetWeight, previousWeight + blendStep)
		elseif previousWeight > targetWeight then
			nextWeight = math.max(targetWeight, previousWeight - blendStep)
		end
		chunk.clusterBlendWeights[clusterIndex] = nextWeight

		local targetBiome = primary
		if secondary ~= primary and nextWeight >= 128 then
			targetBiome = secondary
		end

		local changed = false
		if targetBiome ~= chunk.clusterChosenBiomeIds[clusterIndex] then
			changed = self:applyBiomeToCluster(chunk, clusterIndex, targetBiome)
		end
		if nextWeight ~= previousWeight then
			changed = true
		end
		return changed
	end)
end

function Runtime.stepAiSlice(self: Runtime, chunk: Data.ChunkData, dt: number, sliceCount: number): (boolean, number)
	return processEntitySlice(chunk, self.aiEntityCursorByChunkKey, sliceCount, function(slot: number, entityId: number): boolean
		local entities = chunk.entities
		local flags = entities.flags[slot]
		if not State.shouldSimulateEntity(flags) then
			return false
		end
		if entities.kinds[slot] ~= Shared.ENTITY_KIND.CREATURE then
			return false
		end

		local previousVX = entities.velX[slot]
		local previousVZ = entities.velZ[slot]
		local previousFlags = flags
		local moveNoise = Shared.signedRandom(self.world.seed, self.world.tick, entityId, slot, 77)
		entities.velX[slot] = entities.velX[slot] * 0.86 + moveNoise * 2.3 * dt
		entities.velZ[slot] = entities.velZ[slot] * 0.86 + moveNoise * 1.9 * dt

		local speedSq = entities.velX[slot] * entities.velX[slot] + entities.velZ[slot] * entities.velZ[slot]
		if speedSq < 0.0004 then
			entities.flags[slot] = State.setFlag(flags, State.ENTITY_FLAGS.SLEEPING, true)
		else
			entities.flags[slot] = State.setFlag(flags, State.ENTITY_FLAGS.SLEEPING, false)
		end

		return previousVX ~= entities.velX[slot]
			or previousVZ ~= entities.velZ[slot]
			or previousFlags ~= entities.flags[slot]
	end)
end

function Runtime.stepPhysicsSlice(self: Runtime, chunk: Data.ChunkData, dt: number, sliceCount: number): (boolean, number)
	local gravity = 28
	local tileSize = math.max(0.001, self.config.tileSize)

	return processEntitySlice(chunk, self.physicsEntityCursorByChunkKey, sliceCount, function(slot: number, _: number): boolean
		local entities = chunk.entities
		local flags = entities.flags[slot]
		if not State.shouldSimulateEntity(flags) then
			return false
		end

		local previousX = entities.posX[slot]
		local previousY = entities.posY[slot]
		local previousZ = entities.posZ[slot]

		entities.velY[slot] -= gravity * dt
		entities.posX[slot] += entities.velX[slot] * dt
		entities.posY[slot] += entities.velY[slot] * dt
		entities.posZ[slot] += entities.velZ[slot] * dt

		local tileX = math.floor(entities.posX[slot] / tileSize)
		local tileZ = math.floor(entities.posZ[slot] / tileSize)
		local surfaceY = Shared.sampleSurfaceHeight(self.world.seed, tileX, tileZ)
		local floorY = (surfaceY + 1) * tileSize
		if entities.posY[slot] < floorY then
			entities.posY[slot] = floorY
			entities.velY[slot] = 0
		end

		return previousX ~= entities.posX[slot] or previousY ~= entities.posY[slot] or previousZ ~= entities.posZ[slot]
	end)
end

function Runtime.new(world: Data.WorldData, debugModuleRaw: any)
	local self = setmetatable({
		world = world,
		config = world.config,
		debug = debugModuleRaw,
		chunkCursor = 1,
		corruptionClusterCursorByChunkKey = {} :: { [string]: number },
		biomeClusterCursorByChunkKey = {} :: { [string]: number },
		aiEntityCursorByChunkKey = {} :: { [string]: number },
		physicsEntityCursorByChunkKey = {} :: { [string]: number },
	}, Runtime)
	return self
end

function Runtime.tick(self: Runtime, dt: number)
	local debugModule = self.debug
	local beginToken = if debugModule and debugModule.beginFrameScope then debugModule:beginFrameScope("runtime_tick") else nil

	self.world.tick += 1
	Data.compactActiveChunkKeys(self.world)
	local activeChunkKeys = self.world.activeChunkKeys
	local activeCount = #activeChunkKeys
	if activeCount <= 0 then
		if debugModule and beginToken ~= nil and debugModule.endFrameScope then
			debugModule:endFrameScope("runtime_tick", beginToken)
		end
		return
	end

	local chunkBudget = math.min(activeCount, self.config.maxChunksPerRuntimeTick)
	local runtimeBudget = self.config.maxRuntimeSecondsPerTick
	local startTime = os.clock()
	local selectedChunks = Sift.Array.create(chunkBudget)

	while #selectedChunks < chunkBudget do
		if os.clock() - startTime >= runtimeBudget then
			break
		end
		if self.chunkCursor > activeCount then
			self.chunkCursor = 1
		end

		local chunkKey = activeChunkKeys[self.chunkCursor]
		self.chunkCursor += 1
		if chunkKey == nil then
			continue
		end

		local chunk = self.world.chunksByKey[chunkKey]
		if chunk == nil then
			self.world.activeChunkLookup[chunkKey] = nil
			continue
		end
		if not State.shouldSimulateChunk(chunk.flags) then
			continue
		end
		selectedChunks[#selectedChunks + 1] = chunk
	end

	local selectedCount = #selectedChunks
	if selectedCount <= 0 then
		if debugModule and beginToken ~= nil and debugModule.endFrameScope then
			debugModule:endFrameScope("runtime_tick", beginToken)
		end
		return
	end

	local clusterSlice = math.max(1, self.config.runtimeClusterSlice)
	local entitySlice = math.max(1, self.config.runtimeEntitySlice)
	local corruptionSlicePerChunk = resolveSlicePerChunk(
		self.config.budgetCorruptionClustersPerTick,
		selectedCount,
		clusterSlice
	)
	local biomeSlicePerChunk = resolveSlicePerChunk(
		self.config.budgetBiomeSpreadClustersPerTick,
		selectedCount,
		clusterSlice
	)
	local aiSlicePerChunk = resolveSlicePerChunk(self.config.budgetAiEntitiesPerTick, selectedCount, entitySlice)
	local physicsSlicePerChunk = resolveSlicePerChunk(self.config.budgetPhysicsEntitiesPerTick, selectedCount, entitySlice)

	local processedChunks = 0
	local processedCorruption = 0
	local processedBiome = 0
	local processedAi = 0
	local processedPhysics = 0

	for _, chunk in selectedChunks do
		local changed = false
		local corruptionChanged, corruptionProcessed = self:stepCorruptionSlice(chunk, dt, corruptionSlicePerChunk)
		local biomeChanged, biomeProcessed = self:stepBiomeSpreadSlice(chunk, dt, biomeSlicePerChunk)
		local aiChanged, aiProcessed = self:stepAiSlice(chunk, dt, aiSlicePerChunk)
		local physicsChanged, physicsProcessed = self:stepPhysicsSlice(chunk, dt, physicsSlicePerChunk)

		processedCorruption += corruptionProcessed
		processedBiome += biomeProcessed
		processedAi += aiProcessed
		processedPhysics += physicsProcessed

		if corruptionChanged or biomeChanged or aiChanged or physicsChanged then
			changed = true
		end

		if changed then
			Data.bumpChunkRevision(chunk)
		else
			Data.clearChunkDirty(chunk)
		end

		processedChunks += 1
	end

	if debugModule ~= nil then
		if debugModule.incrementCounter then
			debugModule:incrementCounter("runtime_chunks_processed", processedChunks)
			debugModule:incrementCounter("runtime_corruption_clusters", processedCorruption)
			debugModule:incrementCounter("runtime_biome_clusters", processedBiome)
			debugModule:incrementCounter("runtime_ai_entities", processedAi)
			debugModule:incrementCounter("runtime_physics_entities", processedPhysics)
		end
		if beginToken ~= nil and debugModule.endFrameScope then
			debugModule:endFrameScope("runtime_tick", beginToken)
		end
	end
end

return Runtime
