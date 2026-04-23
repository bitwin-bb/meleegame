--!strict

local LiquidServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.LiquidServiceUtils)
local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local HazardBinder = {}
HazardBinder.__index = HazardBinder
setmetatable(HazardBinder, ModelBinder)

local bossServiceServer = nil
local hpServiceServer = nil
local liquidServiceServer = nil
local npcServiceServer = nil

local function getBossServiceServer()
	if bossServiceServer == nil then
		bossServiceServer = require(script:FindFirstAncestor("game").Server.Services.BossServiceServer)
	end
	return bossServiceServer
end

local function getHpServiceServer()
	if hpServiceServer == nil then
		hpServiceServer = require(script:FindFirstAncestor("game").Server.Services.HpServiceServer)
	end
	return hpServiceServer
end

local function getLiquidServiceServer()
	if liquidServiceServer == nil then
		liquidServiceServer = require(script:FindFirstAncestor("game").Server.Services.LiquidServiceServer)
	end
	return liquidServiceServer
end

local function getNpcServiceServer()
	if npcServiceServer == nil then
		npcServiceServer = require(script:FindFirstAncestor("game").Server.Services.NpcServiceServer)
	end
	return npcServiceServer
end

local function resolveNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

local function resolveHazardDefaults(self: any): (string, number, number)
	if self:HasTag(TagBinder.Tags.Hazard_Lava) then
		local lavaDefinition = LiquidServiceUtils.LiquidDamage.getLavaDefinition(getLiquidServiceServer().config)
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
	ModelBinder.bindTouchedParts(instance, self.janitor, function(_part: BasePart, other: BasePart)
		self:onTouched(other)
	end)
	return self
end

function HazardBinder.refresh(self: any)
	local kind, defaultDamage, defaultInterval = resolveHazardDefaults(self)
	self.kind = kind
	self.damage = math.max(0, resolveNumberAttribute(self.instance, "HazardDamage", defaultDamage))
	self.interval = math.max(0.05, resolveNumberAttribute(self.instance, "HazardInterval", defaultInterval))
	self.instance:SetAttribute("HazardTagged", true)
	self.instance:SetAttribute("HazardKind", kind)
end

function HazardBinder.onTouched(self: any, other: BasePart)
	if self.damage <= 0 then
		return
	end

	local player = ModelBinder.resolvePlayer(other)
	local humanoid = ModelBinder.resolveHumanoid(other)
	local cooldownKey = if player ~= nil
		then player :: Instance
		else if humanoid ~= nil then humanoid :: Instance else other
	local now = os.clock()
	if now < (self.lastDamageAt[cooldownKey] or 0) then
		return
	end
	self.lastDamageAt[cooldownKey] = now + self.interval

	if player ~= nil then
		getHpServiceServer():damagePlayer(player, self.damage)
		return
	end

	if getNpcServiceServer():damageNpcFromHitPart(other, self.damage, self.instance) > 0 then
		return
	end
	if getBossServiceServer():damageBossFromHitPart(other, self.damage, self.instance, self.kind) > 0 then
		return
	end
	if humanoid ~= nil then
		humanoid:TakeDamage(self.damage)
	end
end

return HazardBinder
