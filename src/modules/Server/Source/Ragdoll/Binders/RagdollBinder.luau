
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local ModelBinder = require("ModelBinder")
local RagdollServiceUtils = require("RagdollServiceUtils")

local RagdollBinder = {}
RagdollBinder.__index = RagdollBinder
setmetatable(RagdollBinder, ModelBinder)

function RagdollBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, RagdollBinder)
	self.model = self:GetModel()
	if self.model == nil then
		return self
	end

	self.context = nil
	self.recoveryToken = 0
	self.ragdollOnDeath = self.instance:GetAttribute("RagdollOnDeath") ~= false
	self.humanoid = self:GetHumanoid()
	self:ApplyRequestedState()

	if self.humanoid ~= nil then
		self:Connect(self.humanoid.Died, function()
			if self.ragdollOnDeath then
				self:SetRagdolled(true, "Death", nil)
			end
		end)
	end

	self:ObserveAttribute("RagdollEnabled", function()
		self:ApplyRequestedState()
	end)

	return self
end

function RagdollBinder.IsPlayerCharacter(self: any): boolean
	return self.model ~= nil and Players:GetPlayerFromCharacter(self.model) ~= nil
end

function RagdollBinder.SetRagdolled(self: any, enabled: boolean, reason: string, impulse: Vector3?)
	if self.model == nil then
		return
	end
	if self:IsPlayerCharacter() then
		return
	end

	if enabled then
		if self.context == nil then
			local rig = RagdollServiceUtils.GetCharacterRig(self.model)
			if rig ~= nil then
				self.context = RagdollServiceUtils.BeginRagdoll(rig, {
					reason = reason,
					impulse = impulse,
				})
			end
		end

		if self.context ~= nil then
			local planeX = self.instance:GetAttribute("RagdollPlaneX")
			if typeof(planeX) == "number" then
				RagdollServiceUtils.EnforceRagdoll2DPlane(self.context, planeX)
			end
		end

		local duration = self.instance:GetAttribute("RagdollDuration")
		if typeof(duration) == "number" and duration > 0 then
			self.recoveryToken += 1
			local token = self.recoveryToken
			task.delay(duration, function()
				if self.destroyed or self.recoveryToken ~= token then
					return
				end
				self:SetRagdolled(false, "Recovery", nil)
			end)
		end
	else
		self.recoveryToken += 1
		if self.context ~= nil then
			RagdollServiceUtils.EndRagdoll(self.context, {
				restoreHumanoid = true,
			})
			self.context = nil
		end
	end

	self.instance:SetAttribute("RagdollActive", self.context ~= nil)
end

function RagdollBinder.ApplyRequestedState(self: any)
	local requested = self.instance:GetAttribute("RagdollEnabled") == true
	if requested then
		self:SetRagdolled(true, tostring(self.instance:GetAttribute("RagdollReason") or "Binder"), nil)
	elseif not self.ragdollOnDeath then
		self:SetRagdolled(false, "Disabled", nil)
	end
end

function RagdollBinder.Cleanup(self: any)
	self:SetRagdolled(false, "Cleanup", nil)
end

return RagdollBinder
