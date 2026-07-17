local require = require(script.Parent.loader).load(script)

local LiquidServiceUtils = require("LiquidServiceUtils")
local ModelBinder = require("ModelBinder")
local TagBinder = require("TagBinder")

local HazardBinder = {}
HazardBinder.__index = HazardBinder
setmetatable(HazardBinder, ModelBinder)

local function getNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

local function getHazardDefaults(self: any): (string, number, number)
	if self:HasTag(TagBinder.Tags.Hazard_Lava) then
		local lavaDefinition = LiquidServiceUtils.LiquidDamage.GetLavaDefinition(self.liquidServiceServer.config)
		if lavaDefinition ~= nil then
			return "Lava", lavaDefinition.lavaTouchDamage, lavaDefinition.lavaTouchInterval
		end
		return "Lava", 58, 0.35
	end
	if self:HasTag(TagBinder.Tags.Hazard_Spikes) then
		return "Spikes", 18, 0.6
	end
	if self:HasTag(TagBinder.Tags.Hazard_Poison) then
		return "Poison", 4, 1
	end
	return "Hazard", 8, 0.5
end

function HazardBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, HazardBinder)
	local dependencies = self:GetDependencies()
	self.bossServiceServer = assert(dependencies.BossServiceServer, "BossServiceServer dependency is unavailable")
	self.hpServiceServer = assert(dependencies.HpServiceServer, "HpServiceServer dependency is unavailable")
	self.liquidServiceServer = assert(dependencies.LiquidServiceServer, "LiquidServiceServer dependency is unavailable")
	self.npcServiceServer = assert(dependencies.NpcServiceServer, "NpcServiceServer dependency is unavailable")
	self.lastDamageAt = {} :: { [Instance]: number }
	self:Refresh()
	ModelBinder.BindTouchedParts(instance, self.janitor, function(_part: BasePart, other: BasePart)
		self:OnTouched(other)
	end)
	return self
end

function HazardBinder.Refresh(self: any)
	local kind, defaultDamage, defaultInterval = getHazardDefaults(self)
	self.kind = kind
	self.damage = math.max(0, getNumberAttribute(self.instance, "HazardDamage", defaultDamage))
	self.interval = math.max(0.05, getNumberAttribute(self.instance, "HazardInterval", defaultInterval))
	self.instance:SetAttribute("HazardTagged", true)
	self.instance:SetAttribute("HazardKind", kind)
end

function HazardBinder.OnTouched(self: any, other: BasePart)
	if self.damage <= 0 then
		return
	end

	local player = (ModelBinder :: any).GetPlayer(other)
	local humanoid = (ModelBinder :: any).GetHumanoid(other)
	local cooldownKey = if player ~= nil
		then player :: Instance
		else if humanoid ~= nil then humanoid :: Instance else other
	local now = os.clock()
	if now < (self.lastDamageAt[cooldownKey] or 0) then
		return
	end
	self.lastDamageAt[cooldownKey] = now + self.interval

	if player ~= nil then
		self.hpServiceServer:DamagePlayer(player, self.damage)
		return
	end

	if self.npcServiceServer:DamageNpcFromHitPart(other, self.damage, self.instance) > 0 then
		return
	end
	if self.bossServiceServer:DamageBossFromHitPart(other, self.damage, self.instance, self.kind) > 0 then
		return
	end
	if humanoid ~= nil then
		humanoid:TakeDamage(self.damage)
	end
end

return HazardBinder
