local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local FoliageBinder = {}
FoliageBinder.__index = FoliageBinder
setmetatable(FoliageBinder, ModelBinder)

local windFoliageServiceClient = nil

local function getWindFoliageServiceClient()
	if windFoliageServiceClient == nil then
		windFoliageServiceClient = require("WindFoliageServiceClient")
	end
	return windFoliageServiceClient
end

function FoliageBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, FoliageBinder)
	self.isRegistered = false

	self:refresh()
	self:ObserveAttribute("WindFoliageEnabled", function()
		self:refresh()
	end)

	return self
end

function FoliageBinder.refresh(self: any)
	local enabled = self.instance:GetAttribute("WindFoliageEnabled") ~= false
	self.instance:SetAttribute("FoliageTagged", true)

	if enabled and not self.isRegistered then
		local ok, registeredEntry = pcall(function()
			return getWindFoliageServiceClient():RegisterFoliage(self.instance)
		end)
		self.isRegistered = ok and registeredEntry ~= nil
	elseif not enabled and self.isRegistered then
		pcall(function()
			getWindFoliageServiceClient():UnregisterFoliage(self.instance)
		end)
		self.isRegistered = false
	end
end

function FoliageBinder.Cleanup(self: any)
	if self.isRegistered then
		pcall(function()
			getWindFoliageServiceClient():UnregisterFoliage(self.instance)
		end)
	end
end

return FoliageBinder
