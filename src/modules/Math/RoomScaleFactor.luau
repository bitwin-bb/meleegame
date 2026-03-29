--!strict

local RoomScaleFactor = {}

export type RoomScaleFactorConfig = {
	enabled: boolean?,
	sampleIntervalSeconds: number?,
	horizontalScanRadiusTiles: number?,
	verticalScanRadiusTiles: number?,
	minimumEnclosedWidthTiles: number?,
	maximumEnclosedWidthTiles: number?,
	minimumEnclosedHeightTiles: number?,
	maximumEnclosedHeightTiles: number?,
	minimumDistanceScale: number?,
	minimumHeightScale: number?,
	minimumLookHeightScale: number?,
	minimumFieldOfViewScale: number?,
	widthWeight: number?,
	heightWeight: number?,
}

export type RoomScaleSource = {
	isEnclosed: boolean,
	widthTiles: number,
	heightTiles: number,
	leftDistance: number?,
	rightDistance: number?,
	upDistance: number?,
	downDistance: number?,
}

export type RoomScaleResult = {
	active: boolean,
	isEnclosed: boolean,
	widthTiles: number,
	heightTiles: number,
	scaleAlpha: number,
	distanceScale: number,
	heightScale: number,
	lookHeightScale: number,
	fieldOfViewScale: number,
}

local DEFAULT_CONFIG: RoomScaleFactorConfig = {
	enabled = true,
	sampleIntervalSeconds = 0.12,
	horizontalScanRadiusTiles = 28,
	verticalScanRadiusTiles = 18,
	minimumEnclosedWidthTiles = 4,
	maximumEnclosedWidthTiles = 28,
	minimumEnclosedHeightTiles = 4,
	maximumEnclosedHeightTiles = 18,
	minimumDistanceScale = 0.56,
	minimumHeightScale = 0.76,
	minimumLookHeightScale = 0.9,
	minimumFieldOfViewScale = 0.86,
	widthWeight = 0.62,
	heightWeight = 0.38,
}

local function clampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function lerp(from: number, to: number, alpha: number): number
	return from + ((to - from) * alpha)
end

function RoomScaleFactor.createDefaultConfig(): RoomScaleFactorConfig
	return table.clone(DEFAULT_CONFIG)
end

function RoomScaleFactor.createDefaultResult(): RoomScaleResult
	return {
		active = false,
		isEnclosed = false,
		widthTiles = 0,
		heightTiles = 0,
		scaleAlpha = 1,
		distanceScale = 1,
		heightScale = 1,
		lookHeightScale = 1,
		fieldOfViewScale = 1,
	}
end

function RoomScaleFactor.sanitizeConfig(
	configRaw: any,
	fallbackConfigRaw: RoomScaleFactorConfig?
): RoomScaleFactorConfig
	local source = if typeof(configRaw) == "table" then (configRaw :: RoomScaleFactorConfig) else {}
	local fallback = if typeof(fallbackConfigRaw) == "table" then fallbackConfigRaw else DEFAULT_CONFIG

	local minimumEnclosedWidthTiles = clampNumber(
		source.minimumEnclosedWidthTiles,
		2,
		256,
		clampNumber(fallback.minimumEnclosedWidthTiles, 2, 256, DEFAULT_CONFIG.minimumEnclosedWidthTiles :: number)
	)
	local maximumEnclosedWidthTiles = clampNumber(
		source.maximumEnclosedWidthTiles,
		minimumEnclosedWidthTiles,
		512,
		clampNumber(
			fallback.maximumEnclosedWidthTiles,
			minimumEnclosedWidthTiles,
			512,
			DEFAULT_CONFIG.maximumEnclosedWidthTiles :: number
		)
	)
	local minimumEnclosedHeightTiles = clampNumber(
		source.minimumEnclosedHeightTiles,
		2,
		256,
		clampNumber(
			fallback.minimumEnclosedHeightTiles,
			2,
			256,
			DEFAULT_CONFIG.minimumEnclosedHeightTiles :: number
		)
	)
	local maximumEnclosedHeightTiles = clampNumber(
		source.maximumEnclosedHeightTiles,
		minimumEnclosedHeightTiles,
		512,
		clampNumber(
			fallback.maximumEnclosedHeightTiles,
			minimumEnclosedHeightTiles,
			512,
			DEFAULT_CONFIG.maximumEnclosedHeightTiles :: number
		)
	)
	local widthWeight = clampNumber(
		source.widthWeight,
		0,
		1,
		clampNumber(fallback.widthWeight, 0, 1, DEFAULT_CONFIG.widthWeight :: number)
	)
	local heightWeight = clampNumber(
		source.heightWeight,
		0,
		1,
		clampNumber(fallback.heightWeight, 0, 1, DEFAULT_CONFIG.heightWeight :: number)
	)

	return {
		enabled = if typeof(source.enabled) == "boolean"
			then source.enabled
			else if typeof(fallback.enabled) == "boolean" then fallback.enabled else true,
		sampleIntervalSeconds = clampNumber(
			source.sampleIntervalSeconds,
			0.01,
			2,
			clampNumber(fallback.sampleIntervalSeconds, 0.01, 2, DEFAULT_CONFIG.sampleIntervalSeconds :: number)
		),
		horizontalScanRadiusTiles = clampNumber(
			source.horizontalScanRadiusTiles,
			2,
			256,
			clampNumber(
				fallback.horizontalScanRadiusTiles,
				2,
				256,
				DEFAULT_CONFIG.horizontalScanRadiusTiles :: number
			)
		),
		verticalScanRadiusTiles = clampNumber(
			source.verticalScanRadiusTiles,
			2,
			256,
			clampNumber(
				fallback.verticalScanRadiusTiles,
				2,
				256,
				DEFAULT_CONFIG.verticalScanRadiusTiles :: number
			)
		),
		minimumEnclosedWidthTiles = minimumEnclosedWidthTiles,
		maximumEnclosedWidthTiles = maximumEnclosedWidthTiles,
		minimumEnclosedHeightTiles = minimumEnclosedHeightTiles,
		maximumEnclosedHeightTiles = maximumEnclosedHeightTiles,
		minimumDistanceScale = clampNumber(
			source.minimumDistanceScale,
			0.2,
			1,
			clampNumber(
				fallback.minimumDistanceScale,
				0.2,
				1,
				DEFAULT_CONFIG.minimumDistanceScale :: number
			)
		),
		minimumHeightScale = clampNumber(
			source.minimumHeightScale,
			0.2,
			1,
			clampNumber(fallback.minimumHeightScale, 0.2, 1, DEFAULT_CONFIG.minimumHeightScale :: number)
		),
		minimumLookHeightScale = clampNumber(
			source.minimumLookHeightScale,
			0.2,
			1,
			clampNumber(
				fallback.minimumLookHeightScale,
				0.2,
				1,
				DEFAULT_CONFIG.minimumLookHeightScale :: number
			)
		),
		minimumFieldOfViewScale = clampNumber(
			source.minimumFieldOfViewScale,
			0.2,
			1,
			clampNumber(
				fallback.minimumFieldOfViewScale,
				0.2,
				1,
				DEFAULT_CONFIG.minimumFieldOfViewScale :: number
			)
		),
		widthWeight = widthWeight,
		heightWeight = heightWeight,
	}
end

function RoomScaleFactor.resolve(configRaw: any, sourceRaw: any): RoomScaleResult
	local config = RoomScaleFactor.sanitizeConfig(configRaw)
	local source = if typeof(sourceRaw) == "table" then (sourceRaw :: RoomScaleSource) else nil
	if config.enabled ~= true or source == nil or source.isEnclosed ~= true then
		return RoomScaleFactor.createDefaultResult()
	end

	local widthTiles = math.max(0, clampNumber(source.widthTiles, 0, 512, 0))
	local heightTiles = math.max(0, clampNumber(source.heightTiles, 0, 512, 0))
	local widthAlpha = math.clamp(
		(widthTiles - (config.minimumEnclosedWidthTiles :: number))
			/ math.max((config.maximumEnclosedWidthTiles :: number) - (config.minimumEnclosedWidthTiles :: number), 0.001),
		0,
		1
	)
	local heightAlpha = math.clamp(
		(heightTiles - (config.minimumEnclosedHeightTiles :: number))
			/ math.max((config.maximumEnclosedHeightTiles :: number) - (config.minimumEnclosedHeightTiles :: number), 0.001),
		0,
		1
	)
	local totalWeight = math.max((config.widthWeight :: number) + (config.heightWeight :: number), 0.001)
	local weightedAlpha =
		((widthAlpha * (config.widthWeight :: number)) + (heightAlpha * (config.heightWeight :: number))) / totalWeight
	local geometricAlpha = math.sqrt(widthAlpha * heightAlpha)
	local scaleAlpha = math.clamp((weightedAlpha * 0.65) + (geometricAlpha * 0.35), 0, 1)

	local result: RoomScaleResult = {
		active = false,
		isEnclosed = true,
		widthTiles = widthTiles,
		heightTiles = heightTiles,
		scaleAlpha = scaleAlpha,
		distanceScale = lerp(config.minimumDistanceScale :: number, 1, scaleAlpha),
		heightScale = lerp(config.minimumHeightScale :: number, 1, scaleAlpha),
		lookHeightScale = lerp(config.minimumLookHeightScale :: number, 1, scaleAlpha),
		fieldOfViewScale = lerp(config.minimumFieldOfViewScale :: number, 1, scaleAlpha),
	}
	result.active = result.distanceScale < 0.999
		or result.heightScale < 0.999
		or result.lookHeightScale < 0.999
		or result.fieldOfViewScale < 0.999
	return result
end

return RoomScaleFactor
