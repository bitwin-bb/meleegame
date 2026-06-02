--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	InputHandler = require(gameRoot.Client.Handlers.InputHandler),
	AnimationHandler = require(gameRoot.Client.Handlers.AnimationHandler),
	MovementHandler = require(gameRoot.Client.Handlers.MovementHandler),
	CombatInputHandler = require(gameRoot.Client.Handlers.CombatInputHandler),
	ToolHandler = require(gameRoot.Client.Handlers.ToolHandler),
	CameraHandler = require(gameRoot.Shared.Features.camera.handlers.CameraHandler),
	UIHandler = require(gameRoot.Client.Handlers.UIHandler),
	EffectHandler = require(gameRoot.Client.Handlers.EffectHandler),
	SoundHandler = require(gameRoot.Client.Handlers.SoundHandler),
})
