--!strict

local Shared = require(script.Parent.Shared)

local State = {}

State.CHUNK_FLAGS = {
	DORMANT = 1,
	ACTIVE = 2,
	CORRUPTED = 4,
	DIRTY = 8,
	PAUSED = 16,
	STREAMED = 32,
}

State.ENTITY_FLAGS = {
	ACTIVE = 1,
	SLEEPING = 2,
	CORRUPTED = 4,
	PREDICTED = 8,
}

State.SYSTEM_FLAGS = {
	RUNNING = 1,
	PAUSED = 2,
	DEBUG = 4,
}

State.CHUNK_STATE = {
	DORMANT = 0,
	ACTIVE = 1,
	CORRUPTED = 2,
	PAUSED = 3,
}

local function hasFlag(flags: number, flag: number): boolean
	return bit32.band(flags, flag) ~= 0
end

local function setFlag(flags: number, flag: number, enabled: boolean): number
	if enabled then
		return bit32.bor(flags, flag)
	end
	return bit32.band(flags, bit32.bnot(flag))
end

State.hasFlag = hasFlag
State.setFlag = setFlag

function State.resolveChunkStateId(chunkFlags: number): number
	if hasFlag(chunkFlags, State.CHUNK_FLAGS.PAUSED) then
		return State.CHUNK_STATE.PAUSED
	end
	if hasFlag(chunkFlags, State.CHUNK_FLAGS.CORRUPTED) then
		return State.CHUNK_STATE.CORRUPTED
	end
	if hasFlag(chunkFlags, State.CHUNK_FLAGS.ACTIVE) then
		return State.CHUNK_STATE.ACTIVE
	end
	return State.CHUNK_STATE.DORMANT
end

function State.shouldSimulateChunk(chunkFlags: number): boolean
	if hasFlag(chunkFlags, State.CHUNK_FLAGS.PAUSED) then
		return false
	end
	return hasFlag(chunkFlags, State.CHUNK_FLAGS.ACTIVE) or hasFlag(chunkFlags, State.CHUNK_FLAGS.CORRUPTED)
end

function State.shouldSimulateEntity(entityFlags: number): boolean
	if hasFlag(entityFlags, State.ENTITY_FLAGS.SLEEPING) then
		return false
	end
	return hasFlag(entityFlags, State.ENTITY_FLAGS.ACTIVE)
end

function State.markChunkActive(chunkFlags: number, active: boolean): number
	local result = setFlag(chunkFlags, State.CHUNK_FLAGS.ACTIVE, active)
	if active then
		result = setFlag(result, State.CHUNK_FLAGS.DORMANT, false)
	else
		result = setFlag(result, State.CHUNK_FLAGS.DORMANT, true)
	end
	return result
end

function State.markChunkCorrupted(chunkFlags: number, corrupted: boolean): number
	return setFlag(chunkFlags, State.CHUNK_FLAGS.CORRUPTED, corrupted)
end

function State.markChunkDirty(chunkFlags: number, dirty: boolean): number
	return setFlag(chunkFlags, State.CHUNK_FLAGS.DIRTY, dirty)
end

function State.markChunkPaused(chunkFlags: number, paused: boolean): number
	return setFlag(chunkFlags, State.CHUNK_FLAGS.PAUSED, paused)
end

function State.distanceClassFromChunkDelta(
	deltaX: number,
	deltaY: number,
	deltaZ: number,
	activeRadius: number,
	verticalRadius: number
): number
	if math.abs(deltaY) > verticalRadius then
		return State.CHUNK_STATE.DORMANT
	end
	local horizontalDistanceSq = deltaX * deltaX + deltaZ * deltaZ
	local radiusSq = activeRadius * activeRadius
	if horizontalDistanceSq <= radiusSq then
		return State.CHUNK_STATE.ACTIVE
	end
	return State.CHUNK_STATE.DORMANT
end

function State.resolveClusterBounds(
	clusterX: number,
	clusterY: number,
	clusterZ: number,
	clusterSize: number,
	tileCountX: number,
	tileCountY: number,
	tileCountZ: number
): (number, number, number, number, number, number)
	local minTileX = clusterX * clusterSize
	local minTileY = clusterY * clusterSize
	local minTileZ = clusterZ * clusterSize
	local maxTileX = math.min(tileCountX - 1, minTileX + clusterSize - 1)
	local maxTileY = math.min(tileCountY - 1, minTileY + clusterSize - 1)
	local maxTileZ = math.min(tileCountZ - 1, minTileZ + clusterSize - 1)
	return minTileX, minTileY, minTileZ, maxTileX, maxTileY, maxTileZ
end

function State.applyCorruptionFromWeight(chunkFlags: number, normalizedWeight: number, activationThreshold: number): number
	local isCorrupted = normalizedWeight >= activationThreshold
	return State.markChunkCorrupted(chunkFlags, isCorrupted)
end

function State.createSystemFlags(debugEnabled: boolean): number
	local flags = State.SYSTEM_FLAGS.RUNNING
	if debugEnabled then
		flags = bit32.bor(flags, State.SYSTEM_FLAGS.DEBUG)
	end
	return flags
end

function State.isValidBiomeId(biomeId: number): boolean
	return biomeId == Shared.BIOME_ID.FOREST
		or biomeId == Shared.BIOME_ID.DESERT
		or biomeId == Shared.BIOME_ID.SNOW
		or biomeId == Shared.BIOME_ID.JUNGLE
		or biomeId == Shared.BIOME_ID.CORRUPTION
end

return State