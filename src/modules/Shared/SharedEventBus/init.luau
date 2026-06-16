
local require = require(script.Parent.loader).load(script)

return {
	Client = require(script:WaitForChild("SharedEventBusClient")),
	Server = require(script:WaitForChild("SharedEventBusServer")),
	Utils = require(script:WaitForChild("SharedEventBusUtils")),
	Core = require(script:WaitForChild("SharedEventBusCore")),
}
