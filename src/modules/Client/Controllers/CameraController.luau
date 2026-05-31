--!strict

local gameRoot = script:FindFirstAncestor("game")
local Handlers = require(gameRoot.Client.Handlers)
local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local CameraController = {}
CameraController.__index = CameraController

export type CameraController = typeof(setmetatable(
	{} :: {
		maid: any,
		Started: any,
		handler: any,
	},
	CameraController
))

function CameraController.new(cameraRaw: any?): CameraController
	local self = setmetatable({
		maid = Maid.new(),
		Started = Signal.new(),
		handler = Handlers.CameraHandler.new(cameraRaw),
	}, CameraController)

	self.maid:GiveTask(self.Started)
	self.maid:GiveTask(self.handler)
	return self
end

function CameraController.Start(self: CameraController): boolean
	self.Started:Fire()
	return true
end

function CameraController.GetHandler(self: CameraController): any
	return self.handler
end

function CameraController.Destroy(self: CameraController)
	self.maid:DoCleaning()
end

CameraController.start = CameraController.Start
CameraController.getHandler = CameraController.GetHandler
CameraController.destroy = CameraController.Destroy

return CameraController
