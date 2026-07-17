
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerController = require("PlayerController"),
	CombatController = require("CombatController"),
	CameraController = require("CameraController"),
	UIController = require("UIControllerClient"),
	InputController = require("InputController"),
	ToolController = require("ToolController"),
})
