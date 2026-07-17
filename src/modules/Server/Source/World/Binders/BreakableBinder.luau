
local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local BreakableBinder = {}
BreakableBinder.__index = BreakableBinder
setmetatable(BreakableBinder, ModelBinder)

local function getNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return valueRaw
end

function BreakableBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, BreakableBinder)
	self.broken = false
	self:Refresh()

	self:ObserveAttribute("BreakableHealth", function()
		self:Refresh()
	end)

	local humanoid = self:GetHumanoid()
	if humanoid ~= nil then
		self:Connect(humanoid.Died, function()
			self:TriggerBreak("HumanoidDied")
		end)
	end

	return self
end

function BreakableBinder.Refresh(self: any)
	local maxHealth = getNumber(self.instance:GetAttribute("BreakableMaxHealth"), 1)
	local health = getNumber(self.instance:GetAttribute("BreakableHealth"), maxHealth)
	self.instance:SetAttribute("BreakableTagged", true)
	self.instance:SetAttribute("BreakableMaxHealth", maxHealth)
	self.instance:SetAttribute("BreakableHealth", health)
	if health <= 0 then
		self:TriggerBreak("HealthDepleted")
	end
end

function BreakableBinder.TriggerBreak(self: any, reason: string)
	if self.broken then
		return
	end
	self.broken = true

	self.instance:SetAttribute("BreakableBroken", true)
	self.instance:SetAttribute("BreakableReason", reason)

	local destroyDelay = self.instance:GetAttribute("BreakableDestroyDelay")
	if typeof(destroyDelay) == "number" and destroyDelay > 0 then
		task.delay(destroyDelay, function()
			if self.destroyed or self.instance.Parent == nil then
				return
			end
			self.instance:Destroy()
		end)
	else
		if self.instance.Parent ~= nil then
			self.instance:Destroy()
		end
	end
end

return BreakableBinder
