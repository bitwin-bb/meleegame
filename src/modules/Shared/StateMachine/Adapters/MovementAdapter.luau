--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
local PhysicsUtils = Nevermore.Get("PhysicsUtils")
local Table = Nevermore.Get("Table")

local MovementAdapter = {}
MovementAdapter.__index = MovementAdapter

export type MovementAdapter = typeof(setmetatable(
	{} :: {
		root: BasePart?,
		humanoid: Humanoid?,
		facing: Vector3,
	},
	MovementAdapter
))

function MovementAdapter.new(rootRaw: any?, humanoidRaw: any?): MovementAdapter
	return setmetatable({
		root = if typeof(rootRaw) == "Instance" and rootRaw:IsA("BasePart") then rootRaw else nil,
		humanoid = if typeof(humanoidRaw) == "Instance" and humanoidRaw:IsA("Humanoid") then humanoidRaw else nil,
		facing = Vector3.zAxis,
	}, MovementAdapter)
end

function MovementAdapter.SetVelocity(self: MovementAdapter, velocity: Vector3)
	if self.root ~= nil then
		self.root.AssemblyLinearVelocity = velocity
	end
end

function MovementAdapter.ApplyImpulse(self: MovementAdapter, impulse: Vector3)
	if self.root ~= nil then
		self.root:ApplyImpulse(impulse)
	end
end

function MovementAdapter.ApplyForce(self: MovementAdapter, force: Vector3, forcePosition: Vector3?)
	if self.root ~= nil then
		PhysicsUtils.applyForce(self.root, force, forcePosition or self.root.Position)
	end
end

function MovementAdapter.SetFacing(self: MovementAdapter, directionRaw: any)
	if typeof(directionRaw) ~= "Vector3" or directionRaw.Magnitude <= 0 then
		return
	end
	self.facing = directionRaw.Unit
end

function MovementAdapter.IsGrounded(self: MovementAdapter): boolean
	local humanoid = self.humanoid
	if humanoid == nil then
		return false
	end
	local state = humanoid:GetState()
	return state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping
end

function MovementAdapter.Destroy(self: MovementAdapter)
	self.root = nil
	self.humanoid = nil
end

MovementAdapter.setVelocity = MovementAdapter.SetVelocity
MovementAdapter.applyImpulse = MovementAdapter.ApplyImpulse
MovementAdapter.applyForce = MovementAdapter.ApplyForce
MovementAdapter.setFacing = MovementAdapter.SetFacing
MovementAdapter.isGrounded = MovementAdapter.IsGrounded
MovementAdapter.destroy = MovementAdapter.Destroy
MovementAdapter.copy = Table.copy

return MovementAdapter
