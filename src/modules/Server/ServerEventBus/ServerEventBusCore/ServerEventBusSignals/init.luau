local require = require(script.Parent.loader).load(script)

return {
	ServerSignal = require(script:WaitForChild("ServerSignal")),
}
