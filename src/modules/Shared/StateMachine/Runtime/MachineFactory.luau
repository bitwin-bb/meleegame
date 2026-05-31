--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
local Promise = Nevermore.Get("Promise")
local Table = Nevermore.Get("Table")

local MachineFactory = {}

function MachineFactory.Create(machineSource: any, configRaw: any?): any?
	if typeof(machineSource) == "function" then
		return machineSource(configRaw)
	end
	if typeof(machineSource) ~= "table" then
		return nil
	end
	local new = machineSource.new or machineSource.New
	if typeof(new) == "function" then
		return new(configRaw)
	end
	local create = machineSource.Create or machineSource.create
	if typeof(create) == "function" then
		return create(configRaw)
	end
	return nil
end

function MachineFactory.PromiseCreate(machineSource: any, configRaw: any?): any
	return Promise.new(function(resolve, reject)
		local machine = MachineFactory.Create(machineSource, configRaw)
		if machine ~= nil then
			resolve(machine)
		else
			reject("failed to create machine")
		end
	end)
end

MachineFactory.promiseCreate = MachineFactory.PromiseCreate
MachineFactory.copy = Table.copy

return MachineFactory
