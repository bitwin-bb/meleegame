
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")

local UIHandler = {}
UIHandler.__index = UIHandler

export type UIHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		Changed: any,
		screens: { [string]: boolean },
	},
	UIHandler
))

function UIHandler.new(): UIHandler
	local self = setmetatable({
		maid = Maid.new(),
		Changed = Signal.new(),
		screens = {},
	}, UIHandler)

	self.maid:GiveTask(self.Changed)
	return self
end

function UIHandler.SetScreenVisible(self: UIHandler, screenName: string, visibleRaw: any)
	local visible = visibleRaw == true
	if self.screens[screenName] == visible then
		return
	end
	self.screens[screenName] = visible
	self.Changed:Fire(screenName, visible)
end

function UIHandler.IsScreenVisible(self: UIHandler, screenName: string): boolean
	return self.screens[screenName] == true
end

function UIHandler.GetSnapshot(self: UIHandler): { [string]: boolean }
	return Table.copy(self.screens)
end

function UIHandler.Destroy(self: UIHandler)
	self.maid:DoCleaning()
	table.clear(self.screens)
end
return UIHandler
