local require = require(script.Parent.loader).load(script)

local EventsServer = require("EventsServer") :: { [string]: string }
local Utils = require("EventBusUtilsServer")

local eventNames: { string } = {}
local eventNameSet: { [string]: boolean } = {}

for _, eventName in EventsServer do
	eventNames[#eventNames + 1] = eventName
	eventNameSet[eventName] = true
end

table.sort(eventNames)

local EventRegistryServer = {}

function EventRegistryServer.GetAll(): { string }
	return table.clone(eventNames)
end

function EventRegistryServer.Has(eventNameRaw: any): boolean
	return typeof(eventNameRaw) == "string" and eventNameSet[eventNameRaw] == true
end

function EventRegistryServer.Assert(eventNameRaw: any): boolean
	if EventRegistryServer.Has(eventNameRaw) then
		return true
	end

	return Utils.ReportUnknownEvent(tostring(eventNameRaw))
end

return EventRegistryServer
