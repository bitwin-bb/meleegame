local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ModelBinder = require("ModelBinder")
local String = require("String")

local LightBinder = {}
LightBinder.__index = LightBinder
setmetatable(LightBinder, ModelBinder)

local function createRuntimeInstanceName(): string
	local guid = String.removePostfix(String.removePrefix(HttpService:GenerateGUID(true), "{"), "}")
	return string.format("%03d", (tonumber(string.sub(guid, 1, 8), 16) or 0) % 1000)
end

local function getNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

local function getBooleanAttribute(instance: Instance, attributeName: string, fallback: boolean): boolean
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "boolean" then
		return value
	end
	return fallback
end

function LightBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, LightBinder)
	self.rootPart = self:GetRootPart()
	self.lights = ModelBinder.CollectLights(instance)
	self.flickerSeed = Random.new():NextNumber(-1000, 1000)
	self.createdLight = nil :: PointLight?

	if #self.lights <= 0 and self.rootPart ~= nil then
		local attachment = Instance.new("Attachment")
		attachment.Name = createRuntimeInstanceName()
		attachment.Parent = self.rootPart
		self:AddCleanup(attachment)

		local light = Instance.new("PointLight")
		light.Name = createRuntimeInstanceName()
		light.Parent = attachment
		self:AddCleanup(light)

		self.createdLight = light
		self.lights = { light }
	end

	self:Refresh()
	self:ObserveAttribute("LightEnabled", function()
		self:Refresh()
	end)
	self:ObserveAttribute("LightBrightness", function()
		self:Refresh()
	end)
	self:ObserveAttribute("LightRange", function()
		self:Refresh()
	end)
	self:ObserveAttribute("LightColor", function()
		self:Refresh()
	end)
	self:ObserveAttribute("LightShadows", function()
		self:Refresh()
	end)
	self:ObserveAttribute("LightFlickerAmount", function()
		self:Refresh()
	end)
	self:Connect(RunService.RenderStepped, function()
		self:Step()
	end)

	return self
end

function LightBinder.Refresh(self: any)
	self.enabled = getBooleanAttribute(self.instance, "LightEnabled", true)
	self.baseBrightness = getNumberAttribute(self.instance, "LightBrightness", 2.1)
	self.range = getNumberAttribute(self.instance, "LightRange", 15)
	self.flickerAmount = math.clamp(getNumberAttribute(self.instance, "LightFlickerAmount", 0.12), 0, 0.75)
	self.shadows = getBooleanAttribute(self.instance, "LightShadows", true)
	self.color = if typeof(self.instance:GetAttribute("LightColor")) == "Color3"
		then self.instance:GetAttribute("LightColor") :: Color3
		else Color3.fromRGB(255, 196, 125)

	self.instance:SetAttribute("LightTagged", true)

	for _, light in self.lights do
		if light:IsA("PointLight") or light:IsA("SpotLight") or light:IsA("SurfaceLight") then
			light.Enabled = self.enabled
			light.Brightness = self.baseBrightness
			light.Range = self.range
			light.Color = self.color
			light.Shadows = self.shadows
		end
	end
end

function LightBinder.Step(self: any)
	if not self.enabled or #self.lights <= 0 then
		return
	end

	local noiseTime = os.clock() * 6 + self.flickerSeed
	local alpha = 1 + math.noise(noiseTime, 0, 0) * self.flickerAmount
	local brightness = math.max(0, self.baseBrightness * alpha)

	for _, light in self.lights do
		if light:IsA("PointLight") or light:IsA("SpotLight") or light:IsA("SurfaceLight") then
			light.Brightness = brightness
		end
	end
end

return LightBinder
