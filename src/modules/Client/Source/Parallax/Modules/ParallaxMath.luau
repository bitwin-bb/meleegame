local require = require(script.Parent.loader).load(script)

local NevermoreMath = require("Math")

local Math = {}

local TERRARIA_TILE_SIZE_PX = 16
local TERRARIA_SURFACE_SCREEN_BASELINE_PX = 600
local TERRARIA_TOP_FADE_WORLD_FRACTION = 0.15
local TERRARIA_TOP_FADE_SCALE = 0.00025
local TERRARIA_SCREEN_ADJUSTMENT_BASE = 0.45
local TERRARIA_REFERENCE_VIEWPORT_HEIGHT_PX = 1080
local TERRARIA_MIN_UI_SCALE = 0.78
local TERRARIA_MAX_UI_SCALE = 1.45
local FALLBACK_TEXTURE_WIDTH_PX = 1024
local FALLBACK_TEXTURE_HEIGHT_PX = 600

local function coerceNumber(valueRaw: any, fallback: number, minimum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and NevermoreMath.isFinite(valueRaw) then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	return value
end

local function roundToEven(value: number): number
	local lower = math.floor(value)
	local fraction = value - lower
	if fraction < 0.5 then
		return lower
	end
	if fraction > 0.5 then
		return lower + 1
	end
	return if lower % 2 == 0 then lower else lower + 1
end

local function computeIeeeRemainder(value: number, divisor: number): number
	return value - divisor * roundToEven(value / divisor)
end

function Math.ComputeDepthWorldToTerrariaPixels(depthWorld: number, tileSize: number?): number
	local depthWorldValue = coerceNumber(depthWorld, 0, nil)
	local GotTileSize = coerceNumber(tileSize, 4, 0.25)
	return depthWorldValue * TERRARIA_TILE_SIZE_PX / GotTileSize
end

function Math.ComputeScreenTopDepthPx(cameraDepthFromTop: number, screenHeight: number, tileSize: number?): number
	local GotCameraDepthFromTop = coerceNumber(cameraDepthFromTop, 0, nil)
	local GotScreenHeight = coerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	return Math.ComputeDepthWorldToTerrariaPixels(GotCameraDepthFromTop, tileSize) - GotScreenHeight * 0.5
end

function Math.ComputeScreenAdjustment(
	screenTopDepthPx: number,
	screenHeight: number,
	surfaceDepthPx: number,
	maxTilesY: number
): number
	local GotScreenTopDepthPx = coerceNumber(screenTopDepthPx, 0, nil)
	local GotScreenHeight = coerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotSurfaceDepthPx = coerceNumber(surfaceDepthPx, 1, 1)
	local GotMaxTilesY = coerceNumber(maxTilesY, 1800, 1)
	local denominator = math.max(GotScreenTopDepthPx + GotScreenHeight, 1)
	local topFade = GotMaxTilesY * TERRARIA_TOP_FADE_WORLD_FRACTION * TERRARIA_TILE_SIZE_PX - GotScreenTopDepthPx
	if topFade < 0 then
		topFade = 0
	end
	topFade *= TERRARIA_TOP_FADE_SCALE
	local screenAdjustment = GotSurfaceDepthPx / denominator
	screenAdjustment *= TERRARIA_SCREEN_ADJUSTMENT_BASE - topFade * topFade

	if GotMaxTilesY <= 1200 then
		screenAdjustment *= -500
	elseif GotMaxTilesY <= 1800 then
		screenAdjustment *= -300
	else
		screenAdjustment *= -150
	end

	return screenAdjustment
end

function Math.ComputeBgTopPx(
	screenTopDepthPx: number,
	screenHeight: number,
	surfaceDepthPx: number,
	verticalStrength: number,
	baseScreenY: number,
	scAdj: number,
	offsetY: number?
): number
	local GotScreenTopDepthPx = coerceNumber(screenTopDepthPx, 0, nil)
	local GotScreenHeight = coerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotSurfaceDepthPx = coerceNumber(surfaceDepthPx, 1, 1)
	local GotVerticalStrength = coerceNumber(verticalStrength, 0, nil)
	local GotBaseScreenY = coerceNumber(baseScreenY, 0, nil)
	local GotScAdj = coerceNumber(scAdj, 0, nil)
	local offsetYValue = coerceNumber(offsetY, 0, nil)
	local screenOffHalf = (GotScreenHeight - TERRARIA_SURFACE_SCREEN_BASELINE_PX) * 0.5
	local backgroundTopMagicNumber = (-GotScreenTopDepthPx + screenOffHalf) / math.max(GotSurfaceDepthPx, 1)

	return backgroundTopMagicNumber * GotVerticalStrength + GotBaseScreenY + GotScAdj + offsetYValue
end

function Math.ComputeUiScale(
	viewportHeightPx: number,
	referenceHeightPx: number?,
	minScale: number?,
	maxScale: number?
): number
	local GotViewportHeightPx = coerceNumber(viewportHeightPx, TERRARIA_REFERENCE_VIEWPORT_HEIGHT_PX, 1)
	local GotReferenceHeightPx = coerceNumber(referenceHeightPx, TERRARIA_REFERENCE_VIEWPORT_HEIGHT_PX, 1)
	local GotMinScale = coerceNumber(minScale, TERRARIA_MIN_UI_SCALE, 0.01)
	local GotMaxScale = coerceNumber(maxScale, TERRARIA_MAX_UI_SCALE, GotMinScale)

	return math.clamp(GotViewportHeightPx / GotReferenceHeightPx, GotMinScale, GotMaxScale)
end

function Math.ScreenTopPxToWorldCenterY(
	bgTopPx: number,
	screenHeight: number,
	cameraY: number,
	visibleHeight: number,
	layerHeightWorld: number,
	uiScale: number?
): number
	local GotBgTopPx = coerceNumber(bgTopPx, 0, nil)
	local GotScreenHeight = coerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotCameraY = coerceNumber(cameraY, 0, nil)
	local GotVisibleHeight = coerceNumber(visibleHeight, 1, 1)
	local GotLayerHeightWorld = coerceNumber(layerHeightWorld, 1, 1)
	local _GotUiScale = coerceNumber(uiScale, 1, 0.01)
	local studsPerScreenPixel = GotVisibleHeight / GotScreenHeight
	local visibleTopY = GotCameraY + GotVisibleHeight * 0.5
	local topWorldY = visibleTopY - GotBgTopPx * studsPerScreenPixel

	return topWorldY - GotLayerHeightWorld * 0.5
end

function Math.ComputeTextureSizeWorld(
	imageWidth: number,
	imageHeight: number,
	bgScale: number,
	visibleHeight: number,
	viewportHeightPx: number,
	uiScale: number?,
	layerSizeScale: number?
): (number, number)
	local imageWidthValue = coerceNumber(imageWidth, FALLBACK_TEXTURE_WIDTH_PX, 1)
	local imageHeightValue = coerceNumber(imageHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotBgScale = coerceNumber(bgScale, 1, 0.01)
	local GotVisibleHeight = coerceNumber(visibleHeight, 1, 1)
	local GotViewportHeightPx = coerceNumber(viewportHeightPx, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotUiScale = coerceNumber(uiScale, 1, 0.01)
	local GotLayerSizeScale = coerceNumber(layerSizeScale, 1, 0.01)
	local studsPerScreenPixel = GotVisibleHeight / GotViewportHeightPx

	return imageWidthValue * GotBgScale * GotUiScale * GotLayerSizeScale * studsPerScreenPixel,
		imageHeightValue * GotBgScale * GotUiScale * GotLayerSizeScale * studsPerScreenPixel
end

function Math.ComputeProjectionScale(sourceVisibleHeight: number, targetVisibleHeight: number): number
	local sourceHeight = coerceNumber(sourceVisibleHeight, 1, 1)
	local targetHeight = coerceNumber(targetVisibleHeight, sourceHeight, 1)
	return targetHeight / sourceHeight
end

function Math.RescaleWrappedOffset(
	offsetWorld: number,
	sourceRepeatWidthWorld: number,
	targetRepeatWidthWorld: number
): number
	local sourceOffset = coerceNumber(offsetWorld, 0, nil)
	local sourceRepeatWidth = coerceNumber(sourceRepeatWidthWorld, 1, 1)
	local targetRepeatWidth = coerceNumber(targetRepeatWidthWorld, sourceRepeatWidth, 1)
	return (sourceOffset / sourceRepeatWidth) * targetRepeatWidth
end

function Math.ComputeHorizontalTextureOffsetWorld(
	cameraWorldAxis: number,
	parallaxX: number,
	textureRepeatWidthWorld: number,
	scrollSpeed: number?,
	now: number?
): number
	local GotCameraWorldAxis = coerceNumber(cameraWorldAxis, 0, nil)
	local GotParallaxX = coerceNumber(parallaxX, 0, nil)
	local GotTextureRepeatWidthWorld = coerceNumber(textureRepeatWidthWorld, 1, 1)
	local GotScrollSpeed = coerceNumber(scrollSpeed, 0, nil)
	local GotNow = coerceNumber(now, 0, nil)
	local value = -GotCameraWorldAxis * GotParallaxX - GotScrollSpeed * GotNow
	local centeredRemainder = computeIeeeRemainder(value, GotTextureRepeatWidthWorld) + GotTextureRepeatWidthWorld * 0.5

	return centeredRemainder % GotTextureRepeatWidthWorld
end
return Math
