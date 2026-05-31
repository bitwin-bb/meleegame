--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local StationBinder = {}
StationBinder.__index = StationBinder
setmetatable(StationBinder, ModelBinder)

local STATION_ID_BY_TAG = {
	[TagBinder.Tags.Station_Workbench] = "Workbench",
	[TagBinder.Tags.Station_Furnace] = "Furnace",
	[TagBinder.Tags.Station_Anvil] = "Anvil",
	[TagBinder.Tags.Station_AlchemyTable] = "AlchemyTable",
}

function StationBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, StationBinder)
	self:updateMetadata()
	return self
end

function StationBinder.resolveStationId(self: any): string
	for tag, stationId in STATION_ID_BY_TAG do
		if self:HasTag(tag) then
			return stationId
		end
	end

	local attributeId = self.instance:GetAttribute("StationId")
	if typeof(attributeId) == "string" and attributeId ~= "" then
		return attributeId
	end

	return "Station"
end

function StationBinder.updateMetadata(self: any)
	local stationId = self:resolveStationId()
	self.instance:SetAttribute("StationTagged", true)
	self.instance:SetAttribute("StationId", stationId)
	if self.instance:GetAttribute("UseActionText") == nil then
		self.instance:SetAttribute("UseActionText", "Use")
	end
	if self.instance:GetAttribute("UseObjectText") == nil then
		self.instance:SetAttribute("UseObjectText", stationId)
	end
end

return StationBinder
