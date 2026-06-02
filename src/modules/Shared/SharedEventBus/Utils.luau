--!strict

local Utils = {}

Utils.DEBUG_WARN_CALLBACK_ERRORS = true

function Utils.Warn(message: string)
	warn("[EventBus] " .. message)
end

return Utils
