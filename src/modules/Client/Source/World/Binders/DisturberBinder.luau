local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local DisturberBinder = {}
DisturberBinder.__index = DisturberBinder
setmetatable(DisturberBinder, ModelBinder)

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

function DisturberBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, DisturberBinder)
	self.windFoliageServiceClient =
		assert(self:GetDependencies().WindFoliageServiceClient, "WindFoliageServiceClient dependency is unavailable")
	self.isTracked = false

	self:Refresh()
	for _, attributeName in DISTURBER_ATTRIBUTE_NAMES do
		self:ObserveAttribute(attributeName, function()
			self:Refresh()
		end)
	end

	return self
end

function DisturberBinder.Refresh(self: any)
	local enabled = self.instance:GetAttribute("WindFoliageDisturbanceEnabled") ~= false
	self.instance:SetAttribute("DisturberTagged", true)

	if enabled and not self.isTracked then
		local ok = pcall(function()
			self.windFoliageServiceClient:TrackDisturber(self.instance, collectOverrideConfig(self.instance))
		end)
		self.isTracked = ok
	elseif enabled and self.isTracked then
		pcall(function()
			self.windFoliageServiceClient:UntrackDisturber(self.instance)
			self.windFoliageServiceClient:TrackDisturber(self.instance, collectOverrideConfig(self.instance))
		end)
	elseif not enabled and self.isTracked then
		pcall(function()
			self.windFoliageServiceClient:UntrackDisturber(self.instance)
		end)
		self.isTracked = false
	end
end

function DisturberBinder.Cleanup(self: any)
	if self.isTracked then
		pcall(function()
			self.windFoliageServiceClient:UntrackDisturber(self.instance)
		end)
	end
end

return DisturberBinder
