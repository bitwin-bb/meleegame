--!strict

local Structures = {}
Structures.__index = Structures

export type TileIdMap = {
	AIR: number,
	DIRT: number,
	STONE: number,
	SAND: number,
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

export type DepthLayer = "Sky" | "Surface" | "Underground" | "Cavern" | "Deep"

export type ColumnProfile = {
	biomeId: number,
	biomeType: number,
	surfaceY: number,
	stoneStartDepth: number,
	topTileId: number,
	subsurfaceTileId: number,
	deepTileId: number,
}

export type StructureChunkContext = {
	chunkX: number,
	chunkY: number,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	getColumnProfile: (worldTileX: number) -> ColumnProfile,
	computeTileIndex: (localX: number, localY: number, width: number) -> number,
}

export type StructureReservation = {
	minTileX: number,
	maxTileX: number,
	minTileY: number,
	maxTileY: number,
	typeName: string,
}

export type StructureGenerationResult = {
	tileOverrides: { [number]: number },
	reservedSurfaceTiles: { [number]: boolean },
	reservations: { StructureReservation },
}

export type StructuresConfig = {
	seed: number,
	tileId: TileIdMap,
	biomeId: BiomeIdMap,
	biomeType: BiomeTypeMap,
	oreFrequency: number,
	oreOctaves: number,
	oreLacunarity: number,
	orePersistence: number,
	oreBlobFrequency: number,
	clayPocketFrequency: number,
	desertConfig: any?,
}

type OreRule = {
	tileId: number,
	minDepth: number,
	maxDepth: number,
	threshold: number,
	blobThreshold: number,
	frequencyScale: number,
}

type DesertStructureSettings = {
	PyramidCellWidth: number,
	PyramidSpawnChance: number,
	PyramidHalfWidthMin: number,
	PyramidHalfWidthMax: number,
	PyramidHeightMin: number,
	PyramidHeightMax: number,
	InteriorPadding: number,
	EdgeBufferTiles: number,
	SurfaceVarianceTolerance: number,
	BuriedDepthMin: number,
	BuriedDepthMax: number,
	EntranceHeight: number,
}

type PyramidDefinition = {
	centerTileX: number,
	baseTileY: number,
	halfWidth: number,
	height: number,
	chamberHalfWidth: number,
	chamberHeight: number,
	chamberFloorY: number,
	entranceSideSign: number,
	entranceHeight: number,
}

local DEFAULT_ORE_FREQUENCY = 0.038
local DEFAULT_ORE_OCTAVES = 2
local DEFAULT_ORE_LACUNARITY = 2
local DEFAULT_ORE_PERSISTENCE = 0.5
local DEFAULT_ORE_BLOB_FREQUENCY = 0.087
local DEFAULT_CLAY_POCKET_FREQUENCY = 0.043

local DEFAULT_DESERT_STRUCTURE_SETTINGS = {
	PyramidCellWidth = 224,
	PyramidSpawnChance = 0.34,
	PyramidHalfWidthMin = 15,
	PyramidHalfWidthMax = 23,
	PyramidHeightMin = 12,
	PyramidHeightMax = 20,
	InteriorPadding = 4,
	EdgeBufferTiles = 18,
	SurfaceVarianceTolerance = 8,
	BuriedDepthMin = 2,
	BuriedDepthMax = 5,
	EntranceHeight = 3,
}

local ORE_OFFSET_X = 997.14
local ORE_OFFSET_Y = 613.88
local BLOB_OFFSET_X = 1171.22
local BLOB_OFFSET_Y = 701.95
local CLAY_OFFSET_X = 1313.64
local CLAY_OFFSET_Y = 809.28
local SEED_X_MULTIPLIER = 0.000227
local SEED_Y_MULTIPLIER = 0.000367
local UINT32_MAX = 0xFFFFFFFF
local INT32_SIGN_BIT = 0x80000000
local UINT32_WRAP = 4294967296
local PYRAMID_RANDOM_SALT = 4801

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

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw :: number), minimum, maximum)
end

local function toUnitInterval(noiseValue: number): number
	return math.clamp((noiseValue + 1) * 0.5, 0, 1)
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

local function computeSeed(seed: number, x: number, y: number, salt: number): number
	local a = bit32.band(seed, UINT32_MAX)
	local b = bit32.band(x * 73856093, UINT32_MAX)
	local c = bit32.band(y * 19349663, UINT32_MAX)
	local d = bit32.band(salt * 83492791, UINT32_MAX)
	local mixed = bit32.bxor(a, b, c, d)
	mixed = bit32.band(mixed * 1664525 + 1013904223, UINT32_MAX)
	if mixed >= INT32_SIGN_BIT then
		return mixed - UINT32_WRAP
	end
	return mixed
end

local function resolveDesertStructureSettings(configRaw: any): DesertStructureSettings
	local settingsRaw = if typeof(configRaw) == "table" then (configRaw :: any).Structures else nil
	local settings = if typeof(settingsRaw) == "table" then settingsRaw else {}

	return {
		PyramidCellWidth = sanitizeInteger(
			settings.PyramidCellWidth,
			96,
			1024,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.PyramidCellWidth
		),
		PyramidSpawnChance = clampNumber(
			settings.PyramidSpawnChance,
			0,
			1,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.PyramidSpawnChance
		),
		PyramidHalfWidthMin = sanitizeInteger(
			settings.PyramidHalfWidthMin,
			8,
			80,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.PyramidHalfWidthMin
		),
		PyramidHalfWidthMax = sanitizeInteger(
			settings.PyramidHalfWidthMax,
			8,
			96,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.PyramidHalfWidthMax
		),
		PyramidHeightMin = sanitizeInteger(
			settings.PyramidHeightMin,
			6,
			64,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.PyramidHeightMin
		),
		PyramidHeightMax = sanitizeInteger(
			settings.PyramidHeightMax,
			6,
			96,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.PyramidHeightMax
		),
		InteriorPadding = sanitizeInteger(
			settings.InteriorPadding,
			2,
			12,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.InteriorPadding
		),
		EdgeBufferTiles = sanitizeInteger(
			settings.EdgeBufferTiles,
			4,
			64,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.EdgeBufferTiles
		),
		SurfaceVarianceTolerance = sanitizeInteger(
			settings.SurfaceVarianceTolerance,
			2,
			32,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.SurfaceVarianceTolerance
		),
		BuriedDepthMin = sanitizeInteger(
			settings.BuriedDepthMin,
			0,
			12,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.BuriedDepthMin
		),
		BuriedDepthMax = sanitizeInteger(
			settings.BuriedDepthMax,
			0,
			16,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.BuriedDepthMax
		),
		EntranceHeight = sanitizeInteger(
			settings.EntranceHeight,
			2,
			8,
			DEFAULT_DESERT_STRUCTURE_SETTINGS.EntranceHeight
		),
	}
end

local function isOreHost(self, tileId: number): boolean
	return tileId == self.tileId.STONE
		or tileId == self.tileId.CORRUPT_STONE
		or tileId == self.tileId.DIRT
		or tileId == self.tileId.CORRUPT_SOIL
		or tileId == self.tileId.MUD
		or tileId == self.tileId.SANDSTONE
end

local function rangesOverlap(minA: number, maxA: number, minB: number, maxB: number): boolean
	return minA <= maxB and maxA >= minB
end

local function isWithinPyramidBounds(pyramid: PyramidDefinition, worldTileX: number, worldTileY: number): boolean
	local horizontalDistance = math.abs(worldTileX - pyramid.centerTileX)
	if horizontalDistance > pyramid.halfWidth then
		return false
	end
	local columnTopY = pyramid.baseTileY + math.floor((1 - horizontalDistance / pyramid.halfWidth) * pyramid.height + 0.5)
	return worldTileY >= pyramid.baseTileY and worldTileY <= columnTopY
end

local function isInsidePyramidChamber(pyramid: PyramidDefinition, worldTileX: number, worldTileY: number): boolean
	local chamberMinX = pyramid.centerTileX - pyramid.chamberHalfWidth
	local chamberMaxX = pyramid.centerTileX + pyramid.chamberHalfWidth
	local chamberMaxY = pyramid.chamberFloorY + pyramid.chamberHeight

	if
		worldTileX >= chamberMinX
		and worldTileX <= chamberMaxX
		and worldTileY >= pyramid.chamberFloorY
		and worldTileY <= chamberMaxY
	then
		return true
	end

	local entranceDirection = pyramid.entranceSideSign
	local entranceOuterX = pyramid.centerTileX + entranceDirection * (pyramid.halfWidth - 1)
	local entranceInnerX = chamberMinX - 1
	if entranceDirection > 0 then
		entranceInnerX = chamberMaxX + 1
	end
	local entranceMinX = math.min(entranceOuterX, entranceInnerX)
	local entranceMaxX = math.max(entranceOuterX, entranceInnerX)
	local entranceTopY = pyramid.chamberFloorY + pyramid.entranceHeight

	return worldTileX >= entranceMinX
		and worldTileX <= entranceMaxX
		and worldTileY >= pyramid.chamberFloorY
		and worldTileY <= entranceTopY
end

function Structures.new(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local tileId = (config :: any).tileId :: TileIdMap

	local desertStructureSettings = resolveDesertStructureSettings((config :: any).desertConfig)
	if desertStructureSettings.PyramidHalfWidthMax < desertStructureSettings.PyramidHalfWidthMin then
		desertStructureSettings.PyramidHalfWidthMax = desertStructureSettings.PyramidHalfWidthMin
	end
	if desertStructureSettings.PyramidHeightMax < desertStructureSettings.PyramidHeightMin then
		desertStructureSettings.PyramidHeightMax = desertStructureSettings.PyramidHeightMin
	end
	if desertStructureSettings.BuriedDepthMax < desertStructureSettings.BuriedDepthMin then
		desertStructureSettings.BuriedDepthMax = desertStructureSettings.BuriedDepthMin
	end

	local self = setmetatable({
		seed = clampNumber((config :: any).seed, -2147483648, 2147483647, 13371337),
		tileId = tileId,
		biomeId = (config :: any).biomeId :: BiomeIdMap,
		biomeType = (config :: any).biomeType :: BiomeTypeMap,
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
		desertStructureSettings = desertStructureSettings,
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

		local oreNoise = toUnitInterval(sampleOctaveNoise(
			self.seed,
			tileX,
			tileY,
			self.oreFrequency * rule.frequencyScale,
			self.oreOctaves,
			self.oreLacunarity,
			self.orePersistence,
			ORE_OFFSET_X + rule.frequencyScale * 113,
			ORE_OFFSET_Y + rule.frequencyScale * 61
		))
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
		local clayNoise = toUnitInterval(sampleOctaveNoise(
			self.seed,
			tileX,
			tileY,
			self.clayPocketFrequency,
			2,
			2,
			0.55,
			CLAY_OFFSET_X,
			CLAY_OFFSET_Y
		))
		if clayNoise > 0.7 then
			return self.tileId.CLAY
		end
	end

	return baseTileId
end

function Structures.resolvePyramidForCell(
	self,
	cellX: number,
	getColumnProfile: (worldTileX: number) -> ColumnProfile
): PyramidDefinition?
	local settings = self.desertStructureSettings
	local randomObject = Random.new(computeSeed(self.seed, cellX, 0, PYRAMID_RANDOM_SALT))
	if randomObject:NextNumber() > settings.PyramidSpawnChance then
		return nil
	end

	local halfWidth = randomObject:NextInteger(settings.PyramidHalfWidthMin, settings.PyramidHalfWidthMax)
	local availableMargin = settings.EdgeBufferTiles + halfWidth + 2
	if availableMargin * 2 >= settings.PyramidCellWidth then
		return nil
	end

	local cellMinX = cellX * settings.PyramidCellWidth
	local centerTileX = randomObject:NextInteger(
		cellMinX + availableMargin,
		cellMinX + settings.PyramidCellWidth - availableMargin
	)
	local minTileX = centerTileX - halfWidth
	local maxTileX = centerTileX + halfWidth

	local sampledColumns = 0
	local desertColumns = 0
	local surfaceSum = 0
	local minSurfaceY = math.huge
	local maxSurfaceY = -math.huge
	for worldTileX = minTileX, maxTileX, 2 do
		local column = getColumnProfile(worldTileX)
		sampledColumns += 1
		if column.biomeId == self.biomeId.DESERT and column.biomeType == self.biomeType.NORMAL then
			desertColumns += 1
		end
		surfaceSum += column.surfaceY
		if column.surfaceY < minSurfaceY then
			minSurfaceY = column.surfaceY
		end
		if column.surfaceY > maxSurfaceY then
			maxSurfaceY = column.surfaceY
		end
	end

	if sampledColumns <= 0 or desertColumns < sampledColumns then
		return nil
	end
	if maxSurfaceY - minSurfaceY > settings.SurfaceVarianceTolerance then
		return nil
	end

	local buriedDepth = randomObject:NextInteger(settings.BuriedDepthMin, settings.BuriedDepthMax)
	local baseTileY = math.floor(surfaceSum / sampledColumns) - buriedDepth
	local maxPyramidHeight = math.max(settings.PyramidHeightMin, math.min(settings.PyramidHeightMax, halfWidth))
	local height = randomObject:NextInteger(settings.PyramidHeightMin, maxPyramidHeight)
	local chamberHalfWidth = math.max(3, halfWidth - settings.InteriorPadding)
	local chamberHeight = math.max(3, height - settings.InteriorPadding - 1)
	local chamberFloorY = baseTileY + math.max(2, math.floor(height * 0.15))

	return {
		centerTileX = centerTileX,
		baseTileY = baseTileY,
		halfWidth = halfWidth,
		height = height,
		chamberHalfWidth = math.min(chamberHalfWidth, halfWidth - 2),
		chamberHeight = chamberHeight,
		chamberFloorY = chamberFloorY,
		entranceSideSign = if randomObject:NextNumber() < 0.5 then -1 else 1,
		entranceHeight = settings.EntranceHeight,
	}
end

function Structures.generateChunkStructures(
	self,
	context: StructureChunkContext
): StructureGenerationResult
	local tileOverrides: { [number]: number } = {}
	local reservedSurfaceTiles: { [number]: boolean } = {}
	local reservations: { StructureReservation } = {}
	local settings = self.desertStructureSettings

	local chunkMaxX = context.tileMinX + context.width - 1
	local chunkMaxY = context.tileMinY + context.height - 1
	local searchPadding = settings.PyramidCellWidth
	local minCell = math.floor((context.tileMinX - searchPadding) / settings.PyramidCellWidth)
	local maxCell = math.floor((chunkMaxX + searchPadding) / settings.PyramidCellWidth)

	for cellX = minCell, maxCell do
		local pyramid = self:resolvePyramidForCell(cellX, context.getColumnProfile)
		if pyramid == nil then
			continue
		end

		local structureMinX = pyramid.centerTileX - pyramid.halfWidth
		local structureMaxX = pyramid.centerTileX + pyramid.halfWidth
		local structureMaxY = pyramid.baseTileY + pyramid.height
		local reservedMinX = structureMinX - settings.EdgeBufferTiles
		local reservedMaxX = structureMaxX + settings.EdgeBufferTiles
		if rangesOverlap(reservedMinX, reservedMaxX, context.tileMinX, chunkMaxX) then
			for reservedX = math.max(reservedMinX, context.tileMinX), math.min(reservedMaxX, chunkMaxX) do
				reservedSurfaceTiles[reservedX] = true
			end
		end

		if not rangesOverlap(structureMinX, structureMaxX, context.tileMinX, chunkMaxX) then
			continue
		end
		if not rangesOverlap(pyramid.baseTileY, structureMaxY, context.tileMinY, chunkMaxY) then
			continue
		end

		reservations[#reservations + 1] = {
			minTileX = structureMinX,
			maxTileX = structureMaxX,
			minTileY = pyramid.baseTileY,
			maxTileY = structureMaxY,
			typeName = "Pyramid",
		}

		local paintMinX = math.max(structureMinX, context.tileMinX)
		local paintMaxX = math.min(structureMaxX, chunkMaxX)
		local paintMinY = math.max(pyramid.baseTileY, context.tileMinY)
		local paintMaxY = math.min(structureMaxY, chunkMaxY)

		for worldTileX = paintMinX, paintMaxX do
			for worldTileY = paintMinY, paintMaxY do
				if not isWithinPyramidBounds(pyramid, worldTileX, worldTileY) then
					continue
				end

				local localX = worldTileX - context.tileMinX
				local localY = worldTileY - context.tileMinY
				local tileIndex = context.computeTileIndex(localX, localY, context.width)

				if isInsidePyramidChamber(pyramid, worldTileX, worldTileY) then
					tileOverrides[tileIndex] = self.tileId.AIR
				else
					local isCap = worldTileY >= pyramid.baseTileY + pyramid.height - 1
					tileOverrides[tileIndex] = if isCap then self.tileId.SAND else self.tileId.SANDSTONE
				end
			end
		end
	end

	return {
		tileOverrides = tileOverrides,
		reservedSurfaceTiles = reservedSurfaceTiles,
		reservations = reservations,
	}
end

export type Structures = typeof(setmetatable(
	{} :: {
		seed: number,
		tileId: TileIdMap,
		biomeId: BiomeIdMap,
		biomeType: BiomeTypeMap,
		oreFrequency: number,
		oreOctaves: number,
		oreLacunarity: number,
		orePersistence: number,
		oreBlobFrequency: number,
		clayPocketFrequency: number,
		desertStructureSettings: DesertStructureSettings,
		oreRules: { OreRule },
	},
	Structures
))

return Structures
