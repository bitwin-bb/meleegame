
local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")
local ToolBinder = require("ToolBinder")

local MeleeBinder = {}
MeleeBinder.__index = MeleeBinder
setmetatable(MeleeBinder, ModelBinder)

local meleeServiceServer = nil

local function getMeleeServiceServer()
	if meleeServiceServer == nil then
		meleeServiceServer = require("MeleeServiceServer")
	end
	return meleeServiceServer
end

local TOOL_ATTRIBUTE_NAMES = {
	"itemId",
	"ItemId",
	"id",
	"itemType",
	"ItemType",
	"type",
	"Type",
}

function MeleeBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, MeleeBinder)
	self.tool = ToolBinder.GetTool(instance)
	if self.tool == nil then
		return self
	end

	self:refresh()
	self:Connect(self.tool.AncestryChanged, function()
		self:refresh()
	end)
	for _, attributeName in TOOL_ATTRIBUTE_NAMES do
		self:Connect(self.tool:GetAttributeChangedSignal(attributeName), function()
			self:refresh()
		end)
	end

	return self
end

function MeleeBinder.refresh(self: any)
	if self.tool == nil then
		return
	end

	local resolution = ToolBinder.Get(self.tool)
	self.tool:SetAttribute("ToolBinderItemId", resolution.itemId)
	self.tool:SetAttribute("ToolBinderItemType", resolution.itemType)
	self.tool:SetAttribute("ToolBinderMelee", resolution.isMelee)

	if resolution.ownerPlayer ~= nil then
		getMeleeServiceServer():RequestRefreshEquipped(resolution.ownerPlayer)
	end
end

return MeleeBinder
