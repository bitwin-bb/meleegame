
local require = require(script.Parent.loader).load(script)

return {
	EventBus = require("EventBusCoreEventBusShared"),
	EventName = require("EventName"),
	EventConnection = require("EventConnection"),
	Types = require("EventBusTypesShared"),
	signals = require("EventBusSignalsShared"),
}
