--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local ServerChunkBinder = {}
ServerChunkBinder.__index = ServerChunkBinder
setmetatable(ServerChunkBinder, ModelBinder)

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

function ServerChunkBinder.new(instance: any, context: any)
	local self = ModelBinder.new(instance, context, ServerChunkBinder) :: any
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

function ServerChunkBinder.updateMetadata(self: any)
	local chunkKey = self.instance:GetAttribute("ChunkKey")
	if typeof(chunkKey) ~= "string" then
		chunkKey = ""
	end

	self.chunkKey = chunkKey
	self.chunkX, self.chunkY = parseChunkKey(chunkKey)
	self.instance:SetAttribute("ServerChunkTagged", true)
	self.instance:SetAttribute("ServerChunkBinderKey", chunkKey)
	self.instance:SetAttribute("ServerChunkBinderReady", true)
end

function ServerChunkBinder.GetChunkKey(self: any): string
	return self.chunkKey
end

function ServerChunkBinder.GetChunkCoordinates(self: any): (number?, number?)
	return self.chunkX, self.chunkY
end

return ServerChunkBinder
