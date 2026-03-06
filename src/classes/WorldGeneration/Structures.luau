--!strict

local Structures = {}
Structures.__index = Structures

export type TileIdMap = {
	AIR: number,
	STONE: number,
	DIRT: number,
	SANDSTONE: number,
	MUD: number,
	CLAY: number,
	COPPER_ORE: number,
	IRON_ORE: number,
	SILVER_ORE: number,
	GOLD_ORE: number,
	CORRUPT_SOIL: number,
	CORRUPT_STONE: number,
}

export type DepthLayer = "Sky" | "Surface" | "Underground" | "Cavern" | "Deep"

export type StructuresConfig = {
	seed: number,
	tileId: TileIdMap,
	oreFrequency: number,
	oreOctaves: number,
	oreLacunarity: number,
	orePersistence: number,
	oreBlobFrequency: number,
	clayPocketFrequency: number,
}

type OreRule = {
	tileId: number,
	minDepth: number,
	maxDepth: number,
	threshold: number,
	blobThreshold: number,
	frequencyScale: number,
}

local DEFAULT_ORE_FREQUENCY = 0.038
local DEFAULT_ORE_OCTAVES = 2
local DEFAULT_ORE_LACUNARITY = 2
local DEFAULT_ORE_PERSISTENCE = 0.5
local DEFAULT_ORE_BLOB_FREQUENCY = 0.087
local DEFAULT_CLAY_POCKET_FREQUENCY = 0.043

local ORE_OFFSET_X = 997.14
local ORE_OFFSET_Y = 613.88
local BLOB_OFFSET_X = 1171.22
local BLOB_OFFSET_Y = 701.95
local CLAY_OFFSET_X = 1313.64
local CLAY_OFFSET_Y = 809.28
local SEED_X_MULTIPLIER = 0.000227
local SEED_Y_MULTIPLIER = 0.000367

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
	local frequency = baseFrequency
	local amplitude = 1
	local total = 0
	local amplitudeSum = 0

	for octave = 1, octaves do
		local sample = math.noise(
			(x + offsetX + octave * 0.67) * frequency,
			(y + offsetY + octave * 0.49) * frequency,
			seed * SEED_X_MULTIPLIER + octave * SEED_Y_MULTIPLIER
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

local function isOreHost(self, tileId: number): boolean
	return tileId == self.tileId.STONE
		or tileId == self.tileId.CORRUPT_STONE
		or tileId == self.tileId.DIRT
		or tileId == self.tileId.CORRUPT_SOIL
		or tileId == self.tileId.MUD
		or tileId == self.tileId.SANDSTONE
end

function Structures.new(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local tileId = (config :: any).tileId :: TileIdMap

	local self = setmetatable({
		seed = clampNumber((config :: any).seed, -2147483648, 2147483647, 13371337),
		tileId = tileId,
		oreFrequency = clampNumber((config :: any).oreFrequency, 0.0001, 1, DEFAULT_ORE_FREQUENCY),
		oreOctaves = sanitizeOctaveCount((config :: any).oreOctaves, DEFAULT_ORE_OCTAVES),
		oreLacunarity = clampNumber((config :: any).oreLacunarity, 1, 4, DEFAULT_ORE_LACUNARITY),
		orePersistence = clampNumber((config :: any).orePersistence, 0.1, 0.95, DEFAULT_ORE_PERSISTENCE),
		oreBlobFrequency = clampNumber(
			(config :: any).oreBlobFrequency,
			0.0001,
			1,
			DEFAULT_ORE_BLOB_FREQUENCY
		),
		clayPocketFrequency = clampNumber(
			(config :: any).clayPocketFrequency,
			0.0001,
			1,
			DEFAULT_CLAY_POCKET_FREQUENCY
		),
		oreRules = {
			{
				tileId = tileId.GOLD_ORE,
				minDepth = 105,
				maxDepth = 500,
				threshold = 0.74,
				blobThreshold = 0.64,
				frequencyScale = 0.9,
			},
			{
				tileId = tileId.SILVER_ORE,
				minDepth = 72,
				maxDepth = 420,
				threshold = 0.71,
				blobThreshold = 0.6,
				frequencyScale = 1,
			},
			{
				tileId = tileId.IRON_ORE,
				minDepth = 38,
				maxDepth = 260,
				threshold = 0.69,
				blobThreshold = 0.57,
				frequencyScale = 1.05,
			},
			{
				tileId = tileId.COPPER_ORE,
				minDepth = 16,
				maxDepth = 180,
				threshold = 0.67,
				blobThreshold = 0.53,
				frequencyScale = 1.16,
			},
		},
	}, Structures)

	return self
end

function Structures.resolveOreTile(
	self,
	baseTileId: number,
	tileX: number,
	tileY: number,
	depthLayer: DepthLayer,
	depthBelowSurface: number
): number
	if baseTileId == self.tileId.AIR then
		return baseTileId
	end

	if depthLayer == "Sky" or depthLayer == "Surface" then
		return baseTileId
	end

	if not isOreHost(self, baseTileId) then
		return baseTileId
	end

	for _, rule in self.oreRules do
		if depthBelowSurface < rule.minDepth or depthBelowSurface > rule.maxDepth then
			continue
		end

		local depthAlpha = math.clamp(
			(depthBelowSurface - rule.minDepth) / math.max(1, rule.maxDepth - rule.minDepth),
			0,
			1
		)
		local threshold = rule.threshold - depthAlpha * 0.05
		if depthLayer == "Deep" then
			threshold -= 0.03
		end

		local oreNoise = sampleOctaveNoise(
			self.seed,
			tileX,
			tileY,
			self.oreFrequency * rule.frequencyScale,
			self.oreOctaves,
			self.oreLacunarity,
			self.orePersistence,
			ORE_OFFSET_X + rule.frequencyScale * 113,
			ORE_OFFSET_Y + rule.frequencyScale * 61
		)
		local blobNoise = math.abs(math.noise(
			(tileX + BLOB_OFFSET_X + rule.frequencyScale * 97) * self.oreBlobFrequency,
			(tileY + BLOB_OFFSET_Y + rule.frequencyScale * 47) * self.oreBlobFrequency,
			self.seed * SEED_Y_MULTIPLIER
		))

		if oreNoise > threshold and blobNoise > rule.blobThreshold then
			return rule.tileId
		end
	end

	if baseTileId == self.tileId.DIRT and depthBelowSurface >= 5 and depthBelowSurface <= 54 then
		local clayNoise = sampleOctaveNoise(
			self.seed,
			tileX,
			tileY,
			self.clayPocketFrequency,
			2,
			2,
			0.55,
			CLAY_OFFSET_X,
			CLAY_OFFSET_Y
		)
		if clayNoise > 0.7 then
			return self.tileId.CLAY
		end
	end

	return baseTileId
end

export type Structures = typeof(setmetatable(
	{} :: {
		seed: number,
		tileId: TileIdMap,
		oreFrequency: number,
		oreOctaves: number,
		oreLacunarity: number,
		orePersistence: number,
		oreBlobFrequency: number,
		clayPocketFrequency: number,
		oreRules: { OreRule },
	},
	Structures
))

return Structures
