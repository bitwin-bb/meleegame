--!strict

--// Modules
local Signal = require(script.Parent.Signal)

--// Types
type ClassData = {
	LengthChanged: Signal.SignalStatic,
	RayHit: Signal.SignalStatic,
	RayPierced: Signal.SignalStatic,
	CastTerminating: Signal.SignalStatic,
}

--// Class Setup
local Class = {}
Class.__index = Class
Class.__type = "CasterEvents" -- For compatibility with TypeMarshaller
export type Class = typeof(setmetatable({} :: ClassData, Class))

function Class.new()
	local self = setmetatable({}, Class) :: Class

	self.LengthChanged = Signal("LengthChanged")
	self.RayHit = Signal("RayHit")
	self.RayPierced = Signal("RayPierced")
	self.CastTerminating = Signal("CastTerminating")

	return self
end

return Class.new
