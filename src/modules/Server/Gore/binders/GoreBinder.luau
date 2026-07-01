
local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local BossServiceUtils = require("BossServiceUtils")
local GoreServiceUtils = require("GoreServiceUtils")
local ModelBinder = require("ModelBinder")
local NpcServiceUtils = require("NpcServiceUtils")
local TagBinder = require("TagBinder")

local GoreBinder = {}
GoreBinder.__index = GoreBinder
setmetatable(GoreBinder, ModelBinder)

local BOSS_BLOOD_COLOR = Color3.fromRGB(132, 10, 18)
local goreServiceServer = nil

local function getGoreServiceServer()
	if goreServiceServer == nil then
		goreServiceServer = require("GoreServiceServer")
	end
	return goreServiceServer
end

local function GetEntityId(model: Model): string?
	local player = Players:GetPlayerFromCharacter(model)
	if player ~= nil then
		return nil
	end

	local bossRuntimeId = BossServiceUtils.GetUntimeIdFromInstance(model)
	if bossRuntimeId ~= nil then
		return ("boss:%s"):format(bossRuntimeId)
	end

	local npcRuntimeId = NpcServiceUtils.GetUntimeIdFromInstance(model)
	if npcRuntimeId ~= nil then
		return GoreServiceUtils.MakeNpcEntityId(npcRuntimeId)
	end

	local existing = model:GetAttribute("GoreEntityId")
	if typeof(existing) == "string" and existing ~= "" then
		return existing
	end

	local generated = HttpService:GenerateGUID(false)
	model:SetAttribute("GoreEntityId", generated)
	return generated
end

function GoreBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, GoreBinder)
	self.model = self:GetModel()
	if self.model == nil then
		return self
	end

	self.entityId = GetEntityId(self.model)
	self.humanoid = self:GetHumanoid()
	self.lastHealth = if self.humanoid ~= nil then self.humanoid.Health else nil
	self.registeredByBinder = false

	if self.entityId ~= nil then
		self:register()
	end
	if self.humanoid ~= nil and self.registeredByBinder then
		self:Connect(self.humanoid.HealthChanged, function(nextHealth: number)
			self:onHealthChanged(nextHealth)
		end)
		self:Connect(self.humanoid.Died, function()
			self:onDied()
		end)
	end

	return self
end

function GoreBinder.GetConfig(self: any): { [string]: any }
	local config = {}
	if self:HasTag(TagBinder.Tags.Gore_Slime) then
		config.bloodColor = GoreServiceUtils.DEFAULT_NPC_BLOOD_COLOR
	elseif self:HasTag(TagBinder.Tags.Gore_Boss) then
		config.bloodColor = BOSS_BLOOD_COLOR
	else
		config.bloodColor = GoreServiceUtils.DEFAULT_PLAYER_BLOOD_COLOR
	end

	config.damageBloodAmount = self.instance:GetAttribute("GoreDamageBloodAmount")
	config.deathBloodAmount = self.instance:GetAttribute("GoreDeathBloodAmount")
	config.deathGibCount = self.instance:GetAttribute("GoreDeathGibCount")
	config.emitDeathGibs = self.instance:GetAttribute("GoreEmitDeathGibs")
	return config
end

function GoreBinder.register(self: any)
	if self.entityId == nil or self.model == nil then
		return
	end

	local goreServiceServer = getGoreServiceServer()
	local existing = goreServiceServer:GetEntityRuntime(self.entityId)
	if existing ~= nil and existing.model == self.model then
		return
	end

	self.registeredByBinder = goreServiceServer:RegisterEntity(self.entityId, self.model, self:GetConfig())
	if self.registeredByBinder then
		self.model:SetAttribute("GoreBinderEntityId", self.entityId)
	end
end

function GoreBinder.onHealthChanged(self: any, nextHealth: number)
	if self.entityId == nil then
		return
	end

	local previousHealth = self.lastHealth
	self.lastHealth = nextHealth
	if typeof(previousHealth) ~= "number" or nextHealth >= previousHealth then
		return
	end

	getGoreServiceServer():emitEntityDamage(self.entityId, self:GetRootPart(), previousHealth - nextHealth)
end

function GoreBinder.onDied(self: any)
	if self.entityId == nil then
		return
	end
	getGoreServiceServer():emitEntityDeath(self.entityId, self:GetRootPart())
end

function GoreBinder.Cleanup(self: any)
	if self.registeredByBinder and self.entityId ~= nil then
		getGoreServiceServer():UnregisterEntity(self.entityId)
	end
end

return GoreBinder
