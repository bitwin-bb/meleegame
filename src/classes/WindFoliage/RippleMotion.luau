--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ripple = require(ReplicatedStorage.Packages.Ripple)

local RippleMotion = {}

local function clampNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

function RippleMotion.createMotion(initialValue: any): any
	local motion = Ripple.createMotion(initialValue)
	motion:immediate(initialValue)
	return motion
end

function RippleMotion.createVectorMotion(initialValue: Vector3): any
	return RippleMotion.createMotion(initialValue)
end

function RippleMotion.resolveSpring(stiffnessRaw: any, dampingRaw: any, fallbackStiffness: number, fallbackDamping: number): { [string]: number }
	local stiffness = clampNumber(stiffnessRaw, fallbackStiffness, 0.01, 200)
	local damping = clampNumber(dampingRaw, fallbackDamping, 0, 100)
	local omega = math.sqrt(stiffness)
	local frequency = math.max(omega / (2 * math.pi), 0.01)
	local dampingRatio = if omega <= 1e-4 then 1 else math.max(damping / (2 * omega), 0)

	return {
		frequency = frequency,
		damping = dampingRatio,
	}
end

return RippleMotion
