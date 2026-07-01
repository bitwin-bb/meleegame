
local require = require(script.Parent.loader).load(script)

return {
	SignalClient = require(script:WaitForChild("SignalClient")),
}
