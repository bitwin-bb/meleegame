local require = require(script.Parent.loader).load(script)

local BossServiceUtils = require("BossServiceUtils")
local ModelBinder = require("ModelBinder")
local TagBinder = require("TagBinder")

local BossBinder = {}
BossBinder.__index = BossBinder
setmetatable(BossBinder, ModelBinder)

local function getBossId(self: any, model: Model): string
	local runtimeBossId = BossServiceUtils.GetBossIdFromInstance(model)
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
		self:UpdateMetadata()
	end
	return self
end

function BossBinder.UpdateMetadata(self: any)
	local model = self.model
	if model == nil then
		return
	end

	model:SetAttribute("BossBinderTagged", true)
	model:SetAttribute("BossBinderBossId", getBossId(self, model))

	local runtimeId = BossServiceUtils.GetRuntimeIdFromInstance(model)
	if runtimeId ~= nil then
		model:SetAttribute("BossBinderRuntimeId", runtimeId)
	end
end

return BossBinder
