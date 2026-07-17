local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

local CullServiceClient = require("CullServiceClient")
local TileChunkRender = require("TileChunkRender")
local TileLayerRenderer = require("TileLayerRenderer")
local WallChunkRender = require("WallChunkRender")
local WallLayerRenderer = require("WallLayerRenderer")

local TileChunkRenderer = {}
TileChunkRenderer.__index = TileChunkRenderer

local function getNumberAttribute(instance: Instance, names: { string }, fallback: number): number
	for _, name in names do
		local value = instance:GetAttribute(name)
		if typeof(value) == "number" then
			return math.floor(value)
		end
	end
	return fallback
end

local function parseChunkKey(chunkKeyRaw: any): (number?, number?)
	if typeof(chunkKeyRaw) ~= "string" then
		return nil, nil
	end

	local chunkXRaw, chunkYRaw = string.match(chunkKeyRaw, "^(-?%d+):(-?%d+)$")
	if chunkXRaw == nil or chunkYRaw == nil then
		return nil, nil
	end

	return tonumber(chunkXRaw), tonumber(chunkYRaw)
end

function TileChunkRenderer.new(chunkInstance: Instance, contextRaw: any?): any
	local self: any = setmetatable({
		_maid = Maid.new(),
		_chunkInstance = chunkInstance,
		_context = if typeof(contextRaw) == "table" then contextRaw else {},
	}, TileChunkRenderer)

	self:_refreshBounds()
	self._layerRenderer = TileLayerRenderer.new(chunkInstance, self._width, self._height)
	self._maid:GiveTask(self._layerRenderer)
	local wallRenderService = self._context.wallRenderService
	local autotileContainer = self._layerRenderer:GetContainer()
	if wallRenderService ~= nil and autotileContainer ~= nil then
		self._wallLayerRenderer = WallLayerRenderer.new(autotileContainer, self._width, self._height)
		self._maid:GiveTask(self._wallLayerRenderer)
	end
	self._cullClient = CullServiceClient:CreateClient({
		key = self._chunkKey,
		tileMinX = self._tileMinX,
		tileMinY = self._tileMinY,
		width = self._width,
		height = self._height,
		renderTile = function(tileX: number, tileY: number)
			self:_renderTile(tileX, tileY)
		end,
		clearTile = function(tileX: number, tileY: number)
			self:_clearTile(tileX, tileY)
		end,
		clearAll = function()
			if self._layerRenderer ~= nil then
				self._layerRenderer:Clear()
			end
			if self._wallLayerRenderer ~= nil then
				self._wallLayerRenderer:Clear()
			end
		end,
	})

	return self
end

function TileChunkRenderer._refreshBounds(self: any)
	local renderService = self._context.renderService
	local chunkSize = if renderService ~= nil and typeof((renderService :: any).GetChunkSize) == "function"
		then (renderService :: any):GetChunkSize()
		else 32
	chunkSize = math.max(1, math.floor(chunkSize))

	local chunkX, chunkY = parseChunkKey(self._chunkInstance:GetAttribute("ChunkKey"))
	chunkX = getNumberAttribute(self._chunkInstance, { "ChunkX", "chunkX" }, chunkX or 0)
	chunkY = getNumberAttribute(self._chunkInstance, { "ChunkY", "chunkY" }, chunkY or 0)
	self._chunkKey = `{chunkX}:{chunkY}`

	self._chunkSize = math.max(1, getNumberAttribute(self._chunkInstance, { "ChunkSize", "chunkSize" }, chunkSize))
	self._tileMinX = getNumberAttribute(self._chunkInstance, { "TileMinX", "tileMinX" }, chunkX * self._chunkSize)
	self._tileMinY = getNumberAttribute(self._chunkInstance, { "TileMinY", "tileMinY" }, chunkY * self._chunkSize)
	self._width =
		math.max(1, getNumberAttribute(self._chunkInstance, { "Width", "TileWidth", "tileWidth" }, self._chunkSize))
	self._height =
		math.max(1, getNumberAttribute(self._chunkInstance, { "Height", "TileHeight", "tileHeight" }, self._chunkSize))
end

function TileChunkRenderer.ContainsTile(self: any, tileX: number, tileY: number): boolean
	return tileX >= self._tileMinX
		and tileX < self._tileMinX + self._width
		and tileY >= self._tileMinY
		and tileY < self._tileMinY + self._height
end

function TileChunkRenderer.GetTileData(self: any, tileX: number, tileY: number): any?
	local renderService = self._context.renderService
	if renderService ~= nil and typeof((renderService :: any).GetTileData) == "function" then
		return (renderService :: any):GetTileData(tileX, tileY)
	end
	return nil
end

function TileChunkRenderer.GetTileSurfaceLayout(
	self: any,
	tileX: number,
	tileY: number,
	definition: any,
	atlasResult: any
)
	local renderService = self._context.renderService
	if renderService ~= nil and typeof((renderService :: any).GetTileSurfaceLayout) == "function" then
		return (renderService :: any):GetTileSurfaceLayout(tileX, tileY, definition, atlasResult)
	end
	return nil
end

function TileChunkRenderer.RenderInitial(self: any)
	if self._cullClient == nil then
		return
	end

	if CullServiceClient:IsConfigured() then
		CullServiceClient:RefreshClient(self._cullClient)
		return
	end

	-- standalone renderers reconcile the chunk without a camera service
	self._cullClient:SetVisibleBounds(self._cullClient:GetChunkBounds())
	while self._cullClient:HasWork() do
		self._cullClient:Step(256)
	end
end

function TileChunkRenderer.UpdateTileAndNeighbors(self: any, tileX: number, tileY: number)
	for offsetX = -1, 1 do
		for offsetY = -1, 1 do
			self:UpdateTile(tileX + offsetX, tileY + offsetY)
		end
	end
end

function TileChunkRenderer._clearTile(self: any, tileX: number, tileY: number)
	if not self:ContainsTile(tileX, tileY) then
		return
	end

	local localX = tileX - self._tileMinX
	local localY = tileY - self._tileMinY
	if self._layerRenderer ~= nil then
		self._layerRenderer:ClearTile(localX, localY)
	end
	if self._wallLayerRenderer ~= nil then
		self._wallLayerRenderer:ClearTile(localX, localY)
	end
end

function TileChunkRenderer._renderTile(self: any, tileX: number, tileY: number)
	if not self:ContainsTile(tileX, tileY) then
		return
	end

	local localX = tileX - self._tileMinX
	local localY = tileY - self._tileMinY
	if self._layerRenderer ~= nil then
		local resolved = TileChunkRender.Resolve(self._context.renderService, tileX, tileY)
		if resolved == nil then
			self._layerRenderer:ClearTile(localX, localY)
		else
			self._layerRenderer:SetTile(localX, localY, resolved.atlasResult, resolved.layout)
		end
	end

	if self._wallLayerRenderer ~= nil then
		local wallResolved = WallChunkRender.Resolve(self._context.wallRenderService, tileX, tileY)
		if wallResolved == nil then
			self._wallLayerRenderer:ClearTile(localX, localY)
		else
			self._wallLayerRenderer:SetTile(localX, localY, wallResolved.atlasResult, wallResolved.layout)
		end
	end
end

function TileChunkRenderer.UpdateTile(self: any, tileX: number, tileY: number)
	if
		self._cullClient == nil
		or not self._cullClient:IsTileVisible(tileX, tileY)
		or not self._cullClient:IsTileActive(tileX, tileY)
	then
		return
	end

	self:_renderTile(tileX, tileY)
end

function TileChunkRenderer.Destroy(self: any)
	if self._cullClient ~= nil then
		CullServiceClient:Unregister(self._cullClient)
		self._cullClient:Destroy()
		self._cullClient = nil
	end
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
end

return TileChunkRenderer
