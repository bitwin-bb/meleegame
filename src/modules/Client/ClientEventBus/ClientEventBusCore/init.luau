
local require = require(script.Parent.loader).load(script)

return {
	ClientBus = require(script:WaitForChild("ClientBus")),
	ClientEvents = require(script:WaitForChild("ClientEvents")),
	ClientEventRegistry = require(script:WaitForChild("ClientEventRegistry")),
	signals = require(script:WaitForChild("ClientEventBusSignals")),
}
