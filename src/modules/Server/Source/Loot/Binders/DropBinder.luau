local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local DropBinder = {}
DropBinder.__index = DropBinder
setmetatable(DropBinder, ModelBinder)

local function getStringAttribute(instance: Instance, attributeName: string): string?
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function DropBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, DropBinder)
	self.lootServiceServer =
		assert(self:GetDependencies().LootServiceServer, "LootServiceServer dependency is unavailable")
	self.didDrop = false
	self:Refresh()
	self:Connect(self.instance.Destroying, function()
		if self.dropOnDestroy then
			self:DropOnce("Destroying")
		end
	end)

	local humanoid = self:GetHumanoid()
	if humanoid ~= nil then
		self:Connect(humanoid.Died, function()
			if self.dropOnDeath then
				self:DropOnce("Death")
			end
		end)
	end

	return self
end

function DropBinder.Refresh(self: any)
	self.dropItemId = getStringAttribute(self.instance, "DropItemId")
	self.dropTableId = getStringAttribute(self.instance, "DropTableId")
	self.dropSourceType = getStringAttribute(self.instance, "DropSourceType")
	self.dropAmount = math.max(1, math.floor(tonumber(self.instance:GetAttribute("DropAmount")) or 1))
	self.dropOnDestroy = self.instance:GetAttribute("DropOnDestroy") == true
	self.dropOnDeath = self.instance:GetAttribute("DropOnDeath") == true
	self.instance:SetAttribute("DropTagged", true)
end

function DropBinder.DropOnce(self: any, reason: string)
	if self.didDrop then
		return
	end
	self.didDrop = true

	local origin = ModelBinder.GetWorldPosition(self.instance)
	if origin == nil then
		return
	end

	local sourceType = if self.dropSourceType ~= nil then self.dropSourceType else reason
	local service = self.lootServiceServer
	if self.dropItemId ~= nil then
		service:SpawnLootRuntime(self.dropItemId, self.dropAmount, origin, {
			sourceType = sourceType,
		})
	end
	if self.dropTableId ~= nil then
		service:SpawnDropsFromTable(self.dropTableId, origin, {
			sourceType = sourceType,
		})
	end
end

return DropBinder
