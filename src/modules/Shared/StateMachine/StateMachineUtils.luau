
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

local Utils = {}

function Utils.GetBlackboard(machine: any): any?
	if typeof(machine) ~= "table" or typeof(machine.GetBlackboard) ~= "function" then
		return nil
	end
	return machine:GetBlackboard()
end

function Utils.Read(machine: any, key: string, fallback: any?): any?
	local blackboard = Utils.GetBlackboard(machine)
	if blackboard == nil or typeof(blackboard.Get) ~= "function" then
		return fallback
	end
	local value = blackboard:Get(key)
	return if value ~= nil then value else fallback
end

function Utils.CallFirst(target: any, methodNames: { string }, ...: any): any?
	if typeof(target) ~= "table" then
		return nil
	end
	for _, methodName in methodNames do
		local method = target[methodName]
		if typeof(method) == "function" then
			return method(target, ...)
		end
	end
	return nil
end

function Utils.Copy(config: { [string]: any }): { [string]: any }
	return Table.copy(config)
end

return Utils
