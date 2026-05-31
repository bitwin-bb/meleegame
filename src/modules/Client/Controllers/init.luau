--!strict

local Nevermore = require(script:FindFirstAncestor("game").Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerController = require(script.PlayerController),
	CombatController = require(script.CombatController),
	CameraController = require(script:FindFirstAncestor("game").Shared.Features.camera.controllers.CameraController),
	UIController = require(script.UIController),
	InputController = require(script.InputController),
	ToolController = require(script.ToolController),
})
