--!strict

local require = require(script.Parent.loader).load(assert(script:FindFirstAncestor("AquariaBackup"), "Missing AquariaBackup package root"))

local ServerEvents = require("ServerEvents") :: { [string]: string }
local Utils = require("Utils")

local eventNames: { string } = {}
local eventNameSet: { [string]: boolean } = {}

for _, eventName in ServerEvents do
	eventNames[#eventNames + 1] = eventName
	eventNameSet[eventName] = true
end

table.sort(eventNames)

local ServerEventRegistry = {}

function ServerEventRegistry.GetAll(): { string }
	return table.clone(eventNames)
end

function ServerEventRegistry.Has(eventNameRaw: any): boolean
	return typeof(eventNameRaw) == "string" and eventNameSet[eventNameRaw] == true
end

function ServerEventRegistry.Assert(eventNameRaw: any): boolean
	if ServerEventRegistry.Has(eventNameRaw) then
		return true
	end

	return Utils.ReportUnknownEvent(tostring(eventNameRaw))
end

return ServerEventRegistry
