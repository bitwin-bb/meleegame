--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cleanup = require(script.Parent.internal.cleanup)
local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

export type TimeoutOptions = {
	enabled: boolean?,
	autoStart: boolean?,
}

export type TimeoutResult = {
	isScheduled: boolean,
	cancel: () -> (),
	flush: () -> (),
	restart: (nextDelaySeconds: number?) -> (),
}

local function sanitizeDelaySeconds(valueRaw: any): number?
	if valueRaw == nil then
		return nil
	end
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return math.max(valueRaw, 0)
end

local function useTimeout(callbackRaw: any, delaySecondsRaw: any, options: TimeoutOptions?): TimeoutResult
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local autoStart = if options ~= nil and options.autoStart ~= nil then options.autoStart == true else true
	local delaySeconds = sanitizeDelaySeconds(delaySecondsRaw)
	local callback = useStableCallback(callbackRaw)
	local generationRef = React.useRef(0)
	local threadRef = React.useRef(nil :: thread?)
	local isScheduled, setIsScheduled = React.useState(false)

	local cancel = React.useCallback(function()
		generationRef.current += 1
		Cleanup.CancelTask(threadRef.current)
		threadRef.current = nil
		setIsScheduled(false)
	end, {})

	local restart = React.useCallback(function(nextDelaySecondsRaw: number?)
		cancel()

		if not enabled then
			return
		end

		local nextDelaySeconds = sanitizeDelaySeconds(nextDelaySecondsRaw)
		if nextDelaySeconds == nil then
			return
		end

		if nextDelaySeconds <= 0 then
			callback()
			return
		end

		generationRef.current += 1
		local generation = generationRef.current
		setIsScheduled(true)
		threadRef.current = task.delay(nextDelaySeconds, function()
			if generationRef.current ~= generation then
				return
			end

			threadRef.current = nil
			setIsScheduled(false)
			callback()
		end)
	end, { cancel, enabled, callback })

	local flush = React.useCallback(function()
		if not isScheduled then
			return
		end

		cancel()
		callback()
	end, { isScheduled, cancel, callback })

	React.useEffect(function()
		if enabled and autoStart and delaySeconds ~= nil then
			restart(delaySeconds)
		else
			cancel()
		end
	end, { enabled, autoStart, delaySeconds, restart, cancel })

	React.useEffect(function()
		return function()
			cancel()
		end
	end, { cancel })

	return {
		isScheduled = isScheduled,
		cancel = cancel,
		flush = flush,
		restart = restart,
	}
end

return useTimeout
