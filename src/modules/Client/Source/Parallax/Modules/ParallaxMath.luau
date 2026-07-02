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

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number?): number
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
	local depthWorldValue = CoerceNumber(depthWorld, 0, nil)
	local GotTileSize = CoerceNumber(tileSize, 4, 0.25)
	return depthWorldValue * TERRARIA_TILE_SIZE_PX / GotTileSize
end

function Math.ComputeScreenTopDepthPx(cameraDepthFromTop: number, screenHeight: number, tileSize: number?): number
	local GotCameraDepthFromTop = CoerceNumber(cameraDepthFromTop, 0, nil)
	local GotScreenHeight = CoerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	return Math.ComputeDepthWorldToTerrariaPixels(GotCameraDepthFromTop, tileSize) - GotScreenHeight * 0.5
end

function Math.ComputeScreenAdjustment(
	screenTopDepthPx: number,
	screenHeight: number,
	surfaceDepthPx: number,
	maxTilesY: number
): number
	local GotScreenTopDepthPx = CoerceNumber(screenTopDepthPx, 0, nil)
	local GotScreenHeight = CoerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotSurfaceDepthPx = CoerceNumber(surfaceDepthPx, 1, 1)
	local GotMaxTilesY = CoerceNumber(maxTilesY, 1800, 1)
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
	local GotScreenTopDepthPx = CoerceNumber(screenTopDepthPx, 0, nil)
	local GotScreenHeight = CoerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotSurfaceDepthPx = CoerceNumber(surfaceDepthPx, 1, 1)
	local GotVerticalStrength = CoerceNumber(verticalStrength, 0, nil)
	local GotBaseScreenY = CoerceNumber(baseScreenY, 0, nil)
	local GotScAdj = CoerceNumber(scAdj, 0, nil)
	local offsetYValue = CoerceNumber(offsetY, 0, nil)
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
	local GotViewportHeightPx = CoerceNumber(viewportHeightPx, TERRARIA_REFERENCE_VIEWPORT_HEIGHT_PX, 1)
	local GotReferenceHeightPx = CoerceNumber(referenceHeightPx, TERRARIA_REFERENCE_VIEWPORT_HEIGHT_PX, 1)
	local GotMinScale = CoerceNumber(minScale, TERRARIA_MIN_UI_SCALE, 0.01)
	local GotMaxScale = CoerceNumber(maxScale, TERRARIA_MAX_UI_SCALE, GotMinScale)

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
	local GotBgTopPx = CoerceNumber(bgTopPx, 0, nil)
	local GotScreenHeight = CoerceNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotCameraY = CoerceNumber(cameraY, 0, nil)
	local GotVisibleHeight = CoerceNumber(visibleHeight, 1, 1)
	local GotLayerHeightWorld = CoerceNumber(layerHeightWorld, 1, 1)
	local _GotUiScale = CoerceNumber(uiScale, 1, 0.01)
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
	local imageWidthValue = CoerceNumber(imageWidth, FALLBACK_TEXTURE_WIDTH_PX, 1)
	local imageHeightValue = CoerceNumber(imageHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotBgScale = CoerceNumber(bgScale, 1, 0.01)
	local GotVisibleHeight = CoerceNumber(visibleHeight, 1, 1)
	local GotViewportHeightPx = CoerceNumber(viewportHeightPx, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local GotUiScale = CoerceNumber(uiScale, 1, 0.01)
	local GotLayerSizeScale = CoerceNumber(layerSizeScale, 1, 0.01)
	local studsPerScreenPixel = GotVisibleHeight / GotViewportHeightPx

	return imageWidthValue * GotBgScale * GotUiScale * GotLayerSizeScale * studsPerScreenPixel,
		imageHeightValue * GotBgScale * GotUiScale * GotLayerSizeScale * studsPerScreenPixel
end

function Math.ComputeHorizontalTextureOffsetWorld(
	cameraWorldAxis: number,
	parallaxX: number,
	textureRepeatWidthWorld: number,
	scrollSpeed: number?,
	now: number?
): number
	local GotCameraWorldAxis = CoerceNumber(cameraWorldAxis, 0, nil)
	local GotParallaxX = CoerceNumber(parallaxX, 0, nil)
	local GotTextureRepeatWidthWorld = CoerceNumber(textureRepeatWidthWorld, 1, 1)
	local GotScrollSpeed = CoerceNumber(scrollSpeed, 0, nil)
	local GotNow = CoerceNumber(now, 0, nil)
	local value = -GotCameraWorldAxis * GotParallaxX - GotScrollSpeed * GotNow
	local centeredRemainder = computeIeeeRemainder(value, GotTextureRepeatWidthWorld) + GotTextureRepeatWidthWorld * 0.5

	return centeredRemainder % GotTextureRepeatWidthWorld
end
return Math
