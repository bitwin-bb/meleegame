--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	PlayerController = require(gameRoot.Client.Controllers.PlayerController),
	CombatController = require(gameRoot.Client.Controllers.CombatController),
	CameraController = require(gameRoot.Shared.Features.camera.controllers.CameraController),
	UIController = require(gameRoot.Client.Controllers.UIController),
	InputController = require(gameRoot.Client.Controllers.InputController),
	ToolController = require(gameRoot.Client.Controllers.ToolController),
})
