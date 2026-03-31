--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Shared = require(script.Parent.Shared)

local Net = {}

Net.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
Net.NETWORK_METHOD_SET_STREAM_RADIUS = "setStreamRadius"
Net.NETWORK_METHOD_SUBMIT_INPUT = "submitInput"

Net.CLIENT_METHOD_APPLY_STATE = "applyState"
Net.CLIENT_METHOD_CHUNK_DELTA = "onChunkDelta"
Net.CLIENT_METHOD_CHUNK_UNLOADED = "onChunkUnloaded"
Net.CLIENT_METHOD_ENTITY_DELTA = "onEntityDelta"
Net.CLIENT_METHOD_DEBUG_COUNTERS = "onDebugCounters"
Net.TRANSITIONAL_LEGACY_BRIDGE_ENABLED = true

export type RlePair = { value: number, length: number }

export type ChunkDelta = {
	key: string,
	chunkX: number,
	chunkY: number,
	chunkZ: number,
	revision: number,
	clusterCountX: number,
	clusterCountY: number,
	clusterCountZ: number,
	clusterChosenBiomeIdsRle: { RlePair },
	clusterBlendWeightsRle: { RlePair },
	clusterSolidMaskRle: { RlePair },
	clusterSurfaceYRle: { RlePair },
	entityCount: number,
	entityIds: { number },
	entityKinds: { number },
	entityFlags: { number },
	entityPosX: { number },
	entityPosY: { number },
	entityPosZ: { number },
}

local LEGACY_BIOME_TYPE_CORRUPTION = 2
local LEGACY_AXIS_MAX = 2048

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function sanitizeBiomeId(valueRaw: any, fallback: number): number
	return sanitizeInteger(valueRaw, Shared.BIOME_ID.FOREST, Shared.BIOME_ID.CORRUPTION, fallback)
end

local function decodeClusterIndex(index: number, countX: number, countY: number): (number, number, number)
	local linear = index - 1
	local clusterX = linear % countX
	local layer = math.floor(linear / countX)
	local clusterY = layer % countY
	local clusterZ = math.floor(layer / countY)
	return clusterX, clusterY, clusterZ
end

local function unpackLegacyChunkKey(chunkKeyRaw: any): (number?, number?, number?)
	if typeof(chunkKeyRaw) ~= "string" then
		return nil, nil, nil
	end

	local chunkX, chunkY, chunkZ = Shared.unpackChunkKey(chunkKeyRaw)
	if chunkX ~= nil and chunkY ~= nil and chunkZ ~= nil then
		return chunkX, chunkY, chunkZ
	end

	local xRaw, yRaw = string.match(chunkKeyRaw, "^(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil then
		return nil, nil, nil
	end

	local x = tonumber(xRaw)
	local y = tonumber(yRaw)
	if x == nil or y == nil then
		return nil, nil, nil
	end

	return x, y, 0
end

function Net.encodeRle(numbers: { number }): { RlePair }
	local encoded: { RlePair } = {}
	if #numbers <= 0 then
		return encoded
	end

	local currentValue = numbers[1]
	local currentLength = 1
	for index = 2, #numbers do
		local value = numbers[index]
		if value == currentValue then
			currentLength += 1
		else
			encoded[#encoded + 1] = {
				value = currentValue,
				length = currentLength,
			}
			currentValue = value
			currentLength = 1
		end
	end

	encoded[#encoded + 1] = {
		value = currentValue,
		length = currentLength,
	}
	return encoded
end

function Net.decodeRle(rleRaw: any): { number }
	if typeof(rleRaw) ~= "table" then
		return {}
	end

	local totalLength = 0
	for _, pair in rleRaw do
		if typeof(pair) == "table" then
			local length = sanitizeInteger((pair :: any).length, 1, 10000000, 1)
			totalLength += length
		end
	end

	local output = Sift.Array.create(totalLength, 0)
	local cursor = 1
	for _, pair in rleRaw do
		if typeof(pair) ~= "table" then
			continue
		end
		local value = if isFiniteNumber((pair :: any).value) then (pair :: any).value else 0
		local length = sanitizeInteger((pair :: any).length, 1, 10000000, 1)
		for _ = 1, length do
			output[cursor] = value
			cursor += 1
		end
	end
	return output
end

local function copyEntitySlice(array: { number }, count: number): { number }
	local copied = Sift.Array.create(count, 0)
	for index = 1, count do
		copied[index] = array[index]
	end
	return copied
end

local function copyLegacyEntitySlice(valuesRaw: any, count: number): { number }
	local copied = Sift.Array.create(count, 0)
	if typeof(valuesRaw) ~= "table" then
		return copied
	end
	for index = 1, count do
		local raw = (valuesRaw :: any)[index]
		copied[index] = if isFiniteNumber(raw) then raw else 0
	end
	return copied
end

function Net.buildChunkDelta(chunk: { [string]: any }, previousRevision: number?): ChunkDelta?
	if typeof(chunk) ~= "table" then
		return nil
	end

	local hasClusterArrays = typeof(chunk.clusterChosenBiomeIds) == "table"
		and typeof(chunk.clusterBlendWeights) == "table"
		and typeof(chunk.clusterSolidMask) == "table"
		and typeof(chunk.clusterSurfaceY) == "table"

	if not hasClusterArrays then
		if not Net.TRANSITIONAL_LEGACY_BRIDGE_ENABLED then
			return nil
		end
		local translated = Net.translateLegacyChunkToChunkDeltaTransitional(chunk)
		if translated == nil then
			return nil
		end
		if previousRevision ~= nil and previousRevision == translated.revision then
			return nil
		end
		return translated
	end

	if previousRevision ~= nil and previousRevision == chunk.revision then
		return nil
	end

	local entities = chunk.entities
	local entityCount = if typeof(entities) == "table" then sanitizeInteger((entities :: any).count, 0, 1000000, 0) else 0

	return {
		key = chunk.key,
		chunkX = chunk.chunkX,
		chunkY = chunk.chunkY,
		chunkZ = chunk.chunkZ,
		revision = chunk.revision,
		clusterCountX = chunk.clusterCountX,
		clusterCountY = chunk.clusterCountY,
		clusterCountZ = chunk.clusterCountZ,
		clusterChosenBiomeIdsRle = Net.encodeRle(chunk.clusterChosenBiomeIds),
		clusterBlendWeightsRle = Net.encodeRle(chunk.clusterBlendWeights),
		clusterSolidMaskRle = Net.encodeRle(chunk.clusterSolidMask),
		clusterSurfaceYRle = Net.encodeRle(chunk.clusterSurfaceY),
		entityCount = entityCount,
		entityIds = if entityCount > 0 then copyEntitySlice(entities.ids, entityCount) else {},
		entityKinds = if entityCount > 0 then copyEntitySlice(entities.kinds, entityCount) else {},
		entityFlags = if entityCount > 0 then copyEntitySlice(entities.flags, entityCount) else {},
		entityPosX = if entityCount > 0 then copyEntitySlice(entities.posX, entityCount) else {},
		entityPosY = if entityCount > 0 then copyEntitySlice(entities.posY, entityCount) else {},
		entityPosZ = if entityCount > 0 then copyEntitySlice(entities.posZ, entityCount) else {},
	}
end

function Net.decodeChunkDelta(deltaRaw: any): { [string]: any }?
	if typeof(deltaRaw) ~= "table" then
		return nil
	end
	local key = (deltaRaw :: any).key
	if typeof(key) ~= "string" or key == "" then
		return nil
	end

	local clusterChosenBiomeIds = Net.decodeRle((deltaRaw :: any).clusterChosenBiomeIdsRle)
	local clusterBlendWeights = Net.decodeRle((deltaRaw :: any).clusterBlendWeightsRle)
	local clusterSolidMask = Net.decodeRle((deltaRaw :: any).clusterSolidMaskRle)
	local clusterSurfaceY = Net.decodeRle((deltaRaw :: any).clusterSurfaceYRle)

	return {
		key = key,
		chunkX = sanitizeInteger((deltaRaw :: any).chunkX, -1000000, 1000000, 0),
		chunkY = sanitizeInteger((deltaRaw :: any).chunkY, -1000000, 1000000, 0),
		chunkZ = sanitizeInteger((deltaRaw :: any).chunkZ, -1000000, 1000000, 0),
		revision = sanitizeInteger((deltaRaw :: any).revision, 0, 1000000000, 0),
		clusterCountX = sanitizeInteger((deltaRaw :: any).clusterCountX, 1, 512, 1),
		clusterCountY = sanitizeInteger((deltaRaw :: any).clusterCountY, 1, 512, 1),
		clusterCountZ = sanitizeInteger((deltaRaw :: any).clusterCountZ, 1, 512, 1),
		clusterChosenBiomeIds = clusterChosenBiomeIds,
		clusterBlendWeights = clusterBlendWeights,
		clusterSolidMask = clusterSolidMask,
		clusterSurfaceY = clusterSurfaceY,
		entityCount = sanitizeInteger((deltaRaw :: any).entityCount, 0, 100000, 0),
		entityIds = if typeof((deltaRaw :: any).entityIds) == "table" then (deltaRaw :: any).entityIds else {},
		entityKinds = if typeof((deltaRaw :: any).entityKinds) == "table" then (deltaRaw :: any).entityKinds else {},
		entityFlags = if typeof((deltaRaw :: any).entityFlags) == "table" then (deltaRaw :: any).entityFlags else {},
		entityPosX = if typeof((deltaRaw :: any).entityPosX) == "table" then (deltaRaw :: any).entityPosX else {},
		entityPosY = if typeof((deltaRaw :: any).entityPosY) == "table" then (deltaRaw :: any).entityPosY else {},
		entityPosZ = if typeof((deltaRaw :: any).entityPosZ) == "table" then (deltaRaw :: any).entityPosZ else {},
	}
end

local function resolveLegacyBiomeId(biomeIdRaw: any, biomeTypeRaw: any, fallbackBiomeId: number): number
	if isFiniteNumber(biomeIdRaw) then
		return sanitizeBiomeId(biomeIdRaw, fallbackBiomeId)
	end
	if isFiniteNumber(biomeTypeRaw) then
		local biomeType = math.floor(biomeTypeRaw)
		if biomeType == LEGACY_BIOME_TYPE_CORRUPTION then
			return Shared.BIOME_ID.CORRUPTION
		end
	end
	return fallbackBiomeId
end

local function resolveLegacyChunkCoordinates(legacy: { [string]: any }): (number, number, number, string)
	local chunkX = sanitizeInteger(legacy.chunkX, -1000000, 1000000, 0)
	local chunkY = sanitizeInteger(legacy.chunkY, -1000000, 1000000, 0)
	local chunkZ = sanitizeInteger(legacy.chunkZ, -1000000, 1000000, 0)
	local key = Shared.packChunkKey(chunkX, chunkY, chunkZ)

	local parsedX, parsedY, parsedZ = unpackLegacyChunkKey(legacy.key)
	if parsedX ~= nil and parsedY ~= nil and parsedZ ~= nil then
		chunkX = parsedX
		chunkY = parsedY
		chunkZ = parsedZ
		key = Shared.packChunkKey(chunkX, chunkY, chunkZ)
	end

	return chunkX, chunkY, chunkZ, key
end

local function resolveLegacyAxisSize(legacy: { [string]: any }, fieldPrimary: string, fieldSecondary: string, fallback: number): number
	local primary = sanitizeInteger(legacy[fieldPrimary], 1, LEGACY_AXIS_MAX, 0)
	if primary > 0 then
		return primary
	end
	local secondary = sanitizeInteger(legacy[fieldSecondary], 1, LEGACY_AXIS_MAX, 0)
	if secondary > 0 then
		return secondary
	end
	return fallback
end

local function resolveLegacyClusterAxisCount(legacy: { [string]: any }, clusterField: string, tileAxisSize: number): number
	local direct = sanitizeInteger(legacy[clusterField], 1, 512, 0)
	if direct > 0 then
		return direct
	end
	return math.max(1, math.ceil(tileAxisSize / math.max(1, Shared.CLUSTER_SIZE)))
end

function Net.decodeLegacyChunkTransitional(legacyRaw: any): { [string]: any }?
	if not Net.TRANSITIONAL_LEGACY_BRIDGE_ENABLED then
		return nil
	end
	if typeof(legacyRaw) ~= "table" then
		return nil
	end

	local legacy = legacyRaw :: { [string]: any }
	local hasLegacyData = typeof(legacy.tiles) == "table"
		or typeof(legacy.biomeIds) == "table"
		or typeof(legacy.biomeTypes) == "table"
		or typeof(legacy.clusterChosenBiomeIds) == "table"
		or typeof(legacy.clusterSolidMask) == "table"
	if not hasLegacyData then
		return nil
	end

	local chunkX, chunkY, chunkZ, key = resolveLegacyChunkCoordinates(legacy)
	local tileCountX = resolveLegacyAxisSize(legacy, "tileCountX", "width", Shared.CLUSTER_SIZE)
	local tileCountY = resolveLegacyAxisSize(legacy, "tileCountY", "height", Shared.CLUSTER_SIZE)
	local tileCountZ = resolveLegacyAxisSize(legacy, "tileCountZ", "depth", 1)

	local clusterCountX = resolveLegacyClusterAxisCount(legacy, "clusterCountX", tileCountX)
	local clusterCountY = resolveLegacyClusterAxisCount(legacy, "clusterCountY", tileCountY)
	local clusterCountZ = resolveLegacyClusterAxisCount(legacy, "clusterCountZ", tileCountZ)
	local expectedClusters = clusterCountX * clusterCountY * clusterCountZ
	local clusterSize = math.max(1, Shared.CLUSTER_SIZE)

	local dominantBiomeId = sanitizeBiomeId(legacy.dominantBiomeId, Shared.BIOME_ID.FOREST)
	local revision = sanitizeInteger(legacy.revision, 0, 1000000000, 0)
	local tileMinY = sanitizeInteger(legacy.tileMinY, -1000000, 1000000, chunkY * tileCountY)

	local clusterChosenBiomeIds = Sift.Array.create(expectedClusters, dominantBiomeId)
	local clusterBlendWeights = Sift.Array.create(expectedClusters, 0)
	local clusterSolidMask = Sift.Array.create(expectedClusters, 0)
	local clusterSurfaceY = Sift.Array.create(expectedClusters, tileMinY)

	local clusterChosenBiomeIdsRaw = if typeof(legacy.clusterChosenBiomeIds) == "table"
		then (legacy.clusterChosenBiomeIds :: { any })
		else nil
	local clusterBlendWeightsRaw = if typeof(legacy.clusterBlendWeights) == "table"
		then (legacy.clusterBlendWeights :: { any })
		else nil
	local clusterSolidMaskRaw = if typeof(legacy.clusterSolidMask) == "table" then (legacy.clusterSolidMask :: { any }) else nil
	local clusterSurfaceYRaw = if typeof(legacy.clusterSurfaceY) == "table" then (legacy.clusterSurfaceY :: { any }) else nil

	if clusterChosenBiomeIdsRaw ~= nil then
		for clusterIndex = 1, expectedClusters do
			clusterChosenBiomeIds[clusterIndex] = sanitizeBiomeId(clusterChosenBiomeIdsRaw[clusterIndex], dominantBiomeId)
			clusterBlendWeights[clusterIndex] = if clusterBlendWeightsRaw ~= nil
				then sanitizeInteger(clusterBlendWeightsRaw[clusterIndex], 0, 255, 0)
				else 0
			clusterSolidMask[clusterIndex] = if clusterSolidMaskRaw ~= nil
				then sanitizeInteger(clusterSolidMaskRaw[clusterIndex], 0, 1, 0)
				else 0

			local clusterLocalX, clusterLocalY, _ = decodeClusterIndex(clusterIndex, clusterCountX, clusterCountY)
			local fallbackSurface = tileMinY + clusterLocalY * clusterSize + (clusterSize - 1)
			clusterSurfaceY[clusterIndex] = if clusterSurfaceYRaw ~= nil
				then sanitizeInteger(clusterSurfaceYRaw[clusterIndex], -1000000, 1000000, fallbackSurface)
				else fallbackSurface
		end
	else
		local tiles = if typeof(legacy.tiles) == "table" then (legacy.tiles :: { any }) else {}
		local biomeIds = if typeof(legacy.biomeIds) == "table" then (legacy.biomeIds :: { any }) else {}
		local biomeTypes = if typeof(legacy.biomeTypes) == "table" then (legacy.biomeTypes :: { any }) else {}
		local blendWeightsRaw = if typeof(legacy.blendWeights) == "table" then (legacy.blendWeights :: { any }) else nil

		local layerArea = tileCountX * tileCountY
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
					local minTileX = clusterLocalX * clusterSize
					local minLocalTileY = clusterLocalY * clusterSize
					local minLocalTileZ = clusterLocalZ * clusterSize
					local maxTileX = math.min(tileCountX - 1, minTileX + clusterSize - 1)
					local maxLocalTileY = math.min(tileCountY - 1, minLocalTileY + clusterSize - 1)
					local maxLocalTileZ = math.min(tileCountZ - 1, minLocalTileZ + clusterSize - 1)

					local forestCount = 0
					local desertCount = 0
					local snowCount = 0
					local jungleCount = 0
					local corruptionCount = 0
					local solidMask = 0
					local highestSolidTileY = -1

					for localTileZ = minLocalTileZ, maxLocalTileZ do
						for localTileY = minLocalTileY, maxLocalTileY do
							for localTileX = minTileX, maxTileX do
								local tileIndex = localTileZ * layerArea + localTileY * tileCountX + localTileX + 1
								local tileId = sanitizeInteger(tiles[tileIndex], 0, 65535, 0)
								if tileId ~= 0 then
									solidMask = 1
									if localTileY > highestSolidTileY then
										highestSolidTileY = localTileY
									end
								end

								local biomeId = resolveLegacyBiomeId(biomeIds[tileIndex], biomeTypes[tileIndex], dominantBiomeId)
								if biomeId == Shared.BIOME_ID.CORRUPTION then
									corruptionCount += 1
								elseif biomeId == Shared.BIOME_ID.JUNGLE then
									jungleCount += 1
								elseif biomeId == Shared.BIOME_ID.SNOW then
									snowCount += 1
								elseif biomeId == Shared.BIOME_ID.DESERT then
									desertCount += 1
								else
									forestCount += 1
								end
							end
						end
					end

					local chosenBiome = dominantBiomeId
					local bestCount = 0
					if forestCount > bestCount then
						bestCount = forestCount
						chosenBiome = Shared.BIOME_ID.FOREST
					end
					if desertCount > bestCount then
						bestCount = desertCount
						chosenBiome = Shared.BIOME_ID.DESERT
					end
					if snowCount > bestCount then
						bestCount = snowCount
						chosenBiome = Shared.BIOME_ID.SNOW
					end
					if jungleCount > bestCount then
						bestCount = jungleCount
						chosenBiome = Shared.BIOME_ID.JUNGLE
					end
					if corruptionCount > bestCount then
						chosenBiome = Shared.BIOME_ID.CORRUPTION
					end

					clusterChosenBiomeIds[clusterIndex] = chosenBiome
					clusterSolidMask[clusterIndex] = solidMask
					clusterSurfaceY[clusterIndex] = tileMinY + (if highestSolidTileY >= 0 then highestSolidTileY else maxLocalTileY)
					clusterBlendWeights[clusterIndex] = if blendWeightsRaw ~= nil
						then sanitizeInteger(blendWeightsRaw[clusterIndex], 0, 255, 0)
						else 0
				end
			end
		end
	end

	local entityCount = sanitizeInteger(legacy.entityCount, 0, 100000, 0)
	return {
		key = key,
		chunkX = chunkX,
		chunkY = chunkY,
		chunkZ = chunkZ,
		revision = revision,
		clusterCountX = clusterCountX,
		clusterCountY = clusterCountY,
		clusterCountZ = clusterCountZ,
		clusterChosenBiomeIds = clusterChosenBiomeIds,
		clusterBlendWeights = clusterBlendWeights,
		clusterSolidMask = clusterSolidMask,
		clusterSurfaceY = clusterSurfaceY,
		entityCount = entityCount,
		entityIds = copyLegacyEntitySlice(legacy.entityIds, entityCount),
		entityKinds = copyLegacyEntitySlice(legacy.entityKinds, entityCount),
		entityFlags = copyLegacyEntitySlice(legacy.entityFlags, entityCount),
		entityPosX = copyLegacyEntitySlice(legacy.entityPosX, entityCount),
		entityPosY = copyLegacyEntitySlice(legacy.entityPosY, entityCount),
		entityPosZ = copyLegacyEntitySlice(legacy.entityPosZ, entityCount),
	}
end

function Net.translateLegacyChunkToChunkDeltaTransitional(legacyRaw: any): ChunkDelta?
	local decoded = Net.decodeLegacyChunkTransitional(legacyRaw)
	if decoded == nil then
		return nil
	end

	local entityCount = sanitizeInteger(decoded.entityCount, 0, 100000, 0)
	return {
		key = decoded.key,
		chunkX = decoded.chunkX,
		chunkY = decoded.chunkY,
		chunkZ = decoded.chunkZ,
		revision = decoded.revision,
		clusterCountX = decoded.clusterCountX,
		clusterCountY = decoded.clusterCountY,
		clusterCountZ = decoded.clusterCountZ,
		clusterChosenBiomeIdsRle = Net.encodeRle(decoded.clusterChosenBiomeIds),
		clusterBlendWeightsRle = Net.encodeRle(decoded.clusterBlendWeights),
		clusterSolidMaskRle = Net.encodeRle(decoded.clusterSolidMask),
		clusterSurfaceYRle = Net.encodeRle(decoded.clusterSurfaceY),
		entityCount = entityCount,
		entityIds = if entityCount > 0 then copyEntitySlice(decoded.entityIds, entityCount) else {},
		entityKinds = if entityCount > 0 then copyEntitySlice(decoded.entityKinds, entityCount) else {},
		entityFlags = if entityCount > 0 then copyEntitySlice(decoded.entityFlags, entityCount) else {},
		entityPosX = if entityCount > 0 then copyEntitySlice(decoded.entityPosX, entityCount) else {},
		entityPosY = if entityCount > 0 then copyEntitySlice(decoded.entityPosY, entityCount) else {},
		entityPosZ = if entityCount > 0 then copyEntitySlice(decoded.entityPosZ, entityCount) else {},
	}
end

function Net.decodeChunkPayload(payloadRaw: any): { [string]: any }?
	local decoded = Net.decodeChunkDelta(payloadRaw)
	if decoded ~= nil then
		return decoded
	end
	return Net.decodeLegacyChunkTransitional(payloadRaw)
end

function Net.validateClientInput(inputRaw: any): (boolean, string)
	if typeof(inputRaw) ~= "table" then
		return false, "payload must be a table"
	end

	local input = inputRaw :: { [string]: any }
	local entityId = sanitizeInteger(input.entityId, 0, 1000000000, 0)
	if entityId <= 0 then
		return false, "entityId is required"
	end
	if not isFiniteNumber(input.moveX) or not isFiniteNumber(input.moveZ) then
		return false, "moveX/moveZ must be numbers"
	end
	if math.abs(input.moveX) > 1.001 or math.abs(input.moveZ) > 1.001 then
		return false, "move input outside [-1, 1]"
	end
	return true, "ok"
end

function Net.predictEntityPosition(
	currentX: number,
	currentY: number,
	currentZ: number,
	velocityX: number,
	velocityY: number,
	velocityZ: number,
	deltaTime: number
): (number, number, number)
	return currentX + velocityX * deltaTime, currentY + velocityY * deltaTime, currentZ + velocityZ * deltaTime
end

function Net.sanitizeStreamRadius(valueRaw: any, fallback: number): number
	return sanitizeInteger(valueRaw, 1, 32, fallback)
end

function Net.chunkPriorityFromCenter(chunkX: number, chunkY: number, chunkZ: number, centerX: number, centerY: number, centerZ: number): number
	local dx = chunkX - centerX
	local dy = chunkY - centerY
	local dz = chunkZ - centerZ
	return dx * dx + dy * dy + dz * dz
end

function Net.unpackChunkKey(chunkKey: string): (number?, number?, number?)
	return Shared.unpackChunkKey(chunkKey)
end

return Net
