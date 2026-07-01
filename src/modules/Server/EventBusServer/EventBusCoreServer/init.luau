local require = require(script.Parent.loader).load(script)

return {
	BusServer = require(script:WaitForChild("BusServer")),
	EventsServer = require(script:WaitForChild("EventsServer")),
	EventRegistryServer = require(script:WaitForChild("EventRegistryServer")),
	signals = require(script:WaitForChild("EventBusSignalsServer")),
}
