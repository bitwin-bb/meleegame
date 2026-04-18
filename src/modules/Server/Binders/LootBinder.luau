--!strict

local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local LootBinder = {}
LootBinder.__index = LootBinder
setmetatable(LootBinder, ModelBinder)

local function resolveStringAttribute(instance: Instance, attributeName: string): string?
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function LootBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, LootBinder)
	self:updateMetadata()
	return self
end

function LootBinder.updateMetadata(self: any)
	local itemId = resolveStringAttribute(self.instance, "LootItemId")
		or resolveStringAttribute(self.instance, "ItemId")
	local amount = self.instance:GetAttribute("LootAmount")
	self.instance:SetAttribute("LootTagged", true)
	if itemId == nil then
		return
	end

	self.instance:SetAttribute("LootItemId", itemId)
	local definition = ItemRegistry.resolveDefinition(itemId)
	if typeof(definition) == "table" then
		self.instance:SetAttribute("LootDisplayName", (definition :: { [string]: any }).name or itemId)
	end
	if typeof(amount) == "number" then
		self.instance:SetAttribute("LootAmount", math.max(1, math.floor(amount)))
	end
end

return LootBinder
