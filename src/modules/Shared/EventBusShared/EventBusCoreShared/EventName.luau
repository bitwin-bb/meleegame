local require = require(script.Parent.loader).load(script)

local EventName = {}

function EventName.Coerce(eventNameRaw: any): string?
	if typeof(eventNameRaw) ~= "string" then
		return nil
	end

	if eventNameRaw == "" then
		return nil
	end

	return eventNameRaw
end

function EventName.Assert(eventNameRaw: any): string
	local eventName = EventName.Coerce(eventNameRaw)
	assert(eventName ~= nil, "eventName must be a non-empty string")
	return eventName
end

return EventName
