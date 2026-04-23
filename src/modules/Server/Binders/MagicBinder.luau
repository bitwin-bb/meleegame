--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local ToolBinder = require(script:FindFirstAncestor("game").Shared.Binders.ToolBinder)

local MagicBinder = {}
MagicBinder.__index = MagicBinder
setmetatable(MagicBinder, ModelBinder)

local magicServiceServer = nil

local function getMagicServiceServer()
	if magicServiceServer == nil then
		magicServiceServer = require(script:FindFirstAncestor("game").Server.Services.MagicServiceServer)
	end
	return magicServiceServer
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

function MagicBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, MagicBinder)
	self.tool = ToolBinder.resolveTool(instance)
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

function MagicBinder.refresh(self: any)
	if self.tool == nil then
		return
	end

	local resolution = ToolBinder.resolve(self.tool)
	self.tool:SetAttribute("ToolBinderItemId", resolution.itemId)
	self.tool:SetAttribute("ToolBinderItemType", resolution.itemType)
	self.tool:SetAttribute("ToolBinderMagic", resolution.isMagic)

	if resolution.ownerPlayer ~= nil then
		getMagicServiceServer():requestRefreshEquipped(resolution.ownerPlayer)
	end
end

return MagicBinder
