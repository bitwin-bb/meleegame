--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local DisturberBinder = {}
DisturberBinder.__index = DisturberBinder
setmetatable(DisturberBinder, ModelBinder)

local windFoliageServiceClient = nil

local function getWindFoliageServiceClient()
	if windFoliageServiceClient == nil then
		windFoliageServiceClient =
			require(script:FindFirstAncestor("game").Client.Services.WindFoliageServiceClient)
	end
	return windFoliageServiceClient
end

local DISTURBER_ATTRIBUTE_NAMES = {
	"WindFoliageDisturbanceRadius",
	"WindFoliageDisturbanceStrength",
	"WindFoliageDisturbanceLifetime",
	"WindFoliageDisturbanceFalloff",
	"WindFoliageDisturbancePropagationDistance",
	"WindFoliageDisturbancePropagationWeight",
	"WindFoliageDisturbanceVelocityInfluence",
}

local function collectOverrideConfig(instance: Instance): { [string]: any }?
	local config = {} :: { [string]: any }

	local radius = instance:GetAttribute("WindFoliageDisturbanceRadius")
	if typeof(radius) == "number" then
		config.radius = radius
	end
	local strength = instance:GetAttribute("WindFoliageDisturbanceStrength")
	if typeof(strength) == "number" then
		config.strength = strength
	end
	local lifetime = instance:GetAttribute("WindFoliageDisturbanceLifetime")
	if typeof(lifetime) == "number" then
		config.lifetime = lifetime
	end
	local falloff = instance:GetAttribute("WindFoliageDisturbanceFalloff")
	if typeof(falloff) == "number" then
		config.falloffCurve = falloff
	end
	local propagationDistance = instance:GetAttribute("WindFoliageDisturbancePropagationDistance")
	if typeof(propagationDistance) == "number" then
		config.propagationDistance = propagationDistance
	end
	local propagationWeight = instance:GetAttribute("WindFoliageDisturbancePropagationWeight")
	if typeof(propagationWeight) == "number" then
		config.propagationWeight = propagationWeight
	end
	local velocityInfluence = instance:GetAttribute("WindFoliageDisturbanceVelocityInfluence")
	if typeof(velocityInfluence) == "number" then
		config.velocityInfluence = velocityInfluence
	end

	if next(config) == nil then
		return nil
	end

	return config
end

function DisturberBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, DisturberBinder)
	self.isTracked = false

	self:refresh()
	for _, attributeName in DISTURBER_ATTRIBUTE_NAMES do
		self:ObserveAttribute(attributeName, function()
			self:refresh()
		end)
	end

	return self
end

function DisturberBinder.refresh(self: any)
	local enabled = self.instance:GetAttribute("WindFoliageDisturbanceEnabled") ~= false
	self.instance:SetAttribute("DisturberTagged", true)

	if enabled and not self.isTracked then
		local ok = pcall(function()
			getWindFoliageServiceClient():trackDisturber(self.instance, collectOverrideConfig(self.instance))
		end)
		self.isTracked = ok
	elseif enabled and self.isTracked then
		pcall(function()
			local nextWindFoliageServiceClient = getWindFoliageServiceClient()
			nextWindFoliageServiceClient:untrackDisturber(self.instance)
			nextWindFoliageServiceClient:trackDisturber(self.instance, collectOverrideConfig(self.instance))
		end)
	elseif not enabled and self.isTracked then
		pcall(function()
			getWindFoliageServiceClient():untrackDisturber(self.instance)
		end)
		self.isTracked = false
	end
end

function DisturberBinder.Cleanup(self: any)
	if self.isTracked then
		pcall(function()
			getWindFoliageServiceClient():untrackDisturber(self.instance)
		end)
	end
end

return DisturberBinder
