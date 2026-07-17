local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local HitboxBinder = {}
HitboxBinder.__index = HitboxBinder
setmetatable(HitboxBinder, ModelBinder)

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

function HitboxBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, HitboxBinder)
	local dependencies = self:GetDependencies()
	self.bossServiceServer = assert(dependencies.BossServiceServer, "BossServiceServer dependency is unavailable")
	self.hpServiceServer = assert(dependencies.HpServiceServer, "HpServiceServer dependency is unavailable")
	self.npcServiceServer = assert(dependencies.NpcServiceServer, "NpcServiceServer dependency is unavailable")
	self.lastHitAt = {} :: { [Instance]: number }
	self:Refresh()
	ModelBinder.BindTouchedParts(instance, self.janitor, function(_part: BasePart, other: BasePart)
		self:OnTouched(other)
	end)
	return self
end

function HitboxBinder.Refresh(self: any)
	self.damage =
		math.max(0, getNumberAttribute(self.instance, "HitboxDamage", getNumberAttribute(self.instance, "Damage", 0)))
	self.interval = math.max(0.05, getNumberAttribute(self.instance, "HitboxInterval", 0.2))
	self.affectsPlayers = getBooleanAttribute(self.instance, "HitboxAffectsPlayers", true)
	self.affectsHumanoids = getBooleanAttribute(self.instance, "HitboxAffectsHumanoids", true)
	self.affectsNpcs = getBooleanAttribute(self.instance, "HitboxAffectsNpcs", true)
	self.affectsBosses = getBooleanAttribute(self.instance, "HitboxAffectsBosses", true)
	self.instance:SetAttribute("HitboxTagged", true)
end

function HitboxBinder.OnTouched(self: any, other: BasePart)
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
		self.hpServiceServer:DamagePlayer(player, self.damage)
		return
	end

	if self.affectsNpcs and self.npcServiceServer:DamageNpcFromHitPart(other, self.damage, self.instance) > 0 then
		return
	end
	if
		self.affectsBosses
		and self.bossServiceServer:DamageBossFromHitPart(other, self.damage, self.instance, "Hitbox") > 0
	then
		return
	end
	if self.affectsHumanoids and humanoid ~= nil then
		humanoid:TakeDamage(self.damage)
	end
end

return HitboxBinder
