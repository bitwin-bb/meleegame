--!strict
-- Exponential damping helpers.

local Angle = require(script.Parent.Angle)

local Damp = {}

function Damp.Factor(lambda: number, dt: number): number
	local rate = math.max(lambda, 0)
	local step = math.max(dt, 0)
	if rate == 0 or step == 0 then
		return 0
	end
	return 1 - math.exp(-rate * step)
end

function Damp.HalfLifeFactor(halfLife: number, dt: number): number
	local life = math.max(halfLife, 0)
	local step = math.max(dt, 0)
	if step == 0 then
		return 0
	end
	if life == 0 then
		return 1
	end
	return 1 - 2 ^ (-step / life)
end

function Damp.value<T>(current: T, target: T, lambda: number, dt: number): T
	local blend = Damp.Factor(lambda, dt)
	return ((((current :: any) + (((target :: any) - (current :: any)) :: any) * blend) :: any) :: T)
end

function Damp.halfLifeValue<T>(current: T, target: T, halfLife: number, dt: number): T
	local blend = Damp.HalfLifeFactor(halfLife, dt)
	return ((((current :: any) + (((target :: any) - (current :: any)) :: any) * blend) :: any) :: T)
end

function Damp.AngleRadians(current: number, target: number, lambda: number, dt: number): number
	return current + Angle.deltaRadians(current, target) * Damp.Factor(lambda, dt)
end

function Damp.AngleDegrees(current: number, target: number, lambda: number, dt: number): number
	return current + Angle.deltaDegrees(current, target) * Damp.Factor(lambda, dt)
end

Damp.factor = Damp.Factor
Damp.halfLifeFactor = Damp.HalfLifeFactor
Damp.angleRadians = Damp.AngleRadians
Damp.angleDegrees = Damp.AngleDegrees

return Damp
