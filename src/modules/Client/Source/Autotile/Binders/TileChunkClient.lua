local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local TileChunkRenderer = require("TileChunkRenderer")

local TileChunkClient = {}
TileChunkClient.__index = TileChunkClient
setmetatable(TileChunkClient, ModelBinder)

local AUTOTILE_PRESENTATION_CHUNK_ATTRIBUTE = "AutotilePresentationChunk"

function TileChunkClient.new(instance: Instance, context: any): any
	local self = ModelBinder.new(instance, context, TileChunkClient)
	if instance:GetAttribute(AUTOTILE_PRESENTATION_CHUNK_ATTRIBUTE) ~= true then
		return self
	end

	self.renderer = TileChunkRenderer.new(instance, context)
	self:AddCleanup(self.renderer)
	self.renderer:RenderInitial()
	return self
end

function TileChunkClient.ContainsTile(self: any, tileX: number, tileY: number): boolean
	return self.renderer ~= nil and self.renderer:ContainsTile(tileX, tileY)
end

function TileChunkClient.UpdateTile(self: any, tileX: number, tileY: number)
	if self.renderer ~= nil then
		self.renderer:UpdateTile(tileX, tileY)
	end
end

function TileChunkClient.UpdateTileAndNeighbors(self: any, tileX: number, tileY: number)
	if self.renderer ~= nil then
		self.renderer:UpdateTileAndNeighbors(tileX, tileY)
	end
end

function TileChunkClient.Cleanup(self: any)
	self.renderer = nil
end

return TileChunkClient
