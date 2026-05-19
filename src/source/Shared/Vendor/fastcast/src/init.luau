--!strict

--[[
	Written by Eti the Spirit (18406183)
	
		The latest patch notes can be located here (and do note, the version at the top of this script might be outdated. I have a thing for forgetting to change it):
		>	https://etithespirit.github.io/ClassAPIDocs/changelog
		
		*** If anything is broken, please don't hesitate to message me! ***
		
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://etithespirit.github.io/ClassAPIDocs
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://etithespirit.github.io/ClassAPIDocs
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://etithespirit.github.io/ClassAPIDocs
		
		YOU SHOULD ONLY CREATE ONE CASTER PER GUN.
		YOU SHOULD >>>NEVER<<< CREATE A NEW CASTER EVERY TIME THE GUN NEEDS TO BE FIRED.
		
		A caster (created with Class.new()) represents a "gun".
		When you consider a gun, you think of stats like accuracy, bullet speed, etc. This is the info a caster stores. 
	
	--
	
	This is a library used to create hitscan-based guns that simulate projectile physics.
	
	This means:
		- You don't have to worry about bullet lag / jittering
		- You don't have to worry about keeping bullets at a low speed due to physics being finnicky between clients
		- You don't have to worry about misfires in bullet's Touched event (e.g. where it may going so fast that it doesn't register)
		
	Hitscan-based guns are commonly seen in the form of laser beams, among other things. Hitscan simply raycasts out to a target
	and says whether it hit or not.
	
	Unfortunately, while reliable in terms of saying if something got hit or not, this method alone cannot be used if you wish
	to implement bullet travel time into a weapon. As a result of that, I made this library - an excellent remedy to this dilemma.
	
	Class is intended to be require()'d once in a script, as you can create as many casters as you need with Class.new()
	This is generally handy since you can store settings and information in these casters, and even send them out to other scripts via events
	for use.
	
	Remember -- A "Caster" represents an entire gun (or whatever is launching your projectiles), *NOT* the individual bullets.
	Make the caster once, then use the caster to fire your bullets. Do not make a caster for each bullet.
--]]

--// Modules
local ActiveCastStatic = require(script.ActiveCast)
local TypeDefs = require(script.TypeDefinitions)
local Config = require(script.Config)
local Events = require(script.Events)
local Signal = require(script.Signal)

--// Types
export type FastCastBehavior = TypeDefs.FastCastBehavior
export type ActiveCast = TypeDefs.ActiveCast
export type ConnectionStatic = Signal.ConnectionStatic
export type SignalStatic = Signal.SignalStatic

type ClassData = {
	WorldRoot: WorldRoot,
	Events: Events.Class,
}

--// Class Setup
local Class = {}
Class.__index = Class
Class.__type = "FastCast" -- For compatibility with TypeMarshaller
export type Class = typeof(setmetatable({} :: ClassData, Class))
-- Represents a Caster with some modifications :: https://etithespirit.github.io/FastCastAPIDocs/fastcast-objects/caster/

function Class.new()
	local self = setmetatable({}, Class) :: Class

	self.WorldRoot = workspace
	self.Events = Events()

	return self
end

function Class.newBehavior(): FastCastBehavior
	return {
		Parallel = false,
		RaycastParams = nil,
		Acceleration = Vector3.new(),
		MaxDistance = 1000,
		CanPierceFunction = nil,
		HighFidelityBehavior = Config.HighFidelityBehavior.Default,
		HighFidelitySegmentSize = 0.5,
		CosmeticBulletTemplate = nil,
		CosmeticBulletProvider = nil,
		CosmeticBulletContainer = nil,
		AutoIgnoreContainer = true,
	}
end

local DEFAULT_DATA_PACKET = Class.newBehavior()
function Class.Fire(
	self: Class,
	origin: Vector3,
	direction: Vector3,
	velocity: Vector3 | number,
	castDataPacket: FastCastBehavior?
): ActiveCastStatic.Class
	local cast = ActiveCastStatic(self.Events, origin, direction, velocity, castDataPacket or DEFAULT_DATA_PACKET)
	cast.RayInfo.WorldRoot = self.WorldRoot
	return cast
end

return Class
