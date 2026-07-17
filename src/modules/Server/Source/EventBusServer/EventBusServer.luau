local require = require(script.Parent.loader).load(script)

return {
	Server = require("EventBusServerRuntime"),
	Utils = require("EventBusUtilsServer"),
	Core = require("EventBusCoreServer"),
}
