--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

export type InfoPopUpOptions = {
	enabled: boolean?,
	eventToken: any?,
	riseDuration: number?,
	holdDuration: number?,
	shrinkDuration: number?,
	fromYOffsetStuds: number?,
	toYOffsetStuds: number?,
	minScale: number?,
}

export type InfoPopUpState = {
	progress: number,
	offsetYStuds: number,
	transparency: number,
	scale: number,
	totalDuration: number,
	finished: boolean,
}

local DEFAULT_RISE_DURATION = 0.34
local DEFAULT_HOLD_DURATION = 2.5
local DEFAULT_SHRINK_DURATION = 0.28
local DEFAULT_FROM_Y_OFFSET_STUDS = 0
local DEFAULT_TO_Y_OFFSET_STUDS = 2.7
local DEFAULT_MIN_SCALE = 0.2

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end

	local value = valueRaw
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function useInfoPopUp(options: InfoPopUpOptions?): InfoPopUpState
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local riseDuration = sanitizeNumber(if options ~= nil then options.riseDuration else nil, DEFAULT_RISE_DURATION, 0.05, 20)
	local holdDuration = sanitizeNumber(if options ~= nil then options.holdDuration else nil, DEFAULT_HOLD_DURATION, 0, 30)
	local shrinkDuration =
		sanitizeNumber(if options ~= nil then options.shrinkDuration else nil, DEFAULT_SHRINK_DURATION, 0.05, 20)
	local fromYOffsetStuds =
		sanitizeNumber(if options ~= nil then options.fromYOffsetStuds else nil, DEFAULT_FROM_Y_OFFSET_STUDS, -100, 100)
	local toYOffsetStuds =
		sanitizeNumber(if options ~= nil then options.toYOffsetStuds else nil, DEFAULT_TO_Y_OFFSET_STUDS, -100, 100)
	local minScale = sanitizeNumber(if options ~= nil then options.minScale else nil, DEFAULT_MIN_SCALE, 0.01, 1)
	local eventToken = if options ~= nil then options.eventToken else nil
	local totalDuration = riseDuration + holdDuration + shrinkDuration

	local elapsedRef = React.useRef(0)
	local progress, setProgress = React.useState(0)

	React.useEffect(function()
		elapsedRef.current = 0
		setProgress(0)
	end, { eventToken, enabled, riseDuration, holdDuration, shrinkDuration, fromYOffsetStuds, toYOffsetStuds, minScale })

	React.useEffect(function()
		if not enabled then
			return nil
		end

		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			elapsedRef.current += math.max(0, deltaTime)
			local nextProgress = math.clamp(elapsedRef.current / math.max(0.05, totalDuration), 0, 1)
			setProgress(function(previousProgress: number): number
				if math.abs(previousProgress - nextProgress) <= 1e-4 then
					return previousProgress
				end
				return nextProgress
			end)
		end)

		return function()
			connection:Disconnect()
		end
	end, { enabled, riseDuration, holdDuration, shrinkDuration, eventToken, totalDuration })

	local clampedProgress = math.clamp(progress, 0, 1)
	local elapsed = clampedProgress * totalDuration
	local riseEnd = riseDuration
	local holdEnd = riseDuration + holdDuration

	local offsetYStuds = toYOffsetStuds
	local transparency = 0
	local scale = 1

	if elapsed <= riseEnd then
		local riseAlpha = math.clamp(elapsed / math.max(0.05, riseDuration), 0, 1)
		offsetYStuds = fromYOffsetStuds + (toYOffsetStuds - fromYOffsetStuds) * riseAlpha

		local totalTravel = math.abs(toYOffsetStuds - fromYOffsetStuds)
		local remainingTravel = math.abs(toYOffsetStuds - offsetYStuds)
		transparency = if totalTravel <= 1e-4 then 0 else math.clamp(remainingTravel / totalTravel, 0, 1)
	elseif elapsed <= holdEnd then
		offsetYStuds = toYOffsetStuds
		transparency = 0
		scale = 1
	else
		local shrinkElapsed = elapsed - holdEnd
		local shrinkAlpha = math.clamp(shrinkElapsed / math.max(0.05, shrinkDuration), 0, 1)
		offsetYStuds = toYOffsetStuds
		scale = 1 - (1 - minScale) * shrinkAlpha
		local scaleAlpha = if 1 - minScale <= 1e-4
			then 1
			else math.clamp((scale - minScale) / (1 - minScale), 0, 1)
		transparency = math.clamp(1 - scaleAlpha, 0, 1)
	end

	return {
		progress = clampedProgress,
		offsetYStuds = offsetYStuds,
		transparency = transparency,
		scale = scale,
		totalDuration = totalDuration,
		finished = elapsed >= totalDuration - 1e-4,
	}
end

return useInfoPopUp
