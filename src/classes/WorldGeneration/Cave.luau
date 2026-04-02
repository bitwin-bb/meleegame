--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Noise = require(ReplicatedStorage.Shared.Modules.Math.Noise)

local Cave = {}
Cave.__index = Cave

export type TileIdMap = {
	AIR: number,
}

export type WallIdMap = {
	NONE: number,
	DIRT: number,
	STONE: number,
	SANDSTONE: number,
	SNOW: number,
	MUD: number,
}

export type BiomeIdMap = {
	FOREST: number,
	DESERT: number,
	SNOW: number,
	JUNGLE: number,
}

export type DepthLayer = "Sky" | "Surface" | "Underground" | "Cavern" | "Deep"

export type CaveConfig = {
	seed: number,
	tileId: TileIdMap,
	wallId: WallIdMap,
	biomeId: BiomeIdMap,
	snowConfig: any?,
	surfaceDepth: number,
	undergroundDepth: number,
	cavernDepth: number,
	caveFrequency: number,
	caveOctaves: number,
	caveLacunarity: number,
	cavePersistence: number,
	tunnelFrequency: number,
	pocketFrequency: number,
	crackFrequency: number,
}

local DEFAULT_SURFACE_DEPTH = 8
local DEFAULT_UNDERGROUND_DEPTH = 52
local DEFAULT_CAVERN_DEPTH = 140
local DEFAULT_CAVE_FREQUENCY = 0.021
local DEFAULT_CAVE_OCTAVES = 3
local DEFAULT_CAVE_LACUNARITY = 2
local DEFAULT_CAVE_PERSISTENCE = 0.5
local DEFAULT_TUNNEL_FREQUENCY = 0.047
local DEFAULT_POCKET_FREQUENCY = 0.016
local DEFAULT_CRACK_FREQUENCY = 0.085
local DEFAULT_SNOW_UNDERGROUND_THRESHOLD_DELTA = -0.025
local DEFAULT_SNOW_CAVERN_THRESHOLD_DELTA = -0.045
local DEFAULT_SNOW_POCKET_THRESHOLD_DELTA = -0.06

local SEED_X_MULTIPLIER = 0.000187
local SEED_Y_MULTIPLIER = 0.000413
local CAVE_OFFSET_X = 517.71
local CAVE_OFFSET_Y = 127.43
local TUNNEL_OFFSET_X = 613.09
local TUNNEL_OFFSET_Y = 233.84
local POCKET_OFFSET_X = 733.45
local POCKET_OFFSET_Y = 311.52
local CRACK_OFFSET_X = 877.02
local CRACK_OFFSET_Y = 421.77

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
	y: number,
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
			(x + offsetX + octave * 1.13) * sampleFrequency,
			(y + offsetY + octave * 0.87) * sampleFrequency,
			seed * SEED_X_MULTIPLIER + octave * SEED_Y_MULTIPLIER
		)
	end)
end

local function resolveWallByBiome(self, biomeId: number, layer: DepthLayer): number
	if biomeId == self.biomeId.DESERT then
		return self.wallId.SANDSTONE
	end

	if biomeId == self.biomeId.SNOW then
		return self.wallId.SNOW
	end

	if biomeId == self.biomeId.JUNGLE then
		return self.wallId.MUD
	end

	if layer == "Cavern" or layer == "Deep" then
		return self.wallId.STONE
	end

	return self.wallId.DIRT
end

function Cave.new(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local tileId = (config :: any).tileId :: TileIdMap
	local wallId = (config :: any).wallId :: WallIdMap
	local biomeId = (config :: any).biomeId :: BiomeIdMap

	local self = setmetatable({
		seed = clampNumber((config :: any).seed, -2147483648, 2147483647, 13371337),
		tileId = tileId,
		wallId = wallId,
		biomeId = biomeId,
		surfaceDepth = math.floor(clampNumber((config :: any).surfaceDepth, 1, 64, DEFAULT_SURFACE_DEPTH)),
		undergroundDepth = math.floor(
			clampNumber((config :: any).undergroundDepth, 16, 256, DEFAULT_UNDERGROUND_DEPTH)
		),
		cavernDepth = math.floor(clampNumber((config :: any).cavernDepth, 64, 512, DEFAULT_CAVERN_DEPTH)),
		caveFrequency = clampNumber((config :: any).caveFrequency, 0.0001, 1, DEFAULT_CAVE_FREQUENCY),
		caveOctaves = sanitizeOctaveCount((config :: any).caveOctaves, DEFAULT_CAVE_OCTAVES),
		caveLacunarity = clampNumber((config :: any).caveLacunarity, 1, 4, DEFAULT_CAVE_LACUNARITY),
		cavePersistence = clampNumber((config :: any).cavePersistence, 0.1, 0.95, DEFAULT_CAVE_PERSISTENCE),
		tunnelFrequency = clampNumber((config :: any).tunnelFrequency, 0.0001, 1, DEFAULT_TUNNEL_FREQUENCY),
		pocketFrequency = clampNumber((config :: any).pocketFrequency, 0.0001, 1, DEFAULT_POCKET_FREQUENCY),
		crackFrequency = clampNumber((config :: any).crackFrequency, 0.0001, 1, DEFAULT_CRACK_FREQUENCY),
		snowUndergroundThresholdDelta = DEFAULT_SNOW_UNDERGROUND_THRESHOLD_DELTA,
		snowCavernThresholdDelta = DEFAULT_SNOW_CAVERN_THRESHOLD_DELTA,
		snowPocketThresholdDelta = DEFAULT_SNOW_POCKET_THRESHOLD_DELTA,
	}, Cave)

	local snowConfig = if typeof((config :: any).snowConfig) == "table" then (config :: any).snowConfig else {}
	local snowCavesConfig = if typeof((snowConfig :: any).Caves) == "table" then (snowConfig :: any).Caves else {}
	self.snowUndergroundThresholdDelta = clampNumber(
		snowCavesConfig.UndergroundThresholdDelta,
		-0.25,
		0.25,
		DEFAULT_SNOW_UNDERGROUND_THRESHOLD_DELTA
	)
	self.snowCavernThresholdDelta = clampNumber(
		snowCavesConfig.CavernThresholdDelta,
		-0.25,
		0.25,
		DEFAULT_SNOW_CAVERN_THRESHOLD_DELTA
	)
	self.snowPocketThresholdDelta = clampNumber(
		snowCavesConfig.PocketThresholdDelta,
		-0.25,
		0.25,
		DEFAULT_SNOW_POCKET_THRESHOLD_DELTA
	)

	self.undergroundDepth = math.max(self.undergroundDepth, self.surfaceDepth + 8)
	self.cavernDepth = math.max(self.cavernDepth, self.undergroundDepth + 24)

	return self
end

function Cave.resolveDepthLayer(self, surfaceY: number, tileY: number): (DepthLayer, number)
	local depth = surfaceY - tileY
	if depth < 0 then
		return "Sky", depth
	end

	if depth <= self.surfaceDepth then
		return "Surface", depth
	end

	if depth <= self.undergroundDepth then
		return "Underground", depth
	end

	if depth <= self.cavernDepth then
		return "Cavern", depth
	end

	return "Deep", depth
end

function Cave.sampleDensity(self, tileX: number, tileY: number): number
	return sampleOctaveNoise(
		self.seed,
		tileX,
		tileY,
		self.caveFrequency,
		self.caveOctaves,
		self.caveLacunarity,
		self.cavePersistence,
		CAVE_OFFSET_X,
		CAVE_OFFSET_Y
	)
end

function Cave.shouldCarve(
	self,
	tileX: number,
	tileY: number,
	biomeId: number,
	depthLayer: DepthLayer,
	depthBelowSurface: number
): boolean
	if depthLayer == "Sky" then
		return false
	end

	if depthBelowSurface < math.max(3, self.surfaceDepth + 2) then
		return false
	end
	if depthLayer == "Surface" then
		return false
	end

	local density = self:sampleDensity(tileX, tileY)
	local tunnel = math.abs(math.noise(
		(tileX + TUNNEL_OFFSET_X) * self.tunnelFrequency,
		(tileY + TUNNEL_OFFSET_Y) * self.tunnelFrequency,
		self.seed * SEED_X_MULTIPLIER
	))
	local pocket = sampleOctaveNoise(
		self.seed,
		tileX,
		tileY,
		self.pocketFrequency,
		2,
		2,
		0.55,
		POCKET_OFFSET_X,
		POCKET_OFFSET_Y
	)
	local crack = math.abs(math.noise(
		(tileX + CRACK_OFFSET_X) * self.crackFrequency,
		(tileY + CRACK_OFFSET_Y) * self.crackFrequency,
		self.seed * SEED_Y_MULTIPLIER
	))

	local threshold = 0.72
	local tunnelThreshold = 0.055
	local pocketThreshold = 0.88
	local crackThreshold = 0.05

	if depthLayer == "Cavern" then
		threshold = 0.5
		tunnelThreshold = 0.1
		pocketThreshold = 0.76
		crackThreshold = 0.056
	elseif depthLayer == "Deep" then
		threshold = 0.42
		tunnelThreshold = 0.09
		pocketThreshold = 0.74
		crackThreshold = 0.045
	else
		local undergroundSpan = math.max(1, self.undergroundDepth - self.surfaceDepth)
		local undergroundDepthAlpha = math.clamp((depthBelowSurface - self.surfaceDepth) / undergroundSpan, 0, 1)
		threshold -= undergroundDepthAlpha * 0.08
		tunnelThreshold -= (1 - undergroundDepthAlpha) * 0.02
		pocketThreshold += (1 - undergroundDepthAlpha) * 0.04
	end

	if biomeId == self.biomeId.DESERT and depthLayer == "Underground" then
		threshold += 0.04
		tunnelThreshold -= 0.01
	elseif biomeId == self.biomeId.SNOW then
		if depthLayer == "Underground" then
			threshold += self.snowUndergroundThresholdDelta
			pocketThreshold += self.snowPocketThresholdDelta * 0.66
		elseif depthLayer == "Cavern" or depthLayer == "Deep" then
			threshold += self.snowCavernThresholdDelta
			pocketThreshold += self.snowPocketThresholdDelta
			tunnelThreshold += 0.01
		end
	elseif biomeId == self.biomeId.JUNGLE and depthLayer ~= "Surface" then
		threshold -= 0.04
	end

	local carveByDensity = density > threshold
	local carveByTunnel = tunnel < tunnelThreshold
	local carveByPocket = pocket > pocketThreshold
	local carveByCrack = depthLayer == "Deep" and crack < crackThreshold

	if carveByDensity then
		return true
	end

	if carveByTunnel then
		return true
	end

	if carveByPocket then
		return true
	end

	if carveByCrack then
		return true
	end

	return false
end

function Cave.resolveWall(
	self,
	tileId: number,
	biomeId: number,
	depthLayer: DepthLayer,
	depthBelowSurface: number
): number
	if depthLayer == "Sky" then
		return self.wallId.NONE
	end

	if depthLayer == "Surface" and depthBelowSurface <= 1 then
		return self.wallId.NONE
	end

	if tileId ~= self.tileId.AIR then
		if depthLayer == "Surface" and depthBelowSurface <= 3 then
			return self.wallId.NONE
		end
		return resolveWallByBiome(self, biomeId, depthLayer)
	end

	if depthLayer == "Surface" then
		return self.wallId.NONE
	end

	return resolveWallByBiome(self, biomeId, depthLayer)
end

export type Cave = typeof(setmetatable(
	{} :: {
		seed: number,
		tileId: TileIdMap,
		wallId: WallIdMap,
		biomeId: BiomeIdMap,
		surfaceDepth: number,
		undergroundDepth: number,
		cavernDepth: number,
		caveFrequency: number,
		caveOctaves: number,
		caveLacunarity: number,
		cavePersistence: number,
		tunnelFrequency: number,
		pocketFrequency: number,
		crackFrequency: number,
	},
	Cave
))

return Cave
