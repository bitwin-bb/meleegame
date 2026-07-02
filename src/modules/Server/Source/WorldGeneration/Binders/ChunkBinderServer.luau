
local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local ChunkBinderServer = {}
ChunkBinderServer.__index = ChunkBinderServer
setmetatable(ChunkBinderServer, ModelBinder)

local function parseChunkKey(chunkKeyRaw: any): (number?, number?)
	if typeof(chunkKeyRaw) ~= "string" then
		return nil, nil
	end

	local xRaw, yRaw = string.match(chunkKeyRaw, "^(-?%d+):(-?%d+)$")
	if xRaw == nil or yRaw == nil then
		return nil, nil
	end

	return tonumber(xRaw), tonumber(yRaw)
end

function ChunkBinderServer.new(instance: any, context: any)
	local self = ModelBinder.new(instance, context, ChunkBinderServer) :: any
	self.model = self:GetModel()
	self.chunkKey = ""
	self.chunkX = nil :: number?
	self.chunkY = nil :: number?

	self:updateMetadata()
	self:ObserveAttribute("ChunkKey", function()
		self:updateMetadata()
	end)

	return self
end

function ChunkBinderServer.updateMetadata(self: any)
	local chunkKey = self.instance:GetAttribute("ChunkKey")
	if typeof(chunkKey) ~= "string" then
		chunkKey = ""
	end

	self.chunkKey = chunkKey
	self.chunkX, self.chunkY = parseChunkKey(chunkKey)
	self.instance:SetAttribute("ServerChunkTagged", true)
	self.instance:SetAttribute("ChunkBinderServerKey", chunkKey)
	self.instance:SetAttribute("ChunkBinderServerReady", true)
end

function ChunkBinderServer.GetChunkKey(self: any): string
	return self.chunkKey
end

function ChunkBinderServer.GetChunkCoordinates(self: any): (number?, number?)
	return self.chunkX, self.chunkY
end

return ChunkBinderServer
