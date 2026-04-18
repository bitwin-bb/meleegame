--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local LiquidBinder = {}
LiquidBinder.__index = LiquidBinder
setmetatable(LiquidBinder, ModelBinder)

function LiquidBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, LiquidBinder)
	self:updateMetadata()
	return self
end

function LiquidBinder.updateMetadata(self: any)
	local chunkKey = self.instance:GetAttribute("ChunkKey")
	self.instance:SetAttribute("LiquidTagged", true)
	if typeof(chunkKey) == "string" and chunkKey ~= "" then
		self.instance:SetAttribute("LiquidChunkKey", chunkKey)
	end
end

return LiquidBinder
