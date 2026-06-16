local require = require(script.Parent.loader).load(script)

local NevermoreMath = require("Math")

local Math = {}

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

function Math.ComputeScreenAdjustment(
	cameraDepthFromTop: number,
	screenHeight: number,
	surfaceDepthFromTop: number,
	maxTilesY: number
): number
	local _cameraDepthFromTop = sanitizeNumber(cameraDepthFromTop, 0, nil)
	local _screenHeight = sanitizeNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local _surfaceDepthFromTop = sanitizeNumber(surfaceDepthFromTop, 1, 1)
	local _maxTilesY = sanitizeNumber(maxTilesY, 1800, _surfaceDepthFromTop)
	return 0
end

function Math.ComputeBgTopPx(
	cameraDepthFromTop: number,
	screenHeight: number,
	surfaceDepthFromTop: number,
	verticalStrength: number,
	baseScreenY: number,
	scAdj: number,
	offsetY: number?
): number
	local resolvedCameraDepthFromTop = sanitizeNumber(cameraDepthFromTop, 0, nil)
	local resolvedScreenHeight = sanitizeNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedSurfaceDepthFromTop = sanitizeNumber(surfaceDepthFromTop, 1, 1)
	local resolvedVerticalStrength = sanitizeNumber(verticalStrength, 0, nil)
	local resolvedBaseScreenY = sanitizeNumber(baseScreenY, 0, nil)
	local resolvedScAdj = sanitizeNumber(scAdj, 0, nil)
	local resolvedOffsetY = sanitizeNumber(offsetY, 0, nil)
	local screenOff = resolvedScreenHeight - FALLBACK_TEXTURE_HEIGHT_PX

	return ((-resolvedCameraDepthFromTop + screenOff / 2) / math.max(resolvedSurfaceDepthFromTop, 1))
			* resolvedVerticalStrength
		+ resolvedBaseScreenY
		+ resolvedScAdj
		+ resolvedOffsetY
end

function Math.ScreenTopPxToWorldCenterY(
	bgTopPx: number,
	screenHeight: number,
	cameraY: number,
	visibleHeight: number,
	layerHeightWorld: number
): number
	local resolvedBgTopPx = sanitizeNumber(bgTopPx, 0, nil)
	local resolvedScreenHeight = sanitizeNumber(screenHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedCameraY = sanitizeNumber(cameraY, 0, nil)
	local resolvedVisibleHeight = sanitizeNumber(visibleHeight, 1, 1)
	local resolvedLayerHeightWorld = sanitizeNumber(layerHeightWorld, 1, 1)
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
	viewportHeightPx: number
): (number, number)
	local resolvedImageWidth = sanitizeNumber(imageWidth, FALLBACK_TEXTURE_WIDTH_PX, 1)
	local resolvedImageHeight = sanitizeNumber(imageHeight, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local resolvedBgScale = sanitizeNumber(bgScale, 1, 0.01)
	local resolvedVisibleHeight = sanitizeNumber(visibleHeight, 1, 1)
	local resolvedViewportHeightPx = sanitizeNumber(viewportHeightPx, FALLBACK_TEXTURE_HEIGHT_PX, 1)
	local studsPerScreenPixel = resolvedVisibleHeight / resolvedViewportHeightPx

	return resolvedImageWidth * resolvedBgScale * studsPerScreenPixel,
		resolvedImageHeight * resolvedBgScale * studsPerScreenPixel
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

	return value % resolvedTextureRepeatWidthWorld
end

Math.computeScreenAdjustment = Math.ComputeScreenAdjustment
Math.computeBgTopPx = Math.ComputeBgTopPx
Math.screenTopPxToWorldCenterY = Math.ScreenTopPxToWorldCenterY
Math.computeTextureSizeWorld = Math.ComputeTextureSizeWorld
Math.computeHorizontalTextureOffsetWorld = Math.ComputeHorizontalTextureOffsetWorld

return Math
