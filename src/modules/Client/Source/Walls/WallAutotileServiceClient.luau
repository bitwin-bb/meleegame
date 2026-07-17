local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Table = require("Table")

local BuildServiceClient = require("BuildServiceClient")
local BuildServiceUtils = require("BuildServiceUtils")
local WallAutotileRegistry = require("WallAutotileRegistry")
local WallServiceUtils = require("WallServiceUtils")
local WorldGenerationConstants = require("WorldGenerationConstants")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

local WallAutotileServiceClient = {}
WallAutotileServiceClient.ServiceName = "WallAutotileServiceClient"

local DEFAULT_TILE_SIZE = WorldGenerationConstants.DEFAULT_TILE_SIZE
local DEFAULT_CHUNK_SIZE = WorldGenerationConstants.DEFAULT_CHUNK_SIZE
local DEFAULT_BASE_PLANE_X = WorldGenerationConstants.DEFAULT_BASE_PLANE_X

local WALL_DATA_BY_ID = {}
for wallId = WallServiceUtils.WALL_ID.DIRT, WallServiceUtils.MAX_WALL_ID do
	WALL_DATA_BY_ID[wallId] = Table.readonly({
		WallId = wallId,
		TileId = wallId,
	})
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getBuildState(): any?
	local state = (BuildServiceClient :: any).state
	return if typeof(state) == "table" then state else nil
end

function WallAutotileServiceClient.Init(self: any, _serviceBag: ServiceBag.ServiceBag)
	if self._maid ~= nil then
		return
	end

	self._maid = Maid.new()
	self._worldSeed = 0
	local function updateWorldSeed(stateRaw: any)
		if typeof(stateRaw) == "table" and isFiniteNumber((stateRaw :: any).seed) then
			self._worldSeed = math.floor((stateRaw :: any).seed)
		end
	end
	updateWorldSeed(WorldGenerationServiceClient:GetState())
	self._maid:GiveTask(WorldGenerationServiceClient.stateChanged:Connect(updateWorldSeed))
end

function WallAutotileServiceClient.GetChunkSize(_self: any): number
	local state = getBuildState()
	if state ~= nil and isFiniteNumber((state :: any).chunkSize) then
		return math.max(1, math.floor((state :: any).chunkSize))
	end
	return DEFAULT_CHUNK_SIZE
end

function WallAutotileServiceClient.GetTileSize(_self: any): number
	local state = getBuildState()
	if state ~= nil and isFiniteNumber((state :: any).tileSize) then
		return math.max(0.05, (state :: any).tileSize)
	end
	return DEFAULT_TILE_SIZE
end

function WallAutotileServiceClient.GetWallAt(_self: any, tileX: number, tileY: number): number
	return WorldGenerationServiceClient:GetWallAt(tileX, tileY)
end

function WallAutotileServiceClient.GetWallData(self: any, tileX: number, tileY: number): any?
	local wallId = self:GetWallAt(tileX, tileY)
	return WALL_DATA_BY_ID[wallId]
end

function WallAutotileServiceClient.GetWallVariantSeed(self: any, wallIdRaw: any): number
	local wallId = WallServiceUtils.CoerceWallId(wallIdRaw) or WallServiceUtils.WALL_ID.NONE
	return self._worldSeed + wallId * 104729
end

function WallAutotileServiceClient.GetWallSurfaceLayout(
	self: any,
	tileX: number,
	tileY: number,
	definitionRaw: any,
	_atlasResultRaw: any
): any
	local state = getBuildState()
	local tileSize = self:GetTileSize()
	local worldOrigin = if state ~= nil and typeof((state :: any).worldOrigin) == "Vector3"
		then (state :: any).worldOrigin
		else Vector3.zero
	local basePlaneX = if state ~= nil and isFiniteNumber((state :: any).basePlaneX)
		then (state :: any).basePlaneX
		else DEFAULT_BASE_PLANE_X
	local logicalTilePixels = if typeof(definitionRaw) == "table"
			and isFiniteNumber((definitionRaw :: any).LogicalTilePixels)
		then math.max(1, (definitionRaw :: any).LogicalTilePixels)
		else 16
	local wallPlaneX = worldOrigin.X + basePlaneX - WorldGenerationServiceClient:GetWallPlaneOffset()

	return {
		cframe = CFrame.new(BuildServiceUtils.TileToWorldCenter(tileX, tileY, worldOrigin, tileSize, wallPlaneX)),
		size = Vector3.new(WorldGenerationConstants.DEFAULT_TILE_DEPTH, tileSize, tileSize),
		pixelsPerStud = logicalTilePixels / tileSize,
	}
end

function WallAutotileServiceClient.SnapshotsHaveDifferentWalls(_self: any, nextRaw: any, previousRaw: any): boolean
	if typeof(nextRaw) ~= "table" or typeof(previousRaw) ~= "table" then
		return nextRaw ~= previousRaw
	end
	local nextWalls = (nextRaw :: any).walls
	local previousWalls = (previousRaw :: any).walls
	if typeof(nextWalls) ~= "table" or typeof(previousWalls) ~= "table" then
		return nextWalls ~= previousWalls
	end
	if #nextWalls ~= #previousWalls then
		return true
	end
	for wallIndex, wallId in nextWalls do
		if previousWalls[wallIndex] ~= wallId then
			return true
		end
	end
	return false
end

function WallAutotileServiceClient.GetMissingAtlasSources(_self: any): { string }
	local sources = {}
	for _, definition in WallAutotileRegistry.GetMissingImageDefinitions() do
		local sourceAsset = (definition :: any).SourceAsset
		if typeof(sourceAsset) == "string" and sourceAsset ~= "" then
			sources[#sources + 1] = sourceAsset
		end
	end
	return sources
end

function WallAutotileServiceClient.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self._worldSeed = nil
end

return WallAutotileServiceClient
