local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local FoliageBinder = {}
FoliageBinder.__index = FoliageBinder
setmetatable(FoliageBinder, ModelBinder)

function FoliageBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, FoliageBinder)
	self.windFoliageServiceClient =
		assert(self:GetDependencies().WindFoliageServiceClient, "WindFoliageServiceClient dependency is unavailable")
	self.isRegistered = false

	self:Refresh()
	self:ObserveAttribute("WindFoliageEnabled", function()
		self:Refresh()
	end)

	return self
end

function FoliageBinder.Refresh(self: any)
	local enabled = self.instance:GetAttribute("WindFoliageEnabled") ~= false
	self.instance:SetAttribute("FoliageTagged", true)

	if enabled and not self.isRegistered then
		local ok, registeredEntry = pcall(function()
			return self.windFoliageServiceClient:RegisterFoliage(self.instance)
		end)
		self.isRegistered = ok and registeredEntry ~= nil
	elseif not enabled and self.isRegistered then
		pcall(function()
			self.windFoliageServiceClient:UnregisterFoliage(self.instance)
		end)
		self.isRegistered = false
	end
end

function FoliageBinder.Cleanup(self: any)
	if self.isRegistered then
		pcall(function()
			self.windFoliageServiceClient:UnregisterFoliage(self.instance)
		end)
	end
end

return FoliageBinder
