
local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local LiquidBinder = {}
LiquidBinder.__index = LiquidBinder
setmetatable(LiquidBinder, ModelBinder)

function LiquidBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, LiquidBinder)
	self:UpdateMetadata()
	return self
end

function LiquidBinder.UpdateMetadata(self: any)
	local chunkKey = self.instance:GetAttribute("ChunkKey")
	self.instance:SetAttribute("LiquidTagged", true)
	if typeof(chunkKey) == "string" and chunkKey ~= "" then
		self.instance:SetAttribute("LiquidChunkKey", chunkKey)
	end
end

return LiquidBinder
