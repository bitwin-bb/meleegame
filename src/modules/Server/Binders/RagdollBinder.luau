--!strict

local Players = game:GetService("Players")

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local RagdollServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.RagdollServiceUtils)

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
	self:applyRequestedState()

	if self.humanoid ~= nil then
		self:Connect(self.humanoid.Died, function()
			if self.ragdollOnDeath then
				self:setRagdolled(true, "Death", nil)
			end
		end)
	end

	self:ObserveAttribute("RagdollEnabled", function()
		self:applyRequestedState()
	end)

	return self
end

function RagdollBinder.isPlayerCharacter(self: any): boolean
	return self.model ~= nil and Players:GetPlayerFromCharacter(self.model) ~= nil
end

function RagdollBinder.setRagdolled(self: any, enabled: boolean, reason: string, impulse: Vector3?)
	if self.model == nil then
		return
	end
	if self:isPlayerCharacter() then
		return
	end

	if enabled then
		if self.context == nil then
			local rig = RagdollServiceUtils.resolveCharacterRig(self.model)
			if rig ~= nil then
				self.context = RagdollServiceUtils.beginRagdoll(rig, {
					reason = reason,
					impulse = impulse,
				})
			end
		end

		if self.context ~= nil then
			local planeX = self.instance:GetAttribute("RagdollPlaneX")
			if typeof(planeX) == "number" then
				RagdollServiceUtils.enforceRagdoll2DPlane(self.context, planeX)
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
				self:setRagdolled(false, "Recovery", nil)
			end)
		end
	else
		self.recoveryToken += 1
		if self.context ~= nil then
			RagdollServiceUtils.endRagdoll(self.context, {
				restoreHumanoid = true,
			})
			self.context = nil
		end
	end

	self.instance:SetAttribute("RagdollActive", self.context ~= nil)
end

function RagdollBinder.applyRequestedState(self: any)
	local requested = self.instance:GetAttribute("RagdollEnabled") == true
	if requested then
		self:setRagdolled(true, tostring(self.instance:GetAttribute("RagdollReason") or "Binder"), nil)
	elseif not self.ragdollOnDeath then
		self:setRagdolled(false, "Disabled", nil)
	end
end

function RagdollBinder.Cleanup(self: any)
	self:setRagdolled(false, "Cleanup", nil)
end

return RagdollBinder
