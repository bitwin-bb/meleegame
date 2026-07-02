
local require = require(script.Parent.loader).load(script)

local EventsClient = require("EventsClient") :: { [string]: string }
local Utils = require("EventBusUtilsClient")

local eventNames: { string } = {}
local eventNameSet: { [string]: boolean } = {}

for _, eventName in EventsClient do
	eventNames[#eventNames + 1] = eventName
	eventNameSet[eventName] = true
end

table.sort(eventNames)

local EventRegistryClient = {}

function EventRegistryClient.GetAll(): { string }
	return table.clone(eventNames)
end

function EventRegistryClient.Has(eventNameRaw: any): boolean
	return typeof(eventNameRaw) == "string" and eventNameSet[eventNameRaw] == true
end

function EventRegistryClient.Assert(eventNameRaw: any): boolean
	if EventRegistryClient.Has(eventNameRaw) then
		return true
	end

	return Utils.ReportUnknownEvent(tostring(eventNameRaw))
end

return EventRegistryClient
