local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cleanup = require("cleanup")
local React = require(ReplicatedStorage.Packages.React)
local useLatest = require("useLatest")

local function dependencyArray(...: any): { any }
	return { ... }
end

export type ThrottleOptions<T> = {
	leading: boolean?,
	trailing: boolean?,
	equalityFn: ((T, T) -> boolean)?,
}

export type ThrottleResult<T> = {
	value: T,
	pending: boolean,
	cancel: () -> (),
	flush: () -> (),
}

local function defaultEquality<T>(a: T, b: T): boolean
	return a == b
end

local function CoerceIntervalSeconds(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.max(valueRaw, 0)
end

local function useThrottle<T>(value: T, intervalSecondsRaw: any, options: ThrottleOptions<T>?): ThrottleResult<T>
	local intervalSeconds = CoerceIntervalSeconds(intervalSecondsRaw)
	local leading = if options ~= nil and options.leading ~= nil then options.leading == true else true
	local trailing = if options ~= nil and options.trailing ~= nil then options.trailing == true else true
	local equalityFn = if options ~= nil and options.equalityFn ~= nil then options.equalityFn else defaultEquality
	local equalityRef = useLatest(equalityFn)
	local throttledValueRef = React.useRef(value)
	local windowStartedAtRef = React.useRef(nil :: number?)
	local pendingValueRef = React.useRef(nil :: T?)
	local pendingThreadRef = React.useRef(nil :: thread?)
	local generationRef = React.useRef(0)
	local throttledValue, setThrottledValue = React.useState(value)
	local pending, setPending = React.useState(false)

	local cancel = React.useCallback(function()
		generationRef.current += 1
		Cleanup.CancelTask(pendingThreadRef.current)
		pendingThreadRef.current = nil
		pendingValueRef.current = nil
		setPending(false)
	end, {})

	local emit = React.useCallback(function(nextValue: T)
		cancel()
		windowStartedAtRef.current = os.clock()
		local equality = equalityRef.current :: (T, T) -> boolean
		if equality(throttledValueRef.current, nextValue) then
			return
		end

		throttledValueRef.current = nextValue
		setThrottledValue(nextValue)
	end, dependencyArray(cancel, equalityRef))

	local flush = React.useCallback(function()
		if pendingValueRef.current == nil then
			return
		end

		emit(pendingValueRef.current :: T)
	end, dependencyArray(emit))

	local scheduleTrailing = React.useCallback(function(delaySeconds: number, nextValue: T)
		cancel()
		generationRef.current += 1
		local generation = generationRef.current
		pendingValueRef.current = nextValue
		setPending(true)
		pendingThreadRef.current = task.delay(delaySeconds, function()
			if generationRef.current ~= generation or pendingValueRef.current == nil then
				return
			end

			local valueToEmit = pendingValueRef.current :: T
			pendingThreadRef.current = nil
			pendingValueRef.current = nil
			setPending(false)
			emit(valueToEmit)
		end)
	end, dependencyArray(cancel, emit))

	React.useEffect(function()
		if intervalSeconds <= 0 then
			emit(value)
			return
		end

		local equality = equalityRef.current :: (T, T) -> boolean
		if equality(throttledValueRef.current, value) and pendingValueRef.current == nil then
			return
		end

		local now = os.clock()
		local windowStartedAt = windowStartedAtRef.current
		if windowStartedAt == nil then
			if leading then
				emit(value)
			elseif trailing then
				windowStartedAtRef.current = now
				scheduleTrailing(intervalSeconds, value)
			end
			return
		end

		local elapsed = now - windowStartedAt
		if elapsed >= intervalSeconds then
			emit(value)
		elseif trailing then
			scheduleTrailing(intervalSeconds - elapsed, value)
		end
	end, dependencyArray(value, intervalSeconds, leading, trailing, emit, scheduleTrailing, equalityRef))

	React.useEffect(function()
		return function()
			cancel()
		end
	end, dependencyArray(cancel))

	return {
		value = throttledValue,
		pending = pending,
		cancel = cancel,
		flush = flush,
	}
end

return useThrottle
