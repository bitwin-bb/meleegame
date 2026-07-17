
local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local LayerBinder = {}
LayerBinder.__index = LayerBinder
setmetatable(LayerBinder, ModelBinder)

local function getNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

local function getLayerIndex(instance: Instance): number
	local attributeValue = instance:GetAttribute("LayerIndex")
	if typeof(attributeValue) == "number" then
		return math.max(1, math.floor(attributeValue))
	end

	local numericSuffix = string.match(instance.Name, "(%d+)$")
	if numericSuffix ~= nil then
		return math.max(1, tonumber(numericSuffix) or 1)
	end

	return 1
end

function LayerBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, LayerBinder)
	self.parts = ModelBinder.CollectBaseParts(instance)

	self:Refresh()
	self:ObserveAttribute("LayerTransparency", function()
		self:Refresh()
	end)
	self:ObserveAttribute("LayerVisible", function()
		self:Refresh()
	end)

	return self
end

function LayerBinder.Refresh(self: any)
	local visible = self.instance:GetAttribute("LayerVisible") ~= false
	local transparency = math.clamp(getNumberAttribute(self.instance, "LayerTransparency", 0), 0, 1)
	local localTransparencyModifier = if visible then transparency else 1
	local layerIndex = getLayerIndex(self.instance)

	self.instance:SetAttribute("LayerTagged", true)
	self.instance:SetAttribute("LayerIndex", layerIndex)

	for _, part in self.parts do
		part.LocalTransparencyModifier = localTransparencyModifier
		part.CastShadow = layerIndex <= 1
	end
end

return LayerBinder
