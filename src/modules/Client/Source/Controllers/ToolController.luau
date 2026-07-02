local require = require(script.Parent.loader).load(script)

local Handlers = require("Handlers")
local Nevermore = require("GoapNevermore")
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local ToolController = {}
ToolController.__index = ToolController

export type ToolController = typeof(setmetatable(
	{} :: {
		maid: any,
		Started: any,
		handler: any,
	},
	ToolController
))

function ToolController.new(toolRaw: any?): ToolController
	local self = setmetatable({
		maid = Maid.new(),
		Started = Signal.new(),
		handler = Handlers.ToolHandler.new(toolRaw),
	}, ToolController)

	self.maid:GiveTask(self.Started)
	self.maid:GiveTask(self.handler)
	return self
end

function ToolController.Start(self: ToolController): boolean
	self.Started:Fire()
	return true
end

function ToolController.GetHandler(self: ToolController): any
	return self.handler
end

function ToolController.Destroy(self: ToolController)
	self.maid:DoCleaning()
end
return ToolController
