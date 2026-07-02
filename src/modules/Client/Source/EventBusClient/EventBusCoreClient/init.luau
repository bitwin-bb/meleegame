
local require = require(script.Parent.loader).load(script)

return {
	BusClient = require(script:WaitForChild("BusClient")),
	EventsClient = require(script:WaitForChild("EventsClient")),
	EventRegistryClient = require(script:WaitForChild("EventRegistryClient")),
	signals = require(script:WaitForChild("EventBusSignalsClient")),
}
