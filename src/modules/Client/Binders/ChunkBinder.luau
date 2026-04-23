--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local ChunkBinder = {}
ChunkBinder.__index = ChunkBinder
setmetatable(ChunkBinder, ModelBinder)

local SKIP_WORLD_ANIMATOR_ATTRIBUTE = "SkipWorldAnimator"
local WORLD_ANIMATOR_RUNTIME_FOLDER_NAME = "WorldAnimatorRuntime"

local worldAnimatorServiceClient = nil

local function getWorldAnimatorServiceClient()
	if worldAnimatorServiceClient == nil then
		worldAnimatorServiceClient =
			require(script:FindFirstAncestor("game").Client.Services.WorldAnimatorServiceClient)
	end
	return worldAnimatorServiceClient
end

local function isInWorldAnimatorRuntime(instance: Instance): boolean
	local current = instance.Parent
	while current ~= nil do
		if current.Name == WORLD_ANIMATOR_RUNTIME_FOLDER_NAME then
			return true
		end
		current = current.Parent
	end
	return false
end

local function shouldNotifyWorldAnimator(model: Model?): boolean
	if model == nil then
		return false
	end
	if model:GetAttribute(SKIP_WORLD_ANIMATOR_ATTRIBUTE) == true then
		return false
	end
	return not isInWorldAnimatorRuntime(model)
end

function ChunkBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, ChunkBinder)
	self.model = self:GetModel()
	self:updateMetadata()

	if shouldNotifyWorldAnimator(self.model) then
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
	if shouldNotifyWorldAnimator(self.model) then
		pcall(function()
			getWorldAnimatorServiceClient():onChunkRemoved(self.model)
		end)
	end
end

return ChunkBinder
