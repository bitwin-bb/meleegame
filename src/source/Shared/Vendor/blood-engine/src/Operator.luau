--!strict

--[[
  @ Description:
    This is the operator of the base system/class,
    it manages the functionality of the droplets,
    the events of the casts, the limit and such.
]]

--// Modules
local LIB_FOLDER = script.Parent.Parent
local PartCache = require(LIB_FOLDER.PartCache)
local FastCast = require(LIB_FOLDER.FastCast)

local Functions = require(script.Parent.Functions)
local Settings = require(script.Parent.Settings)

--// Types
type ClassData = {
	Settings: Settings.Class,

	Registry: { [BasePart]: Settings.Class },
	Connections: { FastCast.ConnectionStatic },

	Droplet: BasePart,
	Cache: PartCache.Class,
	Container: Folder,
	Caster: FastCast.Class,
	Behavior: FastCast.FastCastBehavior,
}

--// Variables
local TypeAttribute = "Type"
local DecayAttribute = "Decaying"
local ExpandAttribute = "Expanding"
local Assets = script.Parent.Assets

-- Meshes
local Meshes = Assets.Meshes
local MeshMap = {
	Default = Meshes.Droplet,
	Decal = Meshes.Decal,
} :: { [string]: MeshPart }

-- Sounds
local Sounds = Assets.Sounds
local StartFolder = Sounds.Start:GetChildren()
local EndFolder = Sounds.End:GetChildren()

--// Class Setup
local Class = {}
Class.__index = Class
export type Class = typeof(setmetatable({} :: ClassData, Class))

--[[
  Class constructor, constructs the class
  including other properties/variables.
]]
function Class.new(SettingsInstance: Settings.Class)
	local self = setmetatable({}, Class) :: Class

	self.Settings = SettingsInstance

	self:Initialize()
	self:InitializeCast()

	return self
end

--[[
  Immediately called after the construction of the class,
  defines properties/variables for after-construction
]]
function Class.Initialize(self: Class)
	local FolderName = self.Settings.FolderName
	local Limit = self.Settings.Limit
	local CastParams = self.Settings.RaycastParams

	local Folder = PartCache.CreateSubFolder(FolderName)
	local Object = Functions.GetDroplet(self.Settings.SplashName)

	-- Class definitions
	local Cache = PartCache.new(Object, Limit, Folder)

	self.Registry = {}
	self.Connections = {}

	self.Droplet = Object
	self.Cache = Cache
	self.Container = Folder
	self.Caster = FastCast.new()
	self.Behavior = Functions.SetupBehavior(Cache, CastParams)
end

--[[
  The Cast-Setup, which is executed immediately
  following the Initialization of the class.

  It efficiently manages events
  associated with the Caster.
]]
function Class.InitializeCast(self: Class)
	-- Self definitions
	local Connections = self.Connections
	local Caster = self.Caster
	local Container = self.Container

	-- Event definitions
	local LengthChanged = Caster.Events.LengthChanged
	local RayHit = Caster.Events.RayHit

	-- Caster Listeners
	Functions.Connect(
		LengthChanged:Connect(function(_, Origin: Vector3, Direction: Vector3, Length: number, _, Object: BasePart?)
			if not Object then
				return
			end

			-- 3D Definition
			local ObjectLength = Object.Size.Z / 2
			local Offset = CFrame.new(0, 0, -(Length - ObjectLength))
			local GoalCFrame = CFrame.new(Origin, Origin + Direction):ToWorldSpace(Offset)

			-- Update properties
			Object.CFrame = GoalCFrame
		end),
		Connections
	)

	Functions.Connect(
		RayHit:Connect(function(_, RaycastResult: RaycastResult, Velocity, Object: BasePart?)
			if not Object then
				return
			end

			-- Options definitions
			local RegistryData = self.Registry[Object] or self.Settings
			local Size = RegistryData.StartingSize
			local SizeRange = RegistryData.DefaultSize
			local Distance = RegistryData.Distance
			local Expansion = RegistryData.Expansion
			local IsDecal = RegistryData.Type == "Decal"

			-- Variable definitions
			local CastInstance = RaycastResult.Instance
			local Position = RaycastResult.Position
			local Normal = RaycastResult.Normal

			local VectorSize = Functions.GetVector(SizeRange)
			local GoalSize = Functions.RefineVectors(IsDecal, Vector3.new(VectorSize.X, VectorSize.Y / 4, VectorSize.X))

			local GoalAngles = Functions.GetAngles(IsDecal, IsDecal)
			local GoalCFrame = Functions.GetCFrame(Position, Normal, IsDecal) * GoalAngles

			local ClosestPart = Functions.GetClosest(Object, Distance, Container)

			local ExpansionLogic = (
				Expansion
				and ClosestPart
				and not ClosestPart:GetAttribute(DecayAttribute)
				and not ClosestPart:GetAttribute(ExpandAttribute)
				and ClosestPart:GetAttribute(TypeAttribute) == RegistryData.Type
			)

			-- Clear the registry entry
			self.Registry[Object] = nil

			-- Evaluates if the droplet is close to another pool, if so, expand.
			if ExpansionLogic then
				self:Expanse(Object, ClosestPart, Velocity, GoalSize, RegistryData)
				return
			end

			-- Update properties
			Object.Anchored = true
			Object.Size = Size
			Object.CFrame = GoalCFrame
			Object.Transparency = Functions.NextNumber(RegistryData.DefaultTransparency)

			--[[
     		Transitions the droplet into a pool,
      		then handles its later functionality.
        	(Decay, Sounds, etc...)
    	]]
			Functions.CreateTween(Object, RegistryData.Tweens.Landed, { Size = GoalSize }):Play()

			self:HandleDroplet(Object, RegistryData)
			self:HitEffects(Object, Velocity, RegistryData)
			if CastInstance:IsA("BasePart") then
				Functions.Weld(CastInstance, Object)
			end
		end),
		Connections
	)
end

--[[
	Destroys PartCache, FastCast, 
	and all the droplets associated with this engine/operator.
]]
function Class.Destroy(self: Class)
	-- Destroy classes
	self.Cache:Dispose()
	Functions.DisconnectAll(self.Connections)

	-- Destroy main container
	if self.Container then
		self.Container:Destroy()
	end
end

--[[
  Emitter, emits a certain amount of droplets,
  at a certain point of origin, with a certain given direction.
]]
function Class.Emit(self: Class, Origin: Vector3, Direction: Vector3, InputData: Settings.Settings?)
	-- At limit, end
	if #self.Cache.InUse >= self.Settings.Limit then
		return
	end

	-- Cache needs parts, so make more
	if #self.Cache.Open <= 0 then
		self.Cache:Expand()
	end

	-- Create a clone of the default settings, and apply specific settings if provided
	local Data = table.clone(self.Settings)
	Data:UpdateSettings((InputData or ({} :: any)) :: Settings.Settings)

	-- Variable definitions
	local Velocity = Functions.NextNumber(Data.DropletVelocity) * 10
	local Position = Functions.GetVector(Data.OffsetRange) / 10

	-- Final definitions
	local FinalPosition = Origin + Vector3.new(Position.X, 0, Position.Z)
	local FinalStart = (Data.RandomOffset and FinalPosition or Origin)

	-- Caster definitions, fire the caster with given arguments
	local ActiveDroplet = self.Caster:Fire(FinalStart, Direction, Velocity, self.Behavior)
	local Droplet = ActiveDroplet.RayInfo.CosmeticBulletObject
	if not Droplet or not Droplet:IsA("MeshPart") then
		return
	end

	-- Update the mesh's look and color
	if MeshMap[Data.Type] then
		Droplet:ApplyMesh(MeshMap[Data.Type])
	end
	Droplet.Color = Data.DropletColor

	-- Assign the registry entry and update the attributes
	self.Registry[Droplet] = Data
	Droplet:SetAttribute(TypeAttribute, Data.Type)
	Droplet:SetAttribute(DecayAttribute, false)
	Droplet:SetAttribute(ExpandAttribute, false)

	-- Execute essential functions
	self:UpdateDroplet(Droplet, Data)
	Functions.PlaySound(Functions.GetRandom(StartFolder) :: Sound?, Droplet)
end

--[[
  A small function, designed to update the properties
  of a recently emitted droplet.
]]
function Class.UpdateDroplet(_, Object: BasePart, Data: Settings.Class)
	-- Variable definitions
	local DropletTrail = Data.Trail
	local DropletVisible = Data.DropletVisible
	local IsDecal = Data.Type == "Decal"

	-- Object definitions
	local Trail = Object:FindFirstChildOfClass("Trail")

	-- Update Object properties
	Object.Transparency = DropletVisible and 0 or 1
	if Trail then
		Trail.Enabled = DropletTrail
	end

	-- Execute essential functions
	if IsDecal then
		Functions.ApplyDecal(Object)
	end
end

--[[
  Handles the given droplet/object after
  it landed on a surface.
]]
function Class.HandleDroplet(self: Class, Object: BasePart, Data: Settings.Class)
	-- Variable definitions
	local Tweens = Data.Tweens
	local DecayDelay = Data.DecayDelay

	local DecayInfo = Tweens.Decay
	local DecayTime = Functions.NextNumber(DecayDelay)

	local ScaleDown = Data.ScaleDown
	local FinalSize = ScaleDown and Vector3.new(0.01, 0.01, 0.01) or Object.Size

	-- Tween definitions
	local DecayTween = Functions.CreateTween(Object, DecayInfo, { Transparency = 1, Size = FinalSize })

	-- Update Droplet properties
	local Trail = Object:FindFirstChildOfClass("Trail")
	if Trail then
		Trail.Enabled = false
	end

	-- Listeners
	DecayTween.Completed:Connect(function()
		DecayTween:Destroy()
		Object:SetAttribute("Decaying", nil)
		self:ReturnDroplet(Object)
	end)

	-- Reset the droplet after the given DecayDelay has passed
	task.delay(DecayTime, function()
		DecayTween:Play()
		Object:SetAttribute("Decaying", true)
	end)
end

--[[
  HitEffects, a sequence of effects to enhance
  the visuals of the droplet->pool
]]
function Class.HitEffects(_, Object: BasePart, Velocity: Vector3, Data: Settings.Class)
	-- Execute essential functions
	Functions.PlaySound(Functions.GetRandom(EndFolder) :: Sound?, Object)

	-- Variable definitions
	local SplashName = Data.SplashName
	local SplashAmount = Data.SplashAmount
	local SplashByVelocity = Data.SplashByVelocity
	local Divider = Data.VelocityDivider
	local IsDecal = Data.Type == "Decal"

	-- Splash
	local FinalVelocity = Velocity.Magnitude / Divider
	local FinalAmount = (SplashByVelocity and FinalVelocity or Functions.NextNumber(SplashAmount))
	local Splash = Object:FindFirstChild(SplashName)
	if Splash and Splash:IsA("Attachment") then
		Splash.Orientation = Vector3.new(0, 0, IsDecal and 0 or 180)
		Functions.EmitParticles(Splash, FinalAmount)
	end
end

--[[
	Simulates the pool expansion
	effect when a droplet is near
	a pool.

	It checks the distance between
	a threshold, then triggers changes
	on the droplet & pool.
]]
function Class.Expanse(
	self: Class,
	Object: BasePart,
	ClosestPart: BasePart,
	Velocity: Vector3,
	Size: Vector3,
	Data: Settings.Class
)
	-- Variable definitions
	local Divider = Data.ExpanseDivider
	local MaximumSize = Data.MaximumSize
	local IsDecal = Data.Type == "Decal"

	-- Info definitions
	local Tweens = Data.Tweens
	local Expand = Tweens.Expand

	-- Value definitions
	local PoolSize = ClosestPart.Size
	local FinalVelocity = Velocity / 20
	local GoalSize = Vector3.new(Size.X, Size.Y / Divider, Size.Z) / Divider

	local FirstSize = Functions.RefineVectors(
		IsDecal,
		Vector3.new(PoolSize.X - FinalVelocity.Z, PoolSize.Y + FinalVelocity.Y, PoolSize.Z - FinalVelocity.Z)
	)

	local LastSize = Vector3.new(PoolSize.X, PoolSize.Y, PoolSize.Z) + GoalSize

	local FinalSize = (LastSize.X < MaximumSize and LastSize or PoolSize)

	-- Update properties
	ClosestPart:SetAttribute("Expanding", true)
	ClosestPart.Size = FirstSize

	-- Transition to Expanded size
	local Tween = Functions.CreateTween(ClosestPart, Expand, { Size = FinalSize })

	Tween:Play()
	Tween.Completed:Connect(function()
		ClosestPart:SetAttribute("Expanding", nil)
		Tween:Destroy()
	end)

	-- Execute essential functions
	Functions.PlaySound(Functions.GetRandom(EndFolder) :: Sound?, ClosestPart)
	self:ReturnDroplet(Object)
end

function Class.Shrink(self: Class, Object: BasePart, Data: Settings.Class)
	-- Variable definitions
	local ScaleDown = Data.ScaleDown
	local FinalSize = ScaleDown and Vector3.new(0.01, 0.01, 0.01) or Object.Size

	-- Tween definitions
	local DecayTween = Functions.CreateTween(Object, Data.Tweens.Decay, { Transparency = 1, Size = FinalSize })

	-- Update Droplet properties
	local Trail = Object:FindFirstChildOfClass("Trail")
	if Trail then
		Trail.Enabled = false
	end

	-- Listeners
	DecayTween.Completed:Connect(function()
		DecayTween:Destroy()
		Object:SetAttribute("Decaying", nil)
		self:ReturnDroplet(Object)
	end)

	-- Reset the droplet after the given DecayDelay has passed
	DecayTween:Play()
	Object:SetAttribute("Decaying", true)
end

--[[
  Resets the given droplet/pool,
  then returns it to the Cache.
]]
function Class.ReturnDroplet(self: Class, Object: BasePart)
	-- Execute essential functions
	Functions.ResetDroplet(Object, self.Droplet)
	self.Cache:ReturnPart(Object)
end

return Class
