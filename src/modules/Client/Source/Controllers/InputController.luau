local require = require(script.Parent.loader).load(script)

local Handlers = require("Handlers")
local Nevermore = require("GoapNevermore")
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local InputController = {}
InputController.__index = InputController

export type InputController = typeof(setmetatable(
	{} :: {
		maid: any,
		Started: any,
		handler: any,
	},
	InputController
))

function InputController.new(): InputController
	local self = setmetatable({
		maid = Maid.new(),
		Started = Signal.new(),
		handler = Handlers.InputHandler.new(),
	}, InputController)

	self.maid:GiveTask(self.Started)
	self.maid:GiveTask(self.handler)
	return self
end

function InputController.Start(self: InputController): boolean
	self.Started:Fire()
	return true
end

function InputController.GetHandler(self: InputController): any
	return self.handler
end

function InputController.Destroy(self: InputController)
	self.maid:DoCleaning()
end
return InputController
