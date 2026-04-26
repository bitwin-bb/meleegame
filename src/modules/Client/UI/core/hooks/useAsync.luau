--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local useMounted = require(script.Parent.useMounted)
local useStableCallback = require(script.Parent.internal.useStableCallback)

export type AsyncStatus = "idle" | "loading" | "success" | "error"

export type AsyncOptions<TValue> = {
	initialValue: TValue?,
	onSuccess: ((TValue?) -> ())?,
	onError: ((string) -> ())?,
}

export type AsyncResult<TValue> = {
	status: AsyncStatus,
	loading: boolean,
	value: TValue?,
	error: string?,
	execute: (...any) -> number,
	cancel: () -> (),
	reset: () -> (),
}

local function cancelPromise(promiseRaw: any)
	if typeof(promiseRaw) ~= "table" then
		return
	end

	local cancel = (promiseRaw :: any).Cancel
	if typeof(cancel) ~= "function" then
		cancel = (promiseRaw :: any).cancel
	end
	if typeof(cancel) == "function" then
		pcall(function()
			cancel(promiseRaw)
		end)
	end
end

local function attachPromiseHandlers(promiseRaw: any, onResolve: (any) -> (), onReject: (any) -> ())
	if typeof(promiseRaw) ~= "table" then
		return
	end

	local thenMethod = (promiseRaw :: any).Then
	if typeof(thenMethod) ~= "function" then
		thenMethod = (promiseRaw :: any).andThen
	end

	local chainedPromise = promiseRaw
	if typeof(thenMethod) == "function" then
		local ok, result = pcall(function()
			return thenMethod(promiseRaw, onResolve)
		end)
		if ok and result ~= nil then
			chainedPromise = result
		else
			pcall(function()
				thenMethod(onResolve)
			end)
		end
	end

	local catchMethod = (chainedPromise :: any).Catch
	if typeof(catchMethod) ~= "function" then
		catchMethod = (chainedPromise :: any).catch
	end
	if typeof(catchMethod) == "function" then
		local ok = pcall(function()
			catchMethod(chainedPromise, onReject)
		end)
		if not ok then
			pcall(function()
				catchMethod(onReject)
			end)
		end
	end
end

local function isPromiseLike(valueRaw: any): boolean
	if typeof(valueRaw) ~= "table" then
		return false
	end
	return typeof((valueRaw :: any).Then) == "function" or typeof((valueRaw :: any).andThen) == "function"
end

local function useAsync<TValue>(callbackRaw: any, options: AsyncOptions<TValue>?): AsyncResult<TValue>
	local callback = useStableCallback(callbackRaw)
	local onSuccess = useStableCallback(if options ~= nil then options.onSuccess else nil)
	local onError = useStableCallback(if options ~= nil then options.onError else nil)
	local mountedRef = useMounted()
	local initialValue = if options ~= nil then options.initialValue else nil
	local requestIdRef = React.useRef(0)
	local activePromiseRef = React.useRef(nil)
	local status, setStatus = React.useState("idle" :: AsyncStatus)
	local loading, setLoading = React.useState(false)
	local value, setValue = React.useState(initialValue)
	local error, setError = React.useState(nil :: string?)

	local cancel = React.useCallback(function()
		requestIdRef.current += 1
		cancelPromise(activePromiseRef.current)
		activePromiseRef.current = nil
		if mountedRef.current then
			setLoading(false)
			setStatus("idle")
		end
	end, { mountedRef })

	local reset = React.useCallback(function()
		cancel()
		if mountedRef.current then
			setValue(initialValue)
			setError(nil)
		end
	end, { cancel, initialValue, mountedRef })

	local execute = React.useCallback(function(...): number
		requestIdRef.current += 1
		local requestId = requestIdRef.current
		cancelPromise(activePromiseRef.current)
		activePromiseRef.current = nil

		if mountedRef.current then
			setLoading(true)
			setStatus("loading")
			setError(nil)
		end

		local ok, result = pcall(callback, ...)
		if not ok then
			if mountedRef.current and requestIdRef.current == requestId then
				local message = tostring(result)
				setLoading(false)
				setStatus("error")
				setError(message)
				onError(message)
			end
			return requestId
		end

		if isPromiseLike(result) then
			activePromiseRef.current = result
			attachPromiseHandlers(result, function(resolvedValue: any)
				if not mountedRef.current or requestIdRef.current ~= requestId then
					return
				end

				activePromiseRef.current = nil
				setLoading(false)
				setStatus("success")
				setValue(resolvedValue)
				setError(nil)
				onSuccess(resolvedValue)
			end, function(rejectedValue: any)
				if not mountedRef.current or requestIdRef.current ~= requestId then
					return
				end

				activePromiseRef.current = nil
				local message = tostring(rejectedValue)
				setLoading(false)
				setStatus("error")
				setError(message)
				onError(message)
			end)
			return requestId
		end

		if mountedRef.current and requestIdRef.current == requestId then
			setLoading(false)
			setStatus("success")
			setValue(result)
			setError(nil)
			onSuccess(result)
		end

		return requestId
	end, { callback, mountedRef, onSuccess, onError })

	React.useEffect(function()
		return function()
			cancel()
		end
	end, { cancel })

	return {
		status = status,
		loading = loading,
		value = value,
		error = error,
		execute = execute,
		cancel = cancel,
		reset = reset,
	}
end

return useAsync
