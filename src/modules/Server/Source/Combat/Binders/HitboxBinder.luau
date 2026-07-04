
local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local HitboxBinder = {}
HitboxBinder.__index = HitboxBinder
setmetatable(HitboxBinder, ModelBinder)

local bossServiceServer = nil
local hpServiceServer = nil
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

local function GetBooleanAttribute(instance: Instance, attributeName: string, fallback: boolean): boolean
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "boolean" then
		return value
	end
	return fallback
end

function HitboxBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, HitboxBinder)
	self.lastHitAt = {} :: { [Instance]: number }
	self:refresh()
	ModelBinder.BindTouchedParts(instance, self.janitor, function(_part: BasePart, other: BasePart)
		self:onTouched(other)
	end)
	return self
end

function HitboxBinder.refresh(self: any)
	self.damage = math.max(
		0,
		GetNumberAttribute(self.instance, "HitboxDamage", GetNumberAttribute(self.instance, "Damage", 0))
	)
	self.interval = math.max(0.05, GetNumberAttribute(self.instance, "HitboxInterval", 0.2))
	self.affectsPlayers = GetBooleanAttribute(self.instance, "HitboxAffectsPlayers", true)
	self.affectsHumanoids = GetBooleanAttribute(self.instance, "HitboxAffectsHumanoids", true)
	self.affectsNpcs = GetBooleanAttribute(self.instance, "HitboxAffectsNpcs", true)
	self.affectsBosses = GetBooleanAttribute(self.instance, "HitboxAffectsBosses", true)
	self.instance:SetAttribute("HitboxTagged", true)
end

function HitboxBinder.onTouched(self: any, other: BasePart)
	if self.damage <= 0 then
		return
	end

	local player = (ModelBinder :: any).GetPlayer(other)
	local humanoid = (ModelBinder :: any).GetHumanoid(other)
	local cooldownKey = if player ~= nil
		then player :: Instance
		else if humanoid ~= nil then humanoid :: Instance else other
	local now = os.clock()
	if now < (self.lastHitAt[cooldownKey] or 0) then
		return
	end
	self.lastHitAt[cooldownKey] = now + self.interval

	if player ~= nil and self.affectsPlayers then
		getHpServiceServer():DamagePlayer(player, self.damage)
		return
	end

	if self.affectsNpcs and getNpcServiceServer():DamageNpcFromHitPart(other, self.damage, self.instance) > 0 then
		return
	end
	if
		self.affectsBosses
		and getBossServiceServer():DamageBossFromHitPart(other, self.damage, self.instance, "Hitbox") > 0
	then
		return
	end
	if self.affectsHumanoids and humanoid ~= nil then
		humanoid:TakeDamage(self.damage)
	end
end

return HitboxBinder
