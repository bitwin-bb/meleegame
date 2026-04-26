--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cleanup = require(script.Parent.internal.cleanup)
local React = require(ReplicatedStorage.Packages.React)
local useLatest = require(script.Parent.internal.useLatest)

export type SignalOptions<TValue> = {
	initialValue: TValue?,
	getCurrent: (() -> TValue?)?,
	equalityFn: ((TValue?, TValue?) -> boolean)?,
}

local function defaultSelector(...)
	return ...
end

local function defaultEquality<TValue>(a: TValue?, b: TValue?): boolean
	return a == b
end

local function connectSignal(signalRaw: any, callbackRaw: (...any) -> ()): any
	if typeof(signalRaw) == "RBXScriptSignal" then
		return (signalRaw :: RBXScriptSignal):Connect(callbackRaw)
	end

	if typeof(signalRaw) ~= "table" then
		return nil
	end

	local connect = (signalRaw :: any).Connect
	if typeof(connect) ~= "function" then
		connect = (signalRaw :: any).connect
	end
	if typeof(connect) ~= "function" then
		return nil
	end

	local ok, result = pcall(function()
		return connect(signalRaw, callbackRaw)
	end)
	if ok then
		return result
	end

	local okWithoutSelf, resultWithoutSelf = pcall(function()
		return connect(callbackRaw)
	end)
	if okWithoutSelf then
		return resultWithoutSelf
	end

	return nil
end

local function useSignal<TValue>(signalRaw: any, selectorRaw: any, options: SignalOptions<TValue>?): TValue?
	local selector = if typeof(selectorRaw) == "function" then selectorRaw else defaultSelector
	local equalityFn = if options ~= nil and options.equalityFn ~= nil then options.equalityFn else defaultEquality
	local selectorRef = useLatest(selector)
	local equalityRef = useLatest(equalityFn)
	local getCurrent = if options ~= nil then options.getCurrent else nil
	local initialValue = if typeof(getCurrent) == "function"
		then getCurrent()
		else if options ~= nil then options.initialValue else nil
	local valueRef = React.useRef(initialValue)
	local value, setValue = React.useState(initialValue)

	local applyValue = React.useCallback(function(nextValue: TValue?)
		if equalityRef.current(valueRef.current, nextValue) then
			return
		end

		valueRef.current = nextValue
		setValue(nextValue)
	end, { equalityRef })

	React.useEffect(function()
		if typeof(getCurrent) == "function" then
			applyValue(getCurrent())
		end

		local connection = connectSignal(signalRaw, function(...)
			local nextValue = selectorRef.current(...)
			applyValue(nextValue)
		end)

		return function()
			Cleanup.Call(connection)
		end
	end, { signalRaw, getCurrent, applyValue, selectorRef })

	return value
end

return useSignal
