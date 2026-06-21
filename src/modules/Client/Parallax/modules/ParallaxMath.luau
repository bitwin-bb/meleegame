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

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?): number
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
	local resolvedDepthWorld = sanitizeNumber(depthWorld, 0, nil)
	local resolvedTileSize = sanitizeNumber(tileSize, 4, 0.25)
	return resolvedDepthWorld * TERRARIA_TILE_SIZE_PX / resolvedTileSize
end

function Math.ComputeScreenTopDepthPx(cameraDepthFromTop: number, screenHeight: number, tileSize: number?): number
	local resolvedCameraDepthFromTop = sanitizeNumber(cameraDepthFromTop, 0, nil)
	local resolvedScreenHeight = sanitizeNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	return Math.ComputeDepthWorldToTerrariaPixels(resolvedCameraDepthFromTop, tileSize) - resolvedScreenHeight * 0.5
end

function Math.ComputeScreenAdjustment(
	screenTopDepthPx: number,
	screenHeight: number,
	surfaceDepthPx: number,
	maxTilesY: number
): number
	local resolvedScreenTopDepthPx = sanitizeNumber(screenTopDepthPx, 0, nil)
	local resolvedScreenHeight = sanitizeNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedSurfaceDepthPx = sanitizeNumber(surfaceDepthPx, 1, 1)
	local resolvedMaxTilesY = sanitizeNumber(maxTilesY, 1800, 1)
	local denominator = math.max(resolvedScreenTopDepthPx + resolvedScreenHeight, 1)
	local topFade = resolvedMaxTilesY * TERRARIA_TOP_FADE_WORLD_FRACTION * TERRARIA_TILE_SIZE_PX
		- resolvedScreenTopDepthPx
	if topFade < 0 then
		topFade = 0
	end
	topFade *= TERRARIA_TOP_FADE_SCALE
	local screenAdjustment = resolvedSurfaceDepthPx / denominator
	screenAdjustment *= TERRARIA_SCREEN_ADJUSTMENT_BASE - topFade * topFade

	if resolvedMaxTilesY <= 1200 then
		screenAdjustment *= -500
	elseif resolvedMaxTilesY <= 1800 then
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
	local resolvedScreenTopDepthPx = sanitizeNumber(screenTopDepthPx, 0, nil)
	local resolvedScreenHeight = sanitizeNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedSurfaceDepthPx = sanitizeNumber(surfaceDepthPx, 1, 1)
	local resolvedVerticalStrength = sanitizeNumber(verticalStrength, 0, nil)
	local resolvedBaseScreenY = sanitizeNumber(baseScreenY, 0, nil)
	local resolvedScAdj = sanitizeNumber(scAdj, 0, nil)
	local resolvedOffsetY = sanitizeNumber(offsetY, 0, nil)
	local screenOffHalf = (resolvedScreenHeight - TERRARIA_SURFACE_SCREEN_BASELINE_PX) * 0.5
	local backgroundTopMagicNumber = (-resolvedScreenTopDepthPx + screenOffHalf)
		/ math.max(resolvedSurfaceDepthPx, 1)

	return backgroundTopMagicNumber * resolvedVerticalStrength + resolvedBaseScreenY + resolvedScAdj + resolvedOffsetY
end

function Math.ComputeUiScale(
	viewportHeightPx: number,
	referenceHeightPx: number?,
	minScale: number?,
	maxScale: number?
): number
	local resolvedViewportHeightPx = sanitizeNumber(viewportHeightPx, TERRARIA_REFERENCE_VIEWPORT_HEIGHT_PX, 1)
	local resolvedReferenceHeightPx = sanitizeNumber(referenceHeightPx, TERRARIA_REFERENCE_VIEWPORT_HEIGHT_PX, 1)
	local resolvedMinScale = sanitizeNumber(minScale, TERRARIA_MIN_UI_SCALE, 0.01)
	local resolvedMaxScale = sanitizeNumber(maxScale, TERRARIA_MAX_UI_SCALE, resolvedMinScale)

	return math.clamp(resolvedViewportHeightPx / resolvedReferenceHeightPx, resolvedMinScale, resolvedMaxScale)
end

function Math.ScreenTopPxToWorldCenterY(
	bgTopPx: number,
	screenHeight: number,
	cameraY: number,
	visibleHeight: number,
	layerHeightWorld: number,
	uiScale: number?
): number
	local resolvedBgTopPx = sanitizeNumber(bgTopPx, 0, nil)
	local resolvedScreenHeight = sanitizeNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedCameraY = sanitizeNumber(cameraY, 0, nil)
	local resolvedVisibleHeight = sanitizeNumber(visibleHeight, 1, 1)
	local resolvedLayerHeightWorld = sanitizeNumber(layerHeightWorld, 1, 1)
	local _resolvedUiScale = sanitizeNumber(uiScale, 1, 0.01)
	local studsPerScreenPixel = resolvedVisibleHeight / resolvedScreenHeight
	local visibleTopY = resolvedCameraY + resolvedVisibleHeight * 0.5
	local topWorldY = visibleTopY - resolvedBgTopPx * studsPerScreenPixel

	return topWorldY - resolvedLayerHeightWorld * 0.5
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
	local resolvedImageWidth = sanitizeNumber(imageWidth, FALLBACK_TEXTURE_WIDTH_PX, 1)
	local resolvedImageHeight = sanitizeNumber(imageHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedBgScale = sanitizeNumber(bgScale, 1, 0.01)
	local resolvedVisibleHeight = sanitizeNumber(visibleHeight, 1, 1)
	local resolvedViewportHeightPx = sanitizeNumber(viewportHeightPx, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedUiScale = sanitizeNumber(uiScale, 1, 0.01)
	local resolvedLayerSizeScale = sanitizeNumber(layerSizeScale, 1, 0.01)
	local studsPerScreenPixel = resolvedVisibleHeight / resolvedViewportHeightPx

	return resolvedImageWidth * resolvedBgScale * resolvedUiScale * resolvedLayerSizeScale * studsPerScreenPixel,
		resolvedImageHeight * resolvedBgScale * resolvedUiScale * resolvedLayerSizeScale * studsPerScreenPixel
end

function Math.ComputeHorizontalTextureOffsetWorld(
	cameraWorldAxis: number,
	parallaxX: number,
	textureRepeatWidthWorld: number,
	scrollSpeed: number?,
	now: number?
): number
	local resolvedCameraWorldAxis = sanitizeNumber(cameraWorldAxis, 0, nil)
	local resolvedParallaxX = sanitizeNumber(parallaxX, 0, nil)
	local resolvedTextureRepeatWidthWorld = sanitizeNumber(textureRepeatWidthWorld, 1, 1)
	local resolvedScrollSpeed = sanitizeNumber(scrollSpeed, 0, nil)
	local resolvedNow = sanitizeNumber(now, 0, nil)
	local value = resolvedCameraWorldAxis * resolvedParallaxX + resolvedScrollSpeed * resolvedNow
	local centeredRemainder = computeIeeeRemainder(value, resolvedTextureRepeatWidthWorld)
		+ resolvedTextureRepeatWidthWorld * 0.5

	return centeredRemainder % resolvedTextureRepeatWidthWorld
end

Math.computeDepthWorldToTerrariaPixels = Math.ComputeDepthWorldToTerrariaPixels
Math.computeScreenTopDepthPx = Math.ComputeScreenTopDepthPx
Math.computeScreenAdjustment = Math.ComputeScreenAdjustment
Math.computeBgTopPx = Math.ComputeBgTopPx
Math.computeUiScale = Math.ComputeUiScale
Math.screenTopPxToWorldCenterY = Math.ScreenTopPxToWorldCenterY
Math.computeTextureSizeWorld = Math.ComputeTextureSizeWorld
Math.computeHorizontalTextureOffsetWorld = Math.ComputeHorizontalTextureOffsetWorld

return Math
