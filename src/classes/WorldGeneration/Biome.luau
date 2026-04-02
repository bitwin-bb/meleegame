--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Noise = require(ReplicatedStorage.Shared.Modules.Math.Noise)

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
	snowDetailNoise: number,
	snowIceNoise: number,
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
	desertConfig: any?,
	snowConfig: any?,
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
local DESERT_SIDE_OFFSET = 1827.913
local DESERT_ANCHOR_OFFSET = 1949.307
local DESERT_BAND_NOISE_OFFSET = 2063.771
local DESERT_BAND_HALF_WIDTH_MIN = 110
local DESERT_BAND_HALF_WIDTH_MAX = 240
local DESERT_BAND_FEATHER_WIDTH = 125
local DESERT_HUMIDITY_MAX = 0.32
local DESERT_TEMPERATURE_MIN = -0.08
local DESERT_REGION_THRESHOLD = 0.22
local DEFAULT_DESERT_HEIGHT_OFFSET = -3
local DEFAULT_DESERT_DUNE_AMPLITUDE = 8.5
local DEFAULT_DESERT_DUNE_FREQUENCY = 0.0052
local DEFAULT_DESERT_DUNE_OCTAVES = 3
local DEFAULT_DESERT_DUNE_LACUNARITY = 1.92
local DEFAULT_DESERT_DUNE_PERSISTENCE = 0.52
local DEFAULT_DESERT_DETAIL_AMPLITUDE = 1.85
local DEFAULT_DESERT_DETAIL_FREQUENCY = 0.018
local DEFAULT_DESERT_BASE_TERRAIN_INFLUENCE = 0.22
local DEFAULT_DESERT_STONE_DEPTH_OFFSET = 3
local DEFAULT_DESERT_SUBSURFACE_SAND_DEPTH = 7
local DEFAULT_DESERT_SANDSTONE_DEPTH = 16
local SNOW_SIDE_OFFSET = 2147.331
local SNOW_ANCHOR_OFFSET = 2261.117
local SNOW_BAND_MACRO_OFFSET = 2379.541
local SNOW_BAND_BORDER_OFFSET = 2497.873
local SNOW_DETAIL_OFFSET = 2611.409
local SNOW_ICE_OFFSET = 2729.667
local DEFAULT_SNOW_REGION_WEIGHT = 1.08
local DEFAULT_SNOW_TEMPERATURE_MAX = 0.18
local DEFAULT_SNOW_HUMIDITY_MAX = 0.42
local DEFAULT_SNOW_REGION_THRESHOLD = 0.2
local DEFAULT_SNOW_BAND_HALF_WIDTH_MIN = 120
local DEFAULT_SNOW_BAND_HALF_WIDTH_MAX = 235
local DEFAULT_SNOW_BAND_FEATHER_WIDTH = 132
local DEFAULT_SNOW_ANCHOR_DISTANCE_BASE = 220
local DEFAULT_SNOW_ANCHOR_DISTANCE_JITTER = 108
local DEFAULT_SNOW_MACRO_FREQUENCY_SCALE = 0.88
local DEFAULT_SNOW_BORDER_FREQUENCY_SCALE = 1.38
local DEFAULT_SNOW_DETAIL_FREQUENCY_SCALE = 2.16
local DEFAULT_SNOW_HEIGHT_OFFSET = 0
local DEFAULT_SNOW_SMOOTHED_RIDGE_SCALE = 0.78
local DEFAULT_SNOW_STONE_DEPTH_OFFSET = 2
local DEFAULT_SNOW_CAP_DEPTH = 3
local DEFAULT_SNOW_COLD_SOIL_DEPTH = 6
local DEFAULT_SNOW_ICE_DEPTH_START = 11
local DEFAULT_SNOW_ICE_BAND_THICKNESS = 10
local DEFAULT_SNOW_ICE_DENSITY = 0.34
local DEFAULT_SNOW_PACKED_SNOW_DENSITY = 0.52

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

local function resolveTileIdByName(tileIdMap: TileIdMap, nameRaw: any, fallback: number): number
	if typeof(nameRaw) ~= "string" then
		return fallback
	end
	local tileId = (tileIdMap :: any)[nameRaw]
	if isFiniteNumber(tileId) then
		return tileId
	end
	return fallback
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
	return Noise.fbmOctaves(octaves, persistence, lacunarity, function(octave, frequency)
		local sampleFrequency = baseFrequency * frequency
		return math.noise(
			(x + offsetX + octave * 0.73) * sampleFrequency,
			offsetY + octave * 3.11 + seed * SEED_Y_MULTIPLIER,
			seed * SEED_X_MULTIPLIER + octave * 0.17
		)
	end)
end

local function resolveBiomeSurfaceTiles(self, biomeId: number, biomeType: number): (number, number, number)
	if biomeType == self.biomeType.CORRUPTION then
		return self.tileId.CORRUPT_GRASS, self.tileId.CORRUPT_SOIL, self.tileId.CORRUPT_STONE
	end

	if biomeId == self.biomeId.DESERT then
		return self.desertSurfaceTileId, self.desertFillerTileId, self.desertDeepTileId
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

local function resolveDesertPlacement(self): (number, number, number)
	local preferredSideSign = -self.junglePreferredSideSign
	if preferredSideSign == 0 then
		local sideNoise = math.noise(self.seed * SEED_X_MULTIPLIER + DESERT_SIDE_OFFSET, 57.81, 21.17)
		preferredSideSign = if sideNoise >= 0 then 1 else -1
	end

	local anchorNoise = math.noise(self.seed * 0.001391 + DESERT_ANCHOR_OFFSET, 0, 0)
	local widthNoise = math.noise(self.seed * 0.001713 + DESERT_ANCHOR_OFFSET + 41.3, 0, 0)
	local bandHalfWidth = math.floor(
		math.clamp(
			DESERT_BAND_HALF_WIDTH_MIN
				+ (widthNoise + 1) * 0.5 * (DESERT_BAND_HALF_WIDTH_MAX - DESERT_BAND_HALF_WIDTH_MIN),
			DESERT_BAND_HALF_WIDTH_MIN,
			DESERT_BAND_HALF_WIDTH_MAX
		)
	)

	local baseDistance = self.corruptionRadiusStart * 0.44 + 105
	local jitter = anchorNoise * 88
	local anchorDistance = math.floor(math.max(110, baseDistance + jitter))

	return preferredSideSign, anchorDistance, bandHalfWidth
end

local function sampleDesertBandWeight(self, tileX: number): number
	if tileX * self.desertPreferredSideSign <= 0 then
		return 0
	end

	local sideDistance = math.abs(tileX)
	local distanceFromAnchor = math.abs(sideDistance - self.desertAnchorDistance)
	local fullWidth = self.desertBandHalfWidth + DESERT_BAND_FEATHER_WIDTH
	if distanceFromAnchor > fullWidth then
		return 0
	end

	local coreAlpha = 1 - math.clamp(distanceFromAnchor / self.desertBandHalfWidth, 0, 1)
	local featherAlpha = 1
		- math.clamp((distanceFromAnchor - self.desertBandHalfWidth) / DESERT_BAND_FEATHER_WIDTH, 0, 1)

	local bandNoise = sampleOctaveNoise(
		self.seed + 3181,
		tileX,
		self.biomeFrequency * 1.06,
		math.max(2, self.biomeOctaves - 1),
		self.biomeLacunarity,
		self.biomePersistence,
		DESERT_BAND_NOISE_OFFSET,
		63.19
	)

	return math.clamp(coreAlpha * 0.84 + featherAlpha * 0.28 + bandNoise * 0.16, 0, 1)
end

local function resolveSnowPlacement(self): (number, number, number)
	local preferredSideSign = self.junglePreferredSideSign
	if preferredSideSign == 0 then
		local sideNoise = math.noise(self.seed * SEED_X_MULTIPLIER + SNOW_SIDE_OFFSET, 61.53, 37.91)
		preferredSideSign = if sideNoise >= 0 then 1 else -1
	end

	local anchorNoise = math.noise(self.seed * 0.001913 + SNOW_ANCHOR_OFFSET, 0, 0)
	local widthNoise = math.noise(self.seed * 0.002173 + SNOW_ANCHOR_OFFSET + 27.4, 0, 0)
	local bandHalfWidth = math.floor(
		math.clamp(
			self.snowBandHalfWidthMin
				+ (widthNoise + 1) * 0.5 * (self.snowBandHalfWidthMax - self.snowBandHalfWidthMin),
			self.snowBandHalfWidthMin,
			self.snowBandHalfWidthMax
		)
	)

	local baseDistance = self.corruptionRadiusStart * 0.52 + self.snowAnchorDistanceBase
	local jitter = anchorNoise * self.snowAnchorDistanceJitter
	local anchorDistance = math.floor(math.max(130, baseDistance + jitter))

	return preferredSideSign, anchorDistance, bandHalfWidth
end

local function sampleSnowBandWeight(self, tileX: number): number
	if tileX * self.snowPreferredSideSign <= 0 then
		return 0
	end

	local sideDistance = math.abs(tileX)
	local distanceFromAnchor = math.abs(sideDistance - self.snowAnchorDistance)
	local fullWidth = self.snowBandHalfWidth + self.snowBandFeatherWidth
	if distanceFromAnchor > fullWidth then
		return 0
	end

	local coreAlpha = 1 - math.clamp(distanceFromAnchor / self.snowBandHalfWidth, 0, 1)
	local featherAlpha = 1 - math.clamp(
		(distanceFromAnchor - self.snowBandHalfWidth) / self.snowBandFeatherWidth,
		0,
		1
	)

	local macroNoise = sampleOctaveNoise(
		self.seed + 3511,
		tileX,
		self.biomeFrequency * self.snowMacroFrequencyScale,
		math.max(2, self.biomeOctaves - 1),
		self.biomeLacunarity,
		self.biomePersistence,
		SNOW_BAND_MACRO_OFFSET,
		73.11
	)
	local borderNoise = sampleOctaveNoise(
		self.seed + 3791,
		tileX,
		self.biomeFrequency * self.snowBorderFrequencyScale,
		2,
		2,
		0.52,
		SNOW_BAND_BORDER_OFFSET,
		91.47
	)
	local detailNoise = math.noise(
		(tileX + SNOW_DETAIL_OFFSET) * (self.biomeFrequency * self.snowDetailFrequencyScale),
		SNOW_DETAIL_OFFSET,
		self.seed * SEED_X_MULTIPLIER
	)

	return math.clamp(
		coreAlpha * 0.76 + featherAlpha * 0.26 + macroNoise * 0.18 + borderNoise * 0.12 + detailNoise * 0.08,
		0,
		1
	)
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
		desertPreferredSideSign = -1,
		desertAnchorDistance = 220,
		desertBandHalfWidth = 150,
		desertHeightOffset = DEFAULT_DESERT_HEIGHT_OFFSET,
		desertDuneAmplitude = DEFAULT_DESERT_DUNE_AMPLITUDE,
		desertDuneFrequency = DEFAULT_DESERT_DUNE_FREQUENCY,
		desertDuneOctaves = DEFAULT_DESERT_DUNE_OCTAVES,
		desertDuneLacunarity = DEFAULT_DESERT_DUNE_LACUNARITY,
		desertDunePersistence = DEFAULT_DESERT_DUNE_PERSISTENCE,
		desertDetailAmplitude = DEFAULT_DESERT_DETAIL_AMPLITUDE,
		desertDetailFrequency = DEFAULT_DESERT_DETAIL_FREQUENCY,
		desertBaseTerrainInfluence = DEFAULT_DESERT_BASE_TERRAIN_INFLUENCE,
		desertStoneDepthOffset = DEFAULT_DESERT_STONE_DEPTH_OFFSET,
		desertSubsurfaceSandDepth = DEFAULT_DESERT_SUBSURFACE_SAND_DEPTH,
		desertSandstoneDepth = DEFAULT_DESERT_SANDSTONE_DEPTH,
		desertSurfaceTileId = tileId.SAND,
		desertFillerTileId = tileId.SAND,
		desertDeepTileId = tileId.SANDSTONE,
		snowPreferredSideSign = 1,
		snowAnchorDistance = 260,
		snowBandHalfWidth = 150,
		snowBandHalfWidthMin = DEFAULT_SNOW_BAND_HALF_WIDTH_MIN,
		snowBandHalfWidthMax = DEFAULT_SNOW_BAND_HALF_WIDTH_MAX,
		snowBandFeatherWidth = DEFAULT_SNOW_BAND_FEATHER_WIDTH,
		snowRegionWeight = DEFAULT_SNOW_REGION_WEIGHT,
		snowTemperatureMax = DEFAULT_SNOW_TEMPERATURE_MAX,
		snowHumidityMax = DEFAULT_SNOW_HUMIDITY_MAX,
		snowRegionThreshold = DEFAULT_SNOW_REGION_THRESHOLD,
		snowAnchorDistanceBase = DEFAULT_SNOW_ANCHOR_DISTANCE_BASE,
		snowAnchorDistanceJitter = DEFAULT_SNOW_ANCHOR_DISTANCE_JITTER,
		snowMacroFrequencyScale = DEFAULT_SNOW_MACRO_FREQUENCY_SCALE,
		snowBorderFrequencyScale = DEFAULT_SNOW_BORDER_FREQUENCY_SCALE,
		snowDetailFrequencyScale = DEFAULT_SNOW_DETAIL_FREQUENCY_SCALE,
		snowHeightOffset = DEFAULT_SNOW_HEIGHT_OFFSET,
		snowSmoothedRidgeScale = DEFAULT_SNOW_SMOOTHED_RIDGE_SCALE,
		snowStoneDepthOffset = DEFAULT_SNOW_STONE_DEPTH_OFFSET,
		snowCapDepth = DEFAULT_SNOW_CAP_DEPTH,
		snowColdSoilDepth = DEFAULT_SNOW_COLD_SOIL_DEPTH,
		snowIceDepthStart = DEFAULT_SNOW_ICE_DEPTH_START,
		snowIceBandThickness = DEFAULT_SNOW_ICE_BAND_THICKNESS,
		snowIceDensity = DEFAULT_SNOW_ICE_DENSITY,
		snowPackedSnowDensity = DEFAULT_SNOW_PACKED_SNOW_DENSITY,
	}, Biome)

	local desertConfig = if typeof((config :: any).desertConfig) == "table" then (config :: any).desertConfig else {}
	local duneConfig = if typeof((desertConfig :: any).Dunes) == "table" then (desertConfig :: any).Dunes else {}
	local desertSurfaceConfig = if typeof((desertConfig :: any).Surface) == "table"
		then (desertConfig :: any).Surface
		else {}
	self.desertHeightOffset = clampNumber(
		duneConfig.HeightOffset,
		-64,
		64,
		DEFAULT_DESERT_HEIGHT_OFFSET
	)
	self.desertDuneAmplitude = clampNumber(
		duneConfig.Amplitude,
		0,
		128,
		DEFAULT_DESERT_DUNE_AMPLITUDE
	)
	self.desertDuneFrequency = clampNumber(
		duneConfig.Frequency,
		0.0001,
		1,
		DEFAULT_DESERT_DUNE_FREQUENCY
	)
	self.desertDuneOctaves = sanitizeOctaveCount(duneConfig.Octaves, DEFAULT_DESERT_DUNE_OCTAVES)
	self.desertDuneLacunarity = clampNumber(
		duneConfig.Lacunarity,
		1,
		4,
		DEFAULT_DESERT_DUNE_LACUNARITY
	)
	self.desertDunePersistence = clampNumber(
		duneConfig.Persistence,
		0.1,
		0.95,
		DEFAULT_DESERT_DUNE_PERSISTENCE
	)
	self.desertDetailAmplitude = clampNumber(
		duneConfig.DetailAmplitude,
		0,
		64,
		DEFAULT_DESERT_DETAIL_AMPLITUDE
	)
	self.desertDetailFrequency = clampNumber(
		duneConfig.DetailFrequency,
		0.0001,
		1,
		DEFAULT_DESERT_DETAIL_FREQUENCY
	)
	self.desertBaseTerrainInfluence = clampNumber(
		duneConfig.BaseTerrainInfluence,
		0,
		1,
		DEFAULT_DESERT_BASE_TERRAIN_INFLUENCE
	)
	self.desertStoneDepthOffset = clampNumber(
		duneConfig.StoneDepthOffset,
		0,
		32,
		DEFAULT_DESERT_STONE_DEPTH_OFFSET
	)
	self.desertSubsurfaceSandDepth = clampNumber(
		desertSurfaceConfig.SubsurfaceSandDepth,
		1,
		64,
		DEFAULT_DESERT_SUBSURFACE_SAND_DEPTH
	)
	self.desertSandstoneDepth = clampNumber(
		desertSurfaceConfig.SandstoneDepth,
		1,
		96,
		DEFAULT_DESERT_SANDSTONE_DEPTH
	)
	self.desertSurfaceTileId =
		resolveTileIdByName(self.tileId, desertSurfaceConfig.SurfaceTile, self.tileId.SAND)
	self.desertFillerTileId =
		resolveTileIdByName(self.tileId, desertSurfaceConfig.FillerTile, self.tileId.SAND)
	self.desertDeepTileId =
		resolveTileIdByName(self.tileId, desertSurfaceConfig.DeepTile, self.tileId.SANDSTONE)

	local snowConfig = if typeof((config :: any).snowConfig) == "table" then (config :: any).snowConfig else {}
	local snowRegionConfig = if typeof((snowConfig :: any).Region) == "table" then (snowConfig :: any).Region else {}
	local snowTerrainConfig = if typeof((snowConfig :: any).Terrain) == "table" then (snowConfig :: any).Terrain else {}
	local snowSurfaceConfig = if typeof((snowConfig :: any).Surface) == "table" then (snowConfig :: any).Surface else {}
	self.snowBandHalfWidthMin = math.floor(clampNumber(
		snowRegionConfig.BandHalfWidthMin,
		32,
		1024,
		DEFAULT_SNOW_BAND_HALF_WIDTH_MIN
	))
	self.snowBandHalfWidthMax = math.floor(clampNumber(
		snowRegionConfig.BandHalfWidthMax,
		self.snowBandHalfWidthMin,
		2048,
		DEFAULT_SNOW_BAND_HALF_WIDTH_MAX
	))
	self.snowBandFeatherWidth = math.floor(clampNumber(
		snowRegionConfig.BandFeatherWidth,
		24,
		512,
		DEFAULT_SNOW_BAND_FEATHER_WIDTH
	))
	self.snowRegionWeight = clampNumber(snowRegionConfig.Weight, 0.1, 4, DEFAULT_SNOW_REGION_WEIGHT)
	self.snowTemperatureMax = clampNumber(
		snowRegionConfig.TemperatureMax,
		-1,
		1,
		DEFAULT_SNOW_TEMPERATURE_MAX
	)
	self.snowHumidityMax = clampNumber(snowRegionConfig.HumidityMax, -1, 1, DEFAULT_SNOW_HUMIDITY_MAX)
	self.snowRegionThreshold = clampNumber(
		snowRegionConfig.PrimaryThreshold,
		0,
		1,
		DEFAULT_SNOW_REGION_THRESHOLD
	)
	self.snowAnchorDistanceBase = clampNumber(
		snowRegionConfig.AnchorDistanceBase,
		32,
		4096,
		DEFAULT_SNOW_ANCHOR_DISTANCE_BASE
	)
	self.snowAnchorDistanceJitter = clampNumber(
		snowRegionConfig.AnchorDistanceJitter,
		0,
		2048,
		DEFAULT_SNOW_ANCHOR_DISTANCE_JITTER
	)
	self.snowMacroFrequencyScale = clampNumber(
		snowRegionConfig.MacroFrequencyScale,
		0.1,
		4,
		DEFAULT_SNOW_MACRO_FREQUENCY_SCALE
	)
	self.snowBorderFrequencyScale = clampNumber(
		snowRegionConfig.BorderFrequencyScale,
		0.1,
		6,
		DEFAULT_SNOW_BORDER_FREQUENCY_SCALE
	)
	self.snowDetailFrequencyScale = clampNumber(
		snowRegionConfig.DetailFrequencyScale,
		0.1,
		8,
		DEFAULT_SNOW_DETAIL_FREQUENCY_SCALE
	)
	self.snowHeightOffset = clampNumber(snowTerrainConfig.HeightOffset, -64, 64, DEFAULT_SNOW_HEIGHT_OFFSET)
	self.snowSmoothedRidgeScale = clampNumber(
		snowTerrainConfig.SmoothedRidgeScale,
		0,
		2,
		DEFAULT_SNOW_SMOOTHED_RIDGE_SCALE
	)
	self.snowStoneDepthOffset = clampNumber(
		snowTerrainConfig.StoneDepthOffset,
		0,
		32,
		DEFAULT_SNOW_STONE_DEPTH_OFFSET
	)
	self.snowCapDepth = math.floor(clampNumber(snowSurfaceConfig.SnowCapDepth, 1, 16, DEFAULT_SNOW_CAP_DEPTH))
	self.snowColdSoilDepth = math.floor(clampNumber(
		snowSurfaceConfig.ColdSoilDepth,
		1,
		32,
		DEFAULT_SNOW_COLD_SOIL_DEPTH
	))
	self.snowIceDepthStart = math.floor(clampNumber(
		snowSurfaceConfig.IceDepthStart,
		1,
		64,
		DEFAULT_SNOW_ICE_DEPTH_START
	))
	self.snowIceBandThickness = math.floor(clampNumber(
		snowSurfaceConfig.IceBandThickness,
		1,
		64,
		DEFAULT_SNOW_ICE_BAND_THICKNESS
	))
	self.snowIceDensity = clampNumber(snowSurfaceConfig.IceDensity, 0, 1, DEFAULT_SNOW_ICE_DENSITY)
	self.snowPackedSnowDensity = clampNumber(
		snowSurfaceConfig.PackedSnowDensity,
		0,
		1,
		DEFAULT_SNOW_PACKED_SNOW_DENSITY
	)

	if self.stoneDepthMax < self.stoneDepthMin then
		self.stoneDepthMax = self.stoneDepthMin
	end

	local preferredSideSign, placementMode, anchorDistance, bandHalfWidth, placementLabel = resolveJunglePlacement(self)
	self.junglePreferredSideSign = preferredSideSign
	self.junglePlacementMode = placementMode
	self.jungleAnchorDistance = anchorDistance
	self.jungleBandHalfWidth = bandHalfWidth
	self.junglePlacementLabel = placementLabel
	local desertPreferredSideSign, desertAnchorDistance, desertBandHalfWidth = resolveDesertPlacement(self)
	self.desertPreferredSideSign = desertPreferredSideSign
	self.desertAnchorDistance = desertAnchorDistance
	self.desertBandHalfWidth = desertBandHalfWidth
	local snowPreferredSideSign, snowAnchorDistance, snowBandHalfWidth = resolveSnowPlacement(self)
	self.snowPreferredSideSign = snowPreferredSideSign
	self.snowAnchorDistance = snowAnchorDistance
	self.snowBandHalfWidth = snowBandHalfWidth

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
	local desertHeatBias = math.max(0, temperature - 0.05) * 0.28
	local desertAridBias = math.max(0, -humidity) * 0.22
	local desertScore = temperature * 1.14 - humidity * 0.38 + desertHeatBias + desertAridBias
	local snowScore = -temperature * 1.05 - humidity * 0.08 + math.max(0, -temperature - 0.02) * 0.22
	local jungleScore = sampleJungleScore(self, tileX, temperature, humidity)
	local forestScore = 1 - math.abs(temperature * 0.6) - math.abs(humidity * 0.35)
	local desertBandWeight = sampleDesertBandWeight(self, tileX)
	if desertBandWeight > 0 then
		desertScore += desertBandWeight * 1.26
		if temperature >= DESERT_TEMPERATURE_MIN and humidity <= DESERT_HUMIDITY_MAX then
			desertScore += 0.18 + desertBandWeight * 0.12
		end
	end

	local jungleBandWeight = sampleJungleBandWeight(self, tileX)
	if humidity >= JUNGLE_HUMIDITY_MIN and jungleBandWeight > 0 then
		local weightedJungleScore = jungleScore + jungleBandWeight * 1.18
		if weightedJungleScore >= JUNGLE_REGION_THRESHOLD then
			return self.biomeId.JUNGLE
		end
	end

	local snowBandWeight = sampleSnowBandWeight(self, tileX)
	if snowBandWeight > 0 then
		snowScore += snowBandWeight * self.snowRegionWeight
		if temperature <= self.snowTemperatureMax and humidity <= self.snowHumidityMax then
			snowScore += 0.16 + snowBandWeight * 0.14
		end
	end

	local selectedBiomeId = self.biomeId.FOREST
	local selectedScore = forestScore

	local qualifiesForBandDesert = desertBandWeight >= DESERT_REGION_THRESHOLD
		and temperature >= DESERT_TEMPERATURE_MIN
		and humidity <= DESERT_HUMIDITY_MAX + 0.08
	if qualifiesForBandDesert or desertScore > selectedScore then
		selectedBiomeId = self.biomeId.DESERT
		selectedScore = desertScore
	end

	local qualifiesForBandSnow = snowBandWeight >= self.snowRegionThreshold
		and temperature <= self.snowTemperatureMax + 0.08
		and humidity <= self.snowHumidityMax + 0.1
	if qualifiesForBandSnow or snowScore > selectedScore then
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

	if biomeId == self.biomeId.DESERT then
		local smoothedRidgeScale = 0.42
		local height = self.surfaceBaseHeight
			+ terrainWave * self.surfaceAmplitude
			+ ridgeWave * self.ridgeAmplitude * smoothedRidgeScale
		return math.floor(height)
	end

	if biomeId == self.biomeId.SNOW then
		local height = self.surfaceBaseHeight
			+ terrainWave * self.surfaceAmplitude
			+ ridgeWave * self.ridgeAmplitude * self.snowSmoothedRidgeScale
		return math.floor(height + self.snowHeightOffset)
	end

	local biomeHeightOffset = 0
	if biomeId == self.biomeId.JUNGLE then
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
		depth += self.desertStoneDepthOffset
	elseif biomeId == self.biomeId.SNOW then
		depth += self.snowStoneDepthOffset
	end
	return math.max(1, math.floor(depth))
end

function Biome.getColumnProfile(self, tileX: number): ColumnProfile
	local temperature, humidity = self:sampleTemperatureHumidity(tileX)
	local biomeId = self:resolveBiomeId(tileX, temperature, humidity)
	local surfaceY = self:sampleSurfaceHeight(tileX, biomeId)
	local biomeType = self:resolveBiomeType(tileX, surfaceY, biomeId)
	local stoneStartDepth = self:sampleStoneStartDepth(tileX, biomeId)
	local snowDetailNoise = sampleOctaveNoise(
		self.seed + 4129,
		tileX,
		self.biomeFrequency * self.snowDetailFrequencyScale,
		2,
		2,
		0.56,
		SNOW_DETAIL_OFFSET,
		47.23
	)
	local snowIceNoise = sampleOctaveNoise(
		self.seed + 4517,
		tileX,
		self.biomeFrequency * (self.snowDetailFrequencyScale + 0.37),
		3,
		2,
		0.52,
		SNOW_ICE_OFFSET,
		63.77
	)
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
		snowDetailNoise = snowDetailNoise,
		snowIceNoise = snowIceNoise,
	}
end

function Biome.resolveTileForDepth(self, column: ColumnProfile, depthBelowSurface: number): number
	if depthBelowSurface < 0 then
		return self.tileId.AIR
	end

	if depthBelowSurface == 0 then
		return column.topTileId
	end

	if column.biomeType == self.biomeType.CORRUPTION then
		if depthBelowSurface < column.stoneStartDepth + 4 then
			return self.tileId.CORRUPT_SOIL
		end
		return self.tileId.CORRUPT_STONE
	end

	if column.biomeId == self.biomeId.JUNGLE and depthBelowSurface < column.stoneStartDepth + 7 then
		return self.tileId.MUD
	end

	if column.biomeId == self.biomeId.DESERT then
		local sandDepthLimit = math.max(column.stoneStartDepth, self.desertSubsurfaceSandDepth)
		if depthBelowSurface < sandDepthLimit then
			return self.desertFillerTileId
		end
		if depthBelowSurface < sandDepthLimit + self.desertSandstoneDepth then
			return self.desertDeepTileId
		end
		return self.desertDeepTileId
	end

	if column.biomeId == self.biomeId.SNOW then
		if depthBelowSurface <= self.snowCapDepth then
			return self.tileId.SNOW
		end

		local coldSoilDepthLimit = math.max(
			self.snowCapDepth + 1,
			math.min(column.stoneStartDepth, self.snowColdSoilDepth)
		)
		if depthBelowSurface < coldSoilDepthLimit then
			if column.snowDetailNoise >= self.snowPackedSnowDensity then
				return self.tileId.SNOW
			end
			if depthBelowSurface >= math.max(2, coldSoilDepthLimit - 2) and column.snowIceNoise >= self.snowIceDensity + 0.14 then
				return self.tileId.ICE
			end
			return self.tileId.DIRT
		end

		local iceDepthStart = math.max(column.stoneStartDepth, self.snowIceDepthStart)
		if depthBelowSurface >= iceDepthStart then
			local iceDepthAlpha = math.clamp(
				(depthBelowSurface - iceDepthStart) / math.max(1, self.snowIceBandThickness),
				0,
				1
			)
			local iceThreshold = self.snowIceDensity - iceDepthAlpha * 0.18
			if column.snowIceNoise >= iceThreshold then
				return self.tileId.ICE
			end
			if iceDepthAlpha < 0.45 and column.snowDetailNoise >= self.snowPackedSnowDensity then
				return self.tileId.SNOW
			end
		end

		return self.tileId.STONE
	end

	if depthBelowSurface < column.stoneStartDepth then
		return column.subsurfaceTileId
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
		desertPreferredSideSign: number,
		desertAnchorDistance: number,
		desertBandHalfWidth: number,
		desertHeightOffset: number,
		desertDuneAmplitude: number,
		desertDuneFrequency: number,
		desertDuneOctaves: number,
		desertDuneLacunarity: number,
		desertDunePersistence: number,
		desertDetailAmplitude: number,
		desertDetailFrequency: number,
		desertBaseTerrainInfluence: number,
		desertStoneDepthOffset: number,
		desertSubsurfaceSandDepth: number,
		desertSandstoneDepth: number,
		desertSurfaceTileId: number,
		desertFillerTileId: number,
		desertDeepTileId: number,
		snowPreferredSideSign: number,
		snowAnchorDistance: number,
		snowBandHalfWidth: number,
		snowBandHalfWidthMin: number,
		snowBandHalfWidthMax: number,
		snowBandFeatherWidth: number,
		snowRegionWeight: number,
		snowTemperatureMax: number,
		snowHumidityMax: number,
		snowRegionThreshold: number,
		snowAnchorDistanceBase: number,
		snowAnchorDistanceJitter: number,
		snowMacroFrequencyScale: number,
		snowBorderFrequencyScale: number,
		snowDetailFrequencyScale: number,
		snowHeightOffset: number,
		snowSmoothedRidgeScale: number,
		snowStoneDepthOffset: number,
		snowCapDepth: number,
		snowColdSoilDepth: number,
		snowIceDepthStart: number,
		snowIceBandThickness: number,
		snowIceDensity: number,
		snowPackedSnowDensity: number,
	},
	Biome
))

return Biome
