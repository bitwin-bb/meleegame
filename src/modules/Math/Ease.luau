--!strict
-- Common easing curves for interpolation timing.

local Num = require(script.Parent.Num)

local Ease = {}

local HALF_PI = math.pi * 0.5

local function resolveAlpha(alpha: number): number
	return Num.saturate(alpha)
end

function Ease.linear(alpha: number): number
	return resolveAlpha(alpha)
end

function Ease.inSine(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - math.cos(x * HALF_PI)
end

function Ease.outSine(alpha: number): number
	local x = resolveAlpha(alpha)
	return math.sin(x * HALF_PI)
end

function Ease.inOutSine(alpha: number): number
	local x = resolveAlpha(alpha)
	return -(math.cos(math.pi * x) - 1) * 0.5
end

function Ease.inQuad(alpha: number): number
	local x = resolveAlpha(alpha)
	return x * x
end

function Ease.outQuad(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) * (1 - x)
end

function Ease.inOutQuad(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 2 * x * x
	end
	return 1 - ((-2 * x + 2) ^ 2) * 0.5
end

function Ease.inCubic(alpha: number): number
	local x = resolveAlpha(alpha)
	return x * x * x
end

function Ease.outCubic(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) ^ 3
end

function Ease.inOutCubic(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 4 * x * x * x
	end
	return 1 - ((-2 * x + 2) ^ 3) * 0.5
end

function Ease.inQuart(alpha: number): number
	local x = resolveAlpha(alpha)
	return x ^ 4
end

function Ease.outQuart(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) ^ 4
end

function Ease.inOutQuart(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 8 * x ^ 4
	end
	return 1 - ((-2 * x + 2) ^ 4) * 0.5
end

function Ease.inQuint(alpha: number): number
	local x = resolveAlpha(alpha)
	return x ^ 5
end

function Ease.outQuint(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) ^ 5
end

function Ease.inOutQuint(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 16 * x ^ 5
	end
	return 1 - ((-2 * x + 2) ^ 5) * 0.5
end

function Ease.inExpo(alpha: number): number
	local x = resolveAlpha(alpha)
	if x == 0 then
		return 0
	end
	return 2 ^ (10 * x - 10)
end

function Ease.outExpo(alpha: number): number
	local x = resolveAlpha(alpha)
	if x == 1 then
		return 1
	end
	return 1 - 2 ^ (-10 * x)
end

function Ease.inOutExpo(alpha: number): number
	local x = resolveAlpha(alpha)
	if x == 0 or x == 1 then
		return x
	end
	if x < 0.5 then
		return 2 ^ (20 * x - 10) * 0.5
	end
	return (2 - 2 ^ (-20 * x + 10)) * 0.5
end

function Ease.inCirc(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - math.sqrt(1 - x * x)
end

function Ease.outCirc(alpha: number): number
	local x = resolveAlpha(alpha)
	return math.sqrt(1 - (x - 1) * (x - 1))
end

function Ease.inOutCirc(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return (1 - math.sqrt(1 - (2 * x) ^ 2)) * 0.5
	end
	return (math.sqrt(1 - (-2 * x + 2) ^ 2) + 1) * 0.5
end

function Ease.inBack(alpha: number, overshoot: number?): number
	local x = resolveAlpha(alpha)
	local s = overshoot or 1.70158
	local c = s + 1
	return c * x * x * x - s * x * x
end

function Ease.outBack(alpha: number, overshoot: number?): number
	local x = resolveAlpha(alpha)
	local s = overshoot or 1.70158
	local c = s + 1
	local y = x - 1
	return 1 + c * y * y * y + s * y * y
end

function Ease.inOutBack(alpha: number, overshoot: number?): number
	local x = resolveAlpha(alpha)
	local s = (overshoot or 1.70158) * 1.525
	if x < 0.5 then
		local y = 2 * x
		return (y * y * ((s + 1) * y - s)) * 0.5
	end
	local y = 2 * x - 2
	return (y * y * ((s + 1) * y + s) + 2) * 0.5
end

return Ease
