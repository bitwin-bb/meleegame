local require = require(script.Parent.loader).load(script)

return {
	Server = require(script:WaitForChild("ServerEventBusServer")),
	Utils = require(script:WaitForChild("ServerEventBusUtils")),
	Core = require(script:WaitForChild("ServerEventBusCore")),
}
