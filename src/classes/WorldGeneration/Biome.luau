--!strict
local Biome = {}
Biome.__index = Biome

export type TileIdMap = {
	AIR: number,
	GRASS: number,
	JUNGLE_GRASS: number,
	DIRT: number,
	STONE: number,
	SAND: number,
	SANDSTONE: number,
	SNOW: number,
	ICE: number,
	MUD: number,
	CLAY: number,
	CORRUPT_GRASS: number,
	CORRUPT_SOIL: number,
	CORRUPT_STONE: number,
}

export type BiomeIdMap = {
	FOREST: number,
	DESERT: number,
	SNOW: number,
	JUNGLE: number,
}

export type BiomeTypeMap = {
	NORMAL: number,
	CORRUPTION: number,
}

export type ColumnProfile = {
	biomeId: number,
	biomeType: number,
	surfaceY: number,
	stoneStartDepth: number,
	topTileId: number,
	subsurfaceTileId: number,
	deepTileId: number,
}

export type BiomeConfig = {
	seed: number,
	tileId: TileIdMap,
	biomeId: BiomeIdMap,
	biomeType: BiomeTypeMap,
	surfaceBaseHeight: number,
	surfaceAmplitude: number,
	surfaceFrequency: number,
	surfaceOctaves: number,
	surfaceLacunarity: number,
	surfacePersistence: number,
	ridgeFrequency: number,
	ridgeAmplitude: number,
	biomeFrequency: number,
	biomeOctaves: number,
	biomeLacunarity: number,
	biomePersistence: number,
	stoneDepthMin: number,
	stoneDepthMax: number,
	corruptionFrequency: number,
	corruptionOctaves: number,
	corruptionLacunarity: number,
	corruptionPersistence: number,
	corruptionThreshold: number,
	corruptionRadiusStart: number,
	corruptionDistanceScale: number,
}

local DEFAULT_SURFACE_BASE_HEIGHT = 18
local DEFAULT_SURFACE_AMPLITUDE = 22
local DEFAULT_SURFACE_FREQUENCY = 0.012
local DEFAULT_SURFACE_OCTAVES = 4
local DEFAULT_SURFACE_LACUNARITY = 2.1
local DEFAULT_SURFACE_PERSISTENCE = 0.48
local DEFAULT_RIDGE_FREQUENCY = 0.028
local DEFAULT_RIDGE_AMPLITUDE = 6
local DEFAULT_BIOME_FREQUENCY = 0.0035
local DEFAULT_BIOME_OCTAVES = 3
local DEFAULT_BIOME_LACUNARITY = 2
local DEFAULT_BIOME_PERSISTENCE = 0.52
local DEFAULT_STONE_DEPTH_MIN = 4
local DEFAULT_STONE_DEPTH_MAX = 14
local DEFAULT_CORRUPTION_FREQUENCY = 0.0021
local DEFAULT_CORRUPTION_OCTAVES = 3
local DEFAULT_CORRUPTION_LACUNARITY = 2.05
local DEFAULT_CORRUPTION_PERSISTENCE = 0.54
local DEFAULT_CORRUPTION_THRESHOLD = 0.44
local DEFAULT_CORRUPTION_RADIUS_START = 180
local DEFAULT_CORRUPTION_DISTANCE_SCALE = 0.0022

local SEED_X_MULTIPLIER = 0.000137
local SEED_Y_MULTIPLIER = 0.000271
local TEMPERATURE_OFFSET = 71.217
local HUMIDITY_OFFSET = 143.903
local SURFACE_OFFSET = 233.119
local RIDGE_OFFSET = 319.727
local STONE_DEPTH_OFFSET = 421.519
local CORRUPTION_PRIMARY_OFFSET = 541.913
local CORRUPTION_SECONDARY_OFFSET = 637.271
local CORRUPTION_DETAIL_OFFSET_X = 733.849
local CORRUPTION_DETAIL_OFFSET_Y = 829.413
local JUNGLE_PRIMARY_OFFSET = 913.267
local JUNGLE_DETAIL_OFFSET_X = 1049.733
local JUNGLE_DETAIL_OFFSET_Y = 1171.221
local JUNGLE_HUMIDITY_MIN = -0.08
local JUNGLE_REGION_THRESHOLD = 0.19
local JUNGLE_SIDE_OFFSET = 1267.531
local JUNGLE_MODE_OFFSET = 1393.117
local JUNGLE_ANCHOR_OFFSET = 1519.881
local JUNGLE_BAND_NOISE_OFFSET = 1673.447
local JUNGLE_BAND_HALF_WIDTH_MIN = 90
local JUNGLE_BAND_HALF_WIDTH_MAX = 220
local JUNGLE_BAND_FEATHER_WIDTH = 110

local DEFAULT_BIOME_TYPE: BiomeTypeMap = {
	NORMAL = 1,
	CORRUPTION = 2,
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw :: number, minimum, maximum)
end

local function sanitizeOctaveCount(valueRaw: any, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw :: number), 1, 8)
end

local function sampleOctaveNoise(
	seed: number,
	x: number,
	baseFrequency: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	offsetX: number,
	offsetY: number
): number
	local frequency = baseFrequency
	local amplitude = 1
	local total = 0
	local amplitudeSum = 0

	for octave = 1, octaves do
		local sample = math.noise(
			(x + offsetX + octave * 0.73) * frequency,
			offsetY + octave * 3.11 + seed * SEED_Y_MULTIPLIER,
			seed * SEED_X_MULTIPLIER + octave * 0.17
		)
		total += sample * amplitude
		amplitudeSum += amplitude
		frequency *= lacunarity
		amplitude *= persistence
	end

	if amplitudeSum <= 0 then
		return 0
	end

	return total / amplitudeSum
end

local function resolveBiomeSurfaceTiles(self, biomeId: number, biomeType: number): (number, number, number)
	if biomeType == self.biomeType.CORRUPTION then
		return self.tileId.CORRUPT_GRASS, self.tileId.CORRUPT_SOIL, self.tileId.CORRUPT_STONE
	end

	if biomeId == self.biomeId.DESERT then
		return self.tileId.SAND, self.tileId.SAND, self.tileId.SANDSTONE
	end

	if biomeId == self.biomeId.SNOW then
		return self.tileId.SNOW, self.tileId.SNOW, self.tileId.ICE
	end

	if biomeId == self.biomeId.JUNGLE then
		return self.tileId.JUNGLE_GRASS, self.tileId.MUD, self.tileId.STONE
	end

	return self.tileId.GRASS, self.tileId.DIRT, self.tileId.STONE
end

local function sampleCorruptionScore(self, tileX: number, surfaceY: number): number
	local primaryNoise = sampleOctaveNoise(
		self.seed + 971,
		tileX,
		self.corruptionFrequency,
		self.corruptionOctaves,
		self.corruptionLacunarity,
		self.corruptionPersistence,
		CORRUPTION_PRIMARY_OFFSET,
		37.21
	)
	local secondaryNoise = sampleOctaveNoise(
		self.seed - 563,
		tileX,
		self.corruptionFrequency * 0.48,
		2,
		2,
		0.5,
		CORRUPTION_SECONDARY_OFFSET,
		81.37
	)
	local detailNoise = math.noise(
		(tileX + CORRUPTION_DETAIL_OFFSET_X) * (self.corruptionFrequency * 1.33),
		(surfaceY + CORRUPTION_DETAIL_OFFSET_Y) * 0.016,
		self.seed * SEED_X_MULTIPLIER
	)
	local distanceBias = math.clamp(
		math.max(0, math.abs(tileX) - self.corruptionRadiusStart) * self.corruptionDistanceScale,
		0,
		0.52
	)

	return primaryNoise * 0.58 + secondaryNoise * 0.24 + detailNoise * 0.18 + distanceBias
end

local function sampleJungleScore(self, tileX: number, temperature: number, humidity: number): number
	local jungleBandNoise = sampleOctaveNoise(
		self.seed + 1873,
		tileX,
		self.biomeFrequency * 0.92,
		math.max(2, self.biomeOctaves - 1),
		self.biomeLacunarity,
		self.biomePersistence,
		JUNGLE_PRIMARY_OFFSET,
		129.53
	)
	local jungleDetailNoise = math.noise(
		(tileX + JUNGLE_DETAIL_OFFSET_X) * (self.biomeFrequency * 1.41),
		JUNGLE_DETAIL_OFFSET_Y,
		self.seed * SEED_X_MULTIPLIER
	)
	local humidityScore = humidity * 0.42
	local warmthScore = temperature * 0.08
	local jungleBandScore = jungleBandNoise * 0.74
	local detailScore = jungleDetailNoise * 0.26

	return humidityScore + warmthScore + jungleBandScore + detailScore
end

local function resolveJunglePlacement(self): (number, number, number, number, string)
	local sideNoise = math.noise(self.seed * SEED_X_MULTIPLIER + JUNGLE_SIDE_OFFSET, 19.37, 71.19)
	local preferredSideSign = if sideNoise >= 0 then 1 else -1

	local modeNoise = math.noise(self.seed * SEED_Y_MULTIPLIER + JUNGLE_MODE_OFFSET, 43.21, 12.08)
	local placementMode = if modeNoise >= 0 then 2 else 1

	local anchorNoise = math.noise(self.seed * 0.001173 + JUNGLE_ANCHOR_OFFSET, 0, 0)
	local widthNoise = math.noise(self.seed * 0.001571 + JUNGLE_ANCHOR_OFFSET + 33.7, 0, 0)

	local bandHalfWidth = math.floor(
		math.clamp(
			JUNGLE_BAND_HALF_WIDTH_MIN + (widthNoise + 1) * 0.5 * (JUNGLE_BAND_HALF_WIDTH_MAX - JUNGLE_BAND_HALF_WIDTH_MIN),
			JUNGLE_BAND_HALF_WIDTH_MIN,
			JUNGLE_BAND_HALF_WIDTH_MAX
		)
	)

	local anchorDistance = 0
	local placementLabel = "FarFromCorruption"
	if placementMode == 1 then
		local insideBias = self.corruptionRadiusStart * 0.58
		local jitter = anchorNoise * 54
		anchorDistance = math.floor(math.max(70, insideBias + jitter))
	else
		placementLabel = "BehindCorruption"
		local outsideBias = self.corruptionRadiusStart + 175
		local jitter = anchorNoise * 92
		anchorDistance = math.floor(math.max(self.corruptionRadiusStart + 72, outsideBias + jitter))
	end

	return preferredSideSign, placementMode, anchorDistance, bandHalfWidth, placementLabel
end

local function sampleJungleBandWeight(self, tileX: number): number
	if tileX * self.junglePreferredSideSign <= 0 then
		return 0
	end

	local sideDistance = math.abs(tileX)
	local distanceFromAnchor = math.abs(sideDistance - self.jungleAnchorDistance)
	local fullWidth = self.jungleBandHalfWidth + JUNGLE_BAND_FEATHER_WIDTH
	if distanceFromAnchor > fullWidth then
		return 0
	end

	local coreAlpha = 1 - math.clamp(distanceFromAnchor / self.jungleBandHalfWidth, 0, 1)
	local featherAlpha = 1 - math.clamp((distanceFromAnchor - self.jungleBandHalfWidth) / JUNGLE_BAND_FEATHER_WIDTH, 0, 1)

	local bandNoise = sampleOctaveNoise(
		self.seed + 2441,
		tileX,
		self.biomeFrequency * 1.21,
		2,
		2,
		0.5,
		JUNGLE_BAND_NOISE_OFFSET,
		57.37
	)

	return math.clamp(coreAlpha * 0.78 + featherAlpha * 0.34 + bandNoise * 0.19, 0, 1)
end

function Biome.new(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local tileId = (config :: any).tileId :: TileIdMap
	local biomeId = (config :: any).biomeId :: BiomeIdMap
	local biomeType = if typeof((config :: any).biomeType) == "table"
		then (config :: any).biomeType :: BiomeTypeMap
		else DEFAULT_BIOME_TYPE

	local self = setmetatable({
		seed = clampNumber((config :: any).seed, -2147483648, 2147483647, 13371337),
		tileId = tileId,
		biomeId = biomeId,
		biomeType = biomeType,
		surfaceBaseHeight = clampNumber(
			(config :: any).surfaceBaseHeight,
			-1024,
			1024,
			DEFAULT_SURFACE_BASE_HEIGHT
		),
		surfaceAmplitude = clampNumber((config :: any).surfaceAmplitude, 0, 512, DEFAULT_SURFACE_AMPLITUDE),
		surfaceFrequency = clampNumber((config :: any).surfaceFrequency, 0.0001, 1, DEFAULT_SURFACE_FREQUENCY),
		surfaceOctaves = sanitizeOctaveCount((config :: any).surfaceOctaves, DEFAULT_SURFACE_OCTAVES),
		surfaceLacunarity = clampNumber(
			(config :: any).surfaceLacunarity,
			1,
			4,
			DEFAULT_SURFACE_LACUNARITY
		),
		surfacePersistence = clampNumber(
			(config :: any).surfacePersistence,
			0.1,
			0.95,
			DEFAULT_SURFACE_PERSISTENCE
		),
		ridgeFrequency = clampNumber((config :: any).ridgeFrequency, 0.0001, 1, DEFAULT_RIDGE_FREQUENCY),
		ridgeAmplitude = clampNumber((config :: any).ridgeAmplitude, 0, 512, DEFAULT_RIDGE_AMPLITUDE),
		biomeFrequency = clampNumber((config :: any).biomeFrequency, 0.0001, 1, DEFAULT_BIOME_FREQUENCY),
		biomeOctaves = sanitizeOctaveCount((config :: any).biomeOctaves, DEFAULT_BIOME_OCTAVES),
		biomeLacunarity = clampNumber((config :: any).biomeLacunarity, 1, 4, DEFAULT_BIOME_LACUNARITY),
		biomePersistence = clampNumber(
			(config :: any).biomePersistence,
			0.1,
			0.95,
			DEFAULT_BIOME_PERSISTENCE
		),
		stoneDepthMin = math.floor(
			clampNumber((config :: any).stoneDepthMin, 1, 64, DEFAULT_STONE_DEPTH_MIN)
		),
		stoneDepthMax = math.floor(
			clampNumber((config :: any).stoneDepthMax, 2, 128, DEFAULT_STONE_DEPTH_MAX)
		),
		corruptionFrequency = clampNumber(
			(config :: any).corruptionFrequency,
			0.0001,
			0.5,
			DEFAULT_CORRUPTION_FREQUENCY
		),
		corruptionOctaves = sanitizeOctaveCount((config :: any).corruptionOctaves, DEFAULT_CORRUPTION_OCTAVES),
		corruptionLacunarity = clampNumber(
			(config :: any).corruptionLacunarity,
			1,
			4,
			DEFAULT_CORRUPTION_LACUNARITY
		),
		corruptionPersistence = clampNumber(
			(config :: any).corruptionPersistence,
			0.1,
			0.95,
			DEFAULT_CORRUPTION_PERSISTENCE
		),
		corruptionThreshold = clampNumber(
			(config :: any).corruptionThreshold,
			-1,
			1,
			DEFAULT_CORRUPTION_THRESHOLD
		),
		corruptionRadiusStart = clampNumber(
			(config :: any).corruptionRadiusStart,
			0,
			100000,
			DEFAULT_CORRUPTION_RADIUS_START
		),
		corruptionDistanceScale = clampNumber(
			(config :: any).corruptionDistanceScale,
			0,
			0.02,
			DEFAULT_CORRUPTION_DISTANCE_SCALE
		),
		junglePreferredSideSign = 1,
		junglePlacementMode = 1,
		jungleAnchorDistance = 180,
		jungleBandHalfWidth = 140,
		junglePlacementLabel = "FarFromCorruption",
	}, Biome)

	if self.stoneDepthMax < self.stoneDepthMin then
		self.stoneDepthMax = self.stoneDepthMin
	end

	local preferredSideSign, placementMode, anchorDistance, bandHalfWidth, placementLabel = resolveJunglePlacement(self)
	self.junglePreferredSideSign = preferredSideSign
	self.junglePlacementMode = placementMode
	self.jungleAnchorDistance = anchorDistance
	self.jungleBandHalfWidth = bandHalfWidth
	self.junglePlacementLabel = placementLabel

	return self
end

function Biome.resolveBiomeType(self, tileX: number, surfaceY: number, biomeId: number): number
	local score = sampleCorruptionScore(self, tileX, surfaceY)
	local threshold = self.corruptionThreshold

	if biomeId == self.biomeId.SNOW then
		threshold += 0.04
	elseif biomeId == self.biomeId.DESERT then
		threshold += 0.03
	elseif biomeId == self.biomeId.JUNGLE then
		threshold += 0.11
	end

	if score >= threshold then
		return self.biomeType.CORRUPTION
	end
	return self.biomeType.NORMAL
end

function Biome.sampleTemperatureHumidity(self, tileX: number): (number, number)
	local temperature = sampleOctaveNoise(
		self.seed,
		tileX,
		self.biomeFrequency,
		self.biomeOctaves,
		self.biomeLacunarity,
		self.biomePersistence,
		TEMPERATURE_OFFSET,
		37.45
	)
	local humidity = sampleOctaveNoise(
		self.seed,
		tileX,
		self.biomeFrequency,
		self.biomeOctaves,
		self.biomeLacunarity,
		self.biomePersistence,
		HUMIDITY_OFFSET,
		83.91
	)
	return temperature, humidity
end

function Biome.resolveBiomeId(self, tileX: number, temperature: number, humidity: number): number
	local desertScore = temperature * 1.1 - humidity * 0.45
	local snowScore = -temperature * 1.2 - humidity * 0.1
	local jungleScore = sampleJungleScore(self, tileX, temperature, humidity)
	local forestScore = 1 - math.abs(temperature * 0.6) - math.abs(humidity * 0.35)

	local jungleBandWeight = sampleJungleBandWeight(self, tileX)
	if humidity >= JUNGLE_HUMIDITY_MIN and jungleBandWeight > 0 then
		local weightedJungleScore = jungleScore + jungleBandWeight * 1.18
		if weightedJungleScore >= JUNGLE_REGION_THRESHOLD then
			return self.biomeId.JUNGLE
		end
	end

	local selectedBiomeId = self.biomeId.FOREST
	local selectedScore = forestScore

	if desertScore > selectedScore then
		selectedBiomeId = self.biomeId.DESERT
		selectedScore = desertScore
	end

	if snowScore > selectedScore then
		selectedBiomeId = self.biomeId.SNOW
		selectedScore = snowScore
	end

	return selectedBiomeId
end

function Biome.sampleSurfaceHeight(self, tileX: number, biomeId: number): number
	local terrainWave = sampleOctaveNoise(
		self.seed,
		tileX,
		self.surfaceFrequency,
		self.surfaceOctaves,
		self.surfaceLacunarity,
		self.surfacePersistence,
		SURFACE_OFFSET,
		11.97
	)
	local ridgeWave = math.abs(sampleOctaveNoise(
		self.seed,
		tileX,
		self.ridgeFrequency,
		2,
		2,
		0.5,
		RIDGE_OFFSET,
		29.04
	))

	local biomeHeightOffset = 0
	if biomeId == self.biomeId.DESERT then
		biomeHeightOffset = -4
	elseif biomeId == self.biomeId.SNOW then
		biomeHeightOffset = 6
	elseif biomeId == self.biomeId.JUNGLE then
		biomeHeightOffset = 2
	end

	local height = self.surfaceBaseHeight + terrainWave * self.surfaceAmplitude + ridgeWave * self.ridgeAmplitude
	return math.floor(height + biomeHeightOffset)
end

function Biome.sampleStoneStartDepth(self, tileX: number, biomeId: number): number
	local noiseValue = sampleOctaveNoise(
		self.seed,
		tileX,
		self.surfaceFrequency * 1.25,
		3,
		2,
		0.5,
		STONE_DEPTH_OFFSET,
		53.08
	)
	local alpha = (noiseValue + 1) * 0.5
	local depth = self.stoneDepthMin + (self.stoneDepthMax - self.stoneDepthMin) * alpha
	if biomeId == self.biomeId.DESERT then
		depth += 2
	elseif biomeId == self.biomeId.SNOW then
		depth += 1
	end
	return math.max(1, math.floor(depth))
end

function Biome.getColumnProfile(self, tileX: number): ColumnProfile
	local temperature, humidity = self:sampleTemperatureHumidity(tileX)
	local biomeId = self:resolveBiomeId(tileX, temperature, humidity)
	local surfaceY = self:sampleSurfaceHeight(tileX, biomeId)
	local biomeType = self:resolveBiomeType(tileX, surfaceY, biomeId)
	local stoneStartDepth = self:sampleStoneStartDepth(tileX, biomeId)
	if biomeType == self.biomeType.CORRUPTION then
		stoneStartDepth = math.max(2, stoneStartDepth + 2)
	end
	local topTileId, subsurfaceTileId, deepTileId = resolveBiomeSurfaceTiles(self, biomeId, biomeType)

	return {
		biomeId = biomeId,
		biomeType = biomeType,
		surfaceY = surfaceY,
		stoneStartDepth = stoneStartDepth,
		topTileId = topTileId,
		subsurfaceTileId = subsurfaceTileId,
		deepTileId = deepTileId,
	}
end

function Biome.resolveTileForDepth(self, column: ColumnProfile, depthBelowSurface: number): number
	if depthBelowSurface < 0 then
		return self.tileId.AIR
	end

	if depthBelowSurface == 0 then
		return column.topTileId
	end

	if depthBelowSurface < column.stoneStartDepth then
		return column.subsurfaceTileId
	end

	if column.biomeType == self.biomeType.CORRUPTION then
		if depthBelowSurface < column.stoneStartDepth + 4 then
			return self.tileId.CORRUPT_SOIL
		end
		return self.tileId.CORRUPT_STONE
	end

	if column.biomeId == self.biomeId.SNOW and depthBelowSurface >= column.stoneStartDepth + 8 then
		return self.tileId.ICE
	end

	if column.biomeId == self.biomeId.JUNGLE and depthBelowSurface < column.stoneStartDepth + 7 then
		return self.tileId.MUD
	end

	if column.biomeId == self.biomeId.DESERT and depthBelowSurface < column.stoneStartDepth + 6 then
		return self.tileId.SANDSTONE
	end

	return column.deepTileId
end

function Biome.convertTileToBiomeType(self, tileId: number, biomeType: number): number
	if biomeType == self.biomeType.CORRUPTION then
		if tileId == self.tileId.GRASS or tileId == self.tileId.JUNGLE_GRASS then
			return self.tileId.CORRUPT_GRASS
		end
		if tileId == self.tileId.DIRT or tileId == self.tileId.MUD or tileId == self.tileId.SAND then
			return self.tileId.CORRUPT_SOIL
		end
		if tileId == self.tileId.STONE or tileId == self.tileId.SANDSTONE or tileId == self.tileId.SNOW or tileId == self.tileId.ICE then
			return self.tileId.CORRUPT_STONE
		end
		return tileId
	end

	if tileId == self.tileId.CORRUPT_GRASS then
		return self.tileId.GRASS
	end
	if tileId == self.tileId.CORRUPT_SOIL then
		return self.tileId.DIRT
	end
	if tileId == self.tileId.CORRUPT_STONE then
		return self.tileId.STONE
	end
	return tileId
end

export type Biome = typeof(setmetatable(
	{} :: {
		seed: number,
		tileId: TileIdMap,
		biomeId: BiomeIdMap,
		biomeType: BiomeTypeMap,
		surfaceBaseHeight: number,
		surfaceAmplitude: number,
		surfaceFrequency: number,
		surfaceOctaves: number,
		surfaceLacunarity: number,
		surfacePersistence: number,
		ridgeFrequency: number,
		ridgeAmplitude: number,
		biomeFrequency: number,
		biomeOctaves: number,
		biomeLacunarity: number,
		biomePersistence: number,
		stoneDepthMin: number,
		stoneDepthMax: number,
		corruptionFrequency: number,
		corruptionOctaves: number,
		corruptionLacunarity: number,
		corruptionPersistence: number,
		corruptionThreshold: number,
		corruptionRadiusStart: number,
		corruptionDistanceScale: number,
		junglePreferredSideSign: number,
		junglePlacementMode: number,
		jungleAnchorDistance: number,
		jungleBandHalfWidth: number,
		junglePlacementLabel: string,
	},
	Biome
))

return Biome
