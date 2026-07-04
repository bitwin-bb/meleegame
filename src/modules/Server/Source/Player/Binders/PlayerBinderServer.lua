local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")
local ModelBinder = require("ModelBinder")
local Rx: any = require("Rx")
local TagBinder = require("TagBinder")

local PlayerBinderServer = {}
PlayerBinderServer.__index = PlayerBinderServer
setmetatable(PlayerBinderServer, ModelBinder)

PlayerBinderServer.TAG_NAME = TagBinder.Tags.Character

local function getOwnerPlayer(model: Model?): Player?
	if model == nil then
		return nil
	end

	return Players:GetPlayerFromCharacter(model)
end

function PlayerBinderServer.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, PlayerBinderServer)
	self.model = self:GetModel()
	self.humanoid = self:GetHumanoid()
	self.humanoidMaid = Maid.new()
	self.boundHumanoid = nil
	self.ownerPlayer = getOwnerPlayer(self.model)
	self.janitor:GiveTask(self.humanoidMaid)

	self:BindState()
	self:Refresh()

	return self
end

function PlayerBinderServer.BindState(self: any)
	local signals = {
		Rx.fromSignal(self.instance.AncestryChanged),
		Rx.fromSignal(self.instance.ChildAdded),
		Rx.fromSignal(self.instance.ChildRemoved),
	}

	self.janitor:GiveTask(Rx.merge(signals):Subscribe(function()
		self:Refresh()
	end))
end

function PlayerBinderServer.BindHumanoid(self: any, humanoid: Humanoid?)
	if self.boundHumanoid == humanoid then
		return
	end

	self.boundHumanoid = humanoid
	self.humanoidMaid:DoCleaning()

	if humanoid == nil then
		return
	end

	self.humanoidMaid:GiveTask(Rx.merge({
		Rx.fromSignal(humanoid.HealthChanged),
		Rx.fromSignal(humanoid:GetPropertyChangedSignal("MaxHealth")),
		Rx.fromSignal(humanoid.Died),
	}):Subscribe(function()
		self:Refresh()
	end))
end

function PlayerBinderServer.Refresh(self: any)
	if self.destroyed then
		return
	end

	local model = self:GetModel()
	self.model = model
	self.humanoid = self:GetHumanoid()
	self.ownerPlayer = getOwnerPlayer(model)
	self:BindHumanoid(self.humanoid)

	if model == nil then
		return
	end

	local ownerPlayer = self.ownerPlayer
	local humanoid = self.humanoid
	model:SetAttribute("PlayerTagged", ownerPlayer ~= nil)
	model:SetAttribute("PlayerServerTagged", ownerPlayer ~= nil)
	model:SetAttribute("PlayerAlive", humanoid ~= nil and humanoid.Health > 0)

	if ownerPlayer ~= nil then
		model:SetAttribute("PlayerUserId", ownerPlayer.UserId)
		model:SetAttribute("PlayerName", ownerPlayer.Name)
	else
		model:SetAttribute("PlayerUserId", nil)
		model:SetAttribute("PlayerName", nil)
	end

	if humanoid ~= nil then
		model:SetAttribute("PlayerHealth", humanoid.Health)
		model:SetAttribute("PlayerMaxHealth", humanoid.MaxHealth)
	else
		model:SetAttribute("PlayerHealth", nil)
		model:SetAttribute("PlayerMaxHealth", nil)
	end
end

return PlayerBinderServer
