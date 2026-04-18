--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local FoliageBinder = {}
FoliageBinder.__index = FoliageBinder
setmetatable(FoliageBinder, ModelBinder)

local windFoliageServiceClient = nil

local function getWindFoliageServiceClient()
	if windFoliageServiceClient == nil then
		windFoliageServiceClient =
			require(script:FindFirstAncestor("game").Client.Services.WindFoliageService.WindFoliageServiceClient)
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
		local ok = pcall(function()
			getWindFoliageServiceClient():registerFoliage(self.instance)
		end)
		self.isRegistered = ok
	elseif not enabled and self.isRegistered then
		pcall(function()
			getWindFoliageServiceClient():unregisterFoliage(self.instance)
		end)
		self.isRegistered = false
	end
end

function FoliageBinder.Cleanup(self: any)
	if self.isRegistered then
		pcall(function()
			getWindFoliageServiceClient():unregisterFoliage(self.instance)
		end)
	end
end

return FoliageBinder
