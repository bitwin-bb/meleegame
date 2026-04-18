--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local ChunkBinder = {}
ChunkBinder.__index = ChunkBinder
setmetatable(ChunkBinder, ModelBinder)

local worldAnimatorServiceClient = nil

local function getWorldAnimatorServiceClient()
	if worldAnimatorServiceClient == nil then
		worldAnimatorServiceClient =
			require(script:FindFirstAncestor("game").Client.Services.WorldAnimatorService.WorldAnimatorServiceClient)
	end
	return worldAnimatorServiceClient
end

function ChunkBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, ChunkBinder)
	self.model = self:GetModel()
	self:updateMetadata()

	if self.model ~= nil then
		pcall(function()
			getWorldAnimatorServiceClient():onChunkAdded(self.model)
		end)
	end

	return self
end

function ChunkBinder.updateMetadata(self: any)
	local chunkKey = self.instance:GetAttribute("ChunkKey")
	self.instance:SetAttribute("ChunkTagged", true)
	if typeof(chunkKey) == "string" and chunkKey ~= "" then
		self.instance:SetAttribute("ChunkBinderKey", chunkKey)
	end
end

function ChunkBinder.Cleanup(self: any)
	if self.model ~= nil then
		pcall(function()
			getWorldAnimatorServiceClient():onChunkRemoved(self.model)
		end)
	end
end

return ChunkBinder
