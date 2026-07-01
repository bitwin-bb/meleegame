
local require = require(script.Parent.loader).load(script)

return {
	Client = require(script:WaitForChild("EventBusClient")),
	Utils = require(script:WaitForChild("EventBusUtilsClient")),
	Core = require(script:WaitForChild("EventBusCoreClient")),
}
