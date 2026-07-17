local require = require(script.Parent.loader).load(script)

local CloudScroll = {}

local function coerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw and valueRaw ~= math.huge and valueRaw ~= -math.huge then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

function CloudScroll.GetScaleAlpha(scaleRaw: number, minScaleRaw: number, maxScaleRaw: number): number
	local minScale = coerceNumber(minScaleRaw, 0.4, 0.01, 16)
	local maxScale = coerceNumber(maxScaleRaw, 1, minScale + 0.001, 16)
	local scale = coerceNumber(scaleRaw, minScale, minScale, maxScale)
	return math.clamp((scale - minScale) / (maxScale - minScale), 0, 1)
end

function CloudScroll.GetDepthFactor(
	scaleRaw: number,
	minScaleRaw: number,
	maxScaleRaw: number,
	minDepthFactorRaw: number,
	maxDepthFactorRaw: number
): number
	local alpha = CloudScroll.GetScaleAlpha(scaleRaw, minScaleRaw, maxScaleRaw)
	local minDepthFactor = coerceNumber(minDepthFactorRaw, 0.06, 0, 1)
	local maxDepthFactor = coerceNumber(maxDepthFactorRaw, 0.34, minDepthFactor, 1)
	return minDepthFactor + (maxDepthFactor - minDepthFactor) * alpha
end

function CloudScroll.ComputeHorizonOffset(baseOffsetZ: number, cameraDeltaZ: number, _depthFactor: number): number
	-- full camera compensation keeps clouds anchored to world z
	return baseOffsetZ - cameraDeltaZ
end

function CloudScroll.IsHorizontallyOffscreen(
	centerOffsetZ: number,
	widthStuds: number,
	surfaceHalfWidthStuds: number,
	marginStuds: number
): boolean
	local halfWidth = math.max(widthStuds, 0) * 0.5
	local limit = math.max(surfaceHalfWidthStuds, 0) + math.max(marginStuds, 0)
	return centerOffsetZ + halfWidth < -limit or centerOffsetZ - halfWidth > limit
end

return CloudScroll
