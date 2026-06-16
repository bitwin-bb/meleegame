
local require = require(script.Parent.loader).load(script)

return {
	Client = require(script:WaitForChild("ClientEventBusClient")),
	Utils = require(script:WaitForChild("ClientEventBusUtils")),
	Core = require(script:WaitForChild("ClientEventBusCore")),
}
