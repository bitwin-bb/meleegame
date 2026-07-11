local require = require(script.Parent.loader).load(script)

local Binder = require("Binder")
local Maid = require("Maid")
local Table = require("Table")

local BuildServiceUtils = require("BuildServiceUtils")
local TagBinder = require("TagBinder")
local TileChunkClient = require("TileChunkClient")

local TileChunkBinderClient = {}
TileChunkBinderClient.__index = TileChunkBinderClient

local function createContext(renderService: any): { renderService: any, tags: { string } }
	return Table.readonly({
		renderService = renderService,
		tags = table.freeze({ TagBinder.Tags.Chunk }),
	})
end

local function getNumberAttribute(instance: Instance, names: { string }): number?
	for _, name in names do
		local value = instance:GetAttribute(name)
		if typeof(value) == "number" then
			return math.floor(value)
		end
	end
	return nil
end

local function getChunkKeyForInstance(instance: Instance): string?
	local chunkKeyRaw = instance:GetAttribute("ChunkKey")
	local chunkX, chunkY = BuildServiceUtils.UnpackChunkKey(chunkKeyRaw)
	if chunkX ~= nil and chunkY ~= nil then
		return chunkKeyRaw :: string
	end

	chunkX = getNumberAttribute(instance, { "ChunkX", "chunkX" })
	chunkY = getNumberAttribute(instance, { "ChunkY", "chunkY" })
	if chunkX == nil or chunkY == nil then
		return nil
	end

	return BuildServiceUtils.PackChunkKey(chunkX, chunkY)
end

local function getChunkKeyForTile(renderService: any, tileX: number, tileY: number): string
	local chunkSize = 32
	if renderService ~= nil and typeof((renderService :: any).GetChunkSize) == "function" then
		local chunkSizeRaw = (renderService :: any):GetChunkSize()
		if typeof(chunkSizeRaw) == "number" then
			chunkSize = chunkSizeRaw
		end
	end
	chunkSize = math.max(1, math.floor(chunkSize))

	local chunkX = BuildServiceUtils.ToChunkCoordinate(tileX, chunkSize)
	local chunkY = BuildServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	return BuildServiceUtils.PackChunkKey(chunkX, chunkY)
end

function TileChunkBinderClient.new(renderService: any): any
	local self = setmetatable({
		_maid = Maid.new(),
		_chunkClientsByKey = {},
		_renderService = renderService,
	}, TileChunkBinderClient)

	local context = createContext(renderService)
	self._binder = Binder.new(TagBinder.Tags.Chunk, function(instance: Instance)
		local chunkClient = TileChunkClient.new(instance, context)
		local chunkKey = getChunkKeyForInstance(instance)
		if chunkKey ~= nil then
			self._chunkClientsByKey[chunkKey] = chunkClient
			chunkClient:AddCleanup(function()
				if self._chunkClientsByKey ~= nil and self._chunkClientsByKey[chunkKey] == chunkClient then
					self._chunkClientsByKey[chunkKey] = nil
				end
			end)
		end
		return chunkClient
	end)
	self._binder:Init()
	self._maid:GiveTask(self._binder)
	return self
end

function TileChunkBinderClient.Start(self: any)
	self._binder:Start()
end

function TileChunkBinderClient.GetAll(self: any): { any }
	return self._binder:GetAll()
end

function TileChunkBinderClient.UpdateTile(self: any, tileX: number, tileY: number)
	local chunkKey = getChunkKeyForTile(self._renderService, tileX, tileY)
	local indexedChunkClient = if self._chunkClientsByKey ~= nil then self._chunkClientsByKey[chunkKey] else nil
	if indexedChunkClient ~= nil and indexedChunkClient:ContainsTile(tileX, tileY) then
		indexedChunkClient:UpdateTile(tileX, tileY)
		return
	end

	for _, chunkClient in self._binder:GetAll() do
		if chunkClient:ContainsTile(tileX, tileY) then
			chunkClient:UpdateTile(tileX, tileY)
		end
	end
end

function TileChunkBinderClient.UpdateTileAndNeighbors(self: any, tileX: number, tileY: number)
	for offsetX = -1, 1 do
		for offsetY = -1, 1 do
			self:UpdateTile(tileX + offsetX, tileY + offsetY)
		end
	end
end

function TileChunkBinderClient.RefreshAll(self: any)
	for _, chunkClient in self._binder:GetAll() do
		if chunkClient.renderer ~= nil then
			chunkClient.renderer:RenderInitial()
		end
	end
end

function TileChunkBinderClient.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self._chunkClientsByKey = nil
end

return TileChunkBinderClient
