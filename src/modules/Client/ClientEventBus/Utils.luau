--!strict

local Utils = {}

Utils.ERROR_ON_UNKNOWN_EVENT = false

function Utils.ReportUnknownEvent(eventName: string): boolean
	local message = "[ClientEventBus] unknown event " .. eventName

	if Utils.ERROR_ON_UNKNOWN_EVENT then
		error(message, 3)
	end

	warn(message)
	return false
end

return Utils
