--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
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

MachineJanitor.add = MachineJanitor.Add
MachineJanitor.clean = MachineJanitor.Clean
MachineJanitor.destroy = MachineJanitor.Destroy

return MachineJanitor
