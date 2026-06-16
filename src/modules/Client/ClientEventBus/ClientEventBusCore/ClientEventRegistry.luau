
local require = require(script.Parent.loader).load(script)

local ClientEvents = require("ClientEvents") :: { [string]: string }
local Utils = require("ClientEventBusUtils")

local eventNames: { string } = {}
local eventNameSet: { [string]: boolean } = {}

for _, eventName in ClientEvents do
	eventNames[#eventNames + 1] = eventName
	eventNameSet[eventName] = true
end

table.sort(eventNames)

local ClientEventRegistry = {}

function ClientEventRegistry.GetAll(): { string }
	return table.clone(eventNames)
end

function ClientEventRegistry.Has(eventNameRaw: any): boolean
	return typeof(eventNameRaw) == "string" and eventNameSet[eventNameRaw] == true
end

function ClientEventRegistry.Assert(eventNameRaw: any): boolean
	if ClientEventRegistry.Has(eventNameRaw) then
		return true
	end

	return Utils.ReportUnknownEvent(tostring(eventNameRaw))
end

return ClientEventRegistry
