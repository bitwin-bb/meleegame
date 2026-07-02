
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerController = require(script:WaitForChild("PlayerController")),
	CombatController = require(script:WaitForChild("CombatController")),
	CameraController = require("CameraController"),
	UIController = require(script:WaitForChild("UIControllerClient")),
	InputController = require(script:WaitForChild("InputController")),
	ToolController = require(script:WaitForChild("ToolController")),
})
