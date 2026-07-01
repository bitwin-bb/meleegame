local require = require(script.Parent.loader).load(script)

return {
	Server = require(script:WaitForChild("EventBusServer")),
	Utils = require(script:WaitForChild("EventBusUtilsServer")),
	Core = require(script:WaitForChild("EventBusCoreServer")),
}
