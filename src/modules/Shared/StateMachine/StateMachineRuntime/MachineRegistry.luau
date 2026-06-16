
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")
local ValueObject = Nevermore.Get("ValueObject")

local MachineRegistry = {}
MachineRegistry.__index = MachineRegistry

export type MachineRegistry = typeof(setmetatable(
	{} :: {
		machines: { [string]: any },
		maid: any,
		count: any,
		Registered: any,
		Removed: any,
	},
	MachineRegistry
))

function MachineRegistry.new(): MachineRegistry
	local self = setmetatable({
		machines = {},
		maid = Maid.new(),
		count = ValueObject.new(0, "number"),
		Registered = Signal.new(),
		Removed = Signal.new(),
	}, MachineRegistry)

	self.maid:GiveTask(self.count)
	self.maid:GiveTask(self.Registered)
	self.maid:GiveTask(self.Removed)
	return self
end

function MachineRegistry._syncCount(self: MachineRegistry)
	self.count.Value = Table.count(self.machines)
end

function MachineRegistry.Register(self: MachineRegistry, id: string, machine: any): boolean
	if typeof(id) ~= "string" or id == "" or machine == nil then
		return false
	end
	self.machines[id] = machine
	self:_syncCount()
	self.Registered:Fire(id, machine)
	return true
end

function MachineRegistry.Get(self: MachineRegistry, id: string): any?
	return self.machines[id]
end

function MachineRegistry.Remove(self: MachineRegistry, id: string): any?
	local machine = self.machines[id]
	self.machines[id] = nil
	if machine ~= nil then
		self:_syncCount()
		self.Removed:Fire(id, machine)
	end
	return machine
end

function MachineRegistry.GetSnapshot(self: MachineRegistry): { [string]: any }
	return Table.copy(self.machines)
end

function MachineRegistry.ObserveCount(self: MachineRegistry): any
	return self.count:Observe()
end

function MachineRegistry.Update(self: MachineRegistry, dt: number)
	for _, machine in self.machines do
		if typeof(machine.Update) == "function" then
			machine:Update(dt)
		end
	end
end

function MachineRegistry.Destroy(self: MachineRegistry)
	for _, machine in self.machines do
		if typeof(machine.Destroy) == "function" then
			machine:Destroy()
		end
	end
	table.clear(self.machines)
	self:_syncCount()
	self.maid:DoCleaning()
end

MachineRegistry.register = MachineRegistry.Register
MachineRegistry.get = MachineRegistry.Get
MachineRegistry.remove = MachineRegistry.Remove
MachineRegistry.getSnapshot = MachineRegistry.GetSnapshot
MachineRegistry.observeCount = MachineRegistry.ObserveCount
MachineRegistry.update = MachineRegistry.Update
MachineRegistry.destroy = MachineRegistry.Destroy
MachineRegistry.copy = Table.copy

return MachineRegistry
