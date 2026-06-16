
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local HumanoidUtils = Nevermore.Get("HumanoidUtils")
local Table = Nevermore.Get("Table")

local HumanoidAdapter = {}
HumanoidAdapter.__index = HumanoidAdapter

export type HumanoidAdapter = typeof(setmetatable(
	{} :: {
		humanoid: Humanoid?,
	},
	HumanoidAdapter
))

function HumanoidAdapter.new(humanoidRaw: any?): HumanoidAdapter
	return setmetatable({
		humanoid = if typeof(humanoidRaw) == "Instance" and humanoidRaw:IsA("Humanoid") then humanoidRaw else nil,
	}, HumanoidAdapter)
end

function HumanoidAdapter.GetHealth(self: HumanoidAdapter): number
	return if self.humanoid ~= nil then self.humanoid.Health else 0
end

function HumanoidAdapter.IsAlive(self: HumanoidAdapter): boolean
	return self:GetHealth() > 0
end

function HumanoidAdapter.IsGrounded(self: HumanoidAdapter): boolean
	local humanoid = self.humanoid
	if humanoid == nil then
		return false
	end
	local state = humanoid:GetState()
	return state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping
end

function HumanoidAdapter.ForceUnseat(self: HumanoidAdapter)
	if self.humanoid ~= nil then
		HumanoidUtils.forceUnseatHumanoid(self.humanoid)
	end
end

function HumanoidAdapter.Destroy(self: HumanoidAdapter)
	self.humanoid = nil
end

HumanoidAdapter.getHealth = HumanoidAdapter.GetHealth
HumanoidAdapter.isAlive = HumanoidAdapter.IsAlive
HumanoidAdapter.isGrounded = HumanoidAdapter.IsGrounded
HumanoidAdapter.forceUnseat = HumanoidAdapter.ForceUnseat
HumanoidAdapter.destroy = HumanoidAdapter.Destroy
HumanoidAdapter.copy = Table.copy

return HumanoidAdapter
