local require = require(script.Parent.loader).load(script)

return {
	SignalServer = require(script:WaitForChild("SignalServer")),
}
