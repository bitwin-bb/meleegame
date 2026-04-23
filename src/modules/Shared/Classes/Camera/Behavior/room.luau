--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local RoomScaleFactor = require(script:FindFirstAncestor("game").Shared.Modules.Math.RoomScaleFactor)
local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildServiceUtils)
local BuildServiceClient = require(script:FindFirstAncestor("game").Client.Services.BuildServiceClient)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)

local Room = {}
Room.__index = Room

export type RoomConfig = RoomScaleFactor.RoomScaleFactorConfig
export type RoomScaleResult = RoomScaleFactor.RoomScaleResult
export type ViewConfig = {
	distance: number,
	height: number,
	lookHeight: number,
	fieldOfView: number,
}

export type Room = typeof(setmetatable(
	{} :: {
		config: RoomConfig,
		lastSampleAt: number,
		lastTileX: number?,
		lastTileY: number?,
		cachedScaleResult: RoomScaleResult,
	},
	Room
))

local DEFAULT_CONFIG = RoomScaleFactor.sanitizeConfig(((Configs.cameraData :: any).room or {}) :: RoomConfig)
local AIR_TILE_ID = BuildServiceUtils.AIR_TILE_ID

local function resolveWorldSpace(): (Vector3?, number?)
	local worldGenerationClient = WorldGenerationServiceClient :: any
	local worldGenerationState = worldGenerationClient.state
	local tileSize = if typeof(worldGenerationState) == "table" and typeof(worldGenerationState.tileSize) == "number"
		then worldGenerationState.tileSize
		else nil
	local worldOrigin = nil :: Vector3?
	if typeof(worldGenerationClient.worldOrigin) == "Vector3" then
		worldOrigin = worldGenerationClient.worldOrigin
	elseif typeof(worldGenerationState) == "table" and typeof((worldGenerationState :: any).worldOrigin) == "Vector3" then
		worldOrigin = (worldGenerationState :: any).worldOrigin
	end
	if worldOrigin ~= nil and tileSize ~= nil and tileSize > 0 then
		return worldOrigin, tileSize
	end

	local buildClient = BuildServiceClient :: any
	local buildState = buildClient.state
	if typeof(buildState) ~= "table" then
		return nil, nil
	end

	local buildWorldOrigin = if typeof((buildState :: any).worldOrigin) == "Vector3"
		then (buildState :: any).worldOrigin
		else nil
	local buildTileSize = if typeof((buildState :: any).tileSize) == "number" then (buildState :: any).tileSize else nil
	if buildWorldOrigin ~= nil and buildTileSize ~= nil and buildTileSize > 0 then
		return buildWorldOrigin, buildTileSize
	end

	return nil, nil
end

local function getTileAtFromWorldGeneration(tileX: number, tileY: number): number
	local worldGenerationClient = WorldGenerationServiceClient :: any
	local state = worldGenerationClient.state
	local chunkSnapshots = worldGenerationClient.chunkSnapshots
	if typeof(state) ~= "table" or typeof(chunkSnapshots) ~= "table" then
		return AIR_TILE_ID
	end

	local chunkSize = math.max(1, math.floor((state :: any).chunkSize or 32))
	local chunkX = BuildServiceUtils.toChunkCoordinate(tileX, chunkSize)
	local chunkY = BuildServiceUtils.toChunkCoordinate(tileY, chunkSize)
	local chunkKey = BuildServiceUtils.packChunkKey(chunkX, chunkY)
	local snapshot = chunkSnapshots[chunkKey]
	if typeof(snapshot) ~= "table" then
		return AIR_TILE_ID
	end

	local tileMinX = if typeof((snapshot :: any).tileMinX) == "number"
		then math.floor((snapshot :: any).tileMinX)
		else chunkX * chunkSize
	local tileMinY = if typeof((snapshot :: any).tileMinY) == "number"
		then math.floor((snapshot :: any).tileMinY)
		else chunkY * chunkSize
	local width = if typeof((snapshot :: any).width) == "number"
		then math.max(1, math.floor((snapshot :: any).width))
		else chunkSize
	local height = if typeof((snapshot :: any).height) == "number"
		then math.max(1, math.floor((snapshot :: any).height))
		else chunkSize
	local localX = tileX - tileMinX
	local localY = tileY - tileMinY
	if localX < 0 or localX >= width or localY < 0 or localY >= height then
		return AIR_TILE_ID
	end

	local tiles = (snapshot :: any).tiles
	if typeof(tiles) ~= "table" then
		return AIR_TILE_ID
	end

	local index = BuildServiceUtils.computeTileIndex(localX, localY, width)
	return BuildServiceUtils.sanitizeTileId(tiles[index]) or AIR_TILE_ID
end

local function getTileAt(tileX: number, tileY: number): number
	local buildClient = BuildServiceClient :: any
	if typeof(buildClient.state) == "table" then
		local ok, tileIdOrError = pcall(function()
			return buildClient:getTileAt(tileX, tileY, false)
		end)
		if ok then
			return BuildServiceUtils.sanitizeTileId(tileIdOrError) or AIR_TILE_ID
		end
	end

	return getTileAtFromWorldGeneration(tileX, tileY)
end

local function isSolidTile(tileX: number, tileY: number): boolean
	return BuildServiceUtils.isSolidTile(getTileAt(tileX, tileY))
end

local function resolveOriginTile(tileX: number, tileY: number): (number, number)
	for _, offsetY in { 0, 1, -1, 2, -2 } do
		local candidateTileY = tileY + offsetY
		if not isSolidTile(tileX, candidateTileY) then
			return tileX, candidateTileY
		end
	end
	return tileX, tileY
end

local function resolveBoundaryDistance(
	tileX: number,
	tileY: number,
	stepX: number,
	stepY: number,
	maxDistance: number
): number?
	for distance = 1, maxDistance do
		if isSolidTile(tileX + (stepX * distance), tileY + (stepY * distance)) then
			return distance
		end
	end
	return nil
end

function Room.New(config: RoomConfig?): Room
	return setmetatable({
		config = RoomScaleFactor.sanitizeConfig(config, DEFAULT_CONFIG),
		lastSampleAt = -math.huge,
		lastTileX = nil,
		lastTileY = nil,
		cachedScaleResult = RoomScaleFactor.createDefaultResult(),
	}, Room)
end

function Room.Reset(self: Room)
	self.lastSampleAt = -math.huge
	self.lastTileX = nil
	self.lastTileY = nil
	self.cachedScaleResult = RoomScaleFactor.createDefaultResult()
end

function Room.ApplyConfig(self: Room, config: RoomConfig?)
	self.config = RoomScaleFactor.sanitizeConfig(config, self.config)
	self:reset()
end

function Room.SampleScale(self: Room, worldPosition: Vector3): RoomScaleResult
	if self.config.enabled ~= true then
		self.cachedScaleResult = RoomScaleFactor.createDefaultResult()
		return self.cachedScaleResult
	end

	local worldOrigin, tileSize = resolveWorldSpace()
	if worldOrigin == nil or tileSize == nil then
		self.cachedScaleResult = RoomScaleFactor.createDefaultResult()
		return self.cachedScaleResult
	end

	local tileX, tileY = BuildServiceUtils.worldPositionToTile(worldPosition, worldOrigin, tileSize)
	tileX, tileY = resolveOriginTile(tileX, tileY)

	local now = os.clock()
	local sampleInterval = self.config.sampleIntervalSeconds :: number
	local shouldResample = self.lastTileX ~= tileX
		or self.lastTileY ~= tileY
		or (now - self.lastSampleAt) >= sampleInterval
	if not shouldResample then
		return self.cachedScaleResult
	end

	self.lastSampleAt = now
	self.lastTileX = tileX
	self.lastTileY = tileY

	local horizontalScanRadius = math.max(1, math.floor(self.config.horizontalScanRadiusTiles :: number))
	local verticalScanRadius = math.max(1, math.floor(self.config.verticalScanRadiusTiles :: number))
	local leftDistance = resolveBoundaryDistance(tileX, tileY, -1, 0, horizontalScanRadius)
	local rightDistance = resolveBoundaryDistance(tileX, tileY, 1, 0, horizontalScanRadius)
	local upDistance = resolveBoundaryDistance(tileX, tileY, 0, 1, verticalScanRadius)
	local downDistance = resolveBoundaryDistance(tileX, tileY, 0, -1, verticalScanRadius)
	local isEnclosed = leftDistance ~= nil and rightDistance ~= nil and upDistance ~= nil and downDistance ~= nil
	local widthTiles = if isEnclosed then math.max(1, (leftDistance :: number) + (rightDistance :: number) - 1) else 0
	local heightTiles = if isEnclosed then math.max(1, (upDistance :: number) + (downDistance :: number) - 1) else 0

	self.cachedScaleResult = RoomScaleFactor.resolve(self.config, {
		isEnclosed = isEnclosed,
		widthTiles = widthTiles,
		heightTiles = heightTiles,
		leftDistance = leftDistance,
		rightDistance = rightDistance,
		upDistance = upDistance,
		downDistance = downDistance,
	})
	return self.cachedScaleResult
end

function Room.ResolveViewConfig(self: Room, baseViewConfig: ViewConfig, targetPosition: Vector3?): ViewConfig
	if targetPosition == nil then
		return baseViewConfig
	end

	local scaleResult = self:sampleScale(targetPosition)
	if not scaleResult.active then
		return baseViewConfig
	end

	return {
		distance = baseViewConfig.distance * scaleResult.distanceScale,
		height = baseViewConfig.height * scaleResult.heightScale,
		lookHeight = baseViewConfig.lookHeight * scaleResult.lookHeightScale,
		fieldOfView = baseViewConfig.fieldOfView * scaleResult.fieldOfViewScale,
	}
end

Room.new = Room.New
Room.reset = Room.Reset
Room.applyConfig = Room.ApplyConfig
Room.sampleScale = Room.SampleScale
Room.resolveViewConfig = Room.ResolveViewConfig

return Room
