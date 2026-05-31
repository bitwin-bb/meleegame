--!strict

local Nevermore = require(script:FindFirstAncestor("game").Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	InputHandler = require(script.InputHandler),
	AnimationHandler = require(script.AnimationHandler),
	MovementHandler = require(script.MovementHandler),
	CombatInputHandler = require(script.CombatInputHandler),
	ToolHandler = require(script.ToolHandler),
	CameraHandler = require(script:FindFirstAncestor("game").Shared.Features.camera.handlers.CameraHandler),
	UIHandler = require(script.UIHandler),
	EffectHandler = require(script.EffectHandler),
	SoundHandler = require(script.SoundHandler),
})
