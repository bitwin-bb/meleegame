
local require = require(script.Parent.loader).load(script)

return {
	BusClient = require("BusClient"),
	EventsClient = require("EventsClient"),
	EventRegistryClient = require("EventRegistryClient"),
	signals = require("EventBusSignalsClient"),
}
