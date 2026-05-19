--[[
  @Description: Contains a list of useful functions.
]]

--// Services
local TweenService = game:GetService("TweenService")

--// Modules
local LIB_FOLDER = script.Parent.Parent
local PartCache = require(LIB_FOLDER.PartCache)
local FastCast = require(LIB_FOLDER.FastCast)

--// Variables
local Random = Random.new()

local ASSET_FOLDER = script.Parent.Assets
local Decals = ASSET_FOLDER.Images:GetChildren()

-- Effects
local Effects = ASSET_FOLDER.Effects
local TrailEffects = Effects.Trail
local ImpactEffects = Effects.Impact

--// Module Setup
local System = {}

--[[
  Sets up a `CastBehavior` for later use,
  then returns it.
]]
function System.SetupBehavior(Cache: PartCache.Class, CastParams: RaycastParams): FastCast.FastCastBehavior
	-- Define Variables
	local Behavior = FastCast.newBehavior()

	-- Update Behavior properties
	Behavior.Acceleration = Vector3.new(0, -workspace.Gravity, 0)
	Behavior.MaxDistance = 500
	Behavior.RaycastParams = CastParams
	Behavior.CosmeticBulletProvider = Cache

	-- Export behavior
	return Behavior
end

--[[
	Clones and parents Droplet effects from a template part.
]]
function System.CreateEffects(Parent: BasePart, ImpactName: string)
	-- Variable definitions
	local Trail = TrailEffects:Clone()

	local Attachment0 = Instance.new("Attachment")
	local Attachment1 = Instance.new("Attachment")
	local ImpactAttachment = Instance.new("Attachment")

	-- Update Trail-related properties
	Trail.Attachment0 = Attachment0
	Trail.Attachment1 = Attachment1

	Attachment1.Position = Vector3.new(0.037, 0, 0)
	Attachment0.Name = "Attachment0"
	Attachment1.Name = "Attachment1"

	Attachment0.Parent = Parent
	Attachment1.Parent = Parent
	Trail.Parent = Parent :: any

	-- Update Impact-related properties
	for _, Effect in ipairs(ImpactEffects:GetChildren()) do
		local Clone = Effect:Clone()
		Clone.Parent = ImpactAttachment
	end

	ImpactAttachment.Name = ImpactName
	ImpactAttachment.Parent = Parent
	ImpactAttachment.Orientation = Vector3.new(0, 0, 0)
end

--[[
	Returns an empty object template that's going to be used as a droplet.
]]
function System.GetDroplet(ImpactName: string): BasePart
	-- Variable definitions
	local Droplet = Instance.new("MeshPart")

	-- Update properties
	Droplet.Size = Vector3.new(0.1, 0.1, 0.1)
	Droplet.Transparency = 0.25
	Droplet.Material = Enum.Material.Glass

	Droplet.Anchored = false
	Droplet.CanCollide = false
	Droplet.CanQuery = false
	Droplet.CanTouch = false

	-- Export droplet
	System.CreateEffects(Droplet, ImpactName)

	return Droplet
end

--[[
  Returns a Vector3, given the array range.
]]
function System.GetVector(Range: NumberRange)
	return Vector3.new(System.NextNumber(Range), System.NextNumber(Range), System.NextNumber(Range))
end

--[[
  NextNumber; Uses a global Random class,
  this is done for efficency.
]]
function System.NextNumber(Range: NumberRange): number
	return Random:NextNumber(Range.Min, Range.Max)
end

--[[
  An efficent way of doing TweenService:Create(...)
]]
function System.CreateTween(Object: Instance, Info: TweenInfo, Goal: { [any]: any }): Tween
	return TweenService:Create(Object, Info, Goal)
end

--[[
  Plays a sound in the given parent,
  used to play `End` & `Start` sounds.
]]
function System.PlaySound(Sound: Sound?, Parent: BasePart)
	if not Sound then
		return
	end

	local SoundClone = Sound:Clone()
	SoundClone.Parent = Parent

	SoundClone.Ended:Connect(function()
		SoundClone:Destroy()
	end)

	SoundClone:Play()
end

--[[
  Returns a random value/object from the
  given table.
]]
function System.GetRandom<T>(Table: { T }): T?
	return #Table > 0 and Table[math.random(1, #Table)] or nil
end

--[[
  Resets the properties of the given droplet,
  used to return pools to be recycled.
]]
function System.ResetDroplet(Object: BasePart, Original: BasePart)
	-- Variable definitions
	local Decal = Object:FindFirstChildOfClass("SurfaceAppearance")
	local Weld = Object:FindFirstChildOfClass("WeldConstraint")
	local Trail = Object:FindFirstChildOfClass("Trail")

	-- Reset properties
	Object.Size = Original.Size
	Object.Transparency = Original.Transparency
	Object.Anchored = Original.Anchored

	-- Update outsider properties
	if Trail then
		Trail.Enabled = false
	end

	if Weld then
		Weld:Destroy()
	end

	if Decal then
		Decal:Destroy()
	end

	-- Export object
	return Object
end

--[[
	Manages the sequence of decals;
	initiates only when the Type is designated as Decals.
]]
function System.ApplyDecal(Object: Instance)
	local Decal = System.GetRandom(Decals)
	if not Decal or not Decal:IsA("SurfaceAppearance") then
		return
	end

	-- Update Decal properties
	Decal:Clone().Parent = Object
end

--[[
	Emits particles by looping
	through an attachment's children; emitting a specific
	amount of them using the given amount.
]]
function System.EmitParticles(Attachment: Attachment, Amount: number)
	for _, Particle in Attachment:GetChildren() do
		if Particle:IsA("ParticleEmitter") then
			Particle:Emit(Amount)
		end
	end
end

--[[
	Returns the closest part within a given distance.
]]
function System.GetClosest(Origin: BasePart, Magnitude: number, Ancestor: Instance): BasePart
	-- Variable definitions
	local ClosestPart = nil
	local MinimumDistance = math.huge

	for _, Part in Ancestor:GetChildren() do
		if not Part:IsA("BasePart") then
			continue
		end

		local Distance = (Origin.Position - Part.Position).Magnitude
		local Logic = (not Part.Anchored and Origin ~= Part and Distance < Magnitude and Distance < MinimumDistance)
		if not Logic then
			continue
		end

		MinimumDistance = Distance
		ClosestPart = Part
	end

	-- Export closest part
	return ClosestPart
end

--[[
	Provides the target angles; utilized to
	assign the orientation to base position or CFrame.
]]
function System.GetAngles(IsDecal: boolean, RandomAngles: boolean): CFrame
	-- Variable definitions
	local RandomAngle = Random:NextNumber(0, 180)
	local AngleX = (IsDecal and -math.pi / 2 or math.pi / 2)
	local AngleY = (RandomAngles and RandomAngle or 0)

	-- Export angles
	return CFrame.Angles(AngleX, AngleY, 0)
end

--[[
	Delievers the target position; serves
	as a foundation that is subsequently
	applied with an orientation.
]]
function System.GetCFrame(Position: Vector3, Normal: Vector3, IsDecal: boolean): CFrame
	-- Variable definitions
	local DecalOffset = (IsDecal and (Normal / 76) or Vector3.zero)

	local Base = (Position + DecalOffset)

	local Target = (Position + Normal)

	-- Export cframe
	return CFrame.new(Base, Target)
end

--[[
	Refines the components of the given
	Vector3; utilized to implement modifications
	based on factors.
]]
function System.RefineVectors(IsDecal: boolean, VectorData: Vector3)
	local YVector = (IsDecal and 0 or VectorData.Y)

	return Vector3.new(VectorData.X, YVector, VectorData.Z)
end

--[[
  Weld, creates a WeldConstraint between two parts
   (Part0 and Part1).
]]
function System.Weld(Part0: BasePart, Part1: BasePart): WeldConstraint
	-- Variable definitions
	local Weld = Instance.new("WeldConstraint")

	-- Update Part properties
	Part1.Anchored = false

	-- Update Weld properties
	Weld.Parent = Part1
	Weld.Part0 = Part0
	Weld.Part1 = Part1

	-- Export weld
	return Weld
end

--[[
	Adds a connection to a table that holds connections.
]]
function System.Connect(Connection: FastCast.ConnectionStatic, Holder: { FastCast.ConnectionStatic })
	-- Update table
	table.insert(Holder, Connection)
end

--[[
	Destroys and disconnects all the connections 
	in a table that holds connections.
]]
function System.DisconnectAll(Holder: { FastCast.ConnectionStatic })
	-- Disconnect and destroy connections in Holder
	for Index, Connection: FastCast.ConnectionStatic in Holder do
		Connection:Disconnect()
		Holder[Index] = nil
	end
end

return System
