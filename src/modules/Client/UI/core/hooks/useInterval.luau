--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cleanup = require(script.Parent.internal.cleanup)
local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

export type IntervalOptions = {
	enabled: boolean?,
	autoStart: boolean?,
}

export type IntervalResult = {
	isRunning: boolean,
	cancel: () -> (),
	restart: (nextIntervalSeconds: number?) -> (),
	fire: () -> (),
}

local MINIMUM_INTERVAL_SECONDS = 1 / 240

local function sanitizeIntervalSeconds(valueRaw: any): number?
	if valueRaw == nil then
		return nil
	end
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return math.max(valueRaw, MINIMUM_INTERVAL_SECONDS)
end

local function useInterval(callbackRaw: any, intervalSecondsRaw: any, options: IntervalOptions?): IntervalResult
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local autoStart = if options ~= nil and options.autoStart ~= nil then options.autoStart == true else true
	local intervalSeconds = sanitizeIntervalSeconds(intervalSecondsRaw)
	local callback = useStableCallback(callbackRaw)
	local generationRef = React.useRef(0)
	local threadRef = React.useRef(nil :: thread?)
	local isRunning, setIsRunning = React.useState(false)

	local cancel = React.useCallback(function()
		generationRef.current += 1
		Cleanup.CancelTask(threadRef.current)
		threadRef.current = nil
		setIsRunning(false)
	end, {})

	local restart = React.useCallback(function(nextIntervalSecondsRaw: number?)
		cancel()

		if not enabled then
			return
		end

		local nextIntervalSeconds = sanitizeIntervalSeconds(nextIntervalSecondsRaw)
		if nextIntervalSeconds == nil then
			return
		end

		generationRef.current += 1
		local generation = generationRef.current
		setIsRunning(true)

		local function scheduleNext()
			threadRef.current = task.delay(nextIntervalSeconds, function()
				if generationRef.current ~= generation then
					return
				end

				callback()

				if generationRef.current ~= generation then
					return
				end

				scheduleNext()
			end)
		end

		scheduleNext()
	end, { cancel, enabled, callback })

	local fire = React.useCallback(function()
		callback()
	end, { callback })

	React.useEffect(function()
		if enabled and autoStart and intervalSeconds ~= nil then
			restart(intervalSeconds)
		else
			cancel()
		end
	end, { enabled, autoStart, intervalSeconds, restart, cancel })

	React.useEffect(function()
		return function()
			cancel()
		end
	end, { cancel })

	return {
		isRunning = isRunning,
		cancel = cancel,
		restart = restart,
		fire = fire,
	}
end

return useInterval
