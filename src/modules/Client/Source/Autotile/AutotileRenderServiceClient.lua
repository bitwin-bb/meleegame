local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

local AutotileRegistry = require("AutotileRegistry")
local BuildServiceClient = require("BuildServiceClient")
local BuildServiceUtils = require("BuildServiceUtils")
local TileChunkBinderClient = require("TileChunkBinderClient")

local AutotileRenderServiceClient = {}
AutotileRenderServiceClient.ServiceName = "AutotileRenderServiceClient"

local DEFAULT_TILE_SIZE = 4
local DEFAULT_CHUNK_SIZE = 32
local DEFAULT_BASE_PLANE_X = 0
local DEFAULT_ATLAS_TILE_SIZE = 16

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getBuildState(): any?
	local state = (BuildServiceClient :: any).state
	return if typeof(state) == "table" then state else nil
end

local function coerceAtlasPixelSize(definitionRaw: any, atlasResultRaw: any): number
	if typeof(atlasResultRaw) == "table" then
		local imageRectSize = (atlasResultRaw :: any).ImageRectSize
		if typeof(imageRectSize) == "Vector2" and imageRectSize.X > 0 and imageRectSize.Y > 0 then
			return math.max(imageRectSize.X, imageRectSize.Y)
		end
	end

	if typeof(definitionRaw) == "table" then
		local tileSize = (definitionRaw :: any).TileSize
		if typeof(tileSize) == "Vector2" then
			return math.max(DEFAULT_ATLAS_TILE_SIZE, tileSize.X, tileSize.Y)
		end
		if isFiniteNumber(tileSize) then
			return math.max(DEFAULT_ATLAS_TILE_SIZE, tileSize :: number)
		end
	end

	return DEFAULT_ATLAS_TILE_SIZE
end

local function enqueueTileUpdate(pending: { any }, pendingLookup: { [string]: boolean }, tileX: number, tileY: number)
	local tileKey = BuildServiceUtils.PackTileKey(tileX, tileY)
	if pendingLookup[tileKey] then
		return
	end

	pendingLookup[tileKey] = true
	pending[#pending + 1] = {
		tileX = tileX,
		tileY = tileY,
	}
end

function AutotileRenderServiceClient.Init(self: any)
	if self._maid ~= nil then
		return
	end

	self._maid = Maid.new()
	self._chunkBinder = TileChunkBinderClient.new(self)
	self._maid:GiveTask(self._chunkBinder)
	self._chunkBinder:Start()

	if BuildServiceClient.tileDeltasApplied ~= nil then
		self._maid:GiveTask(BuildServiceClient.tileDeltasApplied:Connect(function(deltas: { any })
			self:OnTileDeltas(deltas)
		end))
	end

	if BuildServiceClient.stateChanged ~= nil then
		self._maid:GiveTask(BuildServiceClient.stateChanged:Connect(function()
			self:RefreshAll()
		end))
	end
end

function AutotileRenderServiceClient.GetChunkSize(_self: any): number
	local state = getBuildState()
	if typeof(state) == "table" and typeof((state :: any).chunkSize) == "number" then
		return math.max(1, math.floor((state :: any).chunkSize))
	end
	return DEFAULT_CHUNK_SIZE
end

function AutotileRenderServiceClient.GetTileSize(_self: any): number
	local state = getBuildState()
	if typeof(state) == "table" and isFiniteNumber((state :: any).tileSize) then
		return math.max(0.05, (state :: any).tileSize)
	end
	return DEFAULT_TILE_SIZE
end

function AutotileRenderServiceClient.GetWorldOrigin(_self: any): Vector3
	local state = getBuildState()
	if typeof(state) == "table" and typeof((state :: any).worldOrigin) == "Vector3" then
		return (state :: any).worldOrigin
	end
	return Vector3.zero
end

function AutotileRenderServiceClient.GetBasePlaneX(_self: any): number
	local state = getBuildState()
	if typeof(state) == "table" and isFiniteNumber((state :: any).basePlaneX) then
		return (state :: any).basePlaneX
	end
	return DEFAULT_BASE_PLANE_X
end

function AutotileRenderServiceClient.GetTileSurfaceLayout(
	self: any,
	tileX: number,
	tileY: number,
	definitionRaw: any,
	atlasResultRaw: any
): any
	local tileSize = self:GetTileSize()
	local atlasPixelSize = coerceAtlasPixelSize(definitionRaw, atlasResultRaw)

	return {
		cframe = CFrame.new(
			BuildServiceUtils.TileToWorldCenter(tileX, tileY, self:GetWorldOrigin(), tileSize, self:GetBasePlaneX())
		),
		size = Vector3.new(tileSize, tileSize, tileSize),
		pixelsPerStud = atlasPixelSize / tileSize,
	}
end

function AutotileRenderServiceClient.GetTileData(_self: any, tileX: number, tileY: number): any?
	local tileId = BuildServiceClient:GetTileAt(tileX, tileY, false)
	if tileId == BuildServiceUtils.AIR_TILE_ID then
		return nil
	end

	local definition = AutotileRegistry.GetDefinition(tileId)
	if definition == nil then
		return {
			TileId = tileId,
		}
	end

	return {
		TileId = tileId,
		ConnectGroup = (definition :: any).ConnectGroup,
	}
end

function AutotileRenderServiceClient.OnTileDeltas(self: any, deltasRaw: any)
	if typeof(deltasRaw) ~= "table" or self._chunkBinder == nil then
		return
	end

	local pending = {}
	local pendingLookup = {}
	for _, deltaRaw in deltasRaw do
		if typeof(deltaRaw) ~= "table" then
			continue
		end

		local tileX = BuildServiceUtils.CoerceTileCoordinate((deltaRaw :: any).tileX)
		local tileY = BuildServiceUtils.CoerceTileCoordinate((deltaRaw :: any).tileY)
		if tileX ~= nil and tileY ~= nil then
			for offsetX = -1, 1 do
				for offsetY = -1, 1 do
					enqueueTileUpdate(pending, pendingLookup, tileX + offsetX, tileY + offsetY)
				end
			end
		end
	end

	for _, coordinate in pending do
		self._chunkBinder:UpdateTile(coordinate.tileX, coordinate.tileY)
	end
end

function AutotileRenderServiceClient.RefreshAll(self: any)
	if self._chunkBinder ~= nil then
		self._chunkBinder:RefreshAll()
	end
end

function AutotileRenderServiceClient.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self._chunkBinder = nil
end

return AutotileRenderServiceClient
