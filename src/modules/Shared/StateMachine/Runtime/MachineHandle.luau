--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
local Promise = Nevermore.Get("Promise")
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")

local MachineJanitor = require(script.Parent.MachineJanitor)

local MachineHandle = {}
MachineHandle.__index = MachineHandle

export type MachineHandle = typeof(setmetatable(
	{} :: {
		id: string,
		machine: any,
		janitor: any,
		Started: any,
		Stopped: any,
		Destroyed: any,
		destroyed: boolean,
	},
	MachineHandle
))

function MachineHandle.new(idRaw: any, machine: any): MachineHandle
	return setmetatable({
		id = if typeof(idRaw) == "string" and idRaw ~= "" then idRaw else "Machine",
		machine = machine,
		janitor = MachineJanitor.new(),
		Started = Signal.new(),
		Stopped = Signal.new(),
		Destroyed = Signal.new(),
		destroyed = false,
	}, MachineHandle)
end

function MachineHandle.Start(self: MachineHandle, initialStateName: string): boolean
	if self.destroyed or typeof(self.machine.Start) ~= "function" then
		return false
	end
	local started = self.machine:Start(initialStateName)
	if started then
		self.Started:Fire(initialStateName)
	end
	return started
end

function MachineHandle.PromiseStart(self: MachineHandle, initialStateName: string): any
	return Promise.new(function(resolve, reject)
		if self:Start(initialStateName) then
			resolve(self)
		else
			reject(string.format("failed to start machine '%s'", self.id))
		end
	end)
end

function MachineHandle.Update(self: MachineHandle, dt: number): boolean
	if self.destroyed or typeof(self.machine.Update) ~= "function" then
		return false
	end
	return self.machine:Update(dt)
end

function MachineHandle.Stop(self: MachineHandle)
	if self.destroyed or typeof(self.machine.Stop) ~= "function" then
		return
	end
	self.machine:Stop()
	self.Stopped:Fire()
end

function MachineHandle.Destroy(self: MachineHandle)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if typeof(self.machine.Destroy) == "function" then
		self.machine:Destroy()
	end
	self.Destroyed:Fire()
	self.Started:Destroy()
	self.Stopped:Destroy()
	self.Destroyed:Destroy()
	self.janitor:Destroy()
end

MachineHandle.start = MachineHandle.Start
MachineHandle.promiseStart = MachineHandle.PromiseStart
MachineHandle.update = MachineHandle.Update
MachineHandle.stop = MachineHandle.Stop
MachineHandle.destroy = MachineHandle.Destroy
MachineHandle.copy = Table.copy

return MachineHandle
