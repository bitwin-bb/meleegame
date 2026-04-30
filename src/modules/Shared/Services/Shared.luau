--!strict

local Shared = {}

export type BiomeIdMap = {
	FOREST: number,
	DESERT: number,
	SNOW: number,
	JUNGLE: number,
	CORRUPTION: number,
}

export type TileIdMap = {
	AIR: number,
	GRASS: number,
	DIRT: number,
	STONE: number,
	SAND: number,
	SNOW: number,
	MUD: number,
	CORRUPT_SOIL: number,
	CORRUPT_STONE: number,
}

export type EntityKindMap = {
	NONE: number,
	CREATURE: number,
	PROJECTILE: number,
	ITEM: number,
}

local UINT32_MAX = 0xFFFFFFFF
local UINT32_WRAP = 4294967296
local INT32_SIGN_BIT = 0x80000000

local NOISE_SEED_X_MULTIPLIER = 0.000137
local NOISE_SEED_Y_MULTIPLIER = 0.000271
local TEMPERATURE_OFFSET_X = 613.73
local TEMPERATURE_OFFSET_Y = 191.19
local HUMIDITY_OFFSET_X = 881.42
local HUMIDITY_OFFSET_Y = 439.57
local TERRAIN_HEIGHT_OFFSET_X = 1193.27
local TERRAIN_HEIGHT_OFFSET_Y = 719.81
local TERRAIN_ROLLING_OFFSET_X = 1311.64
local TERRAIN_ROLLING_OFFSET_Y = 863.52
local TERRAIN_DETAIL_OFFSET_X = 1427.41
local TERRAIN_DETAIL_OFFSET_Y = 1001.33
local CORRUPTION_NOISE_OFFSET_X = 1733.11
local CORRUPTION_NOISE_OFFSET_Y = 1267.89

Shared.CLUSTER_SIZE = 2
Shared.CLUSTER_VOLUME = 8

Shared.BIOME_ID = {
	FOREST = 1,
	DESERT = 2,
	SNOW = 3,
	JUNGLE = 4,
	CORRUPTION = 5,
} :: BiomeIdMap

Shared.TILE_ID = {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	SNOW = 5,
	MUD = 6,
	CORRUPT_SOIL = 7,
	CORRUPT_STONE = 8,
} :: TileIdMap

Shared.ENTITY_KIND = {
	NONE = 0,
	CREATURE = 1,
	PROJECTILE = 2,
	ITEM = 3,
} :: EntityKindMap

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Shared.ClampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

function Shared.ClampInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

function Shared.PackChunkKey(chunkX: number, chunkY: number, chunkZ: number): string
	return `{chunkX}:{chunkY}:{chunkZ}`
end

function Shared.UnpackChunkKey(chunkKeyRaw: any): (number?, number?, number?)
	if typeof(chunkKeyRaw) ~= "string" then
		return nil, nil, nil
	end
	local xRaw, yRaw, zRaw = string.match(chunkKeyRaw, "^(-?%d+):(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil or zRaw == nil then
		return nil, nil, nil
	end

	local chunkX = tonumber(xRaw)
	local chunkY = tonumber(yRaw)
	local chunkZ = tonumber(zRaw)
	if chunkX == nil or chunkY == nil or chunkZ == nil then
		return nil, nil, nil
	end

	return chunkX, chunkY, chunkZ
end

function Shared.ToTileCoordinate(worldAxis: number, tileSize: number): number
	return math.floor(worldAxis / math.max(0.001, tileSize))
end

function Shared.ToChunkCoordinate(tileAxis: number, chunkAxisSize: number): number
	return math.floor(tileAxis / math.max(1, chunkAxisSize))
end

function Shared.ToLocalCoordinate(tileAxis: number, chunkAxis: number, chunkAxisSize: number): number
	return tileAxis - chunkAxis * chunkAxisSize
end

function Shared.ComputeTileIndex(localX: number, localY: number, localZ: number, sizeX: number, sizeY: number): number
	return localZ * sizeX * sizeY + localY * sizeX + localX + 1
end

function Shared.ComputeClusterCount(axisSize: number, clusterSize: number): number
	return math.max(1, math.ceil(axisSize / math.max(1, clusterSize)))
end

function Shared.ComputeClusterIndex(
	clusterLocalX: number,
	clusterLocalY: number,
	clusterLocalZ: number,
	clusterCountX: number,
	clusterCountY: number
): number
	return clusterLocalZ * clusterCountX * clusterCountY + clusterLocalY * clusterCountX + clusterLocalX + 1
end

function Shared.ToUnsignedInt32(value: number): number
	if value < 0 then
		return value + UINT32_WRAP
	end
	return value
end

function Shared.HashInt4(a: number, b: number, c: number, d: number): number
	local mixed = bit32.band(a, UINT32_MAX)
	mixed = bit32.band(bit32.bxor(mixed, bit32.band(b * 73856093, UINT32_MAX)), UINT32_MAX)
	mixed = bit32.band(bit32.bxor(mixed, bit32.band(c * 19349663, UINT32_MAX)), UINT32_MAX)
	mixed = bit32.band(bit32.bxor(mixed, bit32.band(d * 83492791, UINT32_MAX)), UINT32_MAX)
	mixed = bit32.band(mixed * 1664525 + 1013904223, UINT32_MAX)
	if mixed >= INT32_SIGN_BIT then
		return mixed - UINT32_WRAP
	end
	return mixed
end

function Shared.UnitRandom(seed: number, x: number, y: number, z: number, salt: number?): number
	local hashed = Shared.HashInt4(seed + (salt or 0), x, y, z)
	return math.clamp(Shared.ToUnsignedInt32(hashed) / UINT32_MAX, 0, 1)
end

function Shared.SignedRandom(seed: number, x: number, y: number, z: number, salt: number?): number
	return Shared.UnitRandom(seed, x, y, z, salt) * 2 - 1
end

function Shared.SampleFractalNoise2D(
	seed: number,
	x: number,
	z: number,
	frequency: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	offsetX: number,
	offsetY: number
): number
	local value = 0
	local amplitude = 1
	local amplitudeSum = 0
	local currentFrequency = frequency
	local octaveCount = math.max(1, octaves)

	for octave = 1, octaveCount do
		local sample = math.noise(
			(x + offsetX + octave * 0.71) * currentFrequency,
			(z + offsetY + octave * 0.47) * currentFrequency,
			seed * NOISE_SEED_X_MULTIPLIER + octave * NOISE_SEED_Y_MULTIPLIER
		)
		value += sample * amplitude
		amplitudeSum += amplitude
		currentFrequency *= lacunarity
		amplitude *= persistence
	end

	if amplitudeSum <= 0 then
		return 0
	end
	return value / amplitudeSum
end

function Shared.SampleFractalNoise3D(
	seed: number,
	x: number,
	y: number,
	z: number,
	frequency: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	offsetX: number,
	offsetY: number
): number
	local value = 0
	local amplitude = 1
	local amplitudeSum = 0
	local currentFrequency = frequency
	local octaveCount = math.max(1, octaves)

	for octave = 1, octaveCount do
		local sample = math.noise(
			(x + offsetX + octave * 0.39) * currentFrequency,
			(y + offsetY + octave * 0.53) * currentFrequency,
			(z + seed * NOISE_SEED_X_MULTIPLIER + octave * NOISE_SEED_Y_MULTIPLIER) * currentFrequency
		)
		value += sample * amplitude
		amplitudeSum += amplitude
		currentFrequency *= lacunarity
		amplitude *= persistence
	end

	if amplitudeSum <= 0 then
		return 0
	end
	return value / amplitudeSum
end

function Shared.SampleTemperature(seed: number, worldX: number, worldZ: number): number
	return Shared.SampleFractalNoise2D(
		seed,
		worldX,
		worldZ,
		0.0037,
		3,
		2.05,
		0.52,
		TEMPERATURE_OFFSET_X,
		TEMPERATURE_OFFSET_Y
	)
end

function Shared.SampleHumidity(seed: number, worldX: number, worldZ: number): number
	return Shared.SampleFractalNoise2D(
		seed,
		worldX,
		worldZ,
		0.0033,
		3,
		2.02,
		0.55,
		HUMIDITY_OFFSET_X,
		HUMIDITY_OFFSET_Y
	)
end

function Shared.SampleSurfaceHeight(seed: number, worldX: number, worldZ: number): number
	local biomeId = Shared.ResolveBiomeId(seed, worldX, worldZ, {})
	local broad = Shared.SampleFractalNoise3D(
		seed,
		worldX,
		0,
		worldZ,
		0.0024,
		4,
		2.1,
		0.48,
		TERRAIN_HEIGHT_OFFSET_X,
		TERRAIN_HEIGHT_OFFSET_Y
	)
	local rolling = Shared.SampleFractalNoise3D(
		seed + 187,
		worldX,
		0,
		worldZ,
		0.0062,
		3,
		2.05,
		0.5,
		TERRAIN_ROLLING_OFFSET_X,
		TERRAIN_ROLLING_OFFSET_Y
	)
	local detail = Shared.SampleFractalNoise3D(
		seed + 421,
		worldX,
		0,
		worldZ,
		0.015,
		2,
		2,
		0.5,
		TERRAIN_DETAIL_OFFSET_X,
		TERRAIN_DETAIL_OFFSET_Y
	)
	local ridged = math.abs(
		Shared.SampleFractalNoise3D(
			seed - 113,
			worldX,
			0,
			worldZ,
			0.0088,
			2,
			2,
			0.5,
			TERRAIN_DETAIL_OFFSET_X + 317.8,
			TERRAIN_DETAIL_OFFSET_Y + 211.4
		)
	)
	local height = 12 + broad * 13.5 + rolling * 5 + detail * 1.2 + ridged * 3.25

	if biomeId == Shared.BIOME_ID.DESERT then
		height -= 2
		height += Shared.SampleFractalNoise3D(
			seed + 911,
			worldX,
			0,
			worldZ,
			0.0042,
			3,
			1.92,
			0.52,
			TERRAIN_HEIGHT_OFFSET_X + 541.3,
			TERRAIN_HEIGHT_OFFSET_Y + 429.7
		) * 4.5
	elseif biomeId == Shared.BIOME_ID.SNOW then
		height += 1.5
		height += ridged * 1.25
	elseif biomeId == Shared.BIOME_ID.JUNGLE then
		height += 2.5
		height += rolling * 2
	elseif biomeId == Shared.BIOME_ID.CORRUPTION then
		height += ridged * 2.5 - 1
	end

	return math.floor(height + 0.5)
end

function Shared.ResolveBiomeId(seed: number, worldX: number, worldZ: number, thresholds: { [string]: number }): number
	local temperature = Shared.SampleTemperature(seed, worldX, worldZ)
	local humidity = Shared.SampleHumidity(seed, worldX, worldZ)
	local corruptionNoise = Shared.SampleFractalNoise2D(
		seed,
		worldX,
		worldZ,
		0.0018,
		3,
		2,
		0.54,
		CORRUPTION_NOISE_OFFSET_X,
		CORRUPTION_NOISE_OFFSET_Y
	)

	if corruptionNoise >= (thresholds.corruptionNoise or 0.52) then
		return Shared.BIOME_ID.CORRUPTION
	end
	if temperature >= (thresholds.desertHeat or 0.33) and humidity < 0.15 then
		return Shared.BIOME_ID.DESERT
	end
	if temperature <= (thresholds.snowCold or -0.35) then
		return Shared.BIOME_ID.SNOW
	end
	if humidity >= (thresholds.jungleHumidity or 0.28) and temperature > -0.2 then
		return Shared.BIOME_ID.JUNGLE
	end
	return Shared.BIOME_ID.FOREST
end

function Shared.ResolveTileIdForBiomeDepth(biomeId: number, depthBelowSurface: number): number
	if depthBelowSurface < 0 then
		return Shared.TILE_ID.AIR
	end
	if biomeId == Shared.BIOME_ID.CORRUPTION then
		if depthBelowSurface <= 1 then
			return Shared.TILE_ID.CORRUPT_SOIL
		end
		return Shared.TILE_ID.CORRUPT_STONE
	end
	if biomeId == Shared.BIOME_ID.DESERT then
		if depthBelowSurface <= 2 then
			return Shared.TILE_ID.SAND
		end
		return Shared.TILE_ID.STONE
	end
	if biomeId == Shared.BIOME_ID.SNOW then
		if depthBelowSurface <= 2 then
			return Shared.TILE_ID.SNOW
		end
		return Shared.TILE_ID.STONE
	end
	if biomeId == Shared.BIOME_ID.JUNGLE then
		if depthBelowSurface <= 1 then
			return Shared.TILE_ID.GRASS
		end
		if depthBelowSurface <= 5 then
			return Shared.TILE_ID.MUD
		end
		return Shared.TILE_ID.STONE
	end

	if depthBelowSurface == 0 then
		return Shared.TILE_ID.GRASS
	end
	if depthBelowSurface <= 3 then
		return Shared.TILE_ID.DIRT
	end
	return Shared.TILE_ID.STONE
end

Shared.clampNumber = Shared.ClampNumber
Shared.clampInteger = Shared.ClampInteger
Shared.packChunkKey = Shared.PackChunkKey
Shared.unpackChunkKey = Shared.UnpackChunkKey
Shared.toTileCoordinate = Shared.ToTileCoordinate
Shared.toChunkCoordinate = Shared.ToChunkCoordinate
Shared.toLocalCoordinate = Shared.ToLocalCoordinate
Shared.computeTileIndex = Shared.ComputeTileIndex
Shared.computeClusterCount = Shared.ComputeClusterCount
Shared.computeClusterIndex = Shared.ComputeClusterIndex
Shared.toUnsignedInt32 = Shared.ToUnsignedInt32
Shared.hashInt4 = Shared.HashInt4
Shared.unitRandom = Shared.UnitRandom
Shared.signedRandom = Shared.SignedRandom
Shared.sampleFractalNoise2D = Shared.SampleFractalNoise2D
Shared.sampleFractalNoise3D = Shared.SampleFractalNoise3D
Shared.sampleTemperature = Shared.SampleTemperature
Shared.sampleHumidity = Shared.SampleHumidity
Shared.sampleSurfaceHeight = Shared.SampleSurfaceHeight
Shared.resolveBiomeId = Shared.ResolveBiomeId
Shared.resolveTileIdForBiomeDepth = Shared.ResolveTileIdForBiomeDepth

return Shared
