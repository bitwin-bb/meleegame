
local require = require(script.Parent.loader).load(script)

return {
	Client = require("EventBusClientRuntime"),
	Utils = require("EventBusUtilsClient"),
	Core = require("EventBusCoreClient"),
}
