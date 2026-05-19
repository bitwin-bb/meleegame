--!strict
-- Common easing curves for interpolation timing.

local Num = require(script.Parent.Num)

local Ease = {}

local HALF_PI = math.pi * 0.5

local function resolveAlpha(alpha: number): number
	return Num.saturate(alpha)
end

function Ease.Linear(alpha: number): number
	return resolveAlpha(alpha)
end

function Ease.InSine(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - math.cos(x * HALF_PI)
end

function Ease.OutSine(alpha: number): number
	local x = resolveAlpha(alpha)
	return math.sin(x * HALF_PI)
end

function Ease.InOutSine(alpha: number): number
	local x = resolveAlpha(alpha)
	return -(math.cos(math.pi * x) - 1) * 0.5
end

function Ease.InQuad(alpha: number): number
	local x = resolveAlpha(alpha)
	return x * x
end

function Ease.OutQuad(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) * (1 - x)
end

function Ease.InOutQuad(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 2 * x * x
	end
	return 1 - ((-2 * x + 2) ^ 2) * 0.5
end

function Ease.InCubic(alpha: number): number
	local x = resolveAlpha(alpha)
	return x * x * x
end

function Ease.OutCubic(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) ^ 3
end

function Ease.InOutCubic(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 4 * x * x * x
	end
	return 1 - ((-2 * x + 2) ^ 3) * 0.5
end

function Ease.InQuart(alpha: number): number
	local x = resolveAlpha(alpha)
	return x ^ 4
end

function Ease.OutQuart(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) ^ 4
end

function Ease.InOutQuart(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 8 * x ^ 4
	end
	return 1 - ((-2 * x + 2) ^ 4) * 0.5
end

function Ease.InQuint(alpha: number): number
	local x = resolveAlpha(alpha)
	return x ^ 5
end

function Ease.OutQuint(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - (1 - x) ^ 5
end

function Ease.InOutQuint(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return 16 * x ^ 5
	end
	return 1 - ((-2 * x + 2) ^ 5) * 0.5
end

function Ease.InExpo(alpha: number): number
	local x = resolveAlpha(alpha)
	if x == 0 then
		return 0
	end
	return 2 ^ (10 * x - 10)
end

function Ease.OutExpo(alpha: number): number
	local x = resolveAlpha(alpha)
	if x == 1 then
		return 1
	end
	return 1 - 2 ^ (-10 * x)
end

function Ease.InOutExpo(alpha: number): number
	local x = resolveAlpha(alpha)
	if x == 0 or x == 1 then
		return x
	end
	if x < 0.5 then
		return 2 ^ (20 * x - 10) * 0.5
	end
	return (2 - 2 ^ (-20 * x + 10)) * 0.5
end

function Ease.InCirc(alpha: number): number
	local x = resolveAlpha(alpha)
	return 1 - math.sqrt(1 - x * x)
end

function Ease.OutCirc(alpha: number): number
	local x = resolveAlpha(alpha)
	return math.sqrt(1 - (x - 1) * (x - 1))
end

function Ease.InOutCirc(alpha: number): number
	local x = resolveAlpha(alpha)
	if x < 0.5 then
		return (1 - math.sqrt(1 - (2 * x) ^ 2)) * 0.5
	end
	return (math.sqrt(1 - (-2 * x + 2) ^ 2) + 1) * 0.5
end

function Ease.InBack(alpha: number, overshoot: number?): number
	local x = resolveAlpha(alpha)
	local s = overshoot or 1.70158
	local c = s + 1
	return c * x * x * x - s * x * x
end

function Ease.OutBack(alpha: number, overshoot: number?): number
	local x = resolveAlpha(alpha)
	local s = overshoot or 1.70158
	local c = s + 1
	local y = x - 1
	return 1 + c * y * y * y + s * y * y
end

function Ease.InOutBack(alpha: number, overshoot: number?): number
	local x = resolveAlpha(alpha)
	local s = (overshoot or 1.70158) * 1.525
	if x < 0.5 then
		local y = 2 * x
		return (y * y * ((s + 1) * y - s)) * 0.5
	end
	local y = 2 * x - 2
	return (y * y * ((s + 1) * y + s) + 2) * 0.5
end

Ease.linear = Ease.Linear
Ease.inSine = Ease.InSine
Ease.outSine = Ease.OutSine
Ease.inOutSine = Ease.InOutSine
Ease.inQuad = Ease.InQuad
Ease.outQuad = Ease.OutQuad
Ease.inOutQuad = Ease.InOutQuad
Ease.inCubic = Ease.InCubic
Ease.outCubic = Ease.OutCubic
Ease.inOutCubic = Ease.InOutCubic
Ease.inQuart = Ease.InQuart
Ease.outQuart = Ease.OutQuart
Ease.inOutQuart = Ease.InOutQuart
Ease.inQuint = Ease.InQuint
Ease.outQuint = Ease.OutQuint
Ease.inOutQuint = Ease.InOutQuint
Ease.inExpo = Ease.InExpo
Ease.outExpo = Ease.OutExpo
Ease.inOutExpo = Ease.InOutExpo
Ease.inCirc = Ease.InCirc
Ease.outCirc = Ease.OutCirc
Ease.inOutCirc = Ease.InOutCirc
Ease.inBack = Ease.InBack
Ease.outBack = Ease.OutBack
Ease.inOutBack = Ease.InOutBack

return Ease
