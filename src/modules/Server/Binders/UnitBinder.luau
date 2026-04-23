--!strict

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local NpcServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.NpcServiceUtils)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local UnitBinder = {}
UnitBinder.__index = UnitBinder
setmetatable(UnitBinder, ModelBinder)

local function resolveUnitKind(self: any): string
	if self:HasTag(TagBinder.Tags.Character) then
		return "Character"
	end
	if self:HasTag(TagBinder.Tags.Boss) then
		return "Boss"
	end
	if self:HasTag(TagBinder.Tags.Npc) then
		return "Npc"
	end
	return "Unit"
end

function UnitBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, UnitBinder)
	self.model = self:GetModel()
	self.humanoid = self:GetHumanoid()

	if self.model ~= nil then
		self:updateState()
	end
	if self.humanoid ~= nil then
		self:Connect(self.humanoid.HealthChanged, function()
			self:updateState()
		end)
		self:Connect(self.humanoid:GetPropertyChangedSignal("MaxHealth"), function()
			self:updateState()
		end)
		self:Connect(self.humanoid.Died, function()
			self:updateState()
		end)
	end

	return self
end

function UnitBinder.updateState(self: any)
	local model = self.model
	if model == nil then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	self.humanoid = humanoid

	model:SetAttribute("UnitTagged", true)
	model:SetAttribute("UnitKind", resolveUnitKind(self))
	model:SetAttribute("UnitAlive", humanoid ~= nil and humanoid.Health > 0)

	if humanoid ~= nil then
		model:SetAttribute("UnitHealth", humanoid.Health)
		model:SetAttribute("UnitMaxHealth", humanoid.MaxHealth)
	end

	local bossRuntimeId = BossServiceUtils.resolveRuntimeIdFromInstance(model)
	if bossRuntimeId ~= nil then
		model:SetAttribute("UnitRuntimeId", bossRuntimeId)
		return
	end

	local npcRuntimeId = NpcServiceUtils.resolveRuntimeIdFromInstance(model)
	if npcRuntimeId ~= nil then
		model:SetAttribute("UnitRuntimeId", npcRuntimeId)
	end
end

return UnitBinder
