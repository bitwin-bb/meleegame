
local require = require(script.Parent.loader).load(script)

return {
	EventBus = require(script:WaitForChild("EventBusCoreEventBusShared")),
	EventName = require(script:WaitForChild("EventName")),
	EventConnection = require(script:WaitForChild("EventConnection")),
	Types = require(script:WaitForChild("EventBusTypesShared")),
	signals = require(script:WaitForChild("EventBusSignalsShared")),
}
