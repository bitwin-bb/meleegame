local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local PickupBinder = {}
PickupBinder.__index = PickupBinder
setmetatable(PickupBinder, ModelBinder)

local ITEM_ATTRIBUTE_NAMES = {
	"PickupItemId",
	"LootItemId",
	"ItemId",
	"PlacedItemId",
}

local function getStringAttribute(instance: Instance, attributeNames: { string }): string?
	for _, attributeName in attributeNames do
		local value = instance:GetAttribute(attributeName)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

function PickupBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, PickupBinder)
	self.inventoryServiceServer =
		assert(self:GetDependencies().InventoryServiceServer, "InventoryServiceServer dependency is unavailable")
	self.cooldowns = {} :: { [Player]: number }
	self:Refresh()
	ModelBinder.BindTouchedParts(instance, self.janitor, function(_part: BasePart, other: BasePart)
		self:OnTouched(other)
	end)
	return self
end

function PickupBinder.Refresh(self: any)
	self.itemId = getStringAttribute(self.instance, ITEM_ATTRIBUTE_NAMES)
	self.amount = math.max(1, math.floor(tonumber(self.instance:GetAttribute("PickupAmount")) or 1))
	self.destroyOnCollect = self.instance:GetAttribute("PickupDestroyOnCollect") ~= false
	self.instance:SetAttribute("PickupTagged", true)
end

function PickupBinder.OnTouched(self: any, other: BasePart)
	if self.itemId == nil then
		return
	end

	local player = ModelBinder.GetPlayer(other)
	if player == nil then
		return
	end

	local now = os.clock()
	if now < (self.cooldowns[player] or 0) then
		return
	end
	self.cooldowns[player] = now + 0.15

	local addResult = self.inventoryServiceServer:AddItem(player, self.itemId, self.amount, {})
	if addResult.added <= 0 then
		return
	end

	if addResult.leftover > 0 then
		self.amount = addResult.leftover
		self.instance:SetAttribute("PickupAmount", self.amount)
	else
		self.amount = 0
		if self.destroyOnCollect and self.instance.Parent ~= nil then
			self.instance:Destroy()
		end
	end
end

return PickupBinder
