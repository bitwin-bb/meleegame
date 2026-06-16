local require = require(script.Parent.loader).load(script)

return {
	ServerBus = require(script:WaitForChild("ServerBus")),
	ServerEvents = require(script:WaitForChild("ServerEvents")),
	ServerEventRegistry = require(script:WaitForChild("ServerEventRegistry")),
	signals = require(script:WaitForChild("ServerEventBusSignals")),
}
