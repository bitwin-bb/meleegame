
local require = require(script.Parent.loader).load(script)

local LiquidServiceUtils = require("LiquidServiceUtils")
local ModelBinder = require("ModelBinder")
local TagBinder = require("TagBinder")

local HazardBinder = {}
HazardBinder.__index = HazardBinder
setmetatable(HazardBinder, ModelBinder)

local bossServiceServer = nil
local hpServiceServer = nil
local liquidServiceServer = nil
local npcServiceServer = nil

local function getBossServiceServer()
	if bossServiceServer == nil then
		bossServiceServer = require("BossServiceServer")
	end
	return bossServiceServer
end

local function getHpServiceServer()
	if hpServiceServer == nil then
		hpServiceServer = require("HpServiceServer")
	end
	return hpServiceServer
end

local function getLiquidServiceServer()
	if liquidServiceServer == nil then
		liquidServiceServer = require("LiquidServiceServer")
	end
	return liquidServiceServer
end

local function getNpcServiceServer()
	if npcServiceServer == nil then
		npcServiceServer = require("NpcServiceServer")
	end
	return npcServiceServer
end

local function GetNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

local function GetHazardDefaults(self: any): (string, number, number)
	if self:HasTag(TagBinder.Tags.Hazard_Lava) then
		local lavaDefinition = LiquidServiceUtils.LiquidDamage.GetLavaDefinition(getLiquidServiceServer().config)
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

function HazardBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, HazardBinder)
	self.lastDamageAt = {} :: { [Instance]: number }
	self:refresh()
	ModelBinder.BindTouchedParts(instance, self.janitor, function(_part: BasePart, other: BasePart)
		self:onTouched(other)
	end)
	return self
end

function HazardBinder.refresh(self: any)
	local kind, defaultDamage, defaultInterval = GetHazardDefaults(self)
	self.kind = kind
	self.damage = math.max(0, GetNumberAttribute(self.instance, "HazardDamage", defaultDamage))
	self.interval = math.max(0.05, GetNumberAttribute(self.instance, "HazardInterval", defaultInterval))
	self.instance:SetAttribute("HazardTagged", true)
	self.instance:SetAttribute("HazardKind", kind)
end

function HazardBinder.onTouched(self: any, other: BasePart)
	if self.damage <= 0 then
		return
	end

	local player = ModelBinder.GetPlayer(other)
	local humanoid = ModelBinder.GetHumanoid(other)
	local cooldownKey = if player ~= nil
		then player :: Instance
		else if humanoid ~= nil then humanoid :: Instance else other
	local now = os.clock()
	if now < (self.lastDamageAt[cooldownKey] or 0) then
		return
	end
	self.lastDamageAt[cooldownKey] = now + self.interval

	if player ~= nil then
		getHpServiceServer():DamagePlayer(player, self.damage)
		return
	end

	if getNpcServiceServer():DamageNpcFromHitPart(other, self.damage, self.instance) > 0 then
		return
	end
	if getBossServiceServer():DamageBossFromHitPart(other, self.damage, self.instance, self.kind) > 0 then
		return
	end
	if humanoid ~= nil then
		humanoid:TakeDamage(self.damage)
	end
end

return HazardBinder
