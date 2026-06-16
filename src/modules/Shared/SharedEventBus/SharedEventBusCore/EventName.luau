local require = require(script.Parent.loader).load(script)

local EventName = {}

function EventName.Sanitize(eventNameRaw: any): string?
	if typeof(eventNameRaw) ~= "string" then
		return nil
	end

	if eventNameRaw == "" then
		return nil
	end

	return eventNameRaw
end

function EventName.Assert(eventNameRaw: any): string
	local eventName = EventName.Sanitize(eventNameRaw)
	assert(eventName ~= nil, "eventName must be a non-empty string")
	return eventName
end

EventName.sanitize = EventName.Sanitize
EventName.assert = EventName.Assert

return EventName
