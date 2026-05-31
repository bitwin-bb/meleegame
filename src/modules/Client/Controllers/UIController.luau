--!strict

local gameRoot = script:FindFirstAncestor("game")
local Handlers = require(gameRoot.Client.Handlers)
local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local UIController = {}
UIController.__index = UIController

export type UIController = typeof(setmetatable(
	{} :: {
		maid: any,
		Started: any,
		handler: any,
	},
	UIController
))

function UIController.new(): UIController
	local self = setmetatable({
		maid = Maid.new(),
		Started = Signal.new(),
		handler = Handlers.UIHandler.new(),
	}, UIController)

	self.maid:GiveTask(self.Started)
	self.maid:GiveTask(self.handler)
	return self
end

function UIController.Start(self: UIController): boolean
	self.Started:Fire()
	return true
end

function UIController.GetHandler(self: UIController): any
	return self.handler
end

function UIController.Destroy(self: UIController)
	self.maid:DoCleaning()
end

UIController.start = UIController.Start
UIController.getHandler = UIController.GetHandler
UIController.destroy = UIController.Destroy

return UIController
