
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	InputHandler = require("InputHandler"),
	AnimationHandler = require("AnimationHandler"),
	MovementHandler = require("MovementHandler"),
	CombatInputHandler = require("CombatInputHandler"),
	ToolHandler = require("ToolHandler"),
	CameraHandler = require("CameraHandler"),
	UIHandler = require("UIHandler"),
	EffectHandler = require("EffectHandler"),
	SoundHandler = require("SoundHandler"),
})
