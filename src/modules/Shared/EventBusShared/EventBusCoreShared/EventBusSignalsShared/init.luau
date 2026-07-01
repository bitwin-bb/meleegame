local require = require(script.Parent.loader).load(script)

return {
	Signal = require("Signal"),
	Connection = require(script:WaitForChild("Connection")),
}
