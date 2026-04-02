--!strict
-- Bezier, Hermite, and Catmull-Rom curve sampling helpers.

local Curve = {}

local function add<T>(a: T, b: T): T
	return (((a :: any) + (b :: any)) :: any) :: T
end

local function mul<T>(value: T, scalar: number): T
	return (((value :: any) * scalar) :: any) :: T
end

function Curve.quadratic<T>(p0: T, p1: T, p2: T, t: number): T
	local u = 1 - t
	return add(
		add(mul(p0, u * u), mul(p1, 2 * u * t)),
		mul(p2, t * t)
	)
end

function Curve.quadraticTangent<T>(p0: T, p1: T, p2: T, t: number): T
	return add(
		mul((((p1 :: any) - (p0 :: any)) :: any) :: T, 2 * (1 - t)),
		mul((((p2 :: any) - (p1 :: any)) :: any) :: T, 2 * t)
	)
end

function Curve.cubic<T>(p0: T, p1: T, p2: T, p3: T, t: number): T
	local u = 1 - t
	local uu = u * u
	local tt = t * t
	return add(
		add(mul(p0, uu * u), mul(p1, 3 * uu * t)),
		add(mul(p2, 3 * u * tt), mul(p3, tt * t))
	)
end

function Curve.hermite<T>(p0: T, m0: T, p1: T, m1: T, t: number): T
	local tt = t * t
	local ttt = tt * t
	local h00 = 2 * ttt - 3 * tt + 1
	local h10 = ttt - 2 * tt + t
	local h01 = -2 * ttt + 3 * tt
	local h11 = ttt - tt

	return add(
		add(mul(p0, h00), mul(m0, h10)),
		add(mul(p1, h01), mul(m1, h11))
	)
end

function Curve.catmullRom<T>(p0: T, p1: T, p2: T, p3: T, t: number, tension: number?): T
	local tightness = tension or 0
	local m1 = mul((((p2 :: any) - (p0 :: any)) :: any) :: T, 0.5 * (1 - tightness))
	local m2 = mul((((p3 :: any) - (p1 :: any)) :: any) :: T, 0.5 * (1 - tightness))
	return Curve.hermite(p1, m1, p2, m2, t)
end

return Curve
