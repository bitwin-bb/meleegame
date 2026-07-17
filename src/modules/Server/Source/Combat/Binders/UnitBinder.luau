local require = require(script.Parent.loader).load(script)

local BossServiceUtils = require("BossServiceUtils")
local ModelBinder = require("ModelBinder")
local NpcServiceUtils = require("NpcServiceUtils")
local TagBinder = require("TagBinder")

local UnitBinder = {}
UnitBinder.__index = UnitBinder
setmetatable(UnitBinder, ModelBinder)

local function getUnitKind(self: any): string
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
		self:UpdateState()
	end
	if self.humanoid ~= nil then
		self:Connect(self.humanoid.HealthChanged, function()
			self:UpdateState()
		end)
		self:Connect(self.humanoid:GetPropertyChangedSignal("MaxHealth"), function()
			self:UpdateState()
		end)
		self:Connect(self.humanoid.Died, function()
			self:UpdateState()
		end)
	end

	return self
end

function UnitBinder.UpdateState(self: any)
	local model = self.model
	if model == nil then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	self.humanoid = humanoid

	model:SetAttribute("UnitTagged", true)
	model:SetAttribute("UnitKind", getUnitKind(self))
	model:SetAttribute("UnitAlive", humanoid ~= nil and humanoid.Health > 0)

	if humanoid ~= nil then
		model:SetAttribute("UnitHealth", humanoid.Health)
		model:SetAttribute("UnitMaxHealth", humanoid.MaxHealth)
	end

	local bossRuntimeId = BossServiceUtils.GetRuntimeIdFromInstance(model)
	if bossRuntimeId ~= nil then
		model:SetAttribute("UnitRuntimeId", bossRuntimeId)
		return
	end

	local npcRuntimeId = NpcServiceUtils.GetRuntimeIdFromInstance(model)
	if npcRuntimeId ~= nil then
		model:SetAttribute("UnitRuntimeId", npcRuntimeId)
	end
end

return UnitBinder
