
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Core").Table

local Utils = {}

function Utils.CopyDictionary(valuesRaw: any): { [string]: any }
	return if typeof(valuesRaw) == "table" then Table.copy(valuesRaw) else {}
end

function Utils.ReadBlackboard(agent: any, keyRaw: any, fallback: any?): any
	if typeof(agent) ~= "table" then
		return fallback
	end
	local getBlackboard = agent.GetBlackboard or agent.getBlackboard
	if typeof(getBlackboard) ~= "function" then
		return fallback
	end
	local blackboard = getBlackboard(agent)
	if typeof(blackboard) ~= "table" then
		return fallback
	end
	local get = blackboard.Get or blackboard.get
	if typeof(get) ~= "function" then
		return fallback
	end
	local value = get(blackboard, keyRaw)
	return if value == nil then fallback else value
end

function Utils.WriteWorldState(agent: any, keyRaw: any, value: any): boolean
	if typeof(agent) ~= "table" then
		return false
	end
	local setWorldState = agent.SetWorldState or agent.setWorldState
	if typeof(setWorldState) ~= "function" then
		return false
	end
	setWorldState(agent, keyRaw, value)
	return true
end

function Utils.ReadWorldState(agent: any, keyRaw: any, fallback: any?): any
	if typeof(agent) ~= "table" then
		return fallback
	end
	local getWorldState = agent.GetWorldState or agent.getWorldState
	if typeof(getWorldState) ~= "function" then
		return fallback
	end
	local value = getWorldState(agent, keyRaw)
	return if value == nil then fallback else value
end

function Utils.CallFirst(target: any, methodNames: { string }, ...): (boolean, any?)
	if typeof(target) ~= "table" then
		return false, nil
	end
	for _, methodName in methodNames do
		local method = target[methodName]
		if typeof(method) == "function" then
			local ok, result = pcall(method, target, ...)
			return ok, result
		end
	end
	return false, nil
end

function Utils.GetName(value: any, fallback: string): string
	if typeof(value) == "table" and typeof(value.Name) == "string" and value.Name ~= "" then
		return value.Name
	end
	return fallback
end

function Utils.FormatValue(value: any): string
	if typeof(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end
return Utils
