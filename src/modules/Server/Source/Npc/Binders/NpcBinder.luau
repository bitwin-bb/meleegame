
local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")
local NpcServiceUtils = require("NpcServiceUtils")
local TagBinder = require("TagBinder")

local NpcBinder = {}
NpcBinder.__index = NpcBinder
setmetatable(NpcBinder, ModelBinder)

local function GetNpcType(self: any, model: Model): string
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
	model:SetAttribute("NpcBinderType", GetNpcType(self, model))

	local runtimeId = NpcServiceUtils.GetUntimeIdFromInstance(model)
	if runtimeId ~= nil then
		model:SetAttribute("NpcBinderRuntimeId", runtimeId)
	end
end

return NpcBinder
