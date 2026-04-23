--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local NpcServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.NpcServiceUtils)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local NpcBinder = {}
NpcBinder.__index = NpcBinder
setmetatable(NpcBinder, ModelBinder)

local function resolveNpcType(self: any, model: Model): string
	local runtimeType = model:GetAttribute(NpcServiceUtils.RUNTIME_NPC_TYPE_ATTRIBUTE)
	if typeof(runtimeType) == "string" and runtimeType ~= "" then
		return runtimeType
	end
	if self:HasTag(TagBinder.Tags.Npc_Slime) then
		return "Slime"
	end
	if self:HasTag(TagBinder.Tags.Npc_Flying) then
		return "Flying"
	end
	if self:HasTag(TagBinder.Tags.Npc_Ground) then
		return "Ground"
	end
	return "Npc"
end

function NpcBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, NpcBinder)
	self.model = self:GetModel()
	if self.model ~= nil then
		self:updateMetadata()
	end
	return self
end

function NpcBinder.updateMetadata(self: any)
	local model = self.model
	if model == nil then
		return
	end

	model:SetAttribute("NpcBinderTagged", true)
	model:SetAttribute("NpcBinderType", resolveNpcType(self, model))

	local runtimeId = NpcServiceUtils.resolveRuntimeIdFromInstance(model)
	if runtimeId ~= nil then
		model:SetAttribute("NpcBinderRuntimeId", runtimeId)
	end
end

return NpcBinder
