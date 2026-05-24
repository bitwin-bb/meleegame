--[[
	@ Writer: @Smileeiles
	@ Version: v1.1.3
	@ Description:
		A droplet emitter system,
		used to emit droplets from a specified origin point.

		These droplets are then given a velocity,
		and upon landing on a surface, transform into pools.

		This process can be customized to suit various needs and genres.
]]

--// Modules
local Operator = require(script.Operator)
local Settings = require(script.Settings)
local Functions = require(script.Functions)

--// Types
type ClassData = {
	ActiveHandler: Settings.Class,
	ActiveEngine: Operator.Class,
}
export type Settings = Settings.Settings

--// Class Setup
local Class = {}
Class.__index = Class
export type Class = typeof(setmetatable({} :: ClassData, Class))

--[[
	Class constructor, constructs the class
	including other properties/variables.
]]
function Class.new(Data: Settings?)
	local self = setmetatable({}, Class) :: Class

	self.ActiveHandler = Settings.new(Data or {} :: Settings)
	self.ActiveEngine = Operator.new(self.ActiveHandler)

	return self
end

--[[
	Emitter, emits droplets based on given amount,
	origin & direction.

	This is utilized when you prefer
	not to create a loop just for the
	purpose of emitting a few droplets.
]]
function Class.EmitAmount(self: Class, Origin: Vector3 | BasePart, Direction: Vector3?, Amount: number, Data: Settings?)
	for _ = 1, Amount, 1 do
		-- Define variables for later use
		local DelayTime = Functions.NextNumber(self.ActiveHandler.DropletDelay)

		-- Emit a droplet in the specified direction & origin
		self:Emit(Origin, Direction, Data)

		-- Delays the next droplet to be emitted
		task.wait(DelayTime)
	end
end

--[[
	EmitOnce, a variant of the Emit method; emits a single droplet.
	Unlike Emit, which uses a loop to emit multiple droplets,
	EmitOnce only emits one droplet per call.

	This is useful when you want to control the emission
	loop externally.
]]
function Class.Emit(self: Class, Origin: Vector3 | BasePart?, Direction: Vector3?, Data: Settings?)
	-- Get pos
	local Pos: Vector3
	if not Origin then
		-- Must exist
		return
	elseif typeof(Origin) == "Vector3" then
		Pos = Origin
	elseif Origin:IsA("BasePart") then
		if Origin.Parent then
			Pos = Origin.Position
		else
			return
		end
	end

	-- Emit a single droplet
	self.ActiveEngine:Emit(Pos, Direction or Functions.GetVector(NumberRange.new(-10, 10)) / 10, Data)
end

--[[
	GetSettings, returns all the settings of the
	current class instance.

	Use this function when you want to access
	the settings for external handling of the system.
]]
function Class.GetSettings(self: Class): Settings.Class
	return self.ActiveHandler
end

--[[
	UpdateSettings, updates the settings of the
	current class instance.

	It uses the `Handler:UpdateSettings()`, which
	uses the given `Data` array/table to update individual settings.
]]
function Class.UpdateSettings(self: Class, Data: Settings)
	self.ActiveHandler:UpdateSettings(Data)
end

--[[
	Destroy, destroys anything associated 
	with the settings/handler and the operator/engine.
	
	Use this function when there is no longer a use
	for the created engine. (Like when a character dies, etc.)
]]
function Class.Destroy(self: Class)
	self.ActiveEngine:Destroy()
end

return Class.new

