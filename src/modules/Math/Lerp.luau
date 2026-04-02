--!strict
-- Linear interpolation helpers.

local Angle = require(script.Parent.Angle)
local Num = require(script.Parent.Num)

local Lerp = {}

function Lerp.value<T>(a: T, b: T, alpha: number): T
	return ((((a :: any) + (((b :: any) - (a :: any)) :: any) * alpha) :: any) :: T)
end

function Lerp.clamped<T>(a: T, b: T, alpha: number): T
	return Lerp.value(a, b, Num.saturate(alpha))
end

function Lerp.angleRadians(a: number, b: number, alpha: number): number
	return a + Angle.deltaRadians(a, b) * alpha
end

function Lerp.angleDegrees(a: number, b: number, alpha: number): number
	return a + Angle.deltaDegrees(a, b) * alpha
end

function Lerp.color3(a: Color3, b: Color3, alpha: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * alpha,
		a.G + (b.G - a.G) * alpha,
		a.B + (b.B - a.B) * alpha
	)
end

function Lerp.bilinear<T>(c00: T, c10: T, c01: T, c11: T, tx: number, ty: number): T
	local top = Lerp.value(c00, c10, tx)
	local bottom = Lerp.value(c01, c11, tx)
	return Lerp.value(top, bottom, ty)
end

function Lerp.trilinear<T>(
	c000: T,
	c100: T,
	c010: T,
	c110: T,
	c001: T,
	c101: T,
	c011: T,
	c111: T,
	tx: number,
	ty: number,
	tz: number
): T
	local front = Lerp.bilinear(c000, c100, c010, c110, tx, ty)
	local back = Lerp.bilinear(c001, c101, c011, c111, tx, ty)
	return Lerp.value(front, back, tz)
end

return Lerp
