--!strict

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local BossBinder = {}
BossBinder.__index = BossBinder
setmetatable(BossBinder, ModelBinder)

local function resolveBossId(self: any, model: Model): string
	local runtimeBossId = BossServiceUtils.resolveBossIdFromInstance(model)
	if runtimeBossId ~= nil then
		return runtimeBossId
	end
	if self:HasTag(TagBinder.Tags.Boss_EyeOfCthulhu) then
		return "EyeOfCthulhu"
	end
	return "Boss"
end

function BossBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, BossBinder)
	self.model = self:GetModel()
	if self.model ~= nil then
		self:updateMetadata()
	end
	return self
end

function BossBinder.updateMetadata(self: any)
	local model = self.model
	if model == nil then
		return
	end

	model:SetAttribute("BossBinderTagged", true)
	model:SetAttribute("BossBinderBossId", resolveBossId(self, model))

	local runtimeId = BossServiceUtils.resolveRuntimeIdFromInstance(model)
	if runtimeId ~= nil then
		model:SetAttribute("BossBinderRuntimeId", runtimeId)
	end
end

return BossBinder
