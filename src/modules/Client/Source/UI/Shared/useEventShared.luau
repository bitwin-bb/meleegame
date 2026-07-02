local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type UseEventOptions = {
	enabled: boolean?,
	once: boolean?,
}

local function isSignal(value: any): boolean
	return typeof(value) == "RBXScriptSignal"
end

local function useEvent(eventOrCallback: any, callbackOrOptions: any?, optionsRaw: UseEventOptions?): (...any) -> ...any
	local signal = if isSignal(eventOrCallback) then eventOrCallback :: RBXScriptSignal else nil
	local callbackRaw = if signal ~= nil then callbackOrOptions else eventOrCallback
	local options = if signal ~= nil and typeof(optionsRaw) == "table"
		then optionsRaw :: UseEventOptions
		else if signal == nil and typeof(callbackOrOptions) == "table"
			then callbackOrOptions :: UseEventOptions
			else nil
	local callbackRef = React.useRef(callbackRaw)

	React.useEffect(function()
		callbackRef.current = callbackRaw
	end, { callbackRaw })

	local stableCallback = React.useCallback(function(...)
		local callback = callbackRef.current
		if typeof(callback) ~= "function" then
			return nil
		end

		return callback(...)
	end, {})

	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local once = options ~= nil and options.once == true
	(React.useEffect :: any)(function(): (() -> ())?
		if signal == nil or not enabled then
			return nil
		end

		local connection: RBXScriptConnection?
		connection = signal:Connect(function(...)
			stableCallback(...)
			if once and connection ~= nil then
				connection:Disconnect()
				connection = nil
			end
		end)

		return function()
			if connection ~= nil then
				connection:Disconnect()
				connection = nil
			end
		end
	end, { signal, enabled, once, stableCallback } :: { any })

	return stableCallback
end

return useEvent
