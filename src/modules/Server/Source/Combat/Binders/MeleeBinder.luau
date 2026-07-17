local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")
local ToolBinder = require("ToolBinder")

local MeleeBinder = {}
MeleeBinder.__index = MeleeBinder
setmetatable(MeleeBinder, ModelBinder)

local TOOL_ATTRIBUTE_NAMES = {
	"itemId",
	"ItemId",
	"id",
	"itemType",
	"ItemType",
	"type",
	"Type",
}

function MeleeBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, MeleeBinder)
	self.meleeServiceServer =
		assert(self:GetDependencies().MeleeServiceServer, "MeleeServiceServer dependency is unavailable")
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

function MeleeBinder.Refresh(self: any)
	if self.tool == nil then
		return
	end

	local resolution = ToolBinder.Get(self.tool)
	self.tool:SetAttribute("ToolBinderItemId", resolution.itemId)
	self.tool:SetAttribute("ToolBinderItemType", resolution.itemType)
	self.tool:SetAttribute("ToolBinderMelee", resolution.isMelee)

	if resolution.ownerPlayer ~= nil then
		self.meleeServiceServer:RequestRefreshEquipped(resolution.ownerPlayer)
	end
end

return MeleeBinder
