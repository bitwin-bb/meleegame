--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local useLatest = require(script.Parent.internal.useLatest)
local useTimeout = require(script.Parent.useTimeout)

export type DebounceOptions<T> = {
	leading: boolean?,
	equalityFn: ((T, T) -> boolean)?,
}

export type DebounceResult<T> = {
	value: T,
	pending: boolean,
	cancel: () -> (),
	flush: () -> (),
}

local function defaultEquality<T>(a: T, b: T): boolean
	return a == b
end

local function sanitizeDelaySeconds(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.max(valueRaw, 0)
end

local function useDebounce<T>(value: T, delaySecondsRaw: any, options: DebounceOptions<T>?): DebounceResult<T>
	local delaySeconds = sanitizeDelaySeconds(delaySecondsRaw)
	local leading = if options ~= nil and options.leading ~= nil then options.leading == true else false
	local equalityFn = if options ~= nil and options.equalityFn ~= nil then options.equalityFn else defaultEquality
	local equalityRef = useLatest(equalityFn)
	local latestValueRef = useLatest(value)
	local debouncedValueRef = React.useRef(value)
	local debouncedValue, setDebouncedValue = React.useState(value)

	local commitLatestValue = React.useCallback(function()
		local nextValue = latestValueRef.current
		if equalityRef.current(debouncedValueRef.current, nextValue) then
			return
		end

		debouncedValueRef.current = nextValue
		setDebouncedValue(nextValue)
	end, { latestValueRef, equalityRef })

	local timeout = useTimeout(commitLatestValue, delaySeconds, {
		enabled = true,
		autoStart = false,
	})
	local cancelTimeout = timeout.cancel
	local restartTimeout = timeout.restart
	local isTimeoutScheduled = timeout.isScheduled

	React.useEffect(function()
		if equalityRef.current(debouncedValueRef.current, value) then
			cancelTimeout()
			return
		end

		if delaySeconds <= 0 then
			commitLatestValue()
			return
		end

		if leading and not isTimeoutScheduled then
			debouncedValueRef.current = value
			setDebouncedValue(value)
		end

		restartTimeout(delaySeconds)
	end, {
		value,
		delaySeconds,
		leading,
		isTimeoutScheduled,
		cancelTimeout,
		restartTimeout,
		commitLatestValue,
		equalityRef,
	})

	return {
		value = debouncedValue,
		pending = isTimeoutScheduled,
		cancel = cancelTimeout,
		flush = timeout.flush,
	}
end

return useDebounce
