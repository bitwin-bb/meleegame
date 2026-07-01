local require = require(script.Parent.loader).load(script)

local Math = require("Math")

local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

local Horizon = {}

export type HorizonSample = {
	globalSurfaceY: number,
	localSurfaceY: number,
	horizonY: number,
	worldTopY: number,
	cameraDepthFromTop: number,
	surfaceDepthFromTop: number,
}

local DEFAULT_MAX_TILES_Y = 1800
local DEFAULT_TILE_SIZE = 4
local DEFAULT_CHUNK_SIZE = 32
local SURFACE_SAMPLE_COUNT = 17
local WORLD_TOP_DEPTH_FACTOR = 0.15
local MIN_WORLD_TOP_DEPTH_FACTOR = 0.1
local MIN_WORLD_TOP_DEPTH_TILES = 24

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and Math.isFinite(valueRaw) then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	return value
end

local function GetFiniteNumber(valueRaw: any): number?
	if typeof(valueRaw) == "number" and Math.isFinite(valueRaw) then
		return valueRaw
	end
	return nil
end

local function safeCall(service: any, methodName: string, ...: any): any?
	if service == nil then
		return nil
	end
	local method = service[methodName]
	if typeof(method) ~= "function" then
		return nil
	end

	local ok, result = pcall(method, service, ...)
	if not ok then
		return nil
	end
	return result
end

local function GetWorldGenerationService(runtime: any): any
	if typeof(runtime) == "table" and runtime.worldGenerationServiceClient ~= nil then
		return runtime.worldGenerationServiceClient
	end
	return WorldGenerationServiceClient
end

local function GetLayoutSnapshot(runtime: any): any
	if typeof(runtime) ~= "table" then
		return nil
	end
	local layoutStateValue = runtime.layoutStateValue
	if typeof(layoutStateValue) == "table" and typeof(layoutStateValue.Value) == "table" then
		return layoutStateValue.Value
	end
	local getter = runtime._GetCurrentLayoutSnapshot
	if typeof(getter) == "function" then
		local ok, result = pcall(getter, runtime)
		if ok and typeof(result) == "table" then
			return result
		end
	end
	return nil
end

local function GetUntimeNumber(runtime: any, key: string, fallback: number, minimum: number?): number
	if typeof(runtime) == "table" then
		return CoerceNumber(runtime[key], fallback, minimum)
	end
	return CoerceNumber(nil, fallback, minimum)
end

local function GetGlobalSurfaceY(runtime: any): number
	local worldSurfaceY = if typeof(runtime) == "table" then GetFiniteNumber(runtime.worldSurfaceY) else nil
	if worldSurfaceY ~= nil then
		return worldSurfaceY
	end

	local seaLevelY = if typeof(runtime) == "table" then GetFiniteNumber(runtime.seaLevelY) else nil
	if seaLevelY ~= nil then
		return seaLevelY
	end

	local worldOrigin = if typeof(runtime) == "table" then runtime.worldOrigin else nil
	if typeof(worldOrigin) == "Vector3" then
		return worldOrigin.Y
	end
	return 0
end

local function GetWorldTopY(runtime: any, globalSurfaceY: number): number
	local layoutSnapshot = GetLayoutSnapshot(runtime)
	local tileSize = if typeof(layoutSnapshot) == "table"
		then CoerceNumber(layoutSnapshot.tileSize, DEFAULT_TILE_SIZE, 0.25)
		else DEFAULT_TILE_SIZE
	local maxTilesY = GetUntimeNumber(runtime, "maxTilesY", DEFAULT_MAX_TILES_Y, 1)
	local fallbackWorldTopDepth = maxTilesY * tileSize * WORLD_TOP_DEPTH_FACTOR
	local minimumWorldTopDepth =
		math.max(tileSize * MIN_WORLD_TOP_DEPTH_TILES, fallbackWorldTopDepth * MIN_WORLD_TOP_DEPTH_FACTOR)
	local worldTopY = if typeof(runtime) == "table" then GetFiniteNumber(runtime.worldTopY) else nil
	if worldTopY ~= nil and worldTopY >= globalSurfaceY + minimumWorldTopDepth then
		return worldTopY
	end

	return globalSurfaceY + fallbackWorldTopDepth
end

local function insertSurfaceSample(samples: { number }, valueRaw: any)
	local value = GetFiniteNumber(valueRaw)
	if value ~= nil then
		table.insert(samples, value)
	end
end

local function GetSampleField(sampleRaw: any): number?
	if typeof(sampleRaw) ~= "table" then
		return nil
	end
	return GetFiniteNumber(sampleRaw.parallaxHorizonY)
		or GetFiniteNumber(sampleRaw.smoothedSurfaceY)
		or GetFiniteNumber(sampleRaw.averageSurfaceY)
		or GetFiniteNumber(sampleRaw.surfaceY)
		or GetFiniteNumber(sampleRaw.worldSurfaceY)
end

local function computeMedian(samples: { number }): number?
	if #samples <= 0 then
		return nil
	end
	table.sort(samples)
	local midpoint = (#samples + 1) * 0.5
	local lower = math.floor(midpoint)
	local upper = math.ceil(midpoint)
	return (samples[lower] + samples[upper]) * 0.5
end

local function sampleExactSurfaceBand(
	service: any,
	cameraPosition: Vector3,
	subjectPosition: Vector3?,
	sampleRadiusStuds: number
): number?
	local samples: { number } = {}
	local center = subjectPosition or cameraPosition
	for index = 1, SURFACE_SAMPLE_COUNT do
		local alpha = if SURFACE_SAMPLE_COUNT == 1 then 0.5 else (index - 1) / (SURFACE_SAMPLE_COUNT - 1)
		local offsetZ = (alpha - 0.5) * sampleRadiusStuds * 2
		local samplePosition = Vector3.new(center.X, center.Y, center.Z + offsetZ)

		insertSurfaceSample(samples, safeCall(service, "GetSurfaceYAtWorldPosition", samplePosition))
		insertSurfaceSample(
			samples,
			GetSampleField(safeCall(service, "getParallaxSampleAtWorldPosition", samplePosition))
		)
	end
	return computeMedian(samples)
end

local function GetLocalSurfaceY(
	service: any,
	cameraPosition: Vector3,
	subjectPosition: Vector3?,
	sampleRadiusStuds: number
): number?
	local samplePosition = subjectPosition or cameraPosition
	local directHorizon = GetFiniteNumber(safeCall(service, "getParallaxHorizonYAtWorldPosition", samplePosition))
	if directHorizon ~= nil then
		return directHorizon
	end

	local smoothedSurface = GetFiniteNumber(safeCall(service, "getSmoothedSurfaceYAtWorldPosition", samplePosition))
	if smoothedSurface ~= nil then
		return smoothedSurface
	end

	local averageSurface = GetFiniteNumber(
		safeCall(service, "getAverageSurfaceYAroundWorldPosition", samplePosition, sampleRadiusStuds)
	)
	if averageSurface ~= nil then
		return averageSurface
	end

	local richSample = GetSampleField(safeCall(service, "getParallaxSampleAtWorldPosition", samplePosition))
	if richSample ~= nil then
		return richSample
	end

	return sampleExactSurfaceBand(service, cameraPosition, subjectPosition, sampleRadiusStuds)
end

function Horizon.GetHorizon(
	runtime: any,
	cameraPosition: Vector3,
	subjectPosition: Vector3?,
	_dt: number
): HorizonSample
	local layoutSnapshot = GetLayoutSnapshot(runtime)
	local tileSize = if typeof(layoutSnapshot) == "table"
		then CoerceNumber(layoutSnapshot.tileSize, DEFAULT_TILE_SIZE, 0.25)
		else DEFAULT_TILE_SIZE
	local chunkSize = if typeof(layoutSnapshot) == "table"
		then math.max(1, math.floor(CoerceNumber(layoutSnapshot.chunkSize, DEFAULT_CHUNK_SIZE, 1)))
		else DEFAULT_CHUNK_SIZE
	local sampleRadiusStuds = tileSize * chunkSize * 2
	local globalSurfaceY = GetGlobalSurfaceY(runtime)
	local localSurfaceY = GetLocalSurfaceY(
		GetWorldGenerationService(runtime),
		cameraPosition,
		subjectPosition,
		sampleRadiusStuds
	) or globalSurfaceY
	local horizonY = globalSurfaceY

	if typeof(runtime) == "table" then
		runtime.smoothedParallaxHorizonY = horizonY
	end

	local worldTopY = GetWorldTopY(runtime, globalSurfaceY)
	local cameraDepthFromTop = worldTopY - cameraPosition.Y
	local surfaceDepthFromTop = math.max(worldTopY - horizonY, 1)

	return {
		globalSurfaceY = globalSurfaceY,
		localSurfaceY = localSurfaceY,
		horizonY = horizonY,
		worldTopY = worldTopY,
		cameraDepthFromTop = cameraDepthFromTop,
		surfaceDepthFromTop = surfaceDepthFromTop,
	}
end


return Horizon
