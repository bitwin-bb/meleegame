
local require = require(script.Parent.loader).load(script)

return {
	EventBus = require(script:WaitForChild("SharedEventBusCoreEventBus")),
	EventName = require(script:WaitForChild("EventName")),
	EventConnection = require(script:WaitForChild("EventConnection")),
	Types = require(script:WaitForChild("SharedEventBusTypes")),
	signals = require(script:WaitForChild("SharedEventBusSignals")),
}
