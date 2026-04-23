--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local HitboxBinder = {}
HitboxBinder.__index = HitboxBinder
setmetatable(HitboxBinder, ModelBinder)

local bossServiceServer = nil
local hpServiceServer = nil
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

local function resolveBooleanAttribute(instance: Instance, attributeName: string, fallback: boolean): boolean
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
	ModelBinder.bindTouchedParts(instance, self.janitor, function(_part: BasePart, other: BasePart)
		self:onTouched(other)
	end)
	return self
end

function HitboxBinder.refresh(self: any)
	self.damage = math.max(
		0,
		resolveNumberAttribute(self.instance, "HitboxDamage", resolveNumberAttribute(self.instance, "Damage", 0))
	)
	self.interval = math.max(0.05, resolveNumberAttribute(self.instance, "HitboxInterval", 0.2))
	self.affectsPlayers = resolveBooleanAttribute(self.instance, "HitboxAffectsPlayers", true)
	self.affectsHumanoids = resolveBooleanAttribute(self.instance, "HitboxAffectsHumanoids", true)
	self.affectsNpcs = resolveBooleanAttribute(self.instance, "HitboxAffectsNpcs", true)
	self.affectsBosses = resolveBooleanAttribute(self.instance, "HitboxAffectsBosses", true)
	self.instance:SetAttribute("HitboxTagged", true)
end

function HitboxBinder.onTouched(self: any, other: BasePart)
	if self.damage <= 0 then
		return
	end

	local player = ModelBinder.resolvePlayer(other)
	local humanoid = ModelBinder.resolveHumanoid(other)
	local cooldownKey = if player ~= nil
		then player :: Instance
		else if humanoid ~= nil then humanoid :: Instance else other
	local now = os.clock()
	if now < (self.lastHitAt[cooldownKey] or 0) then
		return
	end
	self.lastHitAt[cooldownKey] = now + self.interval

	if player ~= nil and self.affectsPlayers then
		getHpServiceServer():damagePlayer(player, self.damage)
		return
	end

	if self.affectsNpcs and getNpcServiceServer():damageNpcFromHitPart(other, self.damage, self.instance) > 0 then
		return
	end
	if self.affectsBosses and getBossServiceServer():damageBossFromHitPart(other, self.damage, self.instance, "Hitbox") > 0 then
		return
	end
	if self.affectsHumanoids and humanoid ~= nil then
		humanoid:TakeDamage(self.damage)
	end
end

return HitboxBinder
