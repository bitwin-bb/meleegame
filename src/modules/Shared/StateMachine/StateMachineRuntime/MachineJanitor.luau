
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Maid = Nevermore.Get("Maid")

local MachineJanitor = {}
MachineJanitor.__index = MachineJanitor

export type MachineJanitor = typeof(setmetatable(
	{} :: {
		janitor: any,
	},
	MachineJanitor
))

function MachineJanitor.new(): MachineJanitor
	return setmetatable({
		janitor = Maid.new(),
	}, MachineJanitor)
end

function MachineJanitor.Add(self: MachineJanitor, chore: any): any
	self.janitor:GiveTask(chore)
	return chore
end

function MachineJanitor.Clean(self: MachineJanitor)
	self.janitor:DoCleaning()
end

function MachineJanitor.Destroy(self: MachineJanitor)
	self.janitor:Destroy()
end
return MachineJanitor
