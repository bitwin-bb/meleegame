local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

local AtlasResolver = require("AtlasResolver")
local AutotileRegistry = require("AutotileRegistry")
local EightWayBlobRule = require("EightWayBlobRule")
local FourWay16Rule = require("FourWay16Rule")
local Full256Rule = require("Full256Rule")
local MaskResolver = require("MaskResolver")
local TileLayerRenderer = require("TileLayerRenderer")

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

local function getRuleForDefinition(definition: any): any
	local mode = if typeof(definition) == "table" then (definition :: any).Mode else nil
	if mode == "FourWay16" then
		return FourWay16Rule
	end
	if mode == "Full256" then
		return Full256Rule
	end
	return EightWayBlobRule
end

local function shouldRenderSurfaceGuiDefinition(definition: any): boolean
	return typeof(definition) == "table" and rawget(definition, "UseSurfaceGui") == true
end

function TileChunkRenderer.new(chunkInstance: Instance, contextRaw: any?): any
	local self = setmetatable({
		_maid = Maid.new(),
		_chunkInstance = chunkInstance,
		_context = if typeof(contextRaw) == "table" then contextRaw else {},
	}, TileChunkRenderer)

	self:_refreshBounds()
	self._layerRenderer = TileLayerRenderer.new(chunkInstance)
	self._maid:GiveTask(self._layerRenderer)

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

	self._chunkSize = getNumberAttribute(self._chunkInstance, { "ChunkSize", "chunkSize" }, chunkSize)
	self._tileMinX = getNumberAttribute(self._chunkInstance, { "TileMinX", "tileMinX" }, chunkX * self._chunkSize)
	self._tileMinY = getNumberAttribute(self._chunkInstance, { "TileMinY", "tileMinY" }, chunkY * self._chunkSize)
	self._width = getNumberAttribute(self._chunkInstance, { "Width", "TileWidth", "tileWidth" }, self._chunkSize)
	self._height = getNumberAttribute(self._chunkInstance, { "Height", "TileHeight", "tileHeight" }, self._chunkSize)
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
	for localY = 0, self._height - 1 do
		for localX = 0, self._width - 1 do
			self:UpdateTile(self._tileMinX + localX, self._tileMinY + localY)
		end
	end
end

function TileChunkRenderer.UpdateTileAndNeighbors(self: any, tileX: number, tileY: number)
	for offsetX = -1, 1 do
		for offsetY = -1, 1 do
			self:UpdateTile(tileX + offsetX, tileY + offsetY)
		end
	end
end

function TileChunkRenderer.UpdateTile(self: any, tileX: number, tileY: number)
	if self._layerRenderer == nil or not self:ContainsTile(tileX, tileY) then
		return
	end

	local localX = tileX - self._tileMinX
	local localY = tileY - self._tileMinY
	local tileData = self:GetTileData(tileX, tileY)
	if typeof(tileData) ~= "table" then
		self._layerRenderer:ClearTile(localX, localY)
		return
	end

	local tileId = (tileData :: any).TileId or (tileData :: any).tileId
	local definition = AutotileRegistry.GetDefinition(tileId)
	if not shouldRenderSurfaceGuiDefinition(definition) then
		self._layerRenderer:ClearTile(localX, localY)
		return
	end

	local mask = MaskResolver.Resolve(function(scanX: number, scanY: number)
		return self:GetTileData(scanX, scanY)
	end, Vector2.new(tileX, tileY), getRuleForDefinition(definition))
	local atlasResult = AtlasResolver.Resolve(definition, mask, Vector2.new(tileX, tileY), rawget(definition, "VariantSeed"))
	self._layerRenderer:SetTile(
		localX,
		localY,
		atlasResult,
		self:GetTileSurfaceLayout(tileX, tileY, definition, atlasResult)
	)
end

function TileChunkRenderer.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
end

return TileChunkRenderer
