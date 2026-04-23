--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local DropBinder = {}
DropBinder.__index = DropBinder
setmetatable(DropBinder, ModelBinder)

local lootServiceServer = nil

local function getLootServiceServer()
	if lootServiceServer == nil then
		lootServiceServer = require(script:FindFirstAncestor("game").Server.Services.LootServiceServer)
	end
	return lootServiceServer
end

local function resolveStringAttribute(instance: Instance, attributeName: string): string?
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function DropBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, DropBinder)
	self.didDrop = false
	self:refresh()
	self:Connect(self.instance.Destroying, function()
		if self.dropOnDestroy then
			self:dropOnce("Destroying")
		end
	end)

	local humanoid = self:GetHumanoid()
	if humanoid ~= nil then
		self:Connect(humanoid.Died, function()
			if self.dropOnDeath then
				self:dropOnce("Death")
			end
		end)
	end

	return self
end

function DropBinder.refresh(self: any)
	self.dropItemId = resolveStringAttribute(self.instance, "DropItemId")
	self.dropTableId = resolveStringAttribute(self.instance, "DropTableId")
	self.dropSourceType = resolveStringAttribute(self.instance, "DropSourceType")
	self.dropAmount = math.max(1, math.floor(tonumber(self.instance:GetAttribute("DropAmount")) or 1))
	self.dropOnDestroy = self.instance:GetAttribute("DropOnDestroy") == true
	self.dropOnDeath = self.instance:GetAttribute("DropOnDeath") == true
	self.instance:SetAttribute("DropTagged", true)
end

function DropBinder.dropOnce(self: any, reason: string)
	if self.didDrop then
		return
	end
	self.didDrop = true

	local origin = ModelBinder.resolveWorldPosition(self.instance)
	if origin == nil then
		return
	end

	local sourceType = if self.dropSourceType ~= nil then self.dropSourceType else reason
	local lootServiceServer = getLootServiceServer()
	if self.dropItemId ~= nil then
		lootServiceServer:spawnLootRuntime(self.dropItemId, self.dropAmount, origin, {
			sourceType = sourceType,
		})
	end
	if self.dropTableId ~= nil then
		lootServiceServer:spawnDropsFromTable(self.dropTableId, origin, {
			sourceType = sourceType,
		})
	end
end

return DropBinder
