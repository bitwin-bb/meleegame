
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.Get("Table")

return Table.copy({
	InputHandler = require(script:WaitForChild("InputHandler")),
	AnimationHandler = require(script:WaitForChild("AnimationHandler")),
	MovementHandler = require(script:WaitForChild("MovementHandler")),
	CombatInputHandler = require(script:WaitForChild("CombatInputHandler")),
	ToolHandler = require(script:WaitForChild("ToolHandler")),
	CameraHandler = require("CameraHandler"),
	UIHandler = require(script:WaitForChild("UIHandler")),
	EffectHandler = require(script:WaitForChild("EffectHandler")),
	SoundHandler = require(script:WaitForChild("SoundHandler")),
})
