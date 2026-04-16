local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

export type BeatMotionOptions = {
	enabled: boolean?,
	auto: boolean?,
	bpm: number?,
	baseScale: number?,
	primaryScale: number?,
	secondaryScale: number?,
	secondaryDelay: number?,
	recoverDelay: number?,
	spring: SpringOptions?,
}

export type BeatMotionResult = {
	scale: React.Binding<number>,
	beat: () -> (),
}

local DEFAULT_SPRING: SpringOptions = {
	frequency = 1,
	damping = 0.85,
}

local DEFAULT_BPM = 72
local DEFAULT_BASE_SCALE = 1
local DEFAULT_PRIMARY_SCALE = 1.08
local DEFAULT_SECONDARY_SCALE = 1.04
local DEFAULT_SECONDARY_DELAY = 0.11
local DEFAULT_RECOVER_DELAY = 0.24

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end

	local nextValue = value
	if minimum ~= nil and nextValue < minimum then
		nextValue = minimum
	end
	if maximum ~= nil and nextValue > maximum then
		nextValue = maximum
	end
	return nextValue
end

local function useBeatMotion(options: BeatMotionOptions?): BeatMotionResult
	local enabled = if options and options.enabled ~= nil then options.enabled else true
	local auto = if options and options.auto ~= nil then options.auto else true
	local bpm = sanitizeNumber(if options then options.bpm else nil, DEFAULT_BPM, 1, 400)
	local baseScale = sanitizeNumber(if options then options.baseScale else nil, DEFAULT_BASE_SCALE, 0.01, 10)
	local primaryScale = sanitizeNumber(if options then options.primaryScale else nil, DEFAULT_PRIMARY_SCALE, 0.01, 10)
	local secondaryScale = sanitizeNumber(
		if options then options.secondaryScale else nil,
		DEFAULT_SECONDARY_SCALE,
		0.01,
		10
	)
	local secondaryDelay = sanitizeNumber(if options then options.secondaryDelay else nil, DEFAULT_SECONDARY_DELAY, 0, 5)
	local recoverDelay = sanitizeNumber(if options then options.recoverDelay else nil, DEFAULT_RECOVER_DELAY, 0, 5)
	local spring = if options and options.spring then options.spring else DEFAULT_SPRING

	local scale, setScale = React.useBinding(baseScale)
	local motionRef = React.useRef(nil :: NumberMotion?)
	local aliveRef = React.useRef(true)
	local elapsedRef = React.useRef(0)
	local manualBeatUntilRef = React.useRef(0)

	React.useEffect(function()
		aliveRef.current = true
		local motion = Ripple.createMotion(baseScale)
		motionRef.current = motion
		elapsedRef.current = 0
		manualBeatUntilRef.current = 0
		setScale(baseScale)

		local steppedConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local nextTarget = baseScale

			if enabled and auto then
				elapsedRef.current += deltaTime
				local period = 60 / bpm
				local phase = (elapsedRef.current % period) / period

				local pulseA = primaryScale - baseScale
				local pulseB = secondaryScale - baseScale
				local widthA = 0.055
				local widthB = 0.06
				local centerA = 0.12
				local centerB = 0.28

				local influenceA = math.exp(-(((phase - centerA) * (phase - centerA)) / (2 * widthA * widthA)))
				local influenceB = math.exp(-(((phase - centerB) * (phase - centerB)) / (2 * widthB * widthB)))
				nextTarget = baseScale + pulseA * influenceA + pulseB * influenceB
			elseif enabled and manualBeatUntilRef.current > 0 then
				manualBeatUntilRef.current = math.max(0, manualBeatUntilRef.current - deltaTime)
				local alpha = if recoverDelay > 0 then manualBeatUntilRef.current / recoverDelay else 0
				nextTarget = baseScale + (primaryScale - baseScale) * alpha
			end

			motion:spring(nextTarget, spring)
			setScale(motion:step(deltaTime))
		end)

		return function()
			aliveRef.current = false
			steppedConnection:Disconnect()
			motion:destroy()
			motionRef.current = nil
		end
	end, { enabled, auto, bpm, baseScale, primaryScale, secondaryScale, spring })

	React.useEffect(function()
		local motion = motionRef.current
		if not motion then
			return
		end

		motion:immediate(baseScale)
		setScale(baseScale)
	end, { baseScale })

	local beat = React.useCallback(function()
		local motion = motionRef.current
		if not motion or not aliveRef.current then
			return
		end

		manualBeatUntilRef.current = recoverDelay
		motion:spring(primaryScale, spring)
		task.delay(secondaryDelay, function()
			if not aliveRef.current then
				return
			end
			local nextMotion = motionRef.current
			if nextMotion then
				nextMotion:spring(secondaryScale, spring)
			end
		end)
	end, { baseScale, primaryScale, secondaryScale, secondaryDelay, recoverDelay, spring })

	return {
		scale = scale,
		beat = beat,
	}
end

return useBeatMotion
