--!strict

--[[
  @ Description:
    A class that handles settings,
    a group of keys that have an assigned value.
]]

--// Types
type ClassData = {
	FolderName: string, -- Specifies the name of the folder containing the droplets.
	Type: "Default" | "Decal" | "Brick", -- Defines the droplet type. It can be either "Default" (Sphere), "Decal" or "Brick".
	Limit: number, -- Sets the maximum number of droplets that can be created.
	Filter: { Instance }, -- An array/table of instances that should be ignored during droplet collision.

	SizeY: NumberRange, -- Specifices the range of the thickness/flatness/depth of the pool. Lesser is flatter.
	DefaultSize: NumberRange, -- Specifies the default size range of a pool.
	DefaultTransparency: NumberRange, -- Specifies the default transparency range of a pool.
	StartingSize: Vector3, -- Sets the initial size of the droplets upon landing.
	ScaleDown: boolean, -- Determines whether the pool should scale down when decaying.

	DropletDelay: NumberRange, -- Sets the delay between emitting droplets in a loop (for the EmitAmount method).
	DropletVelocity: NumberRange, -- Controls the velocity of the emitted droplet.
	DropletVisible: boolean, -- Determines if the droplet is visible upon emission.
	DropletColor: Color3, -- Determines the color of the emitted droplet.

	RandomOffset: boolean, -- Determines whether a droplet should spawn at a random offset from a given position.
	OffsetRange: NumberRange, -- Specifies the offset range for the position vectors.

	SplashName: string, -- The name of the attachment that releases particles on surface contact.
	SplashAmount: NumberRange, -- Sets the number of particles to emit upon impact.
	SplashByVelocity: boolean, -- If true, sets the number of particles based on the velocity of the droplet.
	VelocityDivider: number, -- Controls how much the velocity can affect the splash amount, Higher values reduce the effect.

	Expansion: boolean, -- Determines whether a pool can expand when a droplet lands on it.
	Distance: number, -- Sets the distance (in studs) within which the droplet should check for nearby pools
	ExpanseDivider: number, -- Controls how much a pool's size can increase. Higher values reduce the increase.
	MaximumSize: number, -- Sets the maximum size a pool can reach.

	Trail: boolean, -- Controls the visibility of the trail during droplet emission.
	DecayDelay: NumberRange, -- Sets the delay before the droplet decays and recycles

	Tweens: {
		Landed: TweenInfo,
		Decay: TweenInfo,
		Expand: TweenInfo,
		[string]: TweenInfo,
	},

	RaycastParams: RaycastParams,
}
export type Settings = ClassData

--// Class Setup
local Class = {}
Class.__index = Class
export type Class = typeof(setmetatable({} :: ClassData, Class))

--[[
  Class constructor, constructs the class
  including other properties/variables.
]]
function Class.new(Data: ClassData)
	local self = setmetatable({}, Class) :: Class

	self.FolderName = "Droplets"
	self.Type = "Default"
	self.Limit = 500
	self.Filter = {}

	self.SizeY = NumberRange.new(0.1, 0.175)
	self.DefaultSize = NumberRange.new(0.4, 0.7)
	self.DefaultTransparency = NumberRange.new(0.3, 0.4)
	self.StartingSize = Vector3.new(0.1, 0.3, 0.1)
	self.ScaleDown = true

	self.DropletDelay = NumberRange.new(0.01, 0.03)
	self.DropletVelocity = NumberRange.new(1, 2)
	self.DropletVisible = false
	self.DropletColor = Color3.fromRGB(103, 0, 0)

	self.RandomOffset = true
	self.OffsetRange = NumberRange.new(-5, 5)

	self.SplashName = "Impact"
	self.SplashAmount = NumberRange.new(5, 10)
	self.SplashByVelocity = true
	self.VelocityDivider = 8

	self.Expansion = true
	self.Distance = 0.2
	self.ExpanseDivider = 3
	self.MaximumSize = 0.7

	self.Trail = true
	self.DecayDelay = NumberRange.new(10, 15)

	-- Contains all the tweens used by the module
	self.Tweens = {
		Landed = TweenInfo.new(0.5, Enum.EasingStyle.Cubic), -- Used for when a droplet has landed on a surface.
		Decay = TweenInfo.new(1, Enum.EasingStyle.Cubic), -- Used for when a droplet is decaying.
		Expand = TweenInfo.new(0.5, Enum.EasingStyle.Cubic), -- Used for when a droplet is expanding (Pool Expansion).
	}

	-- Fill the default settings with values from the Data array
	for Setting, Value in Data do
		-- Add tweens
		if Setting == "Tweens" and typeof(Value) == "table" then
			for Tween, Info in Value :: { [string]: TweenInfo } do
				self.Tweens[Tween] = Info
			end

			continue
		end

		-- Set settings
		self[Setting] = Value
	end

	self:CreateParams()

	return self
end

--[[
  Updates settings with values from the provided array.
]]
function Class.UpdateSettings(self: Class, Data: ClassData)
	-- Update settings
	for Setting, Value in Data do
		self[Setting] = Value
	end

	-- Update Param properties
	self.RaycastParams.FilterDescendantsInstances = self.Filter
end

--[[
	Manages the instantiation of the RaycastParams
	aswell as the configuration of the filter.
]]
function Class.CreateParams(self: Class)
	-- Variable definitions
	local Params = RaycastParams.new()

	-- Update Params properties
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = self.Filter

	-- Assign Params as a self value
	self.RaycastParams = Params
end

return Class
