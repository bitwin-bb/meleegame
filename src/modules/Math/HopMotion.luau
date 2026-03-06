--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ripple = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

local HopMotion = {}
HopMotion.__index = HopMotion

export type HopConfig = {
	duration: number?,
	arcHeight: number?,
	minArcHeight: number?,
	maxArcHeight: number?,
	spring: SpringOptions?,
}

export type HopStep = {
	position: Vector3,
	velocity: Vector3,
	alpha: number,
	completed: boolean,
}

export type HopMotion = typeof(setmetatable(
	{} :: {
		duration: number,
		arcHeight: number,
		minArcHeight: number,
		maxArcHeight: number,
		spring: SpringOptions,
		progressMotion: NumberMotion,
		origin: Vector3,
		destination: Vector3,
		elapsed: number,
		lastAlpha: number,
		lastPosition: Vector3,
		active: boolean,
		completed: boolean,
	},
	HopMotion
))

local DEFAULT_DURATION = 0.45
local DEFAULT_MIN_ARC_HEIGHT = 0.9
local DEFAULT_MAX_ARC_HEIGHT = 8
local DEFAULT_ARC_DISTANCE_MULTIPLIER = 0.3

local DEFAULT_SPRING: SpringOptions = {
	frequency = 9,
	damping = 1,
}

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end

	return value
end

local function cloneSpringOptions(source: SpringOptions?): SpringOptions
	local spring: SpringOptions = {
		frequency = DEFAULT_SPRING.frequency,
		damping = DEFAULT_SPRING.damping,
	}

	if source == nil then
		return spring
	end

	for key, value in source do
		spring[key] = value
	end

	if source.frequency ~= nil then
		spring.frequency = sanitizeNumber(source.frequency, spring.frequency or 9, 0.01, 120)
	end
	if source.damping ~= nil then
		spring.damping = sanitizeNumber(source.damping, spring.damping or 1, 0, 20)
	end

	return spring
end

function HopMotion.computeArcHeight(horizontalDistanceRaw: any, minArcHeightRaw: any, maxArcHeightRaw: any): number
	local horizontalDistance = sanitizeNumber(horizontalDistanceRaw, 0, 0, nil)
	local minArcHeight = sanitizeNumber(minArcHeightRaw, DEFAULT_MIN_ARC_HEIGHT, 0, nil)
	local maxArcHeight = sanitizeNumber(maxArcHeightRaw, DEFAULT_MAX_ARC_HEIGHT, minArcHeight, nil)

	local scaledHeight = horizontalDistance * DEFAULT_ARC_DISTANCE_MULTIPLIER
	return math.clamp(scaledHeight, minArcHeight, maxArcHeight)
end

function HopMotion.new(configRaw: HopConfig?): HopMotion
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local minArcHeight = sanitizeNumber(config.minArcHeight, DEFAULT_MIN_ARC_HEIGHT, 0, nil)
	local maxArcHeight = sanitizeNumber(config.maxArcHeight, DEFAULT_MAX_ARC_HEIGHT, minArcHeight, nil)
	local duration = sanitizeNumber(config.duration, DEFAULT_DURATION, 0.03, 8)
	local arcHeight = if config.arcHeight ~= nil
		then sanitizeNumber(config.arcHeight, minArcHeight, 0, nil)
		else minArcHeight

	local origin = Vector3.zero
	local progressMotion = Ripple.createMotion(0)

	local self = setmetatable({
		duration = duration,
		arcHeight = arcHeight,
		minArcHeight = minArcHeight,
		maxArcHeight = maxArcHeight,
		spring = cloneSpringOptions(config.spring),
		progressMotion = progressMotion,
		origin = origin,
		destination = origin,
		elapsed = 0,
		lastAlpha = 0,
		lastPosition = origin,
		active = false,
		completed = true,
	}, HopMotion)

	return self
end

function HopMotion.sample(self: HopMotion, alphaRaw: any): Vector3
	local alpha = sanitizeNumber(alphaRaw, 0, 0, 1)
	local linearPosition = self.origin:Lerp(self.destination, alpha)
	local arcOffsetY = 4 * self.arcHeight * alpha * (1 - alpha)
	return linearPosition + Vector3.new(0, arcOffsetY, 0)
end

function HopMotion.start(
	self: HopMotion,
	originRaw: any,
	destinationRaw: any,
	durationRaw: any,
	arcHeightRaw: any
)
	if typeof(originRaw) ~= "Vector3" or typeof(destinationRaw) ~= "Vector3" then
		return
	end

	self.origin = originRaw
	self.destination = destinationRaw
	self.duration = sanitizeNumber(durationRaw, self.duration, 0.03, 8)

	local horizontalDelta = Vector3.new(destinationRaw.X - originRaw.X, 0, destinationRaw.Z - originRaw.Z)
	local computedArcHeight = HopMotion.computeArcHeight(horizontalDelta.Magnitude, self.minArcHeight, self.maxArcHeight)
	self.arcHeight = if arcHeightRaw ~= nil
		then sanitizeNumber(arcHeightRaw, computedArcHeight, 0, nil)
		else computedArcHeight

	self.elapsed = 0
	self.lastAlpha = 0
	self.lastPosition = originRaw
	self.active = true
	self.completed = false
	self.progressMotion:immediate(0)
end

function HopMotion.stop(self: HopMotion, snapToDestinationRaw: any)
	if not self.active and self.completed then
		return
	end

	local snapToDestination = snapToDestinationRaw == true
	self.active = false
	self.completed = true
	if snapToDestination then
		self.lastAlpha = 1
		self.lastPosition = self.destination
		self.progressMotion:immediate(1)
	else
		self.progressMotion:immediate(self.lastAlpha)
	end
end

function HopMotion.isActive(self: HopMotion): boolean
	return self.active
end

function HopMotion.step(self: HopMotion, dtRaw: any): HopStep
	local dt = sanitizeNumber(dtRaw, 0, 0, 1)
	if not self.active then
		return {
			position = self.lastPosition,
			velocity = Vector3.zero,
			alpha = self.lastAlpha,
			completed = self.completed,
		}
	end

	self.elapsed = math.min(self.duration, self.elapsed + dt)
	local rawAlpha = if self.duration > 0 then self.elapsed / self.duration else 1

	self.progressMotion:spring(rawAlpha, self.spring)
	local springAlpha = self.progressMotion:step(dt)
	local smoothedAlpha = rawAlpha + (springAlpha - rawAlpha) * 0.2
	smoothedAlpha = math.clamp(smoothedAlpha, self.lastAlpha, 1)

	local sampledPosition = self:sample(smoothedAlpha)
	local velocity = Vector3.zero
	if dt > 0 then
		velocity = (sampledPosition - self.lastPosition) / dt
	end

	self.lastAlpha = smoothedAlpha
	self.lastPosition = sampledPosition

	local completed = rawAlpha >= 1
	if completed then
		self.lastAlpha = 1
		self.lastPosition = self.destination
		self.active = false
		self.completed = true
		self.progressMotion:immediate(1)
		return {
			position = self.destination,
			velocity = velocity,
			alpha = 1,
			completed = true,
		}
	end

	return {
		position = sampledPosition,
		velocity = velocity,
		alpha = smoothedAlpha,
		completed = false,
	}
end

function HopMotion.destroy(self: HopMotion)
	self.progressMotion:destroy()
	self.active = false
	self.completed = true
end

return HopMotion
