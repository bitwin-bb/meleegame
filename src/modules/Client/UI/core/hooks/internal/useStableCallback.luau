--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local useLatest = require(script.Parent.useLatest)

local function useStableCallback(callbackRaw: any): (...any) -> ...any
	local callbackRef = useLatest(callbackRaw)

	return React.useCallback(function(...)
		local callback = callbackRef.current
		if typeof(callback) ~= "function" then
			return nil
		end

		return callback(...)
	end, {})
end

return useStableCallback
