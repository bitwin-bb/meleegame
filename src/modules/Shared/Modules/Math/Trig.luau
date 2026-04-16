--!strict
-- Trigonometric helpers and safe conversions.

local Num = require(script.Parent.Num)

local Trig = {}

Trig.TAU = math.pi * 2
Trig.DEG_TO_RAD = math.pi / 180
Trig.RAD_TO_DEG = 180 / math.pi

function Trig.DegToRad(degrees: number): number
	return degrees * Trig.DEG_TO_RAD
end

function Trig.RadToDeg(radians: number): number
	return radians * Trig.RAD_TO_DEG
end

function Trig.SinCos(angleRadians: number): (number, number)
	return math.sin(angleRadians), math.cos(angleRadians)
end

function Trig.SafeAsin(value: number): number
	return math.asin(Num.clamp(value, -1, 1))
end

function Trig.SafeAcos(value: number): number
	return math.acos(Num.clamp(value, -1, 1))
end

function Trig.SafeAtan2(y: number, x: number): number
	if x == 0 and y == 0 then
		return 0
	end
	return math.atan2(y, x)
end

Trig.degToRad = Trig.DegToRad
Trig.radToDeg = Trig.RadToDeg
Trig.sinCos = Trig.SinCos
Trig.safeAsin = Trig.SafeAsin
Trig.safeAcos = Trig.SafeAcos
Trig.safeAtan2 = Trig.SafeAtan2

return Trig
