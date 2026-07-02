
local require = require(script.Parent.loader).load(script)

local BiomeConstants = require("BiomeConstants")
local Noise = require("Noise")

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

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw :: number, minimum, maximum)
end

local function CoerceOctaveCount(valueRaw: any, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw :: number), 1, 8)
end

local function GetTileIdByName(tileIdMap: TileIdMap, nameRaw: any, fallback: number): number
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
	return Noise.FbmOctaves(octaves, persistence, lacunarity, function(octave, frequency)
		local sampleFrequency = baseFrequency * frequency
		return math.noise(
			(x + offsetX + octave * 0.73) * sampleFrequency,
			offsetY + octave * 3.11 + seed * BiomeConstants.SEED_Y_MULTIPLIER,
			seed * BiomeConstants.SEED_X_MULTIPLIER + octave * 0.17
		)
	end)
end

local function sampleOctaveNoise3D(
	seed: number,
	x: number,
	z: number,
	baseFrequency: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	offsetX: number,
	offsetZ: number
): number
	return Noise.FbmOctaves(octaves, persistence, lacunarity, function(octave, frequency)
		local sampleFrequency = baseFrequency * frequency
		return math.noise(
			(x + offsetX + octave * 0.73) * sampleFrequency,
			(z + offsetZ + octave * 0.41) * sampleFrequency,
			seed * BiomeConstants.SEED_X_MULTIPLIER + octave * 0.17
		)
	end)
end

local function GetDepthNoiseSample(surfaceDepthRaw: number?, scale: number): (boolean, number)
	local unscaledSurfaceDepth = if isFiniteNumber(surfaceDepthRaw) then surfaceDepthRaw :: number else 0
	return math.abs(unscaledSurfaceDepth) > 0.0001, unscaledSurfaceDepth * scale
end

local function sampleDepthAwareOctaveNoise(
	seed: number,
	tileX: number,
	surfaceDepthRaw: number?,
	depthScale: number,
	baseFrequency: number,
	octaves: number,
	lacunarity: number,
	persistence: number,
	offsetX: number,
	offsetY: number,
	offsetZ: number
): number
	local useDepthNoise, surfaceDepth = GetDepthNoiseSample(surfaceDepthRaw, depthScale)
	if useDepthNoise then
		return sampleOctaveNoise3D(
			seed,
			tileX,
			surfaceDepth,
			baseFrequency,
			octaves,
			lacunarity,
			persistence,
			offsetX,
			offsetZ
		)
	end

	return sampleOctaveNoise(seed, tileX, baseFrequency, octaves, lacunarity, persistence, offsetX, offsetY)
end

local function GetBiomeSurfaceTiles(self: Biome, biomeId: number, biomeType: number): (number, number, number)
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

local function sampleCorruptionScore(self: Biome, tileX: number, surfaceY: number, surfaceDepthRaw: number?): number
	local primaryNoise = sampleDepthAwareOctaveNoise(
		self.seed + 971,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.corruptionFrequency,
		self.corruptionOctaves,
		self.corruptionLacunarity,
		self.corruptionPersistence,
		BiomeConstants.CORRUPTION_PRIMARY_OFFSET,
		37.21,
		BiomeConstants.CORRUPTION_PRIMARY_OFFSET + 209.47
	)
	local secondaryNoise = sampleDepthAwareOctaveNoise(
		self.seed - 563,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.corruptionFrequency * 0.48,
		2,
		2,
		0.5,
		BiomeConstants.CORRUPTION_SECONDARY_OFFSET,
		81.37,
		BiomeConstants.CORRUPTION_SECONDARY_OFFSET + 187.83
	)
	local _, surfaceDepth = GetDepthNoiseSample(surfaceDepthRaw, BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE)
	local detailNoise = math.noise(
		(tileX + BiomeConstants.CORRUPTION_DETAIL_OFFSET_X) * (self.corruptionFrequency * 1.33),
		(surfaceY + BiomeConstants.CORRUPTION_DETAIL_OFFSET_Y) * 0.016,
		surfaceDepth * 0.019 + self.seed * BiomeConstants.SEED_X_MULTIPLIER
	)
	local distanceBias =
		math.clamp(math.max(0, math.abs(tileX) - self.corruptionRadiusStart) * self.corruptionDistanceScale, 0, 0.52)

	return primaryNoise * 0.58 + secondaryNoise * 0.24 + detailNoise * 0.18 + distanceBias
end

local function sampleJungleScore(
	self: Biome,
	tileX: number,
	temperature: number,
	humidity: number,
	surfaceDepthRaw: number?
): number
	local jungleBandNoise = sampleDepthAwareOctaveNoise(
		self.seed + 1873,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.biomeFrequency * 0.92,
		math.max(2, self.biomeOctaves - 1),
		self.biomeLacunarity,
		self.biomePersistence,
		BiomeConstants.JUNGLE_PRIMARY_OFFSET,
		129.53,
		BiomeConstants.JUNGLE_PRIMARY_OFFSET + 233.19
	)
	local _, surfaceDepth = GetDepthNoiseSample(surfaceDepthRaw, BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE)
	local jungleDetailNoise = math.noise(
		(tileX + BiomeConstants.JUNGLE_DETAIL_OFFSET_X) * (self.biomeFrequency * 1.41),
		BiomeConstants.JUNGLE_DETAIL_OFFSET_Y + surfaceDepth * 0.021,
		self.seed * BiomeConstants.SEED_X_MULTIPLIER
	)
	local humidityScore = humidity * 0.42
	local warmthScore = temperature * 0.08
	local jungleBandScore = jungleBandNoise * 0.74
	local detailScore = jungleDetailNoise * 0.26

	return humidityScore + warmthScore + jungleBandScore + detailScore
end

local function GetJunglePlacement(self: Biome): (number, number, number, number, string)
	local sideNoise =
		math.noise(self.seed * BiomeConstants.SEED_X_MULTIPLIER + BiomeConstants.JUNGLE_SIDE_OFFSET, 19.37, 71.19)
	local preferredSideSign = if sideNoise >= 0 then 1 else -1

	local modeNoise =
		math.noise(self.seed * BiomeConstants.SEED_Y_MULTIPLIER + BiomeConstants.JUNGLE_MODE_OFFSET, 43.21, 12.08)
	local placementMode = if modeNoise >= 0 then 2 else 1

	local anchorNoise = math.noise(self.seed * 0.001173 + BiomeConstants.JUNGLE_ANCHOR_OFFSET, 0, 0)
	local widthNoise = math.noise(self.seed * 0.001571 + BiomeConstants.JUNGLE_ANCHOR_OFFSET + 33.7, 0, 0)

	local bandHalfWidth = math.floor(
		math.clamp(
			BiomeConstants.JUNGLE_BAND_HALF_WIDTH_MIN
				+ (widthNoise + 1)
					* 0.5
					* (BiomeConstants.JUNGLE_BAND_HALF_WIDTH_MAX - BiomeConstants.JUNGLE_BAND_HALF_WIDTH_MIN),
			BiomeConstants.JUNGLE_BAND_HALF_WIDTH_MIN,
			BiomeConstants.JUNGLE_BAND_HALF_WIDTH_MAX
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

local function sampleJungleBandWeight(self: Biome, tileX: number, surfaceDepthRaw: number?): number
	if tileX * self.junglePreferredSideSign <= 0 then
		return 0
	end

	local useDepthNoise, surfaceDepth =
		GetDepthNoiseSample(surfaceDepthRaw, BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE)
	local sideDistance = math.abs(tileX)
	local anchorWarp = if useDepthNoise
		then math.noise(
			(tileX + BiomeConstants.JUNGLE_ANCHOR_OFFSET) * (self.biomeFrequency * 0.72),
			(surfaceDepth + BiomeConstants.JUNGLE_MODE_OFFSET) * (self.biomeFrequency * 0.72),
			self.seed * BiomeConstants.SEED_X_MULTIPLIER
		) * BiomeConstants.JUNGLE_BAND_FEATHER_WIDTH * 0.45
		else 0
	local distanceFromAnchor = math.abs(sideDistance - (self.jungleAnchorDistance + anchorWarp))
	local fullWidth = self.jungleBandHalfWidth + BiomeConstants.JUNGLE_BAND_FEATHER_WIDTH
	if distanceFromAnchor > fullWidth then
		return 0
	end

	local coreAlpha = 1 - math.clamp(distanceFromAnchor / self.jungleBandHalfWidth, 0, 1)
	local featherAlpha = 1
		- math.clamp((distanceFromAnchor - self.jungleBandHalfWidth) / BiomeConstants.JUNGLE_BAND_FEATHER_WIDTH, 0, 1)

	local bandNoise = sampleDepthAwareOctaveNoise(
		self.seed + 2441,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.biomeFrequency * 1.21,
		2,
		2,
		0.5,
		BiomeConstants.JUNGLE_BAND_NOISE_OFFSET,
		57.37,
		BiomeConstants.JUNGLE_BAND_NOISE_OFFSET + 271.43
	)

	return math.clamp(coreAlpha * 0.78 + featherAlpha * 0.34 + bandNoise * 0.19, 0, 1)
end

local function GetDesertPlacement(self: Biome): (number, number, number)
	local preferredSideSign = -self.junglePreferredSideSign
	if preferredSideSign == 0 then
		local sideNoise =
			math.noise(self.seed * BiomeConstants.SEED_X_MULTIPLIER + BiomeConstants.DESERT_SIDE_OFFSET, 57.81, 21.17)
		preferredSideSign = if sideNoise >= 0 then 1 else -1
	end

	local anchorNoise = math.noise(self.seed * 0.001391 + BiomeConstants.DESERT_ANCHOR_OFFSET, 0, 0)
	local widthNoise = math.noise(self.seed * 0.001713 + BiomeConstants.DESERT_ANCHOR_OFFSET + 41.3, 0, 0)
	local bandHalfWidth = math.floor(
		math.clamp(
			BiomeConstants.DESERT_BAND_HALF_WIDTH_MIN
				+ (widthNoise + 1)
					* 0.5
					* (BiomeConstants.DESERT_BAND_HALF_WIDTH_MAX - BiomeConstants.DESERT_BAND_HALF_WIDTH_MIN),
			BiomeConstants.DESERT_BAND_HALF_WIDTH_MIN,
			BiomeConstants.DESERT_BAND_HALF_WIDTH_MAX
		)
	)

	local baseDistance = self.corruptionRadiusStart * 0.44 + 105
	local jitter = anchorNoise * 88
	local anchorDistance = math.floor(math.max(110, baseDistance + jitter))

	return preferredSideSign, anchorDistance, bandHalfWidth
end

local function sampleDesertBandWeight(self: Biome, tileX: number, surfaceDepthRaw: number?): number
	if tileX * self.desertPreferredSideSign <= 0 then
		return 0
	end

	local useDepthNoise, surfaceDepth =
		GetDepthNoiseSample(surfaceDepthRaw, BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE)
	local sideDistance = math.abs(tileX)
	local anchorWarp = if useDepthNoise
		then math.noise(
			(tileX + BiomeConstants.DESERT_ANCHOR_OFFSET) * (self.biomeFrequency * 0.68),
			(surfaceDepth + BiomeConstants.DESERT_SIDE_OFFSET) * (self.biomeFrequency * 0.68),
			self.seed * BiomeConstants.SEED_X_MULTIPLIER
		) * BiomeConstants.DESERT_BAND_FEATHER_WIDTH * 0.42
		else 0
	local distanceFromAnchor = math.abs(sideDistance - (self.desertAnchorDistance + anchorWarp))
	local fullWidth = self.desertBandHalfWidth + BiomeConstants.DESERT_BAND_FEATHER_WIDTH
	if distanceFromAnchor > fullWidth then
		return 0
	end

	local coreAlpha = 1 - math.clamp(distanceFromAnchor / self.desertBandHalfWidth, 0, 1)
	local featherAlpha = 1
		- math.clamp((distanceFromAnchor - self.desertBandHalfWidth) / BiomeConstants.DESERT_BAND_FEATHER_WIDTH, 0, 1)

	local bandNoise = sampleDepthAwareOctaveNoise(
		self.seed + 3181,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.biomeFrequency * 1.06,
		math.max(2, self.biomeOctaves - 1),
		self.biomeLacunarity,
		self.biomePersistence,
		BiomeConstants.DESERT_BAND_NOISE_OFFSET,
		63.19,
		BiomeConstants.DESERT_BAND_NOISE_OFFSET + 241.17
	)

	return math.clamp(coreAlpha * 0.84 + featherAlpha * 0.28 + bandNoise * 0.16, 0, 1)
end

local function GetSnowPlacement(self: Biome): (number, number, number)
	local preferredSideSign = self.junglePreferredSideSign
	if preferredSideSign == 0 then
		local sideNoise =
			math.noise(self.seed * BiomeConstants.SEED_X_MULTIPLIER + BiomeConstants.SNOW_SIDE_OFFSET, 61.53, 37.91)
		preferredSideSign = if sideNoise >= 0 then 1 else -1
	end

	local anchorNoise = math.noise(self.seed * 0.001913 + BiomeConstants.SNOW_ANCHOR_OFFSET, 0, 0)
	local widthNoise = math.noise(self.seed * 0.002173 + BiomeConstants.SNOW_ANCHOR_OFFSET + 27.4, 0, 0)
	local bandHalfWidth = math.floor(
		math.clamp(
			self.snowBandHalfWidthMin + (widthNoise + 1) * 0.5 * (self.snowBandHalfWidthMax - self.snowBandHalfWidthMin),
			self.snowBandHalfWidthMin,
			self.snowBandHalfWidthMax
		)
	)

	local baseDistance = self.corruptionRadiusStart * 0.52 + self.snowAnchorDistanceBase
	local jitter = anchorNoise * self.snowAnchorDistanceJitter
	local anchorDistance = math.floor(math.max(130, baseDistance + jitter))

	return preferredSideSign, anchorDistance, bandHalfWidth
end

local function sampleSnowBandWeight(self: Biome, tileX: number, surfaceDepthRaw: number?): number
	if tileX * self.snowPreferredSideSign <= 0 then
		return 0
	end

	local useDepthNoise, surfaceDepth =
		GetDepthNoiseSample(surfaceDepthRaw, BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE)
	local sideDistance = math.abs(tileX)
	local anchorWarp = if useDepthNoise
		then math.noise(
			(tileX + BiomeConstants.SNOW_ANCHOR_OFFSET) * (self.biomeFrequency * 0.7),
			(surfaceDepth + BiomeConstants.SNOW_SIDE_OFFSET) * (self.biomeFrequency * 0.7),
			self.seed * BiomeConstants.SEED_X_MULTIPLIER
		) * self.snowBandFeatherWidth * 0.44
		else 0
	local distanceFromAnchor = math.abs(sideDistance - (self.snowAnchorDistance + anchorWarp))
	local fullWidth = self.snowBandHalfWidth + self.snowBandFeatherWidth
	if distanceFromAnchor > fullWidth then
		return 0
	end

	local coreAlpha = 1 - math.clamp(distanceFromAnchor / self.snowBandHalfWidth, 0, 1)
	local featherAlpha = 1 - math.clamp((distanceFromAnchor - self.snowBandHalfWidth) / self.snowBandFeatherWidth, 0, 1)

	local macroNoise = sampleDepthAwareOctaveNoise(
		self.seed + 3511,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.biomeFrequency * self.snowMacroFrequencyScale,
		math.max(2, self.biomeOctaves - 1),
		self.biomeLacunarity,
		self.biomePersistence,
		BiomeConstants.SNOW_BAND_MACRO_OFFSET,
		73.11,
		BiomeConstants.SNOW_BAND_MACRO_OFFSET + 219.81
	)
	local borderNoise = sampleDepthAwareOctaveNoise(
		self.seed + 3791,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.biomeFrequency * self.snowBorderFrequencyScale,
		2,
		2,
		0.52,
		BiomeConstants.SNOW_BAND_BORDER_OFFSET,
		91.47,
		BiomeConstants.SNOW_BAND_BORDER_OFFSET + 191.67
	)
	local detailNoise = math.noise(
		(tileX + BiomeConstants.SNOW_DETAIL_OFFSET) * (self.biomeFrequency * self.snowDetailFrequencyScale),
		BiomeConstants.SNOW_DETAIL_OFFSET + surfaceDepth * 0.023,
		self.seed * BiomeConstants.SEED_X_MULTIPLIER
	)

	return math.clamp(
		coreAlpha * 0.76 + featherAlpha * 0.26 + macroNoise * 0.18 + borderNoise * 0.12 + detailNoise * 0.08,
		0,
		1
	)
end

function Biome.New(configRaw: any): Biome
	local config = if typeof(configRaw) == "table" then configRaw else {} :: any
	local tileId = (config :: any).tileId :: TileIdMap
	local biomeId = (config :: any).biomeId :: BiomeIdMap
	local biomeType = if typeof((config :: any).biomeType) == "table"
		then (config :: any).biomeType :: BiomeTypeMap
		else BiomeConstants.DEFAULT_BIOME_TYPE

	local self = setmetatable({
		seed = clampNumber((config :: any).seed, -2147483648, 2147483647, 13371337),
		tileId = tileId,
		biomeId = biomeId,
		biomeType = biomeType,
		surfaceBaseHeight = clampNumber(
			(config :: any).surfaceBaseHeight,
			-1024,
			1024,
			BiomeConstants.DEFAULT_SURFACE_BASE_HEIGHT
		),
		surfaceAmplitude = clampNumber(
			(config :: any).surfaceAmplitude,
			0,
			512,
			BiomeConstants.DEFAULT_SURFACE_AMPLITUDE
		),
		surfaceFrequency = clampNumber(
			(config :: any).surfaceFrequency,
			0.0001,
			1,
			BiomeConstants.DEFAULT_SURFACE_FREQUENCY
		),
		surfaceOctaves = CoerceOctaveCount((config :: any).surfaceOctaves, BiomeConstants.DEFAULT_SURFACE_OCTAVES),
		surfaceLacunarity = clampNumber(
			(config :: any).surfaceLacunarity,
			1,
			4,
			BiomeConstants.DEFAULT_SURFACE_LACUNARITY
		),
		surfacePersistence = clampNumber(
			(config :: any).surfacePersistence,
			0.1,
			0.95,
			BiomeConstants.DEFAULT_SURFACE_PERSISTENCE
		),
		ridgeFrequency = clampNumber((config :: any).ridgeFrequency, 0.0001, 1, BiomeConstants.DEFAULT_RIDGE_FREQUENCY),
		ridgeAmplitude = clampNumber((config :: any).ridgeAmplitude, 0, 512, BiomeConstants.DEFAULT_RIDGE_AMPLITUDE),
		biomeFrequency = clampNumber((config :: any).biomeFrequency, 0.0001, 1, BiomeConstants.DEFAULT_BIOME_FREQUENCY),
		biomeOctaves = CoerceOctaveCount((config :: any).biomeOctaves, BiomeConstants.DEFAULT_BIOME_OCTAVES),
		biomeLacunarity = clampNumber((config :: any).biomeLacunarity, 1, 4, BiomeConstants.DEFAULT_BIOME_LACUNARITY),
		biomePersistence = clampNumber(
			(config :: any).biomePersistence,
			0.1,
			0.95,
			BiomeConstants.DEFAULT_BIOME_PERSISTENCE
		),
		stoneDepthMin = math.floor(
			clampNumber((config :: any).stoneDepthMin, 1, 64, BiomeConstants.DEFAULT_STONE_DEPTH_MIN)
		),
		stoneDepthMax = math.floor(
			clampNumber((config :: any).stoneDepthMax, 2, 128, BiomeConstants.DEFAULT_STONE_DEPTH_MAX)
		),
		corruptionFrequency = clampNumber(
			(config :: any).corruptionFrequency,
			0.0001,
			0.5,
			BiomeConstants.DEFAULT_CORRUPTION_FREQUENCY
		),
		corruptionOctaves = CoerceOctaveCount(
			(config :: any).corruptionOctaves,
			BiomeConstants.DEFAULT_CORRUPTION_OCTAVES
		),
		corruptionLacunarity = clampNumber(
			(config :: any).corruptionLacunarity,
			1,
			4,
			BiomeConstants.DEFAULT_CORRUPTION_LACUNARITY
		),
		corruptionPersistence = clampNumber(
			(config :: any).corruptionPersistence,
			0.1,
			0.95,
			BiomeConstants.DEFAULT_CORRUPTION_PERSISTENCE
		),
		corruptionThreshold = clampNumber(
			(config :: any).corruptionThreshold,
			-1,
			1,
			BiomeConstants.DEFAULT_CORRUPTION_THRESHOLD
		),
		corruptionRadiusStart = clampNumber(
			(config :: any).corruptionRadiusStart,
			0,
			100000,
			BiomeConstants.DEFAULT_CORRUPTION_RADIUS_START
		),
		corruptionDistanceScale = clampNumber(
			(config :: any).corruptionDistanceScale,
			0,
			0.02,
			BiomeConstants.DEFAULT_CORRUPTION_DISTANCE_SCALE
		),
		junglePreferredSideSign = 1,
		junglePlacementMode = 1,
		jungleAnchorDistance = 180,
		jungleBandHalfWidth = 140,
		junglePlacementLabel = "FarFromCorruption",
		desertPreferredSideSign = -1,
		desertAnchorDistance = 220,
		desertBandHalfWidth = 150,
		desertHeightOffset = BiomeConstants.DEFAULT_DESERT_HEIGHT_OFFSET,
		desertDuneAmplitude = BiomeConstants.DEFAULT_DESERT_DUNE_AMPLITUDE,
		desertDuneFrequency = BiomeConstants.DEFAULT_DESERT_DUNE_FREQUENCY,
		desertDuneOctaves = BiomeConstants.DEFAULT_DESERT_DUNE_OCTAVES,
		desertDuneLacunarity = BiomeConstants.DEFAULT_DESERT_DUNE_LACUNARITY,
		desertDunePersistence = BiomeConstants.DEFAULT_DESERT_DUNE_PERSISTENCE,
		desertDetailAmplitude = BiomeConstants.DEFAULT_DESERT_DETAIL_AMPLITUDE,
		desertDetailFrequency = BiomeConstants.DEFAULT_DESERT_DETAIL_FREQUENCY,
		desertBaseTerrainInfluence = BiomeConstants.DEFAULT_DESERT_BASE_TERRAIN_INFLUENCE,
		desertStoneDepthOffset = BiomeConstants.DEFAULT_DESERT_STONE_DEPTH_OFFSET,
		desertSubsurfaceSandDepth = BiomeConstants.DEFAULT_DESERT_SUBSURFACE_SAND_DEPTH,
		desertSandstoneDepth = BiomeConstants.DEFAULT_DESERT_SANDSTONE_DEPTH,
		desertSurfaceTileId = tileId.SAND,
		desertFillerTileId = tileId.SAND,
		desertDeepTileId = tileId.SANDSTONE,
		snowPreferredSideSign = 1,
		snowAnchorDistance = 260,
		snowBandHalfWidth = 150,
		snowBandHalfWidthMin = BiomeConstants.DEFAULT_SNOW_BAND_HALF_WIDTH_MIN,
		snowBandHalfWidthMax = BiomeConstants.DEFAULT_SNOW_BAND_HALF_WIDTH_MAX,
		snowBandFeatherWidth = BiomeConstants.DEFAULT_SNOW_BAND_FEATHER_WIDTH,
		snowRegionWeight = BiomeConstants.DEFAULT_SNOW_REGION_WEIGHT,
		snowTemperatureMax = BiomeConstants.DEFAULT_SNOW_TEMPERATURE_MAX,
		snowHumidityMax = BiomeConstants.DEFAULT_SNOW_HUMIDITY_MAX,
		snowRegionThreshold = BiomeConstants.DEFAULT_SNOW_REGION_THRESHOLD,
		snowAnchorDistanceBase = BiomeConstants.DEFAULT_SNOW_ANCHOR_DISTANCE_BASE,
		snowAnchorDistanceJitter = BiomeConstants.DEFAULT_SNOW_ANCHOR_DISTANCE_JITTER,
		snowMacroFrequencyScale = BiomeConstants.DEFAULT_SNOW_MACRO_FREQUENCY_SCALE,
		snowBorderFrequencyScale = BiomeConstants.DEFAULT_SNOW_BORDER_FREQUENCY_SCALE,
		snowDetailFrequencyScale = BiomeConstants.DEFAULT_SNOW_DETAIL_FREQUENCY_SCALE,
		snowHeightOffset = BiomeConstants.DEFAULT_SNOW_HEIGHT_OFFSET,
		snowSmoothedRidgeScale = BiomeConstants.DEFAULT_SNOW_SMOOTHED_RIDGE_SCALE,
		snowStoneDepthOffset = BiomeConstants.DEFAULT_SNOW_STONE_DEPTH_OFFSET,
		snowCapDepth = BiomeConstants.DEFAULT_SNOW_CAP_DEPTH,
		snowColdSoilDepth = BiomeConstants.DEFAULT_SNOW_COLD_SOIL_DEPTH,
		snowIceDepthStart = BiomeConstants.DEFAULT_SNOW_ICE_DEPTH_START,
		snowIceBandThickness = BiomeConstants.DEFAULT_SNOW_ICE_BAND_THICKNESS,
		snowIceDensity = BiomeConstants.DEFAULT_SNOW_ICE_DENSITY,
		snowPackedSnowDensity = BiomeConstants.DEFAULT_SNOW_PACKED_SNOW_DENSITY,
	}, Biome)

	local desertConfig = if typeof((config :: any).desertConfig) == "table"
		then (config :: any).desertConfig
		else {} :: any
	local duneConfig = if typeof((desertConfig :: any).Dunes) == "table" then (desertConfig :: any).Dunes else {} :: any
	local desertSurfaceConfig = if typeof((desertConfig :: any).Surface) == "table"
		then (desertConfig :: any).Surface
		else {} :: any
	self.desertHeightOffset = clampNumber(duneConfig.HeightOffset, -64, 64, BiomeConstants.DEFAULT_DESERT_HEIGHT_OFFSET)
	self.desertDuneAmplitude = clampNumber(duneConfig.Amplitude, 0, 128, BiomeConstants.DEFAULT_DESERT_DUNE_AMPLITUDE)
	self.desertDuneFrequency =
		clampNumber(duneConfig.Frequency, 0.0001, 1, BiomeConstants.DEFAULT_DESERT_DUNE_FREQUENCY)
	self.desertDuneOctaves = CoerceOctaveCount(duneConfig.Octaves, BiomeConstants.DEFAULT_DESERT_DUNE_OCTAVES)
	self.desertDuneLacunarity = clampNumber(duneConfig.Lacunarity, 1, 4, BiomeConstants.DEFAULT_DESERT_DUNE_LACUNARITY)
	self.desertDunePersistence =
		clampNumber(duneConfig.Persistence, 0.1, 0.95, BiomeConstants.DEFAULT_DESERT_DUNE_PERSISTENCE)
	self.desertDetailAmplitude =
		clampNumber(duneConfig.DetailAmplitude, 0, 64, BiomeConstants.DEFAULT_DESERT_DETAIL_AMPLITUDE)
	self.desertDetailFrequency =
		clampNumber(duneConfig.DetailFrequency, 0.0001, 1, BiomeConstants.DEFAULT_DESERT_DETAIL_FREQUENCY)
	self.desertBaseTerrainInfluence =
		clampNumber(duneConfig.BaseTerrainInfluence, 0, 1, BiomeConstants.DEFAULT_DESERT_BASE_TERRAIN_INFLUENCE)
	self.desertStoneDepthOffset =
		clampNumber(duneConfig.StoneDepthOffset, 0, 32, BiomeConstants.DEFAULT_DESERT_STONE_DEPTH_OFFSET)
	self.desertSubsurfaceSandDepth =
		clampNumber(desertSurfaceConfig.SubsurfaceSandDepth, 1, 64, BiomeConstants.DEFAULT_DESERT_SUBSURFACE_SAND_DEPTH)
	self.desertSandstoneDepth =
		clampNumber(desertSurfaceConfig.SandstoneDepth, 1, 96, BiomeConstants.DEFAULT_DESERT_SANDSTONE_DEPTH)
	self.desertSurfaceTileId = GetTileIdByName(self.tileId, desertSurfaceConfig.SurfaceTile, self.tileId.SAND)
	self.desertFillerTileId = GetTileIdByName(self.tileId, desertSurfaceConfig.FillerTile, self.tileId.SAND)
	self.desertDeepTileId = GetTileIdByName(self.tileId, desertSurfaceConfig.DeepTile, self.tileId.SANDSTONE)

	local snowConfig = if typeof((config :: any).snowConfig) == "table" then (config :: any).snowConfig else {} :: any
	local snowRegionConfig = if typeof((snowConfig :: any).Region) == "table"
		then (snowConfig :: any).Region
		else {} :: any
	local snowTerrainConfig = if typeof((snowConfig :: any).Terrain) == "table"
		then (snowConfig :: any).Terrain
		else {} :: any
	local snowSurfaceConfig = if typeof((snowConfig :: any).Surface) == "table"
		then (snowConfig :: any).Surface
		else {} :: any
	self.snowBandHalfWidthMin = math.floor(
		clampNumber(snowRegionConfig.BandHalfWidthMin, 32, 1024, BiomeConstants.DEFAULT_SNOW_BAND_HALF_WIDTH_MIN)
	)
	self.snowBandHalfWidthMax = math.floor(
		clampNumber(
			snowRegionConfig.BandHalfWidthMax,
			self.snowBandHalfWidthMin,
			2048,
			BiomeConstants.DEFAULT_SNOW_BAND_HALF_WIDTH_MAX
		)
	)
	self.snowBandFeatherWidth = math.floor(
		clampNumber(snowRegionConfig.BandFeatherWidth, 24, 512, BiomeConstants.DEFAULT_SNOW_BAND_FEATHER_WIDTH)
	)
	self.snowRegionWeight = clampNumber(snowRegionConfig.Weight, 0.1, 4, BiomeConstants.DEFAULT_SNOW_REGION_WEIGHT)
	self.snowTemperatureMax =
		clampNumber(snowRegionConfig.TemperatureMax, -1, 1, BiomeConstants.DEFAULT_SNOW_TEMPERATURE_MAX)
	self.snowHumidityMax = clampNumber(snowRegionConfig.HumidityMax, -1, 1, BiomeConstants.DEFAULT_SNOW_HUMIDITY_MAX)
	self.snowRegionThreshold =
		clampNumber(snowRegionConfig.PrimaryThreshold, 0, 1, BiomeConstants.DEFAULT_SNOW_REGION_THRESHOLD)
	self.snowAnchorDistanceBase =
		clampNumber(snowRegionConfig.AnchorDistanceBase, 32, 4096, BiomeConstants.DEFAULT_SNOW_ANCHOR_DISTANCE_BASE)
	self.snowAnchorDistanceJitter =
		clampNumber(snowRegionConfig.AnchorDistanceJitter, 0, 2048, BiomeConstants.DEFAULT_SNOW_ANCHOR_DISTANCE_JITTER)
	self.snowMacroFrequencyScale =
		clampNumber(snowRegionConfig.MacroFrequencyScale, 0.1, 4, BiomeConstants.DEFAULT_SNOW_MACRO_FREQUENCY_SCALE)
	self.snowBorderFrequencyScale =
		clampNumber(snowRegionConfig.BorderFrequencyScale, 0.1, 6, BiomeConstants.DEFAULT_SNOW_BORDER_FREQUENCY_SCALE)
	self.snowDetailFrequencyScale =
		clampNumber(snowRegionConfig.DetailFrequencyScale, 0.1, 8, BiomeConstants.DEFAULT_SNOW_DETAIL_FREQUENCY_SCALE)
	self.snowHeightOffset =
		clampNumber(snowTerrainConfig.HeightOffset, -64, 64, BiomeConstants.DEFAULT_SNOW_HEIGHT_OFFSET)
	self.snowSmoothedRidgeScale =
		clampNumber(snowTerrainConfig.SmoothedRidgeScale, 0, 2, BiomeConstants.DEFAULT_SNOW_SMOOTHED_RIDGE_SCALE)
	self.snowStoneDepthOffset =
		clampNumber(snowTerrainConfig.StoneDepthOffset, 0, 32, BiomeConstants.DEFAULT_SNOW_STONE_DEPTH_OFFSET)
	self.snowCapDepth =
		math.floor(clampNumber(snowSurfaceConfig.SnowCapDepth, 1, 16, BiomeConstants.DEFAULT_SNOW_CAP_DEPTH))
	self.snowColdSoilDepth =
		math.floor(clampNumber(snowSurfaceConfig.ColdSoilDepth, 1, 32, BiomeConstants.DEFAULT_SNOW_COLD_SOIL_DEPTH))
	self.snowIceDepthStart =
		math.floor(clampNumber(snowSurfaceConfig.IceDepthStart, 1, 64, BiomeConstants.DEFAULT_SNOW_ICE_DEPTH_START))
	self.snowIceBandThickness = math.floor(
		clampNumber(snowSurfaceConfig.IceBandThickness, 1, 64, BiomeConstants.DEFAULT_SNOW_ICE_BAND_THICKNESS)
	)
	self.snowIceDensity = clampNumber(snowSurfaceConfig.IceDensity, 0, 1, BiomeConstants.DEFAULT_SNOW_ICE_DENSITY)
	self.snowPackedSnowDensity =
		clampNumber(snowSurfaceConfig.PackedSnowDensity, 0, 1, BiomeConstants.DEFAULT_SNOW_PACKED_SNOW_DENSITY)

	if self.stoneDepthMax < self.stoneDepthMin then
		self.stoneDepthMax = self.stoneDepthMin
	end

	local preferredSideSign, placementMode, anchorDistance, bandHalfWidth, placementLabel = GetJunglePlacement(self)
	self.junglePreferredSideSign = preferredSideSign
	self.junglePlacementMode = placementMode
	self.jungleAnchorDistance = anchorDistance
	self.jungleBandHalfWidth = bandHalfWidth
	self.junglePlacementLabel = placementLabel
	local desertPreferredSideSign, desertAnchorDistance, desertBandHalfWidth = GetDesertPlacement(self)
	self.desertPreferredSideSign = desertPreferredSideSign
	self.desertAnchorDistance = desertAnchorDistance
	self.desertBandHalfWidth = desertBandHalfWidth
	local snowPreferredSideSign, snowAnchorDistance, snowBandHalfWidth = GetSnowPlacement(self)
	self.snowPreferredSideSign = snowPreferredSideSign
	self.snowAnchorDistance = snowAnchorDistance
	self.snowBandHalfWidth = snowBandHalfWidth

	return self
end

function Biome.GetBiomeType(
	self: Biome,
	tileX: number,
	surfaceY: number,
	biomeId: number,
	surfaceDepthRaw: number?
): number
	local score = sampleCorruptionScore(self, tileX, surfaceY, surfaceDepthRaw)
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

function Biome.SampleTemperatureHumidity(self: Biome, tileX: number, surfaceDepthRaw: number?): (number, number)
	local temperature = sampleDepthAwareOctaveNoise(
		self.seed,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.biomeFrequency,
		self.biomeOctaves,
		self.biomeLacunarity,
		self.biomePersistence,
		BiomeConstants.TEMPERATURE_OFFSET,
		37.45,
		BiomeConstants.TEMPERATURE_OFFSET + 227.11
	)
	local humidity = sampleDepthAwareOctaveNoise(
		self.seed,
		tileX,
		surfaceDepthRaw,
		BiomeConstants.BIOME_DEPTH_SAMPLE_SCALE,
		self.biomeFrequency,
		self.biomeOctaves,
		self.biomeLacunarity,
		self.biomePersistence,
		BiomeConstants.HUMIDITY_OFFSET,
		83.91,
		BiomeConstants.HUMIDITY_OFFSET + 251.37
	)
	return temperature, humidity
end

function Biome.GetBiomeId(
	self: Biome,
	tileX: number,
	temperature: number,
	humidity: number,
	surfaceDepthRaw: number?
): number
	local desertHeatBias = math.max(0, temperature - 0.05) * 0.28
	local desertAridBias = math.max(0, -humidity) * 0.22
	local desertScore = temperature * 1.14 - humidity * 0.38 + desertHeatBias + desertAridBias
	local snowScore = -temperature * 1.05 - humidity * 0.08 + math.max(0, -temperature - 0.02) * 0.22
	local jungleScore = sampleJungleScore(self, tileX, temperature, humidity, surfaceDepthRaw)
	local forestScore = 1 - math.abs(temperature * 0.6) - math.abs(humidity * 0.35)
	local desertBandWeight = sampleDesertBandWeight(self, tileX, surfaceDepthRaw)
	if desertBandWeight > 0 then
		desertScore += desertBandWeight * 1.26
		if temperature >= BiomeConstants.DESERT_TEMPERATURE_MIN and humidity <= BiomeConstants.DESERT_HUMIDITY_MAX then
			desertScore += 0.18 + desertBandWeight * 0.12
		end
	end

	local jungleBandWeight = sampleJungleBandWeight(self, tileX, surfaceDepthRaw)
	if humidity >= BiomeConstants.JUNGLE_HUMIDITY_MIN and jungleBandWeight > 0 then
		local weightedJungleScore = jungleScore + jungleBandWeight * 1.18
		if weightedJungleScore >= BiomeConstants.JUNGLE_REGION_THRESHOLD then
			return self.biomeId.JUNGLE
		end
	end

	local snowBandWeight = sampleSnowBandWeight(self, tileX, surfaceDepthRaw)
	if snowBandWeight > 0 then
		snowScore += snowBandWeight * self.snowRegionWeight
		if temperature <= self.snowTemperatureMax and humidity <= self.snowHumidityMax then
			snowScore += 0.16 + snowBandWeight * 0.14
		end
	end

	local selectedBiomeId = self.biomeId.FOREST
	local selectedScore = forestScore

	local qualifiesForBandDesert = desertBandWeight >= BiomeConstants.DESERT_REGION_THRESHOLD
		and temperature >= BiomeConstants.DESERT_TEMPERATURE_MIN
		and humidity <= BiomeConstants.DESERT_HUMIDITY_MAX + 0.08
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

local function sampleRawSurfaceHeight(self: Biome, tileX: number, biomeId: number, _surfaceDepthRaw: number?): number
	local broadWave = sampleOctaveNoise(
		self.seed,
		tileX,
		self.surfaceFrequency * 0.42,
		math.max(2, math.min(self.surfaceOctaves, 3)),
		self.surfaceLacunarity,
		self.surfacePersistence,
		BiomeConstants.SURFACE_OFFSET,
		11.97
	)
	local rollingWave = sampleOctaveNoise(
		self.seed + 187,
		tileX,
		self.surfaceFrequency * 1.05,
		math.max(2, math.min(self.surfaceOctaves, 3)),
		self.surfaceLacunarity,
		self.surfacePersistence,
		BiomeConstants.SURFACE_OFFSET + 43.7,
		31.41
	)
	local rawRidgeWave =
		sampleOctaveNoise(self.seed, tileX, self.ridgeFrequency, 2, 2, 0.5, BiomeConstants.RIDGE_OFFSET, 29.04)
	local ridgeWave = math.max(0, math.abs(rawRidgeWave) - 0.34)
	local terrainHeight = broadWave * self.surfaceAmplitude * 0.78 + rollingWave * self.surfaceAmplitude * 0.22

	if biomeId == self.biomeId.DESERT then
		local smoothedRidgeScale = 0.22
		return self.surfaceBaseHeight + terrainHeight + ridgeWave * self.ridgeAmplitude * smoothedRidgeScale
	end

	if biomeId == self.biomeId.SNOW then
		return self.surfaceBaseHeight
			+ terrainHeight
			+ ridgeWave * self.ridgeAmplitude * math.min(self.snowSmoothedRidgeScale, 0.3)
			+ self.snowHeightOffset
	end

	local biomeHeightOffset = 0
	if biomeId == self.biomeId.JUNGLE then
		biomeHeightOffset = 2
	end

	local height = self.surfaceBaseHeight + terrainHeight + ridgeWave * self.ridgeAmplitude * 0.32
	return height + biomeHeightOffset
end

local function GetSurfaceBiomeIdAt(self: Biome, tileX: number, surfaceDepthRaw: number?): number
	local temperature, humidity = self:SampleTemperatureHumidity(tileX, surfaceDepthRaw)
	return self:GetBiomeId(tileX, temperature, humidity, surfaceDepthRaw)
end

local function sampleRawSurfaceHeightAt(self: Biome, tileX: number, surfaceDepthRaw: number?): number
	local biomeId = GetSurfaceBiomeIdAt(self, tileX, surfaceDepthRaw)
	return sampleRawSurfaceHeight(self, tileX, biomeId, surfaceDepthRaw)
end

local function sampleWeightedSurfaceHeight(
	self: Biome,
	tileX: number,
	centerBiomeId: number,
	surfaceDepthRaw: number?
): number
	local centerHeight = sampleRawSurfaceHeight(self, tileX, centerBiomeId, surfaceDepthRaw)
	local nearLeftHeight = sampleRawSurfaceHeightAt(self, tileX - 1, surfaceDepthRaw)
	local nearRightHeight = sampleRawSurfaceHeightAt(self, tileX + 1, surfaceDepthRaw)
	local farLeftHeight = sampleRawSurfaceHeightAt(self, tileX - 2, surfaceDepthRaw)
	local farRightHeight = sampleRawSurfaceHeightAt(self, tileX + 2, surfaceDepthRaw)

	local totalWeight = BiomeConstants.SURFACE_SMOOTH_CENTER_WEIGHT
		+ BiomeConstants.SURFACE_SMOOTH_NEAR_WEIGHT * 2
		+ BiomeConstants.SURFACE_SMOOTH_FAR_WEIGHT * 2
	return (
		centerHeight * BiomeConstants.SURFACE_SMOOTH_CENTER_WEIGHT
		+ (nearLeftHeight + nearRightHeight) * BiomeConstants.SURFACE_SMOOTH_NEAR_WEIGHT
		+ (farLeftHeight + farRightHeight) * BiomeConstants.SURFACE_SMOOTH_FAR_WEIGHT
	) / totalWeight
end

function Biome.SampleSurfaceHeight(self: Biome, tileX: number, biomeId: number, surfaceDepthRaw: number?): number
	local weightedHeightCache = {} :: { [number]: number }
	local function GetWeightedHeight(sampleTileX: number, sampleBiomeId: number?): number
		local cached = weightedHeightCache[sampleTileX]
		if cached ~= nil then
			return cached
		end

		local GotBiomeId = if sampleBiomeId ~= nil
			then sampleBiomeId
			else GetSurfaceBiomeIdAt(self, sampleTileX, surfaceDepthRaw)
		local height = sampleWeightedSurfaceHeight(self, sampleTileX, GotBiomeId, surfaceDepthRaw)
		weightedHeightCache[sampleTileX] = height
		return height
	end

	local smoothedHeight = GetWeightedHeight(tileX, biomeId)
	local upperSlopeBound = smoothedHeight
	local lowerSlopeBound = smoothedHeight
	for offset = -BiomeConstants.SURFACE_SLOPE_LIMIT_RADIUS_TILES, BiomeConstants.SURFACE_SLOPE_LIMIT_RADIUS_TILES do
		if offset == 0 then
			continue
		end

		local sampleHeight = GetWeightedHeight(tileX + offset, nil)
		local allowedStep = math.abs(offset) * BiomeConstants.SURFACE_MAX_NEIGHBOR_STEP_TILES
		upperSlopeBound = math.min(upperSlopeBound, sampleHeight + allowedStep)
		lowerSlopeBound = math.max(lowerSlopeBound, sampleHeight - allowedStep)
	end

	local limitedHeight = (upperSlopeBound + lowerSlopeBound) * 0.5
	return math.floor(limitedHeight + 0.5)
end

function Biome.SampleStoneStartDepth(self: Biome, tileX: number, biomeId: number): number
	local noiseValue = sampleOctaveNoise(
		self.seed,
		tileX,
		self.surfaceFrequency * 1.25,
		3,
		2,
		0.5,
		BiomeConstants.STONE_DEPTH_OFFSET,
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

function Biome.GetColumnProfile(self: Biome, tileX: number, surfaceDepth: number?): ColumnProfile
	local temperature, humidity = self:SampleTemperatureHumidity(tileX, surfaceDepth)
	local biomeId = self:GetBiomeId(tileX, temperature, humidity, surfaceDepth)
	local surfaceTemperature, surfaceHumidity = self:SampleTemperatureHumidity(tileX, nil)
	local surfaceBiomeId = self:GetBiomeId(tileX, surfaceTemperature, surfaceHumidity, nil)
	local surfaceY = self:SampleSurfaceHeight(tileX, surfaceBiomeId, nil)
	local biomeType = self:GetBiomeType(tileX, surfaceY, biomeId, surfaceDepth)
	local stoneStartDepth = self:SampleStoneStartDepth(tileX, biomeId)
	local snowDetailNoise = sampleOctaveNoise(
		self.seed + 4129,
		tileX,
		self.biomeFrequency * self.snowDetailFrequencyScale,
		2,
		2,
		0.56,
		BiomeConstants.SNOW_DETAIL_OFFSET,
		47.23
	)
	local snowIceNoise = sampleOctaveNoise(
		self.seed + 4517,
		tileX,
		self.biomeFrequency * (self.snowDetailFrequencyScale + 0.37),
		3,
		2,
		0.52,
		BiomeConstants.SNOW_ICE_OFFSET,
		63.77
	)
	if biomeType == self.biomeType.CORRUPTION then
		stoneStartDepth = math.max(2, stoneStartDepth + 2)
	end
	local topTileId, subsurfaceTileId, deepTileId = GetBiomeSurfaceTiles(self, biomeId, biomeType)

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

-- Background depth columns inherit the foreground profile so every layer reads as one terrain mass.
function Biome.GetDepthColumnProfile(
	_self: Biome,
	_tileX: number,
	_layerIndex: number,
	baseColumn: ColumnProfile
): ColumnProfile
	return baseColumn
end

function Biome.GetTileForDepth(self: Biome, column: ColumnProfile, depthBelowSurface: number): number
	if depthBelowSurface < 0 then
		return self.tileId.AIR
	end

	if column.biomeId == self.biomeId.SNOW and column.biomeType ~= self.biomeType.CORRUPTION then
		if depthBelowSurface == 0 then
			if column.snowIceNoise >= self.snowIceDensity + 0.18 then
				return self.tileId.ICE
			end
			return self.tileId.SNOW
		end

		if depthBelowSurface <= self.snowCapDepth then
			if depthBelowSurface >= 2 and column.snowIceNoise >= self.snowIceDensity + 0.08 then
				return self.tileId.ICE
			end
			return self.tileId.SNOW
		end

		local coldSoilDepthLimit =
			math.max(self.snowCapDepth + 1, math.min(column.stoneStartDepth, self.snowColdSoilDepth))
		if depthBelowSurface < coldSoilDepthLimit then
			if column.snowIceNoise >= self.snowIceDensity then
				return self.tileId.ICE
			end
			return self.tileId.SNOW
		end

		local iceDepthStart = math.max(column.stoneStartDepth, self.snowIceDepthStart)
		if depthBelowSurface >= iceDepthStart then
			local iceDepthAlpha =
				math.clamp((depthBelowSurface - iceDepthStart) / math.max(1, self.snowIceBandThickness), 0, 1)
			local iceThreshold = self.snowIceDensity - iceDepthAlpha * 0.18
			if column.snowIceNoise >= iceThreshold then
				return self.tileId.ICE
			end
			if iceDepthAlpha < 0.45 and column.snowDetailNoise >= self.snowPackedSnowDensity then
				return self.tileId.SNOW
			end
		end

		return self.tileId.ICE
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

	if depthBelowSurface < column.stoneStartDepth then
		return column.subsurfaceTileId
	end

	return column.deepTileId
end

function Biome.ConvertTileToBiomeType(self: Biome, tileId: number, biomeType: number): number
	if biomeType == self.biomeType.CORRUPTION then
		if tileId == self.tileId.GRASS or tileId == self.tileId.JUNGLE_GRASS then
			return self.tileId.CORRUPT_GRASS
		end
		if tileId == self.tileId.DIRT or tileId == self.tileId.MUD or tileId == self.tileId.SAND then
			return self.tileId.CORRUPT_SOIL
		end
		if
			tileId == self.tileId.STONE
			or tileId == self.tileId.SANDSTONE
			or tileId == self.tileId.SNOW
			or tileId == self.tileId.ICE
		then
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
