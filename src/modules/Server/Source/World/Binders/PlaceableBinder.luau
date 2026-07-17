
local require = require(script.Parent.loader).load(script)

local ItemRegistry = require("ItemRegistry")
local ModelBinder = require("ModelBinder")
local TagBinder = require("TagBinder")

local PlaceableBinder = {}
PlaceableBinder.__index = PlaceableBinder
setmetatable(PlaceableBinder, ModelBinder)

local function getItemId(instance: Instance): string?
	local placedItemId = instance:GetAttribute("PlacedItemId")
	if typeof(placedItemId) == "string" and placedItemId ~= "" then
		return placedItemId
	end

	local itemId = instance:GetAttribute("ItemId")
	if typeof(itemId) == "string" and itemId ~= "" then
		return itemId
	end

	return nil
end

function PlaceableBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, PlaceableBinder)
	self:UpdateMetadata()
	return self
end

function PlaceableBinder.UpdateMetadata(self: any)
	local itemId = getItemId(self.instance)
	self.instance:SetAttribute("PlaceableTagged", true)

	if itemId == nil then
		return
	end

	self.instance:SetAttribute("PlaceableItemId", itemId)
	local definition = ItemRegistry.GetDefinition(itemId)
	if typeof(definition) ~= "table" then
		return
	end

	if self:HasTag(TagBinder.Tags.Placeable_Torch) or itemId == "Torch" then
		self.instance:SetAttribute("PlaceableKind", "Torch")
		if self.instance:GetAttribute("LightEnabled") == nil then
			self.instance:SetAttribute("LightEnabled", true)
		end
		return
	end

	if self:HasTag(TagBinder.Tags.Placeable_Workbench) or itemId == "Workbench" then
		self.instance:SetAttribute("PlaceableKind", "Workbench")
		if self.instance:GetAttribute("UseObjectText") == nil then
			self.instance:SetAttribute("UseObjectText", "Workbench")
		end
	end
end

return PlaceableBinder
