--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local HumanoidUtils = Nevermore.Get("HumanoidUtils")
local Maid = Nevermore.Get("Maid")
local PhysicsUtils = Nevermore.Get("PhysicsUtils")

local MovementHandler = {}
MovementHandler.__index = MovementHandler

export type MovementHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		character: Model?,
		humanoid: Humanoid?,
		root: BasePart?,
		facing: Vector3,
	},
	MovementHandler
))

function MovementHandler.new(characterRaw: any?): MovementHandler
	local self = setmetatable({
		maid = Maid.new(),
		character = nil,
		humanoid = nil,
		root = nil,
		facing = Vector3.zAxis,
	}, MovementHandler)

	self:SetCharacter(characterRaw)
	return self
end

function MovementHandler.SetCharacter(self: MovementHandler, characterRaw: any?)
	self.character = if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model") then characterRaw else nil
	self.humanoid = if self.character ~= nil then HumanoidUtils.getHumanoid(self.character) else nil
	local root = if self.character ~= nil then self.character:FindFirstChild("HumanoidRootPart") else nil
	self.root = if root ~= nil and root:IsA("BasePart") then root else nil
end

function MovementHandler.SetVelocity(self: MovementHandler, velocity: Vector3)
	if self.root ~= nil then
		self.root.AssemblyLinearVelocity = velocity
	end
end

function MovementHandler.ApplyImpulse(self: MovementHandler, impulse: Vector3)
	if self.root ~= nil then
		self.root:ApplyImpulse(impulse)
	end
end

function MovementHandler.ApplyForce(self: MovementHandler, force: Vector3, forcePosition: Vector3?)
	if self.root ~= nil then
		PhysicsUtils.applyForce(self.root, force, forcePosition or self.root.Position)
	end
end

function MovementHandler.SetFacing(self: MovementHandler, directionRaw: any)
	if typeof(directionRaw) ~= "Vector3" or directionRaw.Magnitude <= 0 then
		return
	end
	self.facing = directionRaw.Unit
end

function MovementHandler.IsGrounded(self: MovementHandler): boolean
	local humanoid = self.humanoid
	if humanoid == nil then
		return false
	end
	local state = humanoid:GetState()
	return state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping
end

function MovementHandler.Destroy(self: MovementHandler)
	self.maid:DoCleaning()
	self.character = nil
	self.humanoid = nil
	self.root = nil
end

MovementHandler.setCharacter = MovementHandler.SetCharacter
MovementHandler.setVelocity = MovementHandler.SetVelocity
MovementHandler.applyImpulse = MovementHandler.ApplyImpulse
MovementHandler.applyForce = MovementHandler.ApplyForce
MovementHandler.setFacing = MovementHandler.SetFacing
MovementHandler.isGrounded = MovementHandler.IsGrounded
MovementHandler.destroy = MovementHandler.Destroy

return MovementHandler
