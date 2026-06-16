
local require = require(script.Parent.loader).load(script)

return {
	ClientSignal = require(script:WaitForChild("ClientSignal")),
}
