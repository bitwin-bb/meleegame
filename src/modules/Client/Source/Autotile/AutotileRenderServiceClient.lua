local require = require(script.Parent.loader).load(script)

local BinderSupportClient = require("BinderSupportClient")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

local AutotileRegistry = require("AutotileRegistry")
local BuildServiceClient = require("BuildServiceClient")
local BuildServiceUtils = require("BuildServiceUtils")
local TagBinder = require("TagBinder")
local TileRenderServiceClient = require("TileRenderServiceClient")
local WallAutotileServiceClient = require("WallAutotileServiceClient")
local WorldGenerationConstants = require("WorldGenerationConstants")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

local AutotileRenderServiceClient = {}
AutotileRenderServiceClient.ServiceName = "AutotileRenderServiceClient"

local DEFAULT_TILE_SIZE = 2
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
	if typeof(definitionRaw) == "table" then
		local tileSize = (definitionRaw :: any).TileSize
		if typeof(tileSize) == "Vector2" then
			return math.max(DEFAULT_ATLAS_TILE_SIZE, tileSize.X, tileSize.Y)
		end
		if isFiniteNumber(tileSize) then
			return math.max(DEFAULT_ATLAS_TILE_SIZE, tileSize :: number)
		end
	end

	if typeof(atlasResultRaw) == "table" then
		local imageRectSize = (atlasResultRaw :: any).ImageRectSize
		if typeof(imageRectSize) == "Vector2" and imageRectSize.X > 0 and imageRectSize.Y > 0 then
			return math.max(imageRectSize.X, imageRectSize.Y)
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

local function getChunkKeyForInstance(instance: Instance): string?
	local chunkKeyRaw = instance:GetAttribute("ChunkKey")
	local chunkX, chunkY = BuildServiceUtils.UnpackChunkKey(chunkKeyRaw)
	if chunkX ~= nil and chunkY ~= nil then
		return chunkKeyRaw :: string
	end
	return nil
end

local function getChunkKeyForTile(self: any, tileX: number, tileY: number): string
	local chunkSize = self:GetChunkSize()
	return BuildServiceUtils.PackChunkKey(
		BuildServiceUtils.ToChunkCoordinate(tileX, chunkSize),
		BuildServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	)
end

local function updateTile(self: any, tileX: number, tileY: number)
	local chunkKey = getChunkKeyForTile(self, tileX, tileY)
	local indexedChunkClient = self._chunkClientsByKey[chunkKey]
	if indexedChunkClient ~= nil and indexedChunkClient:ContainsTile(tileX, tileY) then
		indexedChunkClient:UpdateTile(tileX, tileY)
		return
	end

	for _, chunkClient in self._chunkBinder:GetAll() do
		if chunkClient:ContainsTile(tileX, tileY) then
			chunkClient:UpdateTile(tileX, tileY)
		end
	end
end

function AutotileRenderServiceClient.Init(self: any, serviceBag: ServiceBag.ServiceBag)
	if self._maid ~= nil then
		return
	end

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._chunkBinder = serviceBag:GetService(BinderSupportClient):Get(TagBinder.Tags.Chunk)
	self._wallRenderService = serviceBag:GetService(WallAutotileServiceClient)
	self._chunkClientsByKey = {}
	local function registerChunkClient(chunkClient: any)
		local chunkKey = getChunkKeyForInstance(chunkClient._obj)
		if chunkKey ~= nil and chunkClient.renderer ~= nil then
			self._chunkClientsByKey[chunkKey] = chunkClient
		end
	end
	for _, chunkClient in self._chunkBinder:GetAll() do
		registerChunkClient(chunkClient)
	end
	self._maid:GiveTask(self._chunkBinder:GetClassAddedSignal():Connect(registerChunkClient))
	self._maid:GiveTask(self._chunkBinder:GetClassRemovingSignal():Connect(function(chunkClient: any)
		local chunkKey = getChunkKeyForInstance(chunkClient._obj)
		if chunkKey ~= nil and self._chunkClientsByKey[chunkKey] == chunkClient then
			self._chunkClientsByKey[chunkKey] = nil
		end
	end))
	self._renderScheduler = TileRenderServiceClient.new({
		tileDeltasApplied = BuildServiceClient.tileDeltasApplied,
		stateChanged = BuildServiceClient.stateChanged,
		updateTile = function(tileX: number, tileY: number)
			if self._chunkBinder ~= nil then
				updateTile(self, tileX, tileY)
			end
		end,
		refreshAll = function()
			self:RefreshAll()
		end,
	})
	self._maid:GiveTask(self._renderScheduler)
	self._maid:GiveTask(
		WorldGenerationServiceClient.chunkSnapshotsChanged:Connect(
			function(chunkKey: string, nextSnapshot: any, previousSnapshot: any)
				if self._renderScheduler ~= nil then
					local chunkSize = self:GetChunkSize()
					self._renderScheduler:QueueChunkBoundary(chunkKey, chunkSize)
					if self._wallRenderService:SnapshotsHaveDifferentWalls(nextSnapshot, previousSnapshot) then
						self._renderScheduler:QueueChunk(chunkKey, chunkSize)
					end
				end
			end
		)
	)
	self._renderScheduler:RequestRefresh()
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
	local worldOrigin = self:GetWorldOrigin()
	local surfacePlaneX = worldOrigin.X + self:GetBasePlaneX()

	return {
		cframe = CFrame.new(BuildServiceUtils.TileToWorldCenter(tileX, tileY, worldOrigin, tileSize, surfacePlaneX)),
		size = Vector3.new(WorldGenerationConstants.DEFAULT_TILE_DEPTH, tileSize, tileSize),
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
		updateTile(self, coordinate.tileX, coordinate.tileY)
	end
end

function AutotileRenderServiceClient.RefreshAll(self: any)
	if self._chunkBinder ~= nil then
		for _, chunkClient in self._chunkBinder:GetAll() do
			if chunkClient.renderer ~= nil then
				chunkClient.renderer:RenderInitial()
			end
		end
	end
end

function AutotileRenderServiceClient.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self._serviceBag = nil
	self._chunkBinder = nil
	self._chunkClientsByKey = nil
	self._renderScheduler = nil
	self._wallRenderService = nil
end

return AutotileRenderServiceClient
