local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")
local ToolBinder = require("ToolBinder")

local MagicBinder = {}
MagicBinder.__index = MagicBinder
setmetatable(MagicBinder, ModelBinder)

local TOOL_ATTRIBUTE_NAMES = {
	"itemId",
	"ItemId",
	"id",
	"itemType",
	"ItemType",
	"type",
	"Type",
}

function MagicBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, MagicBinder)
	self.magicServiceServer =
		assert(self:GetDependencies().MagicServiceServer, "MagicServiceServer dependency is unavailable")
	self.tool = ToolBinder.GetTool(instance)
	if self.tool == nil then
		return self
	end

	self:Refresh()
	self:Connect(self.tool.AncestryChanged, function()
		self:Refresh()
	end)
	for _, attributeName in TOOL_ATTRIBUTE_NAMES do
		self:Connect(self.tool:GetAttributeChangedSignal(attributeName), function()
			self:Refresh()
		end)
	end

	return self
end

function MagicBinder.Refresh(self: any)
	if self.tool == nil then
		return
	end

	local resolution = ToolBinder.Get(self.tool)
	self.tool:SetAttribute("ToolBinderItemId", resolution.itemId)
	self.tool:SetAttribute("ToolBinderItemType", resolution.itemType)
	self.tool:SetAttribute("ToolBinderMagic", resolution.isMagic)

	if resolution.ownerPlayer ~= nil then
		self.magicServiceServer:RequestRefreshEquipped(resolution.ownerPlayer)
	end
end

return MagicBinder
