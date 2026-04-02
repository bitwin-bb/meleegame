--!strict
-- Trigonometric helpers and safe conversions.

local Num = require(script.Parent.Num)

local Trig = {}

Trig.TAU = math.pi * 2
Trig.DEG_TO_RAD = math.pi / 180
Trig.RAD_TO_DEG = 180 / math.pi

function Trig.degToRad(degrees: number): number
	return degrees * Trig.DEG_TO_RAD
end

function Trig.radToDeg(radians: number): number
	return radians * Trig.RAD_TO_DEG
end

function Trig.sinCos(angleRadians: number): (number, number)
	return math.sin(angleRadians), math.cos(angleRadians)
end

function Trig.safeAsin(value: number): number
	return math.asin(Num.clamp(value, -1, 1))
end

function Trig.safeAcos(value: number): number
	return math.acos(Num.clamp(value, -1, 1))
end

function Trig.safeAtan2(y: number, x: number): number
	if x == 0 and y == 0 then
		return 0
	end
	return math.atan2(y, x)
end

return Trig
