--!strict

local LiquidServiceUtils = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldGenerationColor = require(ReplicatedStorage.Shared.Modules.Items.WorldGenerationColor)

LiquidServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"

LiquidServiceUtils.CLIENT_METHOD_APPLY_STATE = "applyState"
LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_SNAPSHOT = "onChunkSnapshot"
LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_DELTA = "onChunkDelta"
LiquidServiceUtils.CLIENT_METHOD_ON_CHUNK_UNLOADED = "onChunkUnloaded"
LiquidServiceUtils.CLIENT_METHOD_ON_EFFECT_EVENT = "onEffectEvent"

LiquidServiceUtils.LIQUID_TYPE = {
	NONE = 0,
	WATER = 1,
	LAVA = 2,
}

LiquidServiceUtils.FLOW_STATE = {
	STILL = 0,
	FALLING = 1,
	SPREADING = 2,
	SETTLING = 3,
}

LiquidServiceUtils.CELL_DEBUG_STATE = {
	ACTIVE = "Active",
	STABLE = "Stable",
	BLOCKED = "Blocked",
	BLOCKED_BY_LOADED_TERRAIN = "BlockedByLoadedTerrain",
	DEFERRED_WAITING_FOR_CHUNK = "DeferredWaitingForChunk",
	SEARCHING_LEAK_PATH = "SearchingLeakPath",
	FALLING = "Falling",
	EQUALIZING = "Equalizing",
}

LiquidServiceUtils.EFFECT_EVENT = {
	ENTER = "enter",
	EXIT = "exit",
	SUBMERGED_START = "submergedStart",
	SUBMERGED_END = "submergedEnd",
	BURN_START = "burnStart",
	BURN_END = "burnEnd",
	SPLASH = "splash",
}

local MAX_FILL = 255
local DEFAULT_FILL_BUCKET_SIZE = 8
local DEFAULT_MIN_VISIBLE_FILL = 6
local DEFAULT_FLOW_SETTLE_EPSILON = 1
local DEFAULT_LIQUID_INTERPOLATION_TIME = 0.18
local DEFAULT_LIQUID_COLOR_DEFINITIONS = WorldGenerationColor.LIQUID_DEFINITIONS
local DEFAULT_LIQUID_BIOME_TINTS = WorldGenerationColor.LIQUID_BIOME_TINTS

LiquidServiceUtils.MAX_FILL = MAX_FILL
LiquidServiceUtils.MIN_VISIBLE_FILL = DEFAULT_MIN_VISIBLE_FILL
LiquidServiceUtils.FILL_BUCKET_SIZE = DEFAULT_FILL_BUCKET_SIZE

type Color3Map = { [number]: Color3 }

export type LiquidDefinition = {
	id: number,
	name: string,
	baseColor: Color3,
	surfaceColor: Color3,
	movementSpeedMultiplier: number,
	material: Enum.Material,
	interiorTransparency: number,
	surfaceTransparency: number,
	sideEqualizeRate: number,
	maxSideTransfer: number,
	settleEpsilon: number,
	renderPriority: number,
	blocksBreathing: boolean,
	supportsDrowning: boolean,
	isBurning: boolean,
	lavaTouchDamage: number,
	lavaTouchInterval: number,
	burnDamage: number,
	burnInterval: number,
	burnDuration: number,
	tintStrength: number,
	lavaAmbientTintStrength: number,
}

export type LiquidSimulationConfig = {
	stepRate: number,
	hazardCheckRate: number,
	streamSyncInterval: number,
	activeSafetyMarginChunks: number,
	disturbedChunkKeepAliveSeconds: number,
	maxChunkStepsPerTick: number,
	maxCellsPerChunkStep: number,
	maxWakeRequestsPerTick: number,
	maxDeltaCellsPerChunk: number,
	fullSnapshotThreshold: number,
	generationSettlePasses: number,
	leakScanDistanceTiles: number,
	consistencySweepInterval: number,
	consistencySweepChunkBudget: number,
}

export type LiquidGenerationConfig = {
	depressionScanRadius: number,
	surfacePoolChance: number,
	surfacePoolMinDepth: number,
	surfacePoolMaxDepth: number,
	surfacePoolFillChance: number,
	cavePocketChance: number,
	cavePocketMinDepth: number,
	cavePocketMaxDepth: number,
	cavePocketMinRadius: number,
	cavePocketMaxRadius: number,
	reservoirChance: number,
	reservoirMinDepth: number,
	reservoirMaxDepth: number,
	reservoirMinRadius: number,
	reservoirMaxRadius: number,
	lavaStartDepth: number,
	lavaCommonDepth: number,
	lavaPocketChance: number,
	lavaReservoirChance: number,
	lavaPocketMinRadius: number,
	lavaPocketMaxRadius: number,
}

export type LiquidRenderConfig = {
	interpolationTime: number,
	surfaceWaveAmplitudeStuds: number,
	surfaceWaveSpeed: number,
	surfaceWaveScale: number,
	rebuildRowsPerFrame: number,
	rebuildFlushInterval: number,
	minVisibleFill: number,
	fillBucketSize: number,
}

export type LiquidBiomeTintConfig = {
	byBiomeId: Color3Map,
	byBiomeType: Color3Map,
	lavaAmbientByBiomeId: Color3Map,
	lavaAmbientByBiomeType: Color3Map,
}

export type LiquidDebugConfig = {
	enabled: boolean,
	logActivations: boolean,
	logDirtyMarks: boolean,
	logSimulationSteps: boolean,
	logStableTransitions: boolean,
	visualizeChunks: boolean,
	visualizeCells: boolean,
}

export type LiquidServiceConfig = {
	maxFill: number,
	simulation: LiquidSimulationConfig,
	generation: LiquidGenerationConfig,
	render: LiquidRenderConfig,
	definitions: { [number]: LiquidDefinition },
	biomeTints: LiquidBiomeTintConfig,
	debug: LiquidDebugConfig,
}

export type LiquidServiceState = {
	ready: boolean,
	tileSize: number,
	chunkSize: number,
	worldOrigin: Vector3,
	maxFill: number,
	interpolationTime: number,
	updatedAt: number,
}

export type LiquidChunkSnapshot = {
	key: string,
	chunkX: number,
	chunkY: number,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	cells: { number },
	revision: number,
	updatedAt: number,
}

export type LiquidChunkDeltaCell = {
	index: number,
	cell: number,
}

export type LiquidChunkDelta = {
	key: string,
	chunkX: number,
	chunkY: number,
	width: number,
	height: number,
	revision: number,
	changes: { LiquidChunkDeltaCell },
	updatedAt: number,
}

export type LiquidSamplePoint = {
	name: string,
	worldPosition: Vector3,
	tileX: number,
	tileY: number,
	liquidType: number,
	fill: number,
	submerged: boolean,
	surfaceWorldY: number?,
	weight: number,
}

export type LiquidQueryResult = {
	inLiquid: boolean,
	dominantType: number,
	breathingLiquidType: number,
	submersionRatio: number,
	breathingSubmerged: boolean,
	meaningfulSubmersion: boolean,
	surfaceWorldY: number?,
	samples: { LiquidSamplePoint },
	typeWeights: { [number]: number },
}

export type LiquidStripDescriptor = {
	key: string,
	typeId: number,
	rowY: number,
	startX: number,
	endX: number,
	widthTiles: number,
	fill: number,
	fillAlpha: number,
	isSurface: boolean,
}

export type LiquidBackgroundLayerSource = {
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tiles: { number },
}

export type LiquidQueryProvider = {
	tileSize: number,
	worldOrigin: Vector3,
	getCellAt: (tileX: number, tileY: number) -> number,
	getLiquidDefinition: ((liquidType: number) -> LiquidDefinition?)?,
}

export type LiquidTileCoordinate = {
	tileX: number,
	tileY: number,
}

export type LiquidCellInspection = {
	hasLiquid: boolean,
	liquidType: number,
	fill: number,
	isStable: boolean,
	state: string,
	reason: string,
	canFlowDown: boolean,
	canEqualize: boolean,
	hasLeakPath: boolean,
	boundaryDependency: boolean,
	waitingOnChunkReady: boolean,
	dependencyChunkKey: string?,
	preferredDirection: number,
	leakDistance: number,
	wakeTiles: { LiquidTileCoordinate },
}

export type LiquidSolverStepResult = {
	changed: boolean,
	active: boolean,
	isStable: boolean,
	state: string,
	reason: string,
	waitingOnChunkReady: boolean,
	dependencyChunkKey: string?,
	downwardTransfer: number,
	lateralTransfer: number,
	liquidType: number,
	fill: number,
	wakeTiles: { LiquidTileCoordinate },
}

export type LiquidSolverAccess = {
	maxFill: number,
	chunkSize: number,
	maxLeakScanDistance: number?,
	getCell: (tileX: number, tileY: number) -> number,
	setCell: (tileX: number, tileY: number, packedCell: number) -> boolean,
	isSolid: (tileX: number, tileY: number) -> boolean,
	isChunkReady: (chunkX: number, chunkY: number) -> boolean,
	pushDirty: (tileX: number, tileY: number, reason: string?, sourceTileX: number?, sourceTileY: number?) -> (),
	getDefinition: (liquidType: number) -> LiquidDefinition?,
	reportCellState: ((
		tileX: number,
		tileY: number,
		state: string,
		reason: string,
		fill: number,
		liquidType: number
	) -> ())?,
	recordMetric: ((metricName: string, amountRaw: any?) -> ())?,
}

local UINT8_MASK = 0xFF
local TYPE_SHIFT = 8
local FLOW_SHIFT = 11
local FLAGS_SHIFT = 14
local TYPE_MASK = 0x7
local FLOW_MASK = 0x7
local FLAGS_MASK = 0x3

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function sanitizeNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function sanitizeColor3(valueRaw: any, fallback: Color3): Color3
	if typeof(valueRaw) == "Color3" then
		return valueRaw
	end
	return fallback
end

local function cloneColor3Map(sourceRaw: any): Color3Map
	local clone: Color3Map = {}
	if typeof(sourceRaw) ~= "table" then
		return clone
	end
	for keyRaw, colorRaw in sourceRaw do
		local key = if isFiniteNumber(keyRaw) then math.floor(keyRaw) else nil
		if key ~= nil and typeof(colorRaw) == "Color3" then
			clone[key] = colorRaw
		end
	end
	return clone
end

local function lerpColor(a: Color3, b: Color3, alphaRaw: any): Color3
	local alpha = sanitizeNumber(alphaRaw, 0, 1, 0)
	return Color3.new(a.R + (b.R - a.R) * alpha, a.G + (b.G - a.G) * alpha, a.B + (b.B - a.B) * alpha)
end

function LiquidServiceUtils.packChunkKey(chunkX: number, chunkY: number): string
	return `{chunkX}:{chunkY}`
end

function LiquidServiceUtils.unpackChunkKey(chunkKeyRaw: any): (number?, number?)
	if typeof(chunkKeyRaw) ~= "string" then
		return nil, nil
	end
	local xRaw, yRaw = string.match(chunkKeyRaw, "^(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil then
		return nil, nil
	end
	local chunkX = tonumber(xRaw)
	local chunkY = tonumber(yRaw)
	if chunkX == nil or chunkY == nil then
		return nil, nil
	end
	return chunkX, chunkY
end

function LiquidServiceUtils.computeTileIndex(localX: number, localY: number, width: number): number
	return localY * width + localX + 1
end

function LiquidServiceUtils.toTileCoordinate(worldAxis: number, tileSize: number): number
	return math.floor(worldAxis / math.max(0.001, tileSize))
end

function LiquidServiceUtils.toChunkCoordinate(tileAxis: number, chunkSize: number): number
	return math.floor(tileAxis / math.max(1, chunkSize))
end

function LiquidServiceUtils.tileToWorldCenter(
	tileX: number,
	tileY: number,
	worldOrigin: Vector3,
	tileSize: number,
	basePlaneX: number
): Vector3
	return Vector3.new(basePlaneX, worldOrigin.Y + (tileY + 0.5) * tileSize, worldOrigin.Z + (tileX + 0.5) * tileSize)
end

local LiquidCell = {}

function LiquidCell.pack(liquidTypeRaw: any, fillRaw: any, flowStateRaw: any, flagsRaw: any?): number
	local liquidType =
		sanitizeInteger(liquidTypeRaw, LiquidServiceUtils.LIQUID_TYPE.NONE, 7, LiquidServiceUtils.LIQUID_TYPE.NONE)
	local fill = sanitizeInteger(fillRaw, 0, MAX_FILL, 0)
	if liquidType == LiquidServiceUtils.LIQUID_TYPE.NONE or fill <= 0 then
		return 0
	end
	local flowState = sanitizeInteger(flowStateRaw, 0, FLOW_MASK, LiquidServiceUtils.FLOW_STATE.STILL)
	local flags = sanitizeInteger(flagsRaw, 0, FLAGS_MASK, 0)
	return bit32.bor(
		fill,
		bit32.lshift(liquidType, TYPE_SHIFT),
		bit32.lshift(flowState, FLOW_SHIFT),
		bit32.lshift(flags, FLAGS_SHIFT)
	)
end

function LiquidCell.unpack(cellRaw: any): (number, number, number, number)
	local packed = if isFiniteNumber(cellRaw) then math.max(0, math.floor(cellRaw)) else 0
	if packed <= 0 then
		return LiquidServiceUtils.LIQUID_TYPE.NONE, 0, LiquidServiceUtils.FLOW_STATE.STILL, 0
	end
	local fill = bit32.band(packed, UINT8_MASK)
	local liquidType = bit32.band(bit32.rshift(packed, TYPE_SHIFT), TYPE_MASK)
	local flowState = bit32.band(bit32.rshift(packed, FLOW_SHIFT), FLOW_MASK)
	local flags = bit32.band(bit32.rshift(packed, FLAGS_SHIFT), FLAGS_MASK)
	if liquidType == LiquidServiceUtils.LIQUID_TYPE.NONE or fill <= 0 then
		return LiquidServiceUtils.LIQUID_TYPE.NONE, 0, LiquidServiceUtils.FLOW_STATE.STILL, 0
	end
	return liquidType, fill, flowState, flags
end

function LiquidCell.getType(cellRaw: any): number
	local liquidType = select(1, LiquidCell.unpack(cellRaw))
	return liquidType
end

function LiquidCell.getFill(cellRaw: any): number
	local fill = select(2, LiquidCell.unpack(cellRaw))
	return fill
end

function LiquidCell.getFlowState(cellRaw: any): number
	local flowState = select(3, LiquidCell.unpack(cellRaw))
	return flowState
end

function LiquidCell.isEmpty(cellRaw: any): boolean
	return LiquidCell.getFill(cellRaw) <= 0 or LiquidCell.getType(cellRaw) == LiquidServiceUtils.LIQUID_TYPE.NONE
end

function LiquidCell.isFull(cellRaw: any, maxFillRaw: any?): boolean
	local maxFill = sanitizeInteger(maxFillRaw, 1, MAX_FILL, MAX_FILL)
	return LiquidCell.getFill(cellRaw) >= maxFill
end

function LiquidCell.withFill(cellRaw: any, fillRaw: any): number
	local liquidType, _, flowState, flags = LiquidCell.unpack(cellRaw)
	return LiquidCell.pack(liquidType, fillRaw, flowState, flags)
end

function LiquidCell.withFlowState(cellRaw: any, flowStateRaw: any): number
	local liquidType, fill, _, flags = LiquidCell.unpack(cellRaw)
	return LiquidCell.pack(liquidType, fill, flowStateRaw, flags)
end

function LiquidCell.make(liquidTypeRaw: any, fillRaw: any, flowStateRaw: any?): number
	return LiquidCell.pack(liquidTypeRaw, fillRaw, flowStateRaw or LiquidServiceUtils.FLOW_STATE.STILL, 0)
end

LiquidServiceUtils.LiquidCell = LiquidCell

local function createDefaultDefinitions(): { [number]: LiquidDefinition }
	return {
		[LiquidServiceUtils.LIQUID_TYPE.WATER] = {
			id = LiquidServiceUtils.LIQUID_TYPE.WATER,
			name = "Water",
			baseColor = (DEFAULT_LIQUID_COLOR_DEFINITIONS[LiquidServiceUtils.LIQUID_TYPE.WATER] or {}).baseColor
				or Color3.fromRGB(74, 174, 225),
			surfaceColor = (DEFAULT_LIQUID_COLOR_DEFINITIONS[LiquidServiceUtils.LIQUID_TYPE.WATER] or {}).surfaceColor
				or Color3.fromRGB(124, 216, 245),
			movementSpeedMultiplier = 0.72,
			material = Enum.Material.SmoothPlastic,
			interiorTransparency = 0.35,
			surfaceTransparency = 0.22,
			sideEqualizeRate = 1,
			maxSideTransfer = 96,
			settleEpsilon = 1,
			renderPriority = 1,
			blocksBreathing = true,
			supportsDrowning = true,
			isBurning = false,
			lavaTouchDamage = 0,
			lavaTouchInterval = 0.35,
			burnDamage = 0,
			burnInterval = 0.5,
			burnDuration = 0,
			tintStrength = 0.72,
			lavaAmbientTintStrength = 0,
		},
		[LiquidServiceUtils.LIQUID_TYPE.LAVA] = {
			id = LiquidServiceUtils.LIQUID_TYPE.LAVA,
			name = "Lava",
			baseColor = (DEFAULT_LIQUID_COLOR_DEFINITIONS[LiquidServiceUtils.LIQUID_TYPE.LAVA] or {}).baseColor
				or Color3.fromRGB(246, 104, 31),
			surfaceColor = (DEFAULT_LIQUID_COLOR_DEFINITIONS[LiquidServiceUtils.LIQUID_TYPE.LAVA] or {}).surfaceColor
				or Color3.fromRGB(255, 187, 76),
			movementSpeedMultiplier = 0.3,
			material = Enum.Material.Neon,
			interiorTransparency = 0.1,
			surfaceTransparency = 0.03,
			sideEqualizeRate = 0.38,
			maxSideTransfer = 36,
			settleEpsilon = 2,
			renderPriority = 2,
			blocksBreathing = false,
			supportsDrowning = false,
			isBurning = true,
			lavaTouchDamage = 58,
			lavaTouchInterval = 0.35,
			burnDamage = 8,
			burnInterval = 0.5,
			burnDuration = 2.5,
			tintStrength = 0,
			lavaAmbientTintStrength = 0.18,
		},
	}
end

local function sanitizeDefinition(liquidType: number, sourceRaw: any, fallback: LiquidDefinition): LiquidDefinition
	local source = if typeof(sourceRaw) == "table" then sourceRaw else {}
	return {
		id = liquidType,
		name = if typeof(source.name) == "string" and source.name ~= "" then source.name else fallback.name,
		baseColor = sanitizeColor3(source.baseColor, fallback.baseColor),
		surfaceColor = sanitizeColor3(source.surfaceColor, fallback.surfaceColor),
		movementSpeedMultiplier = sanitizeNumber(
			source.movementSpeedMultiplier,
			0.05,
			1,
			fallback.movementSpeedMultiplier
		),
		material = if typeof(source.material) == "EnumItem" and source.material.EnumType == Enum.Material
			then source.material
			else fallback.material,
		interiorTransparency = sanitizeNumber(source.interiorTransparency, 0, 1, fallback.interiorTransparency),
		surfaceTransparency = sanitizeNumber(source.surfaceTransparency, 0, 1, fallback.surfaceTransparency),
		sideEqualizeRate = sanitizeNumber(source.sideEqualizeRate, 0.05, 1, fallback.sideEqualizeRate),
		maxSideTransfer = sanitizeInteger(source.maxSideTransfer, 1, MAX_FILL, fallback.maxSideTransfer),
		settleEpsilon = sanitizeInteger(source.settleEpsilon, 0, 16, fallback.settleEpsilon),
		renderPriority = sanitizeInteger(source.renderPriority, 0, 16, fallback.renderPriority),
		blocksBreathing = if typeof(source.blocksBreathing) == "boolean"
			then source.blocksBreathing
			else fallback.blocksBreathing,
		supportsDrowning = if typeof(source.supportsDrowning) == "boolean"
			then source.supportsDrowning
			else fallback.supportsDrowning,
		isBurning = if typeof(source.isBurning) == "boolean" then source.isBurning else fallback.isBurning,
		lavaTouchDamage = sanitizeNumber(source.lavaTouchDamage, 0, 500, fallback.lavaTouchDamage),
		lavaTouchInterval = sanitizeNumber(source.lavaTouchInterval, 0.05, 5, fallback.lavaTouchInterval),
		burnDamage = sanitizeNumber(source.burnDamage, 0, 500, fallback.burnDamage),
		burnInterval = sanitizeNumber(source.burnInterval, 0.05, 5, fallback.burnInterval),
		burnDuration = sanitizeNumber(source.burnDuration, 0, 120, fallback.burnDuration),
		tintStrength = sanitizeNumber(source.tintStrength, 0, 1, fallback.tintStrength),
		lavaAmbientTintStrength = sanitizeNumber(
			source.lavaAmbientTintStrength,
			0,
			1,
			fallback.lavaAmbientTintStrength
		),
	}
end

function LiquidServiceUtils.createDefaultConfig(): LiquidServiceConfig
	return {
		maxFill = MAX_FILL,
		simulation = {
			stepRate = 12,
			hazardCheckRate = 8,
			streamSyncInterval = 0.12,
			activeSafetyMarginChunks = 1,
			disturbedChunkKeepAliveSeconds = 8,
			maxChunkStepsPerTick = 12,
			maxCellsPerChunkStep = 96,
			maxWakeRequestsPerTick = 192,
			maxDeltaCellsPerChunk = 256,
			fullSnapshotThreshold = 160,
			generationSettlePasses = 10,
			leakScanDistanceTiles = 96,
			consistencySweepInterval = 0.9,
			consistencySweepChunkBudget = 12,
		},
		generation = {
			depressionScanRadius = 6,
			surfacePoolChance = 0.92,
			surfacePoolMinDepth = 2,
			surfacePoolMaxDepth = 8,
			surfacePoolFillChance = 1,
			cavePocketChance = 0.018,
			cavePocketMinDepth = 8,
			cavePocketMaxDepth = 90,
			cavePocketMinRadius = 2,
			cavePocketMaxRadius = 5,
			reservoirChance = 0.011,
			reservoirMinDepth = 24,
			reservoirMaxDepth = 160,
			reservoirMinRadius = 4,
			reservoirMaxRadius = 9,
			lavaStartDepth = 44,
			lavaCommonDepth = 92,
			lavaPocketChance = 0.013,
			lavaReservoirChance = 0.009,
			lavaPocketMinRadius = 3,
			lavaPocketMaxRadius = 8,
		},
		render = {
			interpolationTime = DEFAULT_LIQUID_INTERPOLATION_TIME,
			surfaceWaveAmplitudeStuds = 0.08,
			surfaceWaveSpeed = 1.9,
			surfaceWaveScale = 0.45,
			rebuildRowsPerFrame = 8,
			rebuildFlushInterval = 1 / 30,
			minVisibleFill = DEFAULT_MIN_VISIBLE_FILL,
			fillBucketSize = DEFAULT_FILL_BUCKET_SIZE,
		},
		definitions = createDefaultDefinitions(),
		biomeTints = {
			byBiomeId = cloneColor3Map(DEFAULT_LIQUID_BIOME_TINTS.byBiomeId),
			byBiomeType = cloneColor3Map(DEFAULT_LIQUID_BIOME_TINTS.byBiomeType),
			lavaAmbientByBiomeId = cloneColor3Map(DEFAULT_LIQUID_BIOME_TINTS.lavaAmbientByBiomeId),
			lavaAmbientByBiomeType = cloneColor3Map(DEFAULT_LIQUID_BIOME_TINTS.lavaAmbientByBiomeType),
		},
		debug = {
			enabled = false,
			logActivations = false,
			logDirtyMarks = false,
			logSimulationSteps = false,
			logStableTransitions = false,
			visualizeChunks = false,
			visualizeCells = false,
		},
	}
end

function LiquidServiceUtils.sanitizeConfig(configRaw: any, fallbackRaw: LiquidServiceConfig?): LiquidServiceConfig
	local fallback = if fallbackRaw ~= nil then fallbackRaw else LiquidServiceUtils.createDefaultConfig()
	local source = if typeof(configRaw) == "table" then configRaw else {}
	local definitions: { [number]: LiquidDefinition } = {}
	local definitionSource = if typeof(source.definitions) == "table" then source.definitions else {}
	for liquidType, fallbackDefinition in fallback.definitions do
		local sourceDefinition = if typeof(definitionSource) == "table" then definitionSource[liquidType] else nil
		definitions[liquidType] = sanitizeDefinition(liquidType, sourceDefinition, fallbackDefinition)
	end

	local simulationSource = if typeof(source.simulation) == "table" then source.simulation else {}
	local generationSource = if typeof(source.generation) == "table" then source.generation else {}
	local renderSource = if typeof(source.render) == "table" then source.render else {}
	local biomeTintsSource = if typeof(source.biomeTints) == "table" then source.biomeTints else {}
	local debugSource = if typeof(source.debug) == "table" then source.debug else {}

	return {
		maxFill = sanitizeInteger(source.maxFill, 32, MAX_FILL, fallback.maxFill),
		simulation = {
			stepRate = sanitizeNumber(simulationSource.stepRate, 1, 60, fallback.simulation.stepRate),
			hazardCheckRate = sanitizeNumber(
				simulationSource.hazardCheckRate,
				1,
				60,
				fallback.simulation.hazardCheckRate
			),
			streamSyncInterval = sanitizeNumber(
				simulationSource.streamSyncInterval,
				0.03,
				2,
				fallback.simulation.streamSyncInterval
			),
			activeSafetyMarginChunks = sanitizeInteger(
				simulationSource.activeSafetyMarginChunks,
				0,
				4,
				fallback.simulation.activeSafetyMarginChunks
			),
			disturbedChunkKeepAliveSeconds = sanitizeNumber(
				simulationSource.disturbedChunkKeepAliveSeconds,
				0,
				60,
				fallback.simulation.disturbedChunkKeepAliveSeconds
			),
			maxChunkStepsPerTick = sanitizeInteger(
				simulationSource.maxChunkStepsPerTick,
				1,
				128,
				fallback.simulation.maxChunkStepsPerTick
			),
			maxCellsPerChunkStep = sanitizeInteger(
				simulationSource.maxCellsPerChunkStep,
				4,
				2048,
				fallback.simulation.maxCellsPerChunkStep
			),
			maxWakeRequestsPerTick = sanitizeInteger(
				simulationSource.maxWakeRequestsPerTick,
				4,
				4096,
				fallback.simulation.maxWakeRequestsPerTick
			),
			maxDeltaCellsPerChunk = sanitizeInteger(
				simulationSource.maxDeltaCellsPerChunk,
				8,
				4096,
				fallback.simulation.maxDeltaCellsPerChunk
			),
			fullSnapshotThreshold = sanitizeInteger(
				simulationSource.fullSnapshotThreshold,
				8,
				4096,
				fallback.simulation.fullSnapshotThreshold
			),
			generationSettlePasses = sanitizeInteger(
				simulationSource.generationSettlePasses,
				0,
				128,
				fallback.simulation.generationSettlePasses
			),
			leakScanDistanceTiles = sanitizeInteger(
				simulationSource.leakScanDistanceTiles,
				4,
				256,
				fallback.simulation.leakScanDistanceTiles
			),
			consistencySweepInterval = sanitizeNumber(
				simulationSource.consistencySweepInterval,
				0.1,
				30,
				fallback.simulation.consistencySweepInterval
			),
			consistencySweepChunkBudget = sanitizeInteger(
				simulationSource.consistencySweepChunkBudget,
				1,
				256,
				fallback.simulation.consistencySweepChunkBudget
			),
		},
		generation = {
			depressionScanRadius = sanitizeInteger(
				generationSource.depressionScanRadius,
				2,
				24,
				fallback.generation.depressionScanRadius
			),
			surfacePoolChance = sanitizeNumber(
				generationSource.surfacePoolChance,
				0,
				1,
				fallback.generation.surfacePoolChance
			),
			surfacePoolMinDepth = sanitizeInteger(
				generationSource.surfacePoolMinDepth,
				1,
				16,
				fallback.generation.surfacePoolMinDepth
			),
			surfacePoolMaxDepth = sanitizeInteger(
				generationSource.surfacePoolMaxDepth,
				1,
				24,
				fallback.generation.surfacePoolMaxDepth
			),
			surfacePoolFillChance = sanitizeNumber(
				generationSource.surfacePoolFillChance,
				0,
				1,
				fallback.generation.surfacePoolFillChance
			),
			cavePocketChance = sanitizeNumber(
				generationSource.cavePocketChance,
				0,
				1,
				fallback.generation.cavePocketChance
			),
			cavePocketMinDepth = sanitizeInteger(
				generationSource.cavePocketMinDepth,
				0,
				512,
				fallback.generation.cavePocketMinDepth
			),
			cavePocketMaxDepth = sanitizeInteger(
				generationSource.cavePocketMaxDepth,
				0,
				512,
				fallback.generation.cavePocketMaxDepth
			),
			cavePocketMinRadius = sanitizeInteger(
				generationSource.cavePocketMinRadius,
				1,
				16,
				fallback.generation.cavePocketMinRadius
			),
			cavePocketMaxRadius = sanitizeInteger(
				generationSource.cavePocketMaxRadius,
				1,
				24,
				fallback.generation.cavePocketMaxRadius
			),
			reservoirChance = sanitizeNumber(
				generationSource.reservoirChance,
				0,
				1,
				fallback.generation.reservoirChance
			),
			reservoirMinDepth = sanitizeInteger(
				generationSource.reservoirMinDepth,
				0,
				512,
				fallback.generation.reservoirMinDepth
			),
			reservoirMaxDepth = sanitizeInteger(
				generationSource.reservoirMaxDepth,
				0,
				512,
				fallback.generation.reservoirMaxDepth
			),
			reservoirMinRadius = sanitizeInteger(
				generationSource.reservoirMinRadius,
				1,
				24,
				fallback.generation.reservoirMinRadius
			),
			reservoirMaxRadius = sanitizeInteger(
				generationSource.reservoirMaxRadius,
				1,
				32,
				fallback.generation.reservoirMaxRadius
			),
			lavaStartDepth = sanitizeInteger(
				generationSource.lavaStartDepth,
				0,
				1024,
				fallback.generation.lavaStartDepth
			),
			lavaCommonDepth = sanitizeInteger(
				generationSource.lavaCommonDepth,
				0,
				1024,
				fallback.generation.lavaCommonDepth
			),
			lavaPocketChance = sanitizeNumber(
				generationSource.lavaPocketChance,
				0,
				1,
				fallback.generation.lavaPocketChance
			),
			lavaReservoirChance = sanitizeNumber(
				generationSource.lavaReservoirChance,
				0,
				1,
				fallback.generation.lavaReservoirChance
			),
			lavaPocketMinRadius = sanitizeInteger(
				generationSource.lavaPocketMinRadius,
				1,
				24,
				fallback.generation.lavaPocketMinRadius
			),
			lavaPocketMaxRadius = sanitizeInteger(
				generationSource.lavaPocketMaxRadius,
				1,
				32,
				fallback.generation.lavaPocketMaxRadius
			),
		},
		render = {
			interpolationTime = sanitizeNumber(
				renderSource.interpolationTime,
				0.03,
				2,
				fallback.render.interpolationTime
			),
			surfaceWaveAmplitudeStuds = sanitizeNumber(
				renderSource.surfaceWaveAmplitudeStuds,
				0,
				1,
				fallback.render.surfaceWaveAmplitudeStuds
			),
			surfaceWaveSpeed = sanitizeNumber(renderSource.surfaceWaveSpeed, 0, 16, fallback.render.surfaceWaveSpeed),
			surfaceWaveScale = sanitizeNumber(renderSource.surfaceWaveScale, 0.01, 8, fallback.render.surfaceWaveScale),
			rebuildRowsPerFrame = sanitizeInteger(
				renderSource.rebuildRowsPerFrame,
				1,
				64,
				fallback.render.rebuildRowsPerFrame
			),
			rebuildFlushInterval = sanitizeNumber(
				renderSource.rebuildFlushInterval,
				1 / 240,
				1,
				fallback.render.rebuildFlushInterval
			),
			minVisibleFill = sanitizeInteger(renderSource.minVisibleFill, 1, MAX_FILL, fallback.render.minVisibleFill),
			fillBucketSize = sanitizeInteger(renderSource.fillBucketSize, 1, 64, fallback.render.fillBucketSize),
		},
		definitions = definitions,
		biomeTints = {
			byBiomeId = if next(cloneColor3Map(biomeTintsSource.byBiomeId)) ~= nil
				then cloneColor3Map(biomeTintsSource.byBiomeId)
				else cloneColor3Map(fallback.biomeTints.byBiomeId),
			byBiomeType = if next(cloneColor3Map(biomeTintsSource.byBiomeType)) ~= nil
				then cloneColor3Map(biomeTintsSource.byBiomeType)
				else cloneColor3Map(fallback.biomeTints.byBiomeType),
			lavaAmbientByBiomeId = if next(cloneColor3Map(biomeTintsSource.lavaAmbientByBiomeId)) ~= nil
				then cloneColor3Map(biomeTintsSource.lavaAmbientByBiomeId)
				else cloneColor3Map(fallback.biomeTints.lavaAmbientByBiomeId),
			lavaAmbientByBiomeType = if next(cloneColor3Map(biomeTintsSource.lavaAmbientByBiomeType)) ~= nil
				then cloneColor3Map(biomeTintsSource.lavaAmbientByBiomeType)
				else cloneColor3Map(fallback.biomeTints.lavaAmbientByBiomeType),
		},
		debug = {
			enabled = if typeof(debugSource.enabled) == "boolean" then debugSource.enabled else fallback.debug.enabled,
			logActivations = if typeof(debugSource.logActivations) == "boolean"
				then debugSource.logActivations
				else fallback.debug.logActivations,
			logDirtyMarks = if typeof(debugSource.logDirtyMarks) == "boolean"
				then debugSource.logDirtyMarks
				else fallback.debug.logDirtyMarks,
			logSimulationSteps = if typeof(debugSource.logSimulationSteps) == "boolean"
				then debugSource.logSimulationSteps
				else fallback.debug.logSimulationSteps,
			logStableTransitions = if typeof(debugSource.logStableTransitions) == "boolean"
				then debugSource.logStableTransitions
				else fallback.debug.logStableTransitions,
			visualizeChunks = if typeof(debugSource.visualizeChunks) == "boolean"
				then debugSource.visualizeChunks
				else fallback.debug.visualizeChunks,
			visualizeCells = if typeof(debugSource.visualizeCells) == "boolean"
				then debugSource.visualizeCells
				else fallback.debug.visualizeCells,
		},
	}
end

function LiquidServiceUtils.createDefaultState(): LiquidServiceState
	return {
		ready = false,
		tileSize = 2,
		chunkSize = 32,
		worldOrigin = Vector3.zero,
		maxFill = MAX_FILL,
		interpolationTime = DEFAULT_LIQUID_INTERPOLATION_TIME,
		updatedAt = os.clock(),
	}
end

function LiquidServiceUtils.createState(stateRaw: any, fallbackRaw: LiquidServiceState?): LiquidServiceState
	local fallback = if fallbackRaw ~= nil then fallbackRaw else LiquidServiceUtils.createDefaultState()
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	return {
		ready = if typeof(source.ready) == "boolean" then source.ready else fallback.ready,
		tileSize = sanitizeNumber(source.tileSize, 0.05, 64, fallback.tileSize),
		chunkSize = sanitizeInteger(source.chunkSize, 1, 256, fallback.chunkSize),
		worldOrigin = if typeof(source.worldOrigin) == "Vector3" then source.worldOrigin else fallback.worldOrigin,
		maxFill = sanitizeInteger(source.maxFill, 1, MAX_FILL, fallback.maxFill),
		interpolationTime = sanitizeNumber(source.interpolationTime, 0.03, 2, fallback.interpolationTime),
		updatedAt = os.clock(),
	}
end

function LiquidServiceUtils.cloneState(state: LiquidServiceState): LiquidServiceState
	return {
		ready = state.ready,
		tileSize = state.tileSize,
		chunkSize = state.chunkSize,
		worldOrigin = state.worldOrigin,
		maxFill = state.maxFill,
		interpolationTime = state.interpolationTime,
		updatedAt = state.updatedAt,
	}
end

function LiquidServiceUtils.getDefinition(configRaw: LiquidServiceConfig?, liquidTypeRaw: any): LiquidDefinition?
	local config = if configRaw ~= nil then configRaw else LiquidServiceUtils.createDefaultConfig()
	local liquidType = sanitizeInteger(liquidTypeRaw, LiquidServiceUtils.LIQUID_TYPE.NONE, 7, 0)
	return config.definitions[liquidType]
end

local LiquidColor = {}

function LiquidColor.resolveWaterTint(config: LiquidServiceConfig, biomeIdRaw: any, biomeTypeRaw: any): Color3
	local definitions = config.definitions
	local waterDefinition = definitions[LiquidServiceUtils.LIQUID_TYPE.WATER]
	local baseColor = if waterDefinition ~= nil then waterDefinition.baseColor else Color3.fromRGB(74, 174, 225)
	local biomeId = sanitizeInteger(biomeIdRaw, -2048, 2048, 1)
	local biomeType = sanitizeInteger(biomeTypeRaw, -2048, 2048, 1)
	local typeColor = config.biomeTints.byBiomeType[biomeType]
	local biomeColor = config.biomeTints.byBiomeId[biomeId]
	local blended = baseColor
	if typeColor ~= nil then
		blended = lerpColor(blended, typeColor, 0.45)
	end
	if biomeColor ~= nil then
		blended = lerpColor(blended, biomeColor, 0.65)
	end
	return blended
end

function LiquidColor.resolveLavaAmbientTint(config: LiquidServiceConfig, biomeIdRaw: any, biomeTypeRaw: any): Color3?
	local biomeId = sanitizeInteger(biomeIdRaw, -2048, 2048, 1)
	local biomeType = sanitizeInteger(biomeTypeRaw, -2048, 2048, 1)
	local typeColor = config.biomeTints.lavaAmbientByBiomeType[biomeType]
	local biomeColor = config.biomeTints.lavaAmbientByBiomeId[biomeId]
	if typeColor == nil and biomeColor == nil then
		return nil
	end
	if typeColor ~= nil and biomeColor ~= nil then
		return lerpColor(typeColor, biomeColor, 0.5)
	end
	return if biomeColor ~= nil then biomeColor else typeColor
end

function LiquidColor.sampleWaterColorAtWorldPosition(
	config: LiquidServiceConfig,
	worldPosition: Vector3,
	tileSize: number,
	worldOrigin: Vector3,
	sampleBiomeAtTile: (tileX: number, tileY: number) -> (number, number)
): Color3
	local localTileX = (worldPosition.Z - worldOrigin.Z) / math.max(0.001, tileSize)
	local localTileY = (worldPosition.Y - worldOrigin.Y) / math.max(0.001, tileSize)
	local tileX0 = math.floor(localTileX)
	local tileY0 = math.floor(localTileY)
	local fracX = localTileX - tileX0
	local fracY = localTileY - tileY0

	local biomeId00, biomeType00 = sampleBiomeAtTile(tileX0, tileY0)
	local biomeId10, biomeType10 = sampleBiomeAtTile(tileX0 + 1, tileY0)
	local biomeId01, biomeType01 = sampleBiomeAtTile(tileX0, tileY0 + 1)
	local biomeId11, biomeType11 = sampleBiomeAtTile(tileX0 + 1, tileY0 + 1)

	local color00 = LiquidColor.resolveWaterTint(config, biomeId00, biomeType00)
	local color10 = LiquidColor.resolveWaterTint(config, biomeId10, biomeType10)
	local color01 = LiquidColor.resolveWaterTint(config, biomeId01, biomeType01)
	local color11 = LiquidColor.resolveWaterTint(config, biomeId11, biomeType11)

	local top = lerpColor(color00, color10, fracX)
	local bottom = lerpColor(color01, color11, fracX)
	return lerpColor(top, bottom, fracY)
end

function LiquidColor.resolveLiquidColor(
	config: LiquidServiceConfig,
	liquidTypeRaw: any,
	biomeIdRaw: any,
	biomeTypeRaw: any
): Color3
	local liquidType = sanitizeInteger(liquidTypeRaw, 0, 7, 0)
	local definition = config.definitions[liquidType]
	if definition == nil then
		return Color3.fromRGB(255, 255, 255)
	end
	if liquidType == LiquidServiceUtils.LIQUID_TYPE.WATER then
		return LiquidColor.resolveWaterTint(config, biomeIdRaw, biomeTypeRaw)
	end
	if liquidType == LiquidServiceUtils.LIQUID_TYPE.LAVA then
		local ambientTint = LiquidColor.resolveLavaAmbientTint(config, biomeIdRaw, biomeTypeRaw)
		if ambientTint ~= nil then
			return lerpColor(definition.baseColor, ambientTint, definition.lavaAmbientTintStrength)
		end
	end
	return definition.baseColor
end

LiquidServiceUtils.LiquidColor = LiquidColor

local LiquidMesher = {}

local FOREGROUND_TILE_AIR_ID = 0

local function isOpenInBackgroundLayer(
	layerData: LiquidBackgroundLayerSource,
	worldTileX: number,
	worldTileY: number
): boolean
	local localX = worldTileX - layerData.tileMinX
	local localY = worldTileY - layerData.tileMinY
	if localX < 0 or localX >= layerData.width or localY < 0 or localY >= layerData.height then
		return false
	end
	local layerIndex = LiquidServiceUtils.computeTileIndex(localX, localY, layerData.width)
	return (layerData.tiles[layerIndex] or FOREGROUND_TILE_AIR_ID) == FOREGROUND_TILE_AIR_ID
end

function LiquidMesher.buildBackgroundVisualCells(
	config: LiquidServiceConfig,
	sourceCellsRaw: any,
	tileMinXRaw: any,
	tileMinYRaw: any,
	widthRaw: any,
	heightRaw: any,
	layerDataRaw: any,
	layerListIndexRaw: any
): { number }
	local width = sanitizeInteger(widthRaw, 1, 512, 1)
	local height = sanitizeInteger(heightRaw, 1, 512, 1)
	local tileMinX = sanitizeInteger(tileMinXRaw, -10000000, 10000000, 0)
	local tileMinY = sanitizeInteger(tileMinYRaw, -10000000, 10000000, 0)
	local layerListIndex = sanitizeInteger(layerListIndexRaw, 1, 64, 1)
	local total = width * height
	local derivedCells = table.create(total, 0)
	local sourceCells = if typeof(sourceCellsRaw) == "table" then sourceCellsRaw :: { number } else nil
	if sourceCells == nil then
		return derivedCells
	end
	if typeof(layerDataRaw) ~= "table" then
		return derivedCells
	end

	local layerSource = layerDataRaw :: { [string]: any }
	local layerWidth = sanitizeInteger(layerSource.width, 1, 512, width)
	local layerHeight = sanitizeInteger(layerSource.height, 1, 512, height)
	local layerData: LiquidBackgroundLayerSource = {
		tileMinX = sanitizeInteger(layerSource.tileMinX, -10000000, 10000000, tileMinX),
		tileMinY = sanitizeInteger(layerSource.tileMinY, -10000000, 10000000, tileMinY),
		width = layerWidth,
		height = layerHeight,
		tiles = if typeof(layerSource.tiles) == "table" then layerSource.tiles :: { number } else {},
	}
	local minVisibleFill = math.max(1, config.render.minVisibleFill)
	local maxLateralSpread = math.max(0, math.min(3, layerListIndex - 1))

	local queueLocalX = table.create(total)
	local queueLocalY = table.create(total)
	local queueType = table.create(total)
	local queueFill = table.create(total)
	local queueDistance = table.create(total)
	local queueHead = 1
	local queueTail = 0

	local function tryOccupy(
		localX: number,
		localY: number,
		liquidType: number,
		fill: number,
		distance: number
	): boolean
		if localX < 0 or localX >= width or localY < 0 or localY >= height then
			return false
		end
		if liquidType == LiquidServiceUtils.LIQUID_TYPE.NONE or fill < minVisibleFill then
			return false
		end
		local targetIndex = LiquidServiceUtils.computeTileIndex(localX, localY, width)
		if derivedCells[targetIndex] ~= 0 then
			return false
		end
		local worldTileX = tileMinX + localX
		local worldTileY = tileMinY + localY
		if not isOpenInBackgroundLayer(layerData, worldTileX, worldTileY) then
			return false
		end
		derivedCells[targetIndex] = LiquidCell.make(liquidType, fill, LiquidServiceUtils.FLOW_STATE.STILL)
		queueTail += 1
		queueLocalX[queueTail] = localX
		queueLocalY[queueTail] = localY
		queueType[queueTail] = liquidType
		queueFill[queueTail] = fill
		queueDistance[queueTail] = distance
		return true
	end

	for localY = 0, height - 1 do
		for localX = 0, width - 1 do
			local index = LiquidServiceUtils.computeTileIndex(localX, localY, width)
			local liquidType, fill = LiquidCell.unpack(sourceCells[index] or 0)
			if liquidType ~= LiquidServiceUtils.LIQUID_TYPE.NONE and fill >= minVisibleFill then
				tryOccupy(localX, localY, liquidType, fill, 0)
			end
		end
	end

	while queueHead <= queueTail do
		local localX = queueLocalX[queueHead]
		local localY = queueLocalY[queueHead]
		local liquidType = queueType[queueHead]
		local fill = queueFill[queueHead]
		local distance = queueDistance[queueHead]
		queueHead += 1

		if distance >= maxLateralSpread then
			continue
		end

		tryOccupy(localX - 1, localY, liquidType, fill, distance + 1)
		tryOccupy(localX + 1, localY, liquidType, fill, distance + 1)
	end

	return derivedCells
end

function LiquidMesher.buildRowDescriptors(
	config: LiquidServiceConfig,
	cells: { number },
	width: number,
	height: number,
	rowYRaw: any
): { LiquidStripDescriptor }
	local rowY = sanitizeInteger(rowYRaw, 0, math.max(0, height - 1), 0)
	local descriptors: { LiquidStripDescriptor } = {}
	local fillBucketSize = math.max(1, config.render.fillBucketSize)
	local minVisibleFill = math.max(1, config.render.minVisibleFill)

	local activeType = LiquidServiceUtils.LIQUID_TYPE.NONE
	local activeStartX = -1
	local activeFillBucket = -1
	local activeIsSurface = false
	local activeFill = 0

	local function flush(currentXExclusive: number)
		if activeType == LiquidServiceUtils.LIQUID_TYPE.NONE or activeStartX < 0 then
			return
		end
		local endX = currentXExclusive - 1
		local fillAlpha = math.clamp(activeFill / math.max(1, config.maxFill), 0, 1)
		table.insert(descriptors, {
			key = `{activeType}:{rowY}:{activeStartX}:{endX}:{activeFillBucket}:{if activeIsSurface then 1 else 0}`,
			typeId = activeType,
			rowY = rowY,
			startX = activeStartX,
			endX = endX,
			widthTiles = endX - activeStartX + 1,
			fill = activeFill,
			fillAlpha = fillAlpha,
			isSurface = activeIsSurface,
		})
		activeType = LiquidServiceUtils.LIQUID_TYPE.NONE
		activeStartX = -1
		activeFillBucket = -1
		activeIsSurface = false
		activeFill = 0
	end

	for localX = 0, width - 1 do
		local index = LiquidServiceUtils.computeTileIndex(localX, rowY, width)
		local packedCell = cells[index] or 0
		local liquidType, fill = LiquidCell.unpack(packedCell)
		local isVisible = liquidType ~= LiquidServiceUtils.LIQUID_TYPE.NONE and fill >= minVisibleFill
		local cellIsSurface = false
		if isVisible then
			local aboveIndex = if rowY + 1 < height
				then LiquidServiceUtils.computeTileIndex(localX, rowY + 1, width)
				else nil
			local aboveType, aboveFill = LiquidServiceUtils.LIQUID_TYPE.NONE, 0
			if aboveIndex ~= nil then
				aboveType, aboveFill = LiquidCell.unpack(cells[aboveIndex] or 0)
			end
			cellIsSurface = aboveType ~= liquidType or aboveFill < config.maxFill - DEFAULT_FLOW_SETTLE_EPSILON
		end

		local fillBucket = if cellIsSurface
			then math.floor(fill / fillBucketSize)
			else math.floor(config.maxFill / fillBucketSize)
		if not isVisible then
			flush(localX)
			continue
		end

		local canMerge = activeType == liquidType
			and activeFillBucket == fillBucket
			and activeIsSurface == cellIsSurface
		if not canMerge then
			flush(localX)
			activeType = liquidType
			activeStartX = localX
			activeFillBucket = fillBucket
			activeIsSurface = cellIsSurface
			activeFill = fill
		else
			activeFill = math.max(activeFill, fill)
		end
	end

	flush(width)
	return descriptors
end

function LiquidMesher.getAffectedRowsForChanges(width: number, height: number, changedIndices: { number }): { number }
	local rowsLookup: { [number]: boolean } = {}
	local rows: { number } = {}
	for _, index in changedIndices do
		if not isFiniteNumber(index) then
			continue
		end
		local zeroBasedIndex = math.max(0, math.floor(index) - 1)
		local rowY = math.floor(zeroBasedIndex / math.max(1, width))
		for _, affectedRow in { rowY - 1, rowY, rowY + 1 } do
			if affectedRow < 0 or affectedRow >= height then
				continue
			end
			if rowsLookup[affectedRow] then
				continue
			end
			rowsLookup[affectedRow] = true
			table.insert(rows, affectedRow)
		end
	end
	table.sort(rows)
	return rows
end

LiquidServiceUtils.LiquidMesher = LiquidMesher

local LiquidQuery = {}

local DEFAULT_SAMPLE_DEFINITIONS = {
	{
		name = "Feet",
		weight = 0.12,
		offset = function(_root: BasePart, height: number): Vector3
			return Vector3.new(0, -height * 0.48, 0)
		end,
	},
	{
		name = "Root",
		weight = 0.22,
		offset = function(_root: BasePart, _height: number): Vector3
			return Vector3.zero
		end,
	},
	{
		name = "Chest",
		weight = 0.28,
		offset = function(_root: BasePart, height: number): Vector3
			return Vector3.new(0, height * 0.22, 0)
		end,
	},
	{
		name = "Head",
		weight = 0.38,
		offset = function(_root: BasePart, height: number): Vector3
			return Vector3.new(0, height * 0.52, 0)
		end,
	},
}

function LiquidQuery.worldToTile(provider: LiquidQueryProvider, worldPosition: Vector3): (number, number)
	local tileSize = math.max(0.001, provider.tileSize)
	local worldOrigin = provider.worldOrigin
	return LiquidServiceUtils.toTileCoordinate(worldPosition.Z - worldOrigin.Z, tileSize),
		LiquidServiceUtils.toTileCoordinate(worldPosition.Y - worldOrigin.Y, tileSize)
end

function LiquidQuery.getSurfaceWorldY(provider: LiquidQueryProvider, tileY: number, fillRaw: any): number
	local fill = sanitizeInteger(fillRaw, 0, MAX_FILL, 0)
	return provider.worldOrigin.Y + tileY * provider.tileSize + (fill / MAX_FILL) * provider.tileSize
end

function LiquidQuery.sampleWorldPoint(
	provider: LiquidQueryProvider,
	name: string,
	worldPosition: Vector3,
	weight: number
): LiquidSamplePoint
	local tileX, tileY = LiquidQuery.worldToTile(provider, worldPosition)
	local packedCell = provider.getCellAt(tileX, tileY)
	local liquidType, fill = LiquidCell.unpack(packedCell)
	local surfaceWorldY = nil :: number?
	local submerged = false
	if liquidType ~= LiquidServiceUtils.LIQUID_TYPE.NONE and fill > 0 then
		local nextSurfaceWorldY = LiquidQuery.getSurfaceWorldY(provider, tileY, fill)
		surfaceWorldY = nextSurfaceWorldY
		submerged = worldPosition.Y <= nextSurfaceWorldY + 0.001
	end
	return {
		name = name,
		worldPosition = worldPosition,
		tileX = tileX,
		tileY = tileY,
		liquidType = liquidType,
		fill = fill,
		submerged = submerged,
		surfaceWorldY = surfaceWorldY,
		weight = weight,
	}
end

function LiquidQuery.queryCharacter(provider: LiquidQueryProvider, characterRaw: any): LiquidQueryResult
	local emptyResult: LiquidQueryResult = {
		inLiquid = false,
		dominantType = LiquidServiceUtils.LIQUID_TYPE.NONE,
		breathingLiquidType = LiquidServiceUtils.LIQUID_TYPE.NONE,
		submersionRatio = 0,
		breathingSubmerged = false,
		meaningfulSubmersion = false,
		surfaceWorldY = nil,
		samples = {},
		typeWeights = {},
	}

	if typeof(characterRaw) ~= "Instance" or not characterRaw:IsA("Model") then
		return emptyResult
	end

	local rootPart = characterRaw:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		rootPart = characterRaw.PrimaryPart
	end
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return emptyResult
	end

	local height = math.max(2, rootPart.Size.Y + 2.5)
	local totalWeight = 0
	local submergedWeight = 0
	local dominantType = LiquidServiceUtils.LIQUID_TYPE.NONE
	local dominantWeight = -1
	local breathingSubmerged = false
	local breathingLiquidType = LiquidServiceUtils.LIQUID_TYPE.NONE
	local surfaceWorldY = nil :: number?
	local typeWeights: { [number]: number } = {}
	local samples: { LiquidSamplePoint } = {}

	for _, sampleDefinition in DEFAULT_SAMPLE_DEFINITIONS do
		local samplePosition = rootPart.Position + sampleDefinition.offset(rootPart, height)
		local sample =
			LiquidQuery.sampleWorldPoint(provider, sampleDefinition.name, samplePosition, sampleDefinition.weight)
		table.insert(samples, sample)
		totalWeight += sample.weight
		if sample.submerged then
			submergedWeight += sample.weight
			typeWeights[sample.liquidType] = (typeWeights[sample.liquidType] or 0) + sample.weight
			if sample.surfaceWorldY ~= nil then
				if surfaceWorldY == nil or sample.surfaceWorldY > surfaceWorldY then
					surfaceWorldY = sample.surfaceWorldY
				end
			end
			local definition = if provider.getLiquidDefinition ~= nil
				then provider.getLiquidDefinition(sample.liquidType)
				else nil
			if
				definition ~= nil
				and definition.blocksBreathing
				and (sample.name == "Head" or sample.name == "Chest")
			then
				breathingSubmerged = true
				if breathingLiquidType == LiquidServiceUtils.LIQUID_TYPE.NONE or sample.name == "Head" then
					breathingLiquidType = sample.liquidType
				end
			end
		end
	end

	for liquidType, weight in typeWeights do
		if weight > dominantWeight then
			dominantWeight = weight
			dominantType = liquidType
		end
	end

	local submersionRatio = if totalWeight > 0 then submergedWeight / totalWeight else 0
	local meaningfulSubmersion = submersionRatio >= 0.34 or breathingSubmerged
	return {
		inLiquid = submergedWeight > 0,
		dominantType = dominantType,
		breathingLiquidType = breathingLiquidType,
		submersionRatio = submersionRatio,
		breathingSubmerged = breathingSubmerged,
		meaningfulSubmersion = meaningfulSubmersion,
		surfaceWorldY = surfaceWorldY,
		samples = samples,
		typeWeights = typeWeights,
	}
end

LiquidServiceUtils.LiquidQuery = LiquidQuery

local LiquidDamage = {}

function LiquidDamage.shouldBlockBreath(config: LiquidServiceConfig, queryResult: LiquidQueryResult): boolean
	local definition = config.definitions[queryResult.breathingLiquidType]
	if definition == nil then
		return false
	end
	return definition.supportsDrowning and queryResult.breathingSubmerged
end

function LiquidDamage.shouldApplyLavaContact(config: LiquidServiceConfig, queryResult: LiquidQueryResult): boolean
	for liquidType, weight in queryResult.typeWeights do
		local definition = config.definitions[liquidType]
		if definition ~= nil and definition.isBurning and weight > 0 then
			return true
		end
	end
	return false
end

function LiquidDamage.getLavaDefinition(config: LiquidServiceConfig): LiquidDefinition?
	return config.definitions[LiquidServiceUtils.LIQUID_TYPE.LAVA]
end

LiquidServiceUtils.LiquidDamage = LiquidDamage

local LiquidSolver = {}
local CELL_DEBUG_STATE = LiquidServiceUtils.CELL_DEBUG_STATE

local function getChunkCoordinatesForTile(access: LiquidSolverAccess, tileX: number, tileY: number): (number, number)
	local chunkSize = math.max(1, access.chunkSize)
	return LiquidServiceUtils.toChunkCoordinate(tileX, chunkSize),
		LiquidServiceUtils.toChunkCoordinate(tileY, chunkSize)
end

local function inspectOccupancy(
	access: LiquidSolverAccess,
	sourceChunkX: number,
	sourceChunkY: number,
	tileX: number,
	tileY: number,
	liquidType: number
)
	local targetChunkX, targetChunkY = getChunkCoordinatesForTile(access, tileX, tileY)
	if
		(targetChunkX ~= sourceChunkX or targetChunkY ~= sourceChunkY)
		and not access.isChunkReady(targetChunkX, targetChunkY)
	then
		return {
			queryable = false,
			canOccupy = false,
			fill = 0,
			blockedBySolid = false,
			waitingOnChunkReady = true,
			dependencyChunkKey = LiquidServiceUtils.packChunkKey(targetChunkX, targetChunkY),
		}
	end
	if access.isSolid(tileX, tileY) then
		return {
			queryable = true,
			canOccupy = false,
			fill = 0,
			blockedBySolid = true,
			waitingOnChunkReady = false,
			dependencyChunkKey = nil,
		}
	end
	local packedCell = access.getCell(tileX, tileY)
	local existingType, existingFill = LiquidCell.unpack(packedCell)
	if existingType ~= LiquidServiceUtils.LIQUID_TYPE.NONE and existingType ~= liquidType then
		return {
			queryable = true,
			canOccupy = false,
			fill = existingFill,
			blockedBySolid = false,
			waitingOnChunkReady = false,
			dependencyChunkKey = nil,
		}
	end
	return {
		queryable = true,
		canOccupy = true,
		fill = existingFill,
		blockedBySolid = false,
		waitingOnChunkReady = false,
		dependencyChunkKey = nil,
	}
end

local function recordMetric(access: LiquidSolverAccess, metricName: string, amountRaw: any?)
	if access.recordMetric ~= nil then
		access.recordMetric(metricName, amountRaw)
	end
end

local function reportCellState(
	access: LiquidSolverAccess,
	tileX: number,
	tileY: number,
	state: string,
	reason: string,
	fill: number,
	liquidType: number
)
	if access.reportCellState ~= nil then
		access.reportCellState(tileX, tileY, state, reason, fill, liquidType)
	end
end

local function addWakeTile(
	wakeTiles: { LiquidTileCoordinate },
	wakeLookup: { [string]: boolean },
	tileX: number,
	tileY: number
)
	local key = `{tileX}:{tileY}`
	if wakeLookup[key] then
		return
	end
	wakeLookup[key] = true
	table.insert(wakeTiles, {
		tileX = tileX,
		tileY = tileY,
	})
end

local function mergeWakeTiles(
	wakeTiles: { LiquidTileCoordinate },
	wakeLookup: { [string]: boolean },
	sourceTiles: { LiquidTileCoordinate }
)
	for _, tile in sourceTiles do
		addWakeTile(wakeTiles, wakeLookup, tile.tileX, tile.tileY)
	end
end

local function getLeakScanDistance(access: LiquidSolverAccess): number
	return sanitizeInteger(access.maxLeakScanDistance, 4, 256, 96)
end

local function wakeTile(
	access: LiquidSolverAccess,
	sourceTileX: number,
	sourceTileY: number,
	tileX: number,
	tileY: number,
	reason: string
)
	access.pushDirty(tileX, tileY, reason, sourceTileX, sourceTileY)
end

local function wakeInspectionTiles(
	access: LiquidSolverAccess,
	sourceTileX: number,
	sourceTileY: number,
	wakeTiles: { LiquidTileCoordinate },
	reason: string
)
	for _, wakeTileEntry in wakeTiles do
		wakeTile(access, sourceTileX, sourceTileY, wakeTileEntry.tileX, wakeTileEntry.tileY, reason)
	end
end

local function scanLeakPath(
	access: LiquidSolverAccess,
	tileX: number,
	tileY: number,
	liquidType: number,
	direction: number
)
	local wakeTiles: { LiquidTileCoordinate } = {}
	local wakeLookup: { [string]: boolean } = {}
	local maxDistance = getLeakScanDistance(access)
	local sourceChunkX, sourceChunkY = getChunkCoordinatesForTile(access, tileX, tileY)

	for distance = 1, maxDistance do
		local scanX = tileX + direction * distance
		local rowOccupancy = inspectOccupancy(access, sourceChunkX, sourceChunkY, scanX, tileY, liquidType)
		if rowOccupancy.waitingOnChunkReady then
			return {
				found = false,
				boundaryDependency = true,
				waitingOnChunkReady = true,
				dependencyChunkKey = rowOccupancy.dependencyChunkKey,
				distance = distance - 1,
				pathTiles = wakeTiles,
				reason = "awaitingCollisionChunk",
			}
		end
		if not rowOccupancy.canOccupy then
			return {
				found = false,
				boundaryDependency = false,
				waitingOnChunkReady = false,
				dependencyChunkKey = nil,
				distance = distance - 1,
				pathTiles = wakeTiles,
				reason = "sealedByWall",
			}
		end

		addWakeTile(wakeTiles, wakeLookup, scanX, tileY)
		local belowOccupancy = inspectOccupancy(access, sourceChunkX, sourceChunkY, scanX, tileY - 1, liquidType)
		if belowOccupancy.waitingOnChunkReady then
			return {
				found = false,
				boundaryDependency = true,
				waitingOnChunkReady = true,
				dependencyChunkKey = belowOccupancy.dependencyChunkKey,
				distance = distance,
				pathTiles = wakeTiles,
				reason = "awaitingCollisionChunkBelow",
			}
		end
		if belowOccupancy.canOccupy and belowOccupancy.fill < access.maxFill then
			addWakeTile(wakeTiles, wakeLookup, scanX, tileY - 1)
			return {
				found = true,
				boundaryDependency = false,
				waitingOnChunkReady = false,
				dependencyChunkKey = nil,
				distance = distance,
				pathTiles = wakeTiles,
				reason = "foundDrop",
			}
		end
	end

	return {
		found = false,
		boundaryDependency = true,
		waitingOnChunkReady = false,
		dependencyChunkKey = nil,
		distance = maxDistance,
		pathTiles = wakeTiles,
		reason = "scanLimitReached",
	}
end

local function inspectCellDetailed(access: LiquidSolverAccess, tileX: number, tileY: number)
	if access.isSolid(tileX, tileY) then
		return {
			hasLiquid = false,
			liquidType = LiquidServiceUtils.LIQUID_TYPE.NONE,
			fill = 0,
			isStable = true,
			state = CELL_DEBUG_STATE.BLOCKED,
			reason = "solidTile",
			canFlowDown = false,
			canEqualize = false,
			hasLeakPath = false,
			boundaryDependency = false,
			waitingOnChunkReady = false,
			dependencyChunkKey = nil,
			preferredDirection = 0,
			leakDistance = 0,
			wakeTiles = {},
			leftCanEqualize = false,
			rightCanEqualize = false,
			leftLeak = nil,
			rightLeak = nil,
			leftNeighborFill = 0,
			rightNeighborFill = 0,
		}
	end

	local packedCell = access.getCell(tileX, tileY)
	local liquidType, fill = LiquidCell.unpack(packedCell)
	if liquidType == LiquidServiceUtils.LIQUID_TYPE.NONE or fill <= 0 then
		return {
			hasLiquid = false,
			liquidType = LiquidServiceUtils.LIQUID_TYPE.NONE,
			fill = 0,
			isStable = true,
			state = CELL_DEBUG_STATE.BLOCKED,
			reason = "emptyCell",
			canFlowDown = false,
			canEqualize = false,
			hasLeakPath = false,
			boundaryDependency = false,
			waitingOnChunkReady = false,
			dependencyChunkKey = nil,
			preferredDirection = 0,
			leakDistance = 0,
			wakeTiles = {},
			leftCanEqualize = false,
			rightCanEqualize = false,
			leftLeak = nil,
			rightLeak = nil,
			leftNeighborFill = 0,
			rightNeighborFill = 0,
		}
	end

	local definition = access.getDefinition(liquidType)
	local wakeTiles: { LiquidTileCoordinate } = {}
	local wakeLookup: { [string]: boolean } = {}
	addWakeTile(wakeTiles, wakeLookup, tileX, tileY)
	local sourceChunkX, sourceChunkY = getChunkCoordinatesForTile(access, tileX, tileY)

	if definition == nil then
		return {
			hasLiquid = true,
			liquidType = liquidType,
			fill = fill,
			isStable = false,
			state = CELL_DEBUG_STATE.ACTIVE,
			reason = "missingDefinition",
			canFlowDown = false,
			canEqualize = false,
			hasLeakPath = false,
			boundaryDependency = false,
			waitingOnChunkReady = false,
			dependencyChunkKey = nil,
			preferredDirection = 0,
			leakDistance = 0,
			wakeTiles = wakeTiles,
			leftCanEqualize = false,
			rightCanEqualize = false,
			leftLeak = nil,
			rightLeak = nil,
			leftNeighborFill = 0,
			rightNeighborFill = 0,
		}
	end

	local belowOccupancy = inspectOccupancy(access, sourceChunkX, sourceChunkY, tileX, tileY - 1, liquidType)
	local canFlowDown = belowOccupancy.canOccupy and belowOccupancy.fill < access.maxFill
	if canFlowDown then
		addWakeTile(wakeTiles, wakeLookup, tileX, tileY - 1)
	end

	local leftOccupancy = inspectOccupancy(access, sourceChunkX, sourceChunkY, tileX - 1, tileY, liquidType)
	local rightOccupancy = inspectOccupancy(access, sourceChunkX, sourceChunkY, tileX + 1, tileY, liquidType)
	local leftCanOccupy = leftOccupancy.canOccupy
	local rightCanOccupy = rightOccupancy.canOccupy
	local leftNeighborFill = leftOccupancy.fill
	local rightNeighborFill = rightOccupancy.fill
	local leftCanEqualize = leftCanOccupy
		and leftNeighborFill < access.maxFill
		and fill > leftNeighborFill + definition.settleEpsilon
	local rightCanEqualize = rightCanOccupy
		and rightNeighborFill < access.maxFill
		and fill > rightNeighborFill + definition.settleEpsilon

	if leftCanEqualize then
		addWakeTile(wakeTiles, wakeLookup, tileX - 1, tileY)
	end
	if rightCanEqualize then
		addWakeTile(wakeTiles, wakeLookup, tileX + 1, tileY)
	end

	local leftLeak = nil
	local rightLeak = nil
	local waitingOnChunkReady = belowOccupancy.waitingOnChunkReady
		or leftOccupancy.waitingOnChunkReady
		or rightOccupancy.waitingOnChunkReady
	local dependencyChunkKey = belowOccupancy.dependencyChunkKey
		or leftOccupancy.dependencyChunkKey
		or rightOccupancy.dependencyChunkKey
	if not canFlowDown and not waitingOnChunkReady then
		leftLeak = scanLeakPath(access, tileX, tileY, liquidType, -1)
		rightLeak = scanLeakPath(access, tileX, tileY, liquidType, 1)
		if leftLeak ~= nil then
			mergeWakeTiles(wakeTiles, wakeLookup, leftLeak.pathTiles)
		end
		if rightLeak ~= nil then
			mergeWakeTiles(wakeTiles, wakeLookup, rightLeak.pathTiles)
		end
	end

	local hasLeakPath = (leftLeak ~= nil and leftLeak.found) or (rightLeak ~= nil and rightLeak.found)
	local boundaryDependency = (leftLeak ~= nil and leftLeak.boundaryDependency)
		or (rightLeak ~= nil and rightLeak.boundaryDependency)
	waitingOnChunkReady = waitingOnChunkReady
		or (leftLeak ~= nil and leftLeak.waitingOnChunkReady)
		or (rightLeak ~= nil and rightLeak.waitingOnChunkReady)
	dependencyChunkKey = dependencyChunkKey
		or (if leftLeak ~= nil then leftLeak.dependencyChunkKey else nil)
		or (if rightLeak ~= nil then rightLeak.dependencyChunkKey else nil)
	if waitingOnChunkReady then
		boundaryDependency = true
	end
	local preferredDirection = 0
	local leakDistance = 0

	if leftLeak ~= nil and leftLeak.found and rightLeak ~= nil and rightLeak.found then
		if leftLeak.distance <= rightLeak.distance then
			preferredDirection = -1
			leakDistance = leftLeak.distance
		else
			preferredDirection = 1
			leakDistance = rightLeak.distance
		end
	elseif leftLeak ~= nil and leftLeak.found then
		preferredDirection = -1
		leakDistance = leftLeak.distance
	elseif rightLeak ~= nil and rightLeak.found then
		preferredDirection = 1
		leakDistance = rightLeak.distance
	elseif leftCanEqualize or rightCanEqualize then
		if leftCanEqualize and rightCanEqualize then
			if leftNeighborFill <= rightNeighborFill then
				preferredDirection = -1
			else
				preferredDirection = 1
			end
		elseif leftCanEqualize then
			preferredDirection = -1
		else
			preferredDirection = 1
		end
	elseif
		(leftLeak ~= nil and leftLeak.boundaryDependency and not (rightLeak ~= nil and rightLeak.boundaryDependency))
		or (leftOccupancy.waitingOnChunkReady and not rightOccupancy.waitingOnChunkReady)
	then
		preferredDirection = -1
	elseif
		(rightLeak ~= nil and rightLeak.boundaryDependency and not (leftLeak ~= nil and leftLeak.boundaryDependency))
		or (rightOccupancy.waitingOnChunkReady and not leftOccupancy.waitingOnChunkReady)
	then
		preferredDirection = 1
	end

	local canEqualize = leftCanEqualize or rightCanEqualize
	local isStable = not canFlowDown
		and not hasLeakPath
		and not canEqualize
		and not boundaryDependency
		and not waitingOnChunkReady
	local state = CELL_DEBUG_STATE.ACTIVE
	local reason = "containsEscapePath"

	if canFlowDown then
		state = CELL_DEBUG_STATE.FALLING
		reason = "airBelow"
	elseif waitingOnChunkReady then
		state = CELL_DEBUG_STATE.DEFERRED_WAITING_FOR_CHUNK
		reason = if dependencyChunkKey ~= nil
			then `awaitingCollisionChunk {dependencyChunkKey}`
			else "awaitingCollisionChunk"
	elseif hasLeakPath then
		state = CELL_DEBUG_STATE.SEARCHING_LEAK_PATH
		reason =
			`reachableDrop direction={(if preferredDirection < 0 then "left" else "right")} distance={leakDistance}`
	elseif boundaryDependency then
		state = CELL_DEBUG_STATE.SEARCHING_LEAK_PATH
		reason = "boundaryDependencyAwaitingLeakResolution"
	elseif canEqualize then
		state = CELL_DEBUG_STATE.EQUALIZING
		reason = "neighborCanAcceptLiquid"
	elseif isStable then
		if not leftCanOccupy and not rightCanOccupy then
			state = CELL_DEBUG_STATE.BLOCKED_BY_LOADED_TERRAIN
			reason = "downwardSealed lateralBlocked leakPathClear chunkReady"
		else
			state = CELL_DEBUG_STATE.STABLE
			reason = "downwardSealed lateralSealed leakPathClear chunkReady"
		end
	end

	return {
		hasLiquid = true,
		liquidType = liquidType,
		fill = fill,
		isStable = isStable,
		state = state,
		reason = reason,
		canFlowDown = canFlowDown,
		canEqualize = canEqualize,
		hasLeakPath = hasLeakPath,
		boundaryDependency = boundaryDependency,
		waitingOnChunkReady = waitingOnChunkReady,
		dependencyChunkKey = dependencyChunkKey,
		preferredDirection = preferredDirection,
		leakDistance = leakDistance,
		wakeTiles = wakeTiles,
		leftCanEqualize = leftCanEqualize,
		rightCanEqualize = rightCanEqualize,
		leftLeak = leftLeak,
		rightLeak = rightLeak,
		leftNeighborFill = leftNeighborFill,
		rightNeighborFill = rightNeighborFill,
	}
end

function LiquidSolver.inspectCell(access: LiquidSolverAccess, tileX: number, tileY: number)
	local inspection = inspectCellDetailed(access, tileX, tileY)
	reportCellState(access, tileX, tileY, inspection.state, inspection.reason, inspection.fill, inspection.liquidType)
	return inspection
end

local function commitCell(
	access: LiquidSolverAccess,
	tileX: number,
	tileY: number,
	liquidType: number,
	fill: number,
	flowState: number
)
	local packed = LiquidCell.pack(liquidType, fill, flowState, 0)
	if access.setCell(tileX, tileY, packed) then
		for _, dx in { -1, 0, 1 } do
			for _, dy in { -1, 0, 1 } do
				wakeTile(access, tileX, tileY, tileX + dx, tileY + dy, "cellMutation")
			end
		end
	end
end

local function chooseDirectionOrder(tileX: number, tileY: number, preferredDirection: number): { number }
	if preferredDirection == -1 then
		return { -1, 1 }
	end
	if preferredDirection == 1 then
		return { 1, -1 }
	end
	if math.abs(tileX + tileY) % 2 == 0 then
		return { -1, 1 }
	end
	return { 1, -1 }
end

local function computeEqualizeTransfer(
	currentFill: number,
	neighborFill: number,
	definition: LiquidDefinition,
	maxFill: number
): number
	local capacity = maxFill - neighborFill
	if capacity <= 0 then
		return 0
	end
	local difference = currentFill - neighborFill
	if difference <= definition.settleEpsilon then
		return 0
	end
	local equalizedTarget = math.ceil((currentFill + neighborFill) * 0.5)
	local transfer = currentFill - equalizedTarget
	if transfer <= 0 then
		return 0
	end
	return math.min(
		math.max(1, math.floor(transfer * definition.sideEqualizeRate)),
		transfer,
		definition.maxSideTransfer,
		capacity
	)
end

local function computeLeakFeedTransfer(
	currentFill: number,
	neighborFill: number,
	definition: LiquidDefinition,
	maxFill: number,
	leakDistance: number
): number
	local capacity = maxFill - neighborFill
	if capacity <= 0 or currentFill <= 0 or currentFill < neighborFill then
		return 0
	end
	if leakDistance <= 1 then
		return math.min(currentFill, capacity, definition.maxSideTransfer)
	end
	return math.min(currentFill, capacity, definition.maxSideTransfer, math.max(1, math.floor(currentFill * 0.1)))
end

local function flowStateFromDebugState(state: string): number
	if state == CELL_DEBUG_STATE.FALLING then
		return LiquidServiceUtils.FLOW_STATE.FALLING
	end
	if state == CELL_DEBUG_STATE.EQUALIZING or state == CELL_DEBUG_STATE.SEARCHING_LEAK_PATH then
		return LiquidServiceUtils.FLOW_STATE.SPREADING
	end
	if state == CELL_DEBUG_STATE.ACTIVE then
		return LiquidServiceUtils.FLOW_STATE.SETTLING
	end
	return LiquidServiceUtils.FLOW_STATE.STILL
end

function LiquidSolver.stepCell(access: LiquidSolverAccess, tileX: number, tileY: number): LiquidSolverStepResult
	recordMetric(access, "solverIterations", 1)

	local originalPackedCell = access.getCell(tileX, tileY)
	local originalFlowState = LiquidCell.getFlowState(originalPackedCell)
	local inspection = LiquidSolver.inspectCell(access, tileX, tileY)
	if not inspection.hasLiquid then
		return {
			changed = false,
			active = false,
			isStable = true,
			state = inspection.state,
			reason = inspection.reason,
			waitingOnChunkReady = inspection.waitingOnChunkReady,
			dependencyChunkKey = inspection.dependencyChunkKey,
			downwardTransfer = 0,
			lateralTransfer = 0,
			liquidType = inspection.liquidType,
			fill = inspection.fill,
			wakeTiles = inspection.wakeTiles,
		}
	end

	local definition = access.getDefinition(inspection.liquidType)
	if definition == nil then
		commitCell(access, tileX, tileY, LiquidServiceUtils.LIQUID_TYPE.NONE, 0, LiquidServiceUtils.FLOW_STATE.STILL)
		return {
			changed = true,
			active = true,
			isStable = false,
			state = CELL_DEBUG_STATE.ACTIVE,
			reason = "missingDefinition",
			waitingOnChunkReady = false,
			dependencyChunkKey = nil,
			downwardTransfer = 0,
			lateralTransfer = 0,
			liquidType = inspection.liquidType,
			fill = 0,
			wakeTiles = inspection.wakeTiles,
		}
	end

	local currentFill = inspection.fill
	local changed = false
	local downwardTransfer = 0
	local lateralTransfer = 0
	local sourceChunkX, sourceChunkY = getChunkCoordinatesForTile(access, tileX, tileY)

	if inspection.canFlowDown then
		local belowOccupancy =
			inspectOccupancy(access, sourceChunkX, sourceChunkY, tileX, tileY - 1, inspection.liquidType)
		downwardTransfer = math.min(currentFill, access.maxFill - belowOccupancy.fill)
		if downwardTransfer > 0 then
			currentFill -= downwardTransfer
			commitCell(
				access,
				tileX,
				tileY - 1,
				inspection.liquidType,
				belowOccupancy.fill + downwardTransfer,
				LiquidServiceUtils.FLOW_STATE.FALLING
			)
			changed = true
			recordMetric(access, "downwardTransfers", downwardTransfer)
		end
	end

	if currentFill > 0 and downwardTransfer <= 0 then
		for _, direction in chooseDirectionOrder(tileX, tileY, inspection.preferredDirection) do
			local neighborX = tileX + direction
			local neighborOccupancy =
				inspectOccupancy(access, sourceChunkX, sourceChunkY, neighborX, tileY, inspection.liquidType)
			if not neighborOccupancy.canOccupy then
				continue
			end

			local transfer = computeEqualizeTransfer(currentFill, neighborOccupancy.fill, definition, access.maxFill)
			local leakInfo = if direction < 0 then inspection.leftLeak else inspection.rightLeak
			local leakDistance = if leakInfo ~= nil then leakInfo.distance else 0
			if leakInfo ~= nil and (leakInfo.found or leakInfo.boundaryDependency) then
				transfer = math.max(
					transfer,
					computeLeakFeedTransfer(
						currentFill,
						neighborOccupancy.fill,
						definition,
						access.maxFill,
						leakDistance
					)
				)
			end

			if transfer <= 0 then
				continue
			end

			currentFill -= transfer
			lateralTransfer += transfer
			commitCell(
				access,
				neighborX,
				tileY,
				inspection.liquidType,
				neighborOccupancy.fill + transfer,
				LiquidServiceUtils.FLOW_STATE.SPREADING
			)
			changed = true
			recordMetric(access, "lateralTransfers", transfer)
			if currentFill <= 0 then
				break
			end
		end
	end

	local currentState = if downwardTransfer > 0
		then LiquidServiceUtils.FLOW_STATE.SETTLING
		elseif lateralTransfer > 0 then LiquidServiceUtils.FLOW_STATE.SPREADING
		else flowStateFromDebugState(inspection.state)
	if currentFill ~= inspection.fill or currentState ~= originalFlowState then
		changed = true
	end
	commitCell(access, tileX, tileY, inspection.liquidType, currentFill, currentState)

	local finalInspection = LiquidSolver.inspectCell(access, tileX, tileY)
	local isActive = not finalInspection.isStable
	if isActive and not changed and not finalInspection.waitingOnChunkReady then
		wakeInspectionTiles(access, tileX, tileY, finalInspection.wakeTiles, `unstable:{finalInspection.state}`)
		recordMetric(access, "activeCells", 1)
	elseif isActive then
		recordMetric(access, "activeCells", 1)
	end

	return {
		changed = changed,
		active = isActive,
		isStable = finalInspection.isStable,
		state = finalInspection.state,
		reason = finalInspection.reason,
		waitingOnChunkReady = finalInspection.waitingOnChunkReady,
		dependencyChunkKey = finalInspection.dependencyChunkKey,
		downwardTransfer = downwardTransfer,
		lateralTransfer = lateralTransfer,
		liquidType = inspection.liquidType,
		fill = currentFill,
		wakeTiles = finalInspection.wakeTiles,
	}
end

function LiquidSolver.settleGrid(
	config: LiquidServiceConfig,
	cells: { number },
	width: number,
	height: number,
	isSolid: (tileX: number, tileY: number) -> boolean,
	passesRaw: any?
): { number }
	local settled = table.clone(cells)
	local passes = sanitizeInteger(passesRaw, 0, 256, config.simulation.generationSettlePasses)

	local function getCell(tileX: number, tileY: number): number
		if tileX < 0 or tileX >= width or tileY < 0 or tileY >= height then
			return 0
		end
		return settled[LiquidServiceUtils.computeTileIndex(tileX, tileY, width)] or 0
	end

	local function setCell(tileX: number, tileY: number, packedCell: number): boolean
		if tileX < 0 or tileX >= width or tileY < 0 or tileY >= height then
			return false
		end
		local index = LiquidServiceUtils.computeTileIndex(tileX, tileY, width)
		if settled[index] == packedCell then
			return false
		end
		settled[index] = packedCell
		return true
	end

	local noop = function(
		_tileX: number,
		_tileY: number,
		_reason: string?,
		_sourceTileX: number?,
		_sourceTileY: number?
	)
	end
	local access: LiquidSolverAccess = {
		maxFill = config.maxFill,
		chunkSize = math.max(1, width),
		maxLeakScanDistance = config.simulation.leakScanDistanceTiles,
		getCell = getCell,
		setCell = setCell,
		isSolid = isSolid,
		isChunkReady = function(_chunkX: number, _chunkY: number): boolean
			return true
		end,
		pushDirty = noop,
		getDefinition = function(liquidType: number): LiquidDefinition?
			return config.definitions[liquidType]
		end,
	}

	for _ = 1, passes do
		local changed = false
		for rowY = 0, height - 1 do
			for localX = 0, width - 1 do
				local stepResult = LiquidSolver.stepCell(access, localX, rowY)
				if stepResult.changed then
					changed = true
				end
			end
		end
		if not changed then
			break
		end
	end

	return settled
end

LiquidServiceUtils.LiquidSolver = LiquidSolver

return LiquidServiceUtils
