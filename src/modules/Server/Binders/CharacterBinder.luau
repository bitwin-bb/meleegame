--!strict

local Players = game:GetService("Players")

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local CharacterBinder = {}
CharacterBinder.__index = CharacterBinder
setmetatable(CharacterBinder, ModelBinder)

function CharacterBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, CharacterBinder)
	self.model = self:GetModel()
	if self.model == nil then
		return self
	end

	self.ownerPlayer = Players:GetPlayerFromCharacter(self.model)
	self.humanoid = self:GetHumanoid()
	self:updateState()

	if self.humanoid ~= nil then
		self:Connect(self.humanoid.HealthChanged, function()
			self:updateState()
		end)
		self:Connect(self.humanoid:GetPropertyChangedSignal("MaxHealth"), function()
			self:updateState()
		end)
		self:Connect(self.humanoid.Died, function()
			self:updateState()
		end)
	end

	return self
end

function CharacterBinder.updateState(self: any)
	local model = self.model
	if model == nil then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	self.humanoid = humanoid

	model:SetAttribute("CharacterTagged", true)
	model:SetAttribute("CharacterAlive", humanoid ~= nil and humanoid.Health > 0)
	model:SetAttribute("CharacterIsPlayer", self.ownerPlayer ~= nil)

	if self.ownerPlayer ~= nil then
		model:SetAttribute("CharacterUserId", self.ownerPlayer.UserId)
	end
	if humanoid ~= nil then
		model:SetAttribute("CharacterHealth", humanoid.Health)
		model:SetAttribute("CharacterMaxHealth", humanoid.MaxHealth)
	end
end

return CharacterBinder
