local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local ChunkBinder = {}
ChunkBinder.__index = ChunkBinder
setmetatable(ChunkBinder, ModelBinder)

function ChunkBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, ChunkBinder)
	self.model = self:GetModel()
	self:UpdateMetadata()

	return self
end

function ChunkBinder.UpdateMetadata(self: any)
	local chunkKey = self.instance:GetAttribute("ChunkKey")
	self.instance:SetAttribute("ChunkTagged", true)
	if typeof(chunkKey) == "string" and chunkKey ~= "" then
		self.instance:SetAttribute("ChunkBinderKey", chunkKey)
	end
end

function ChunkBinder.Cleanup(_self: any) end

return ChunkBinder
