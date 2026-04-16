--!strict
-- Stateless spring stepping helpers.

local Angle = require(script.Parent.Angle)

local Spring = {}

export type SpringValue = number | Vector2 | Vector3

export type State<T> = {
	value: T,
	velocity: T,
}

local function zeroLike<T>(value: T): T
	local kind = typeof(value)
	if kind == "number" then
		return (0 :: any) :: T
	end
	if kind == "Vector2" then
		return (Vector2.zero :: any) :: T
	end
	return (Vector3.zero :: any) :: T
end

local function add<T>(a: T, b: T): T
	return (((a :: any) + (b :: any)) :: any) :: T
end

local function sub<T>(a: T, b: T): T
	return (((a :: any) - (b :: any)) :: any) :: T
end

local function mul<T>(value: T, scalar: number): T
	return (((value :: any) * scalar) :: any) :: T
end

local function magnitudeSq(value: SpringValue): number
	if typeof(value) == "number" then
		return value * value
	end
	return value:Dot(value)
end

function Spring.state<T>(value: T, velocity: T?): State<T>
	return {
		value = value,
		velocity = if velocity ~= nil then velocity else zeroLike(value),
	}
end

function Spring.step<T>(state: State<T>, target: T, frequency: number, damping: number, dt: number, mass: number?): State<T>
	local step = math.max(dt, 0)
	if step == 0 then
		return {
			value = state.value,
			velocity = state.velocity,
		}
	end

	local hz = math.max(frequency, 0)
	if hz == 0 then
		return {
			value = target,
			velocity = zeroLike(target),
		}
	end

	local omega = 2 * math.pi * hz
	local massScale = math.max(mass or 1, 1e-6)
	local scaledOmega = omega / math.sqrt(massScale)
	local zeta = math.max(damping, 0)
	local f = 1 + 2 * step * zeta * scaledOmega
	local omegaSquared = scaledOmega * scaledOmega
	local hoo = step * omegaSquared
	local hhoo = step * hoo
	local detInv = 1 / (f + hhoo)

	local current = state.value
	local velocity = state.velocity
	local delta = sub(target, current)
	local valueTerm = add(add(mul(current, f), mul(velocity, step)), mul(target, hhoo))
	local velocityTerm = add(velocity, mul(delta, hoo))

	return {
		value = mul(valueTerm, detInv),
		velocity = mul(velocityTerm, detInv),
	}
end

function Spring.StepAngleRadians(
	state: State<number>,
	target: number,
	frequency: number,
	damping: number,
	dt: number,
	mass: number?
): State<number>
	local wrappedTarget = state.value + Angle.deltaRadians(state.value, target)
	return Spring.step(state, wrappedTarget, frequency, damping, dt, mass)
end

function Spring.StepAngleDegrees(
	state: State<number>,
	target: number,
	frequency: number,
	damping: number,
	dt: number,
	mass: number?
): State<number>
	local wrappedTarget = state.value + Angle.deltaDegrees(state.value, target)
	return Spring.step(state, wrappedTarget, frequency, damping, dt, mass)
end

function Spring.isSettled<T>(state: State<T>, target: T, valueEpsilon: number?, velocityEpsilon: number?): boolean
	local valueTolerance = math.max(valueEpsilon or 1e-3, 0)
	local velocityTolerance = math.max(velocityEpsilon or 1e-3, 0)
	local valueDelta = sub(target, state.value) :: any
	local velocity = state.velocity :: any

	return magnitudeSq(valueDelta) <= valueTolerance * valueTolerance
		and magnitudeSq(velocity) <= velocityTolerance * velocityTolerance
end

Spring.stepAngleRadians = Spring.StepAngleRadians
Spring.stepAngleDegrees = Spring.StepAngleDegrees

return Spring
